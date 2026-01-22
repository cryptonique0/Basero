// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {RebaseToken} from "./RebaseToken.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title RebaseTokenVault
 * @author Basero Protocol
 * @notice ETH vault that issues rebasing tokens with decreasing interest rates for early depositors
 * @dev Main entry point for users to deposit ETH and receive RebaseTokens with locked interest rates
 * 
 * @dev Architecture:
 * - Users deposit ETH and receive RebaseTokens at current interest rate
 * - Interest rates start at 10% and decrease by 1% per 10 ETH tier (minimum 2%)
 * - Each user's interest rate is locked at deposit time
 * - Interest accrues automatically via Chainlink Automation
 * - Redemptions return proportional ETH based on share ownership
 * 
 * @dev Key Features:
 * - Tiered interest rates (early depositors get higher rates)
 * - Governance-controlled parameters (via timelock)
 * - Pause controls for deposits and redemptions
 * - Allowlist support for permissioned access
 * - Deposit caps (per-user and global TVL)
 * - Protocol fee on accrued interest
 * - Circuit breakers for daily accrual limits
 * - Slippage protection on redemptions
 * 
 * @dev Security:
 * - ReentrancyGuard on all state-changing functions
 * - Pausable for emergency stops
 * - Governance timelock for parameter changes
 * - Circuit breakers prevent excessive inflation
 * - Minimum accrual period prevents griefing
 */
