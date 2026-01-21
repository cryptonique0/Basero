// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {RebaseToken} from "./RebaseToken.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title RebaseTokenVault
 * @dev Vault contract where users deposit ETH to receive RebaseTokens
 * @notice Interest rates decrease discretely over time and early depositors get higher rates
 */
contract RebaseTokenVault is Ownable, Pausable, ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    RebaseToken public immutable i_rebaseToken;

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

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error InsufficientDeposit();
    error InsufficientBalance();
    error TransferFailed();
    error NoTokensToRedeem();
    error DepositsArePaused();
    error RedeemsArePaused();
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
     * @dev Constructor
     * @param rebaseToken Address of the RebaseToken contract
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
                        PAUSE / GUARDIAN LOGIC
    //////////////////////////////////////////////////////////////*/

    function pauseDeposits() external onlyOwner {
        s_depositsPaused = true;
        emit DepositsPaused(msg.sender);
    }

    function unpauseDeposits() external onlyOwner {
        s_depositsPaused = false;
        emit DepositsUnpaused(msg.sender);
    }

    function pauseRedeems() external onlyOwner {
        s_redeemsPaused = true;
        emit RedeemsPaused(msg.sender);
    }

    function unpauseRedeems() external onlyOwner {
        s_redeemsPaused = false;
        emit RedeemsUnpaused(msg.sender);
    }

    function pauseAll() external onlyOwner {
        _pause();
    }

    function unpauseAll() external onlyOwner {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    function setAllowlistStatus(bool enabled) external onlyOwner {
        s_allowlistEnabled = enabled;
        emit AllowlistStatusChanged(enabled);
    }

    function setAllowlist(address account, bool allowed) external onlyOwner {
        s_allowlist[account] = allowed;
        emit AllowlistUpdated(account, allowed);
    }

    function setDepositCaps(uint256 maxPerAddress, uint256 maxTotal) external onlyOwner {
        if (maxPerAddress == 0 || maxTotal == 0) revert AmountZero();
        s_maxDepositPerAddress = maxPerAddress;
        s_maxTotalDeposits = maxTotal;
        emit DepositCapsUpdated(maxPerAddress, maxTotal);
    }

    function setMinDeposit(uint256 minDeposit) external onlyOwner {
        s_minDeposit = minDeposit;
        emit MinDepositUpdated(minDeposit);
    }

    function setFeeConfig(address recipient, uint256 protocolFeeBps) external onlyOwner {
        if (recipient == address(0)) revert ZeroAddressNotAllowed();
        if (protocolFeeBps > 10_000) revert InvalidProtocolFee();
        s_feeRecipient = recipient;
        s_protocolFeeBps = protocolFeeBps;
        emit FeeConfigUpdated(recipient, protocolFeeBps);
    }

    function setAccrualConfig(uint256 accrualPeriod, uint256 maxDailyAccrualBps) external onlyOwner {
        if (accrualPeriod < MIN_ACCRUAL_PERIOD || accrualPeriod > MAX_ACCRUAL_PERIOD) {
            revert InvalidAccrualPeriod();
        }
        s_accrualPeriod = accrualPeriod;
        s_maxDailyAccrualBps = maxDailyAccrualBps;
        emit AccrualConfigUpdated(accrualPeriod, maxDailyAccrualBps);
    }

    function emergencyWithdrawETH(address to, uint256 amount) external onlyOwner nonReentrant {
        if (to == address(0)) revert ZeroAddressNotAllowed();
        uint256 value = amount == 0 ? address(this).balance : amount;
        if (value == 0) revert AmountZero();
        (bool success,) = to.call{value: value}("");
        if (!success) revert TransferFailed();
        emit EmergencyEthWithdrawn(to, value);
    }

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
     * @dev Deposit ETH to receive RebaseTokens
     * @notice Users receive tokens at the current interest rate
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
     * @dev Redeem RebaseTokens for ETH
     * @param tokenAmount Amount of tokens to redeem
     * @notice Users can only redeem on L1
     */
    function redeem(uint256 tokenAmount) external {
        redeemWithMinOut(tokenAmount, 0);
    }

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
     * @dev Accrue interest to all token holders
     * @notice Called automatically on deposit and redeem
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
     * @dev Update interest rate based on total deposits
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
     * @dev Manually trigger interest accrual (public function)
     */
    function accrueInterest() external {
        _accrueInterest();
    }

    /**
     * @dev Chainlink Automation-compatible check
     */
    function checkUpkeep(bytes calldata) external view returns (bool upkeepNeeded, bytes memory performData) {
        upkeepNeeded = block.timestamp - s_lastAccrualTime >= s_accrualPeriod;
        performData = "";
    }

    /**
     * @dev Chainlink Automation-compatible perform
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
     * @dev Get current interest rate
     */
    function getCurrentInterestRate() external view returns (uint256) {
        return s_currentInterestRate;
    }

    /**
     * @dev Get total ETH deposited in the vault
     */
    function getTotalEthDeposited() external view returns (uint256) {
        return s_totalEthDeposited;
    }

    /**
     * @dev Get user's ETH deposit amount
     */
    function getUserEthDeposited(address user) external view returns (uint256) {
        return s_userEthDeposited[user];
    }

    /**
     * @dev Get time until next interest accrual
     */
    function getTimeUntilNextAccrual() external view returns (uint256) {
        uint256 timePassed = block.timestamp - s_lastAccrualTime;
        if (timePassed >= s_accrualPeriod) {
            return 0;
        }
        return s_accrualPeriod - timePassed;
    }

    /**
     * @dev Get user's interest rate
     */
    function getUserInterestRate(address user) external view returns (uint256) {
        return i_rebaseToken.getInterestRate(user);
    }

    function getAccrualPeriod() external view returns (uint256) {
        return s_accrualPeriod;
    }

    function previewDeposit(uint256 ethAmount) external view returns (uint256 tokens, uint256 rate) {
        return (ethAmount, s_currentInterestRate);
    }

    function previewRedeem(uint256 tokenAmount) external view returns (uint256 ethAmount) {
        uint256 totalShares = i_rebaseToken.getTotalShares();
        if (totalShares == 0) return 0;
        uint256 sharesToBurn = i_rebaseToken.getSharesByTokenAmount(tokenAmount);
        return (s_totalEthDeposited * sharesToBurn) / totalShares;
    }

    function estimateInterest(address user, uint256 horizonDays) external view returns (uint256) {
        uint256 userRate = i_rebaseToken.getInterestRate(user);
        uint256 balance = i_rebaseToken.balanceOf(user);
        return (balance * userRate * horizonDays) / 10_000 / 365;
    }

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
     * @dev Allow contract to receive ETH
     */
    receive() external payable {
        // Forward to deposit function
        this.deposit{value: msg.value}();
    }
}