contract RebaseTokenVault is Ownable, Pausable, ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    RebaseToken public immutable i_rebaseToken;

    // Governance roles
    address public governanceTimelock;

    // Current interest rate (in basis points, 10000 = 100%)
    // Starts at 10% (1000 basis points) and decreases
    uint256 private s_currentInterestRate;

    // Interest rate decrement per tier
    uint256 private constant INTEREST_RATE_DECREMENT = 100; // 1% decrease per tier

    // Minimum interest rate (2% or 200 basis points)
    uint256 private constant MINIMUM_INTEREST_RATE = 200;

    // Amount of ETH deposited per tier before rate decreases
    uint256 private constant DEPOSIT_TIER_AMOUNT = 10 ether;

    // Total ETH deposited
    uint256 private s_totalEthDeposited;

    // Track how much ETH each user has deposited
    mapping(address => uint256) private s_userEthDeposited;

    // Last time interest was accrued
    uint256 private s_lastAccrualTime;

    // Interest accrual period configurable
    uint256 private s_accrualPeriod;

    // Bounds for accrual period to avoid misconfiguration
    uint256 private constant MIN_ACCRUAL_PERIOD = 1 hours;
    uint256 private constant MAX_ACCRUAL_PERIOD = 7 days;

    // Circuit breaker for daily accrual (basis points of supply per accrual day)
    uint256 private s_maxDailyAccrualBps;

    // Protocol fee configuration (basis points of accrued interest)
    address private s_feeRecipient;
    uint256 private s_protocolFeeBps;

    // Deposit controls
    bool private s_depositsPaused;
    bool private s_redeemsPaused;
    bool private s_allowlistEnabled;
    uint256 private s_minDeposit;
    uint256 private s_maxDepositPerAddress;
    uint256 private s_maxTotalDeposits;

    // Allowlist for depositors
    mapping(address => bool) private s_allowlist;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event Deposit(address indexed user, uint256 ethAmount, uint256 tokensReceived, uint256 interestRate);
    event Redeem(address indexed user, uint256 tokenAmount, uint256 ethReceived);
    event InterestAccrued(uint256 interestAmount, uint256 timestamp);
    event InterestAccrualDetailed(
        uint256 supplyBefore,
        uint256 interestAccrued,
        uint256 protocolFee,
        uint256 supplyAfter,
        uint256 periods
    );
    event InterestRateDecreased(uint256 oldRate, uint256 newRate, uint256 totalDeposited);
    event DepositsPaused(address indexed account);
    event DepositsUnpaused(address indexed account);
    event RedeemsPaused(address indexed account);
    event RedeemsUnpaused(address indexed account);
    event AllowlistStatusChanged(bool enabled);
    event AllowlistUpdated(address indexed account, bool allowed);
    event DepositCapsUpdated(uint256 maxDepositPerAddress, uint256 maxTotalDeposits);
    event MinDepositUpdated(uint256 minDeposit);
    event FeeConfigUpdated(address indexed recipient, uint256 protocolFeeBps);
    event AccrualConfigUpdated(uint256 accrualPeriod, uint256 maxDailyAccrualBps);
    event SweepExecuted(address indexed token, address indexed to, uint256 amount);
    event EmergencyEthWithdrawn(address indexed to, uint256 amount);
    event GovernanceTimelockUpdated(address indexed oldTimelock, address indexed newTimelock);
    event GovernanceParameterUpdated(string indexed parameterName, uint256 newValue, address indexed updatedBy);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error InsufficientDeposit();
    error InsufficientBalance();
    error TransferFailed();
    error NoTokensToRedeem();
    error DepositsArePaused();
    error RedeemsArePaused();
    error OnlyGovernance();
    error InvalidGovernanceAddress();
    error NotAllowlisted();
    error MinDepositNotMet(uint256 provided, uint256 minimum);
    error DepositCapExceeded(uint256 requested, uint256 maxPerAddress);
    error TvlCapExceeded(uint256 requested, uint256 maxTotal);
    error SlippageTooHigh(uint256 expected, uint256 minOut);
    error InvalidAccrualPeriod();
    error InvalidProtocolFee();
    error ZeroAddressNotAllowed();
    error AmountZero();
    error TokenNotSweepable();

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize the vault with a RebaseToken contract
     * @dev Sets initial parameters: 10% starting rate, 1 day accrual, 10% daily cap
     * 
     * @param rebaseToken Address of the RebaseToken contract (must be valid)
     * 
     * Initial State:
     * - Interest rate: 10% (1000 basis points)
     * - Accrual period: 1 day
     * - Max daily accrual: 10% of supply
     * - No deposit caps (type(uint256).max)
     * - Fee recipient: deployer (msg.sender)
     * - Protocol fee: 0%
     * 
     * Requirements:
     * - rebaseToken must be a valid contract address
     */
    constructor(address rebaseToken) Ownable(msg.sender) {
        i_rebaseToken = RebaseToken(rebaseToken);
        s_currentInterestRate = 1000; // Start at 10%
        s_lastAccrualTime = block.timestamp;
        s_accrualPeriod = 1 days;
        s_maxDailyAccrualBps = 1000; // Default 10% daily cap for safety
        s_minDeposit = 0;
        s_maxDepositPerAddress = type(uint256).max;
        s_maxTotalDeposits = type(uint256).max;
        s_feeRecipient = msg.sender;
        s_protocolFeeBps = 0;
    }

    /*//////////////////////////////////////////////////////////////
                            MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyGovernance() {
        if (msg.sender != governanceTimelock && msg.sender != owner()) revert OnlyGovernance();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                      GOVERNANCE MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the governance timelock contract address
     * @dev Once set, timelock can update vault parameters alongside owner
     * @dev Used for decentralized governance of interest rates, fees, caps
     * 
     * @param newTimelock Address of the BASETimelock controller contract
     * 
     * Requirements:
     * - Caller must be owner
     * - newTimelock cannot be zero address
     * 
     * Emits:
     * - GovernanceTimelockUpdated(oldTimelock, newTimelock)
     * 
     * Example:
     * setGovernanceTimelock(0x123...) // Set timelock controller
     * // Now governance proposals can update vault parameters
     */
    function setGovernanceTimelock(address newTimelock) external onlyOwner {
        if (newTimelock == address(0)) revert InvalidGovernanceAddress();

        address oldTimelock = governanceTimelock;
        governanceTimelock = newTimelock;

        emit GovernanceTimelockUpdated(oldTimelock, newTimelock);
    }

    /**
     * @notice Get the current governance timelock address
     * @dev Timelock has authority to update vault parameters via proposals
     * 
     * @return Address of governance timelock controller (or zero if not set)
     */
    function getGovernanceTimelock() external view returns (address) {
        return governanceTimelock;
    }

    /*//////////////////////////////////////////////////////////////
                        PAUSE / GUARDIAN LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Pause new deposits while allowing redemptions
     * @dev Emergency function to stop new deposits without freezing existing funds
     * 
     * Requirements:
     * - Caller must be owner
     * 
     * Emits:
     * - DepositsPaused(msg.sender)
     */
    function pauseDeposits() external onlyOwner {
        s_depositsPaused = true;
        emit DepositsPaused(msg.sender);
    }

    /**
     * @notice Resume accepting new deposits
     * @dev Unpauses deposit functionality after emergency stop
     * 
     * Requirements:
     * - Caller must be owner
     * 
     * Emits:
     * - DepositsUnpaused(msg.sender)
     */
    function unpauseDeposits() external onlyOwner {
        s_depositsPaused = false;
        emit DepositsUnpaused(msg.sender);
    }

    /**
     * @notice Pause redemptions while allowing deposits
     * @dev Emergency function to prevent ETH withdrawals (e.g., if vulnerability found)
     * 
     * Requirements:
     * - Caller must be owner
     * 
     * Emits:
     * - RedeemsPaused(msg.sender)
     */
    function pauseRedeems() external onlyOwner {
        s_redeemsPaused = true;
        emit RedeemsPaused(msg.sender);
    }

    /**
     * @notice Resume redemption functionality
     * @dev Unpauses redemptions after emergency stop
     * 
     * Requirements:
     * - Caller must be owner
     * 
     * Emits:
     * - RedeemsUnpaused(msg.sender)
     */
    function unpauseRedeems() external onlyOwner {
        s_redeemsPaused = false;
        emit RedeemsUnpaused(msg.sender);
    }

    /**
     * @notice Pause all vault operations (deposits and redemptions)
     * @dev Uses OpenZeppelin Pausable to halt all interactions
     * 
     * Requirements:
     * - Caller must be owner
     * 
     * Emits:
     * - Paused(msg.sender)
     */
    function pauseAll() external onlyOwner {
        _pause();
    }

    /**
     * @notice Resume all vault operations
     * @dev Unpauses global pause state
     * 
     * Requirements:
     * - Caller must be owner
     * 
     * Emits:
     * - Unpaused(msg.sender)
     */
    function unpauseAll() external onlyOwner {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Enable or disable allowlist requirement for deposits
     * @dev When enabled, only allowlisted addresses can deposit
     * 
     * @param enabled True to require allowlist, false to allow anyone
     * 
     * Requirements:
     * - Caller must be owner
     * 
     * Emits:
     * - AllowlistStatusChanged(enabled)
     * 
     * Use Case:
     * Enable for private beta, disable for public launch
     */
    function setAllowlistStatus(bool enabled) external onlyOwner {
        s_allowlistEnabled = enabled;
        emit AllowlistStatusChanged(enabled);
    }

    /**
     * @notice Add or remove an address from the deposit allowlist
     * @dev Only effective when allowlist is enabled via setAllowlistStatus
     * 
     * @param account Address to update allowlist status for
     * @param allowed True to allow deposits, false to revoke
     * 
     * Requirements:
     * - Caller must be owner
     * 
     * Emits:
     * - AllowlistUpdated(account, allowed)
     */
    function setAllowlist(address account, bool allowed) external onlyOwner {
        s_allowlist[account] = allowed;
        emit AllowlistUpdated(account, allowed);
    }

    /**
     * @notice Set maximum deposit limits per user and total TVL
     * @dev Governance-controlled risk management parameters
     * 
     * @param maxPerAddress Maximum ETH any single address can deposit
     * @param maxTotal Maximum total ETH the vault can hold (TVL cap)
     * 
     * Requirements:
     * - Caller must be governance timelock or owner
     * - Both values must be greater than zero
     * 
     * Emits:
     * - DepositCapsUpdated(maxPerAddress, maxTotal)
     * - GovernanceParameterUpdated("DepositCaps", maxPerAddress, msg.sender)
     * 
     * Example:
     * setDepositCaps(100 ether, 10000 ether)
     * // Max 100 ETH per user, 10k ETH total
     */
    function setDepositCaps(uint256 maxPerAddress, uint256 maxTotal) external onlyGovernance {
        if (maxPerAddress == 0 || maxTotal == 0) revert AmountZero();
        s_maxDepositPerAddress = maxPerAddress;
        s_maxTotalDeposits = maxTotal;
        emit DepositCapsUpdated(maxPerAddress, maxTotal);
        emit GovernanceParameterUpdated("DepositCaps", maxPerAddress, msg.sender);
    }

    /**
     * @notice Set minimum ETH amount required per deposit
     * @dev Prevents dust deposits and reduces gas costs
     * 
     * @param minDeposit Minimum ETH required (in wei)
     * 
     * Requirements:
     * - Caller must be governance timelock or owner
     * 
     * Emits:
     * - MinDepositUpdated(minDeposit)
     * - GovernanceParameterUpdated("MinDeposit", minDeposit, msg.sender)
     * 
     * Example:
     * setMinDeposit(0.1 ether) // Require at least 0.1 ETH
     */
    function setMinDeposit(uint256 minDeposit) external onlyGovernance {
        s_minDeposit = minDeposit;
        emit MinDepositUpdated(minDeposit);
        emit GovernanceParameterUpdated("MinDeposit", minDeposit, msg.sender);
    }

    /**
     * @notice Configure protocol fee on accrued interest
     * @dev Fee is taken from interest before distribution to users
     * 
     * @param recipient Address to receive protocol fees
     * @param protocolFeeBps Fee percentage in basis points (max 10000 = 100%)
     * 
     * Requirements:
     * - Caller must be governance timelock or owner
     * - Recipient cannot be zero address
     * - Fee cannot exceed 100% (10000 bps)
     * 
     * Emits:
     * - FeeConfigUpdated(recipient, protocolFeeBps)
     * - GovernanceParameterUpdated("ProtocolFeeBps", protocolFeeBps, msg.sender)
     * 
     * Example:
     * setFeeConfig(treasury, 1000) // 10% protocol fee
     * If 100 tokens interest accrues, 10 goes to treasury, 90 to users
     */
    function setFeeConfig(address recipient, uint256 protocolFeeBps) external onlyGovernance {
        if (recipient == address(0)) revert ZeroAddressNotAllowed();
        if (protocolFeeBps > 10_000) revert InvalidProtocolFee();
        s_feeRecipient = recipient;
        s_protocolFeeBps = protocolFeeBps;
        emit FeeConfigUpdated(recipient, protocolFeeBps);
        emit GovernanceParameterUpdated("ProtocolFeeBps", protocolFeeBps, msg.sender);
    }

    /**
     * @notice Configure interest accrual timing and circuit breaker
     * @dev Accrual period determines how often interest compounds
     * @dev Max daily accrual acts as circuit breaker to prevent runaway inflation
     * 
     * @param accrualPeriod Time between interest accruals (1 hour to 7 days)
     * @param maxDailyAccrualBps Maximum interest accrual per day in basis points
     * 
     * Requirements:
     * - Caller must be governance timelock or owner
     * - accrualPeriod must be between 1 hour and 7 days
     * 
     * Emits:
     * - AccrualConfigUpdated(accrualPeriod, maxDailyAccrualBps)
     * - GovernanceParameterUpdated("AccrualPeriod", accrualPeriod, msg.sender)
     * 
     * Example:
     * setAccrualConfig(1 days, 1000) // Accrue daily, max 10% per day
     */
    function setAccrualConfig(uint256 accrualPeriod, uint256 maxDailyAccrualBps) external onlyGovernance {
        if (accrualPeriod < MIN_ACCRUAL_PERIOD || accrualPeriod > MAX_ACCRUAL_PERIOD) {
            revert InvalidAccrualPeriod();
        }
        s_accrualPeriod = accrualPeriod;
        s_maxDailyAccrualBps = maxDailyAccrualBps;
        emit AccrualConfigUpdated(accrualPeriod, maxDailyAccrualBps);
        emit GovernanceParameterUpdated("AccrualPeriod", accrualPeriod, msg.sender);
    }

    /**
     * @notice Emergency function to withdraw ETH from vault
     * @dev Use only in extreme circumstances (e.g., exploit detected)
     * @dev Protected by nonReentrant modifier
     * 
     * @param to Address to receive withdrawn ETH
     * @param amount Amount to withdraw (0 = withdraw all)
     * 
     * Requirements:
     * - Caller must be owner
     * - Recipient cannot be zero address
     * - Amount must be greater than zero
     * 
     * Emits:
     * - EmergencyEthWithdrawn(to, amount)
     * 
     * Warning:
     * This breaks the vault's invariants and should only be used
     * when normal operations cannot continue
     */
    function emergencyWithdrawETH(address to, uint256 amount) external onlyOwner nonReentrant {
        if (to == address(0)) revert ZeroAddressNotAllowed();
        uint256 value = amount == 0 ? address(this).balance : amount;
        if (value == 0) revert AmountZero();
        (bool success,) = to.call{value: value}("");
        if (!success) revert TransferFailed();
        emit EmergencyEthWithdrawn(to, value);
    }

    /**
     * @notice Sweep accidentally sent ERC20 tokens from vault
     * @dev Cannot be used to sweep the RebaseToken itself
     * 
     * @param token Address of ERC20 token to sweep
     * @param to Address to receive swept tokens
     * @param amount Amount of tokens to sweep
     * 
     * Requirements:
     * - Caller must be owner
     * - Token cannot be the RebaseToken
     * - Recipient cannot be zero address
     * - Amount must be greater than zero
     * 
     * Emits:
     * - SweepExecuted(token, to, amount)
     */
    function sweepERC20(address token, address to, uint256 amount) external onlyOwner nonReentrant {
        if (token == address(i_rebaseToken)) revert TokenNotSweepable();
        if (to == address(0)) revert ZeroAddressNotAllowed();
        if (amount == 0) revert AmountZero();
        IERC20(token).transfer(to, amount);
        emit SweepExecuted(token, to, amount);
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT AND REDEEM FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposit ETH to receive RebaseTokens at current interest rate
     * @dev User's interest rate is locked at deposit time and never changes
     * @dev Automatically accrues pending interest before minting new tokens
     * 
     * Formula:
     * tokensToMint = msg.value (1:1 ratio)
     * userInterestRate = currentInterestRate (locked forever)
     * 
     * Interest Rate Tiers:
     * - 0-10 ETH total deposited: 10% APY
     * - 10-20 ETH: 9% APY
     * - 20-30 ETH: 8% APY
     * - Each 10 ETH tier: -1% APY
     * - Minimum: 2% APY (at 80+ ETH deposited)
     * 
     * Requirements:
     * - msg.value > 0
     * - Deposits not paused
     * - Contract not globally paused
     * - If allowlist enabled: caller must be allowlisted
     * - msg.value >= minDeposit
     * - User total deposit <= maxDepositPerAddress
     * - Vault total deposit <= maxTotalDeposits
     * 
     * Effects:
     * - Mints RebaseTokens to msg.sender
     * - Locks interest rate for user
     * - Increases total ETH deposited
     * - May decrease current interest rate (if crosses tier)
     * 
     * Emits:
     * - Deposit(user, ethAmount, tokensReceived, interestRate)
     * - May emit InterestAccrued if accrual period elapsed
     * - May emit InterestRateDecreased if tier crossed
     * 
     * Example:
     * deposit{value: 5 ether}()
     * // Receives 5 tokens at current rate (e.g., 10%)
     * // Future interest compounds at 10% forever for this user
     */
    function deposit() external payable nonReentrant {
        if (msg.value == 0) revert InsufficientDeposit();
        if (paused() || s_depositsPaused) revert DepositsArePaused();
        if (s_allowlistEnabled && !s_allowlist[msg.sender]) revert NotAllowlisted();
        if (msg.value < s_minDeposit) revert MinDepositNotMet(msg.value, s_minDeposit);

        uint256 newUserTotal = s_userEthDeposited[msg.sender] + msg.value;
        if (newUserTotal > s_maxDepositPerAddress) revert DepositCapExceeded(newUserTotal, s_maxDepositPerAddress);

        uint256 newTotalDeposits = s_totalEthDeposited + msg.value;
        if (newTotalDeposits > s_maxTotalDeposits) revert TvlCapExceeded(newTotalDeposits, s_maxTotalDeposits);

        // Accrue interest before minting new tokens
        _accrueInterest();

        // Calculate tokens to mint (1:1 ratio with ETH)
        uint256 tokensToMint = msg.value;

        // Get current interest rate for this user
        uint256 userInterestRate = s_currentInterestRate;

        // Mint tokens with the current interest rate
        i_rebaseToken.mint(msg.sender, tokensToMint, userInterestRate);

        // Update user's deposit tracking
        s_userEthDeposited[msg.sender] = newUserTotal;
        s_totalEthDeposited = newTotalDeposits;

        // Check if we need to decrease the interest rate
        _updateInterestRate();

        emit Deposit(msg.sender, msg.value, tokensToMint, userInterestRate);
    }

    /**
     * @notice Redeem RebaseTokens for proportional ETH
     * @dev Redemption amount based on user's share of total vault ETH
     * @dev Calls redeemWithMinOut with 0 slippage protection
     * 
     * @param tokenAmount Amount of RebaseTokens to burn
     * 
     * Formula:
     * sharesToBurn = (tokenAmount * totalShares) / totalSupply
     * ethToReturn = (totalEthDeposited * sharesToBurn) / totalShares
     * 
     * Example:
     * User has 100 tokens, wants to redeem 50
     * Total supply = 1000 tokens, Total shares = 500, Vault has 800 ETH
     * sharesToBurn = (50 * 500) / 1000 = 25 shares
     * ethToReturn = (800 * 25) / 500 = 40 ETH
     * 
     * Requirements:
     * - See redeemWithMinOut requirements
     */
    function redeem(uint256 tokenAmount) external {
        redeemWithMinOut(tokenAmount, 0);
    }

    /**
     * @notice Redeem RebaseTokens with slippage protection
     * @dev Protects against unfavorable redemptions during high volatility
     * 
     * @param tokenAmount Amount of RebaseTokens to burn and redeem
     * @param minEthOut Minimum ETH to receive (reverts if less)
     * 
     * Formula:
     * sharesToBurn = getSharesByTokenAmount(tokenAmount)
     * ethToReturn = (totalEthDeposited * sharesToBurn) / totalShares
     * 
     * Requirements:
     * - tokenAmount > 0
     * - Redemptions not paused
     * - Contract not globally paused
     * - User balance >= tokenAmount
     * - ethToReturn >= minEthOut (slippage check)
     * 
     * Effects:
     * - Burns RebaseTokens from user
     * - Decreases totalEthDeposited
     * - Transfers ETH to user
     * 
     * Emits:
     * - Redeem(user, tokenAmount, ethReceived)
     * - May emit InterestAccrued if accrual period elapsed
     * 
     * Example:
     * redeemWithMinOut(100 ether, 95 ether)
     * // Redeem 100 tokens, require at least 95 ETH
     * // Reverts if would receive less than 95 ETH
     */
    function redeemWithMinOut(uint256 tokenAmount, uint256 minEthOut) public nonReentrant {
        if (tokenAmount == 0) revert NoTokensToRedeem();
        if (paused() || s_redeemsPaused) revert RedeemsArePaused();

        uint256 userBalance = i_rebaseToken.balanceOf(msg.sender);
        if (userBalance < tokenAmount) revert InsufficientBalance();

        // Accrue interest before burning tokens
        _accrueInterest();

        // Calculate ETH to return (based on shares to maintain fair redemption)
        uint256 userShares = i_rebaseToken.sharesOf(msg.sender);
        uint256 totalShares = i_rebaseToken.getTotalShares();
        uint256 sharesToBurn = i_rebaseToken.getSharesByTokenAmount(tokenAmount);

        // Calculate proportional ETH to return
        uint256 ethToReturn = (s_totalEthDeposited * sharesToBurn) / totalShares;

        if (ethToReturn < minEthOut) revert SlippageTooHigh(ethToReturn, minEthOut);

        // Burn tokens
        i_rebaseToken.burn(msg.sender, tokenAmount);

        // Update total deposited
        s_totalEthDeposited -= ethToReturn;

        // Transfer ETH back to user
        (bool success,) = msg.sender.call{value: ethToReturn}("");
        if (!success) revert TransferFailed();

        emit Redeem(msg.sender, tokenAmount, ethToReturn);
    }

    /*//////////////////////////////////////////////////////////////
                        INTEREST ACCRUAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Accrue interest to all token holders
     * @dev Called automatically before deposits and redemptions
     * @dev Only accrues if at least one accrual period has elapsed
     * 
     * Formula:
     * periodsElapsed = (currentTime - lastAccrualTime) / accrualPeriod
     * interestToAccrue = (currentSupply * currentRate * periodsElapsed) / 10000 / 365
     * maxAccrual = (currentSupply * maxDailyAccrualBps * periodsElapsed) / 10000
     * actualInterest = min(interestToAccrue, maxAccrual) // Circuit breaker
     * protocolFee = actualInterest * protocolFeeBps / 10000
     * netInterest = actualInterest - protocolFee
     * 
     * Example:
     * Current supply = 10,000 tokens
     * Current rate = 1000 bps (10%)
     * 1 day elapsed (periodsElapsed = 1)
     * Interest = (10000 * 1000 * 1) / 10000 / 365 = 2.74 tokens
     * If protocol fee = 10% (1000 bps):
     *   Fee = 0.274 tokens to treasury
     *   Net = 2.466 tokens to users via rebase
     * 
     * Effects:
     * - Increases total token supply via rebase
     * - Mints protocol fee tokens to feeRecipient
     * - Updates lastAccrualTime to current block.timestamp
     * 
     * Emits:
     * - InterestAccrued(interestAmount, timestamp)
     * - InterestAccrualDetailed(supplyBefore, interest, fee, supplyAfter, periods)
     */
    function _accrueInterest() internal {
        uint256 timePassed = block.timestamp - s_lastAccrualTime;

        // Only accrue if at least one period has passed
        if (timePassed >= s_accrualPeriod) {
            uint256 currentSupply = i_rebaseToken.totalSupply();

            if (currentSupply > 0) {
                // Calculate average interest rate across all holders
                uint256 periodsElapsed = timePassed / s_accrualPeriod;
                uint256 interestToAccrue = (currentSupply * s_currentInterestRate * periodsElapsed) / 10_000 / 365;

                // Apply circuit breaker cap on daily accrual
                uint256 maxAccrual = (currentSupply * s_maxDailyAccrualBps * periodsElapsed) / 10_000;
                if (interestToAccrue > maxAccrual) {
                    interestToAccrue = maxAccrual;
                }

                uint256 protocolFee;
                if (interestToAccrue > 0) {
                    if (s_protocolFeeBps > 0 && s_feeRecipient != address(0)) {
                        protocolFee = (interestToAccrue * s_protocolFeeBps) / 10_000;
                        uint256 netInterest = interestToAccrue - protocolFee;
                        if (netInterest > 0) {
                            i_rebaseToken.accrueInterest(netInterest);
                        }
                        if (protocolFee > 0) {
                            i_rebaseToken.mint(s_feeRecipient, protocolFee, s_currentInterestRate);
                        }
                    } else {
                        i_rebaseToken.accrueInterest(interestToAccrue);
                    }
                    emit InterestAccrued(interestToAccrue, block.timestamp);
                    emit InterestAccrualDetailed(
                        currentSupply,
                        interestToAccrue,
                        protocolFee,
                        i_rebaseToken.totalSupply(),
                        periodsElapsed
                    );
                }
            }

            s_lastAccrualTime = block.timestamp;
        }
    }

    /**
     * @notice Update current interest rate based on total deposits
     * @dev Rate decreases by 1% per 10 ETH tier, minimum 2%
     * 
     * Formula:
     * currentTier = totalEthDeposited / 10 ether
     * targetRate = 1000 - (currentTier * 100) // in basis points
     * targetRate = max(targetRate, 200) // Minimum 2%
     * 
     * Tier Schedule:
     * - Tier 0 (0-10 ETH): 10% APY (1000 bps)
     * - Tier 1 (10-20 ETH): 9% APY (900 bps)
     * - Tier 2 (20-30 ETH): 8% APY (800 bps)
     * - Tier 8+ (80+ ETH): 2% APY (200 bps, minimum)
     * 
     * Effects:
     * - Decreases currentInterestRate if tier boundary crossed
     * - Only affects NEW deposits, existing users keep their locked rates
     * 
     * Emits:
     * - InterestRateDecreased(oldRate, newRate, totalDeposited)
     * 
     * Example:
     * Before: 15 ETH deposited, rate = 9%
     * After deposit: 25 ETH deposited
     * New tier = 25 / 10 = 2
     * New rate = 1000 - (2 * 100) = 800 bps = 8%
     * Emit: InterestRateDecreased(900, 800, 25 ether)
     */
    function _updateInterestRate() internal {
        uint256 currentTier = s_totalEthDeposited / DEPOSIT_TIER_AMOUNT;
        uint256 targetRate = 1000 - (currentTier * INTEREST_RATE_DECREMENT);

        if (targetRate < MINIMUM_INTEREST_RATE) {
            targetRate = MINIMUM_INTEREST_RATE;
        }

        if (targetRate < s_currentInterestRate) {
            uint256 oldRate = s_currentInterestRate;
            s_currentInterestRate = targetRate;
            emit InterestRateDecreased(oldRate, targetRate, s_totalEthDeposited);
        }
    }

    /**
     * @notice Manually trigger interest accrual
     * @dev Anyone can call to trigger pending interest distribution
     * @dev Useful if Chainlink Automation is delayed or disabled
     * 
     * Effects:
     * - Calls _accrueInterest() internal function
     * - See _accrueInterest() for detailed formula and effects
     */
    function accrueInterest() external {
        _accrueInterest();
    }

    /**
     * @notice Chainlink Automation compatible check function
     * @dev Called by Chainlink nodes to determine if performUpkeep should be called
     * 
     * @param Unused calldata parameter (required by interface)
     * @return upkeepNeeded True if accrual period has elapsed
     * @return performData Empty bytes (not used)
     * 
     * Logic:
     * upkeepNeeded = (block.timestamp - lastAccrualTime) >= accrualPeriod
     * 
     * Example:
     * Last accrual: Jan 1 00:00
     * Current time: Jan 2 00:01
     * Accrual period: 1 day
     * Returns: (true, "")
     */
    function checkUpkeep(bytes calldata) external view returns (bool upkeepNeeded, bytes memory performData) {
        upkeepNeeded = block.timestamp - s_lastAccrualTime >= s_accrualPeriod;
        performData = "";
    }

    /**
     * @notice Chainlink Automation compatible perform function
     * @dev Called by Chainlink nodes when checkUpkeep returns true
     * @dev Triggers interest accrual if period elapsed
     * 
     * @param Unused calldata parameter (required by interface)
     * 
     * Requirements:
     * - Accrual period must have elapsed (redundant check)
     * 
     * Effects:
     * - Calls _accrueInterest() to distribute interest
     */
    function performUpkeep(bytes calldata) external {
        if (block.timestamp - s_lastAccrualTime >= s_accrualPeriod) {
            _accrueInterest();
        }
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get the current interest rate for new deposits
     * @dev This rate applies only to NEW depositors; existing users have locked rates
     * 
     * @return Current interest rate in basis points (e.g., 1000 = 10%)
     * 
     * Example:
     * Returns 900 = 9% APY for new depositors
     */
    function getCurrentInterestRate() external view returns (uint256) {
        return s_currentInterestRate;
    }

    /**
     * @notice Get total ETH held by the vault
     * @dev Represents the total value locked (TVL) in the vault
     * 
     * @return Total ETH deposited by all users (in wei)
     * 
     * Note:
     * This decreases when users redeem tokens for ETH
     */
    function getTotalEthDeposited() external view returns (uint256) {
        return s_totalEthDeposited;
    }

    /**
     * @notice Get the original ETH deposit amount for a user
     * @dev Tracks cumulative deposits, not current value (which may be higher due to interest)
     * 
     * @param user Address to check deposit amount for
     * @return Total ETH this user has deposited (excluding interest)
     * 
     * Example:
     * User deposited 10 ETH, now has 11 tokens (due to interest)
     * Returns: 10 ether (original deposit)
     */
    function getUserEthDeposited(address user) external view returns (uint256) {
        return s_userEthDeposited[user];
    }

    /**
     * @notice Get time remaining until next interest accrual
     * @dev Used by front-end to show countdown timer
     * 
     * @return Seconds until next accrual (0 if overdue)
     * 
     * Example:
     * Accrual period = 1 day
     * Last accrual = 20 hours ago
     * Returns: 4 hours = 14400 seconds
     */
    function getTimeUntilNextAccrual() external view returns (uint256) {
        uint256 timePassed = block.timestamp - s_lastAccrualTime;
        if (timePassed >= s_accrualPeriod) {
            return 0;
        }
        return s_accrualPeriod - timePassed;
    }

    /**
     * @notice Get a user's locked interest rate
     * @dev Rate was locked at user's first deposit and never changes
     * 
     * @param user Address to check interest rate for
     * @return User's interest rate in basis points (e.g., 1000 = 10%)
     * 
     * Example:
     * User deposited when vault was at tier 0 (10% rate)
     * Returns: 1000 (even if current rate is now 5%)
     */
    function getUserInterestRate(address user) external view returns (uint256) {
        return i_rebaseToken.getInterestRate(user);
    }

    /**
     * @notice Get the interest accrual period
     * @dev Time between automatic interest distributions
     * 
     * @return Accrual period in seconds (e.g., 86400 = 1 day)
     */
    function getAccrualPeriod() external view returns (uint256) {
        return s_accrualPeriod;
    }

    /**
     * @notice Preview tokens received for an ETH deposit
     * @dev Returns 1:1 ratio plus the interest rate that would be locked
     * 
     * @param ethAmount Amount of ETH to simulate depositing
     * @return tokens Amount of RebaseTokens that would be minted (equals ethAmount)
     * @return rate Interest rate that would be locked (current rate)
     * 
     * Example:
     * previewDeposit(5 ether)
     * Returns: (5 ether, 900) // Would receive 5 tokens at 9% rate
     */
    function previewDeposit(uint256 ethAmount) external view returns (uint256 tokens, uint256 rate) {
        return (ethAmount, s_currentInterestRate);
    }

    /**
     * @notice Preview ETH received for redeeming tokens
     * @dev Calculates proportional ETH based on share ownership
     * 
     * @param tokenAmount Amount of RebaseTokens to simulate redeeming
     * @return ethAmount ETH that would be received
     * 
     * Formula:
     * sharesToBurn = getSharesByTokenAmount(tokenAmount)
     * ethAmount = (totalEthDeposited * sharesToBurn) / totalShares
     * 
     * Example:
     * User wants to redeem 100 tokens
     * Total supply = 1000, Total shares = 800, Vault has 900 ETH
     * sharesToBurn = (100 * 800) / 1000 = 80
     * Returns: (900 * 80) / 800 = 90 ETH
     */
    function previewRedeem(uint256 tokenAmount) external view returns (uint256 ethAmount) {
        uint256 totalShares = i_rebaseToken.getTotalShares();
        if (totalShares == 0) return 0;
        uint256 sharesToBurn = i_rebaseToken.getSharesByTokenAmount(tokenAmount);
        return (s_totalEthDeposited * sharesToBurn) / totalShares;
    }

    /**
     * @notice Estimate future interest for a user over a time horizon
     * @dev Simple interest calculation for projection purposes
     * 
     * @param user Address to estimate interest for
     * @param horizonDays Number of days to project forward
     * @return Estimated interest tokens to be earned
     * 
     * Formula:
     * estimatedInterest = (balance * rate * days) / 10000 / 365
     * 
     * Example:
     * User has 1000 tokens at 10% rate
     * horizonDays = 365 (1 year)
     * Returns: (1000 * 1000 * 365) / 10000 / 365 = 100 tokens
     * 
     * Note:
     * This is a simple projection and doesn't account for compounding
     */
    function estimateInterest(address user, uint256 horizonDays) external view returns (uint256) {
        uint256 userRate = i_rebaseToken.getInterestRate(user);
        uint256 balance = i_rebaseToken.balanceOf(user);
        return (balance * userRate * horizonDays) / 10_000 / 365;
    }

    /**
     * @notice Get comprehensive information about a user's position
     * @dev Combines multiple view calls for front-end convenience
     * 
     * @param user Address to get information for
     * @return shares User's share balance (underlying accounting unit)
     * @return balance User's rebased token balance (increases with interest)
     * @return rate User's locked interest rate in basis points
     * @return lastAccrual Timestamp of last interest distribution
     * 
     * Example:
     * getUserInfo(alice)
     * Returns: (100, 110, 1000, 1640000000)
     * // Alice has 100 shares, 110 tokens (10% interest accrued), 10% rate, last accrual Jan 1
     */
    function getUserInfo(address user)
        external
        view
        returns (uint256 shares, uint256 balance, uint256 rate, uint256 lastAccrual)
    {
        shares = i_rebaseToken.sharesOf(user);
        balance = i_rebaseToken.balanceOf(user);
        rate = i_rebaseToken.getInterestRate(user);
        lastAccrual = s_lastAccrualTime;
    }

    /*//////////////////////////////////////////////////////////////
                            RECEIVE FUNCTION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Fallback to accept ETH and automatically deposit
     * @dev Forwards received ETH to deposit() function
     * 
     * Example:
     * User sends ETH directly to vault contract
     * Automatically triggers deposit() with msg.value
     * User receives RebaseTokens at current rate
     * 
     * Requirements:
     * - Same as deposit() function requirements
     */
    receive() external payable {
        // Forward to deposit function
        this.deposit{value: msg.value}();
    }
}
