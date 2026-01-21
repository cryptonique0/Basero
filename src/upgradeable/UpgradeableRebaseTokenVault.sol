// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {UpgradeableRebaseToken} from "./UpgradeableRebaseToken.sol";

/**
 * @title UpgradeableRebaseTokenVault
 * @dev UUPS upgradeable vault for ETH deposits with rebase token minting
 * @notice Includes discrete interest rate system and upgrade safety
 */
contract UpgradeableRebaseTokenVault is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    // ============= Storage Layout V1 =============
    
    UpgradeableRebaseToken public rebaseToken;
    
    uint256 public totalDeposited;
    uint256 public lastAccrualTime;
    uint256 public accrualPeriod;
    uint256 public dailyAccrualCap;
    
    uint256 public baseInterestRate;
    uint256 public rateDecrement;
    uint256 public decrementThreshold;
    uint256 public minimumRate;
    
    mapping(address => uint256) public userDeposits;
    mapping(address => uint256) public userInterestRates;
    mapping(address => uint256) public lastDepositTime;
    
    // ============= Storage Gap (40 slots) =============
    uint256[40] private __gap;
    
    // ============= Events =============
    
    /// @notice Emitted when user deposits ETH and receives rebase tokens
    /// @param user Address of depositor
    /// @param amount ETH amount deposited (in wei)
    /// @param tokens Rebase tokens minted (equal to amount)
    /// @param interestRate Interest rate assigned at deposit time (basis points)
    event Deposited(address indexed user, uint256 amount, uint256 tokens, uint256 interestRate);
    
    /// @notice Emitted when user withdraws ETH by burning rebase tokens
    /// @param user Address of withdrawer
    /// @param amount ETH amount withdrawn (in wei)
    /// @param tokens Rebase tokens burned (equal to amount)
    event Withdrawn(address indexed user, uint256 amount, uint256 tokens);
    
    /// @notice Emitted when interest is accrued (supply rebased)
    /// @param amount Interest amount added to total supply
    /// @param timestamp Block timestamp of accrual
    event InterestAccrued(uint256 amount, uint256 timestamp);
    
    /// @notice Emitted when configuration parameter is updated
    /// @param parameter Name of parameter (e.g., "baseInterestRate")
    /// @param newValue New value in appropriate units
    event ConfigUpdated(string parameter, uint256 newValue);
    
    /// @notice Emitted when vault is upgraded to new implementation
    /// @param implementation Address of new implementation contract
    /// @param version Version number before upgrade
    event Upgraded(address indexed implementation, uint256 version);
    
    // ============= Errors =============
    
    /// @notice Thrown when deposit/withdraw amount is zero
    error ZeroAmount();
    
    /// @notice Thrown when user tries to withdraw more than deposited
    error InsufficientBalance();
    
    /// @notice Thrown when ETH transfer fails
    error TransferFailed();
    
    /// @notice Thrown when accrueInterest called before accrualPeriod elapsed
    error TooSoon();
    
    /// @notice Thrown when interest accrual exceeds dailyAccrualCap
    error ExceedsCap();
    
    /// @notice Thrown when configuration value is invalid
    error InvalidConfig();
    
    // ============= Initialization =============
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    /**
     * @notice Initialize the upgradeable vault (replaces constructor)
     * @dev Sets up ownership, UUPS, pausability, and reentrancy protection
     * @dev Configures default interest rate system: 10% base, decreasing to 2% minimum
     * @param rebaseToken_ Address of UpgradeableRebaseToken (cannot be zero)
     * @param owner_ Address that will own vault and control upgrades
     * @custom:security Must be called atomically with proxy deployment
     * @custom:gas ~220k gas for full initialization
     * @custom:config Base rate: 10%, Decrement: 1% per 10 ETH, Min: 2%, Accrual: daily
     */
    function initialize(
        address rebaseToken_,
        address owner_
    ) public initializer {
        if (rebaseToken_ == address(0) || owner_ == address(0)) revert InvalidConfig();
        
        __Ownable_init(owner_);
        __UUPSUpgradeable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        
        rebaseToken = UpgradeableRebaseToken(rebaseToken_);
        
        // Default configuration
        baseInterestRate = 1000; // 10%
        rateDecrement = 100;     // 1% decrement
        decrementThreshold = 10 ether; // Every 10 ETH
        minimumRate = 200;       // 2% minimum
        
        accrualPeriod = 1 days;
        dailyAccrualCap = 1000 ether;
        lastAccrualTime = block.timestamp;
    }
    
    // ============= Upgrade Authorization =============
    
    /**
     * @notice Internal function to authorize contract upgrades
     * @dev Only callable by contract owner. Called by upgradeToAndCall()
     * @param newImplementation Address of new implementation contract
     * @custom:security Critical function - only owner can upgrade
     * @custom:gas ~5k gas for authorization check
     */
    function _authorizeUpgrade(address newImplementation) 
        internal 
        override 
        onlyOwner 
    {
        emit Upgraded(newImplementation, getVersion());
    }
    
    /**
     * @notice Get the current contract version
     * @dev Returns version before upgrade. Increment in new implementations
     * @return version Current version number (1 for initial deployment)
     * @custom:gas Pure function - no gas cost when called externally
     */
    function getVersion() public pure returns (uint256) {
        return 1;
    }
    
    // ============= Deposit & Withdraw =============
    
    /**
     * @notice Deposit ETH and receive rebase tokens (1:1 ratio)
     * @dev Mints tokens with current interest rate. Rate decreases as totalDeposited increases
     * @dev Pausable and protected against reentrancy
     * @custom:gas ~87k gas (includes token minting and storage updates)
     * @custom:emits Deposited
     * @custom:state Updates userDeposits, userInterestRates, lastDepositTime, totalDeposited
     * @custom:example Deposit 10 ETH → Receive 10 REBASE tokens at current rate (e.g., 8%)
     */
    function deposit() external payable whenNotPaused nonReentrant {
        if (msg.value == 0) revert ZeroAmount();
        
        uint256 currentRate = getCurrentInterestRate();
        uint256 tokensToMint = msg.value;
        
        userDeposits[msg.sender] += msg.value;
        userInterestRates[msg.sender] = currentRate;
        lastDepositTime[msg.sender] = block.timestamp;
        totalDeposited += msg.value;
        
        rebaseToken.mint(msg.sender, tokensToMint, currentRate);
        
        emit Deposited(msg.sender, msg.value, tokensToMint, currentRate);
    }
    
    /**
     * @notice Withdraw ETH by burning rebase tokens (1:1 ratio)
     * @dev Burns tokens and transfers ETH back to user. Must have sufficient deposit
     * @dev Pausable and protected against reentrancy
     * @param amount ETH amount to withdraw (must be ≤ user's deposit)
     * @custom:gas ~80k gas (includes token burning and ETH transfer)
     * @custom:emits Withdrawn
     * @custom:state Updates userDeposits, totalDeposited
     * @custom:security Uses call{value} for ETH transfer, reverts if fails
     */
    function withdraw(uint256 amount) external whenNotPaused nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (userDeposits[msg.sender] < amount) revert InsufficientBalance();
        
        uint256 tokensToBurn = amount;
        
        userDeposits[msg.sender] -= amount;
        totalDeposited -= amount;
        
        rebaseToken.burn(msg.sender, tokensToBurn);
        
        (bool success, ) = msg.sender.call{value: amount}("");
        if (!success) revert TransferFailed();
        
        emit Withdrawn(msg.sender, amount, tokensToBurn);
    }
    
    // ============= Interest Rate System =============
    
    /**
     * @notice Calculate current interest rate based on total deposited
     * @dev Rate decreases linearly: baseRate - (totalDeposited / threshold) * decrement
     * @dev Floors at minimumRate to ensure positive interest
     * @return Current interest rate in basis points (e.g., 1000 = 10%, 200 = 2%)
     * @custom:gas ~3k gas (2 divisions, 2 multiplications, comparison)
     * @custom:example totalDeposited=50 ETH: 1000 - (50/10)*100 = 500 (5%)
     */
    function getCurrentInterestRate() public view returns (uint256) {
        uint256 decrements = totalDeposited / decrementThreshold;
        uint256 totalDecrement = decrements * rateDecrement;
        
        if (totalDecrement >= baseInterestRate - minimumRate) {
            return minimumRate;
        }
        
        return baseInterestRate - totalDecrement;
    }
    
    /**
     * @notice Accrue interest by rebasing token supply upward
     * @dev Callable by anyone after accrualPeriod has elapsed. Applies dailyAccrualCap
     * @dev Calculates interest based on average rate, then rebases total supply
     * @custom:gas ~45k gas (includes rebase call to token contract)
     * @custom:emits InterestAccrued
     * @custom:security Pausable to prevent accrual during emergencies
     * @custom:timing Must wait accrualPeriod (default 1 day) between accruals
     * @custom:example 1000 supply at 10% rate = 100 interest (capped at dailyAccrualCap)
     */
    function accrueInterest() external whenNotPaused {
        if (block.timestamp < lastAccrualTime + accrualPeriod) {
            revert TooSoon();
        }
        
        uint256 currentSupply = rebaseToken.totalSupply();
        if (currentSupply == 0) return;
        
        // Calculate average interest rate weighted by balance
        uint256 averageRate = _calculateAverageRate();
        
        // Calculate interest amount
        uint256 interestAmount = (currentSupply * averageRate) / 10000;
        
        // Apply daily cap
        if (interestAmount > dailyAccrualCap) {
            interestAmount = dailyAccrualCap;
        }
        
        // Rebase supply
        rebaseToken.rebase(interestAmount, true);
        
        lastAccrualTime = block.timestamp;
        
        emit InterestAccrued(interestAmount, block.timestamp);
    }
    
    /**
     * @notice Calculate average interest rate across all users
     * @dev Simplified implementation: returns current interest rate
     * @dev Future versions could implement weighted average by balance
     * @return averageRate Average rate in basis points
     * @custom:gas ~3k gas (calls getCurrentInterestRate)
     */
    function _calculateAverageRate() internal view returns (uint256) {
        // Simplified: use current rate
        return getCurrentInterestRate();
    }
    
    // ============= Configuration =============
    
    /**
     * @notice Set the base interest rate (starting rate at 0 deposits)
     * @dev Must be between 0 and 10000 basis points (0-100%)
     * @param newRate New base rate in basis points (e.g., 1000 = 10%)
     * @custom:gas ~30k gas (SSTORE + event)
     * @custom:emits ConfigUpdated
     * @custom:security Owner-only to prevent rate manipulation
     */
    function setBaseInterestRate(uint256 newRate) external onlyOwner {
        if (newRate == 0 || newRate > 10000) revert InvalidConfig();
        baseInterestRate = newRate;
        emit ConfigUpdated("baseInterestRate", newRate);
    }
    
    /**
     * @notice Set the rate decrement per threshold
     * @dev Amount to decrease rate for each decrementThreshold deposits
     * @param newDecrement Decrement amount in basis points (max 1000 = 10%)
     * @custom:gas ~30k gas (SSTORE + event)
     * @custom:emits ConfigUpdated
     */
    function setRateDecrement(uint256 newDecrement) external onlyOwner {
        if (newDecrement > 1000) revert InvalidConfig();
        rateDecrement = newDecrement;
        emit ConfigUpdated("rateDecrement", newDecrement);
    }
    
    /**
     * @notice Set the threshold for rate decrements
     * @dev Interest rate decreases by rateDecrement for each threshold of deposits
     * @param newThreshold Threshold amount in wei (e.g., 10 ether)
     * @custom:gas ~30k gas (SSTORE + event)
     * @custom:emits ConfigUpdated
     * @custom:example threshold=10 ether means rate drops every 10 ETH deposited
     */
    function setDecrementThreshold(uint256 newThreshold) external onlyOwner {
        if (newThreshold == 0) revert InvalidConfig();
        decrementThreshold = newThreshold;
        emit ConfigUpdated("decrementThreshold", newThreshold);
    }
    
    /**
     * @notice Set the minimum interest rate floor
     * @dev Rate cannot decrease below this value regardless of deposits
     * @param newMin Minimum rate in basis points (must be ≤ baseInterestRate)
     * @custom:gas ~30k gas (SSTORE + event)
     * @custom:emits ConfigUpdated
     */
    function setMinimumRate(uint256 newMin) external onlyOwner {
        if (newMin == 0 || newMin > baseInterestRate) revert InvalidConfig();
        minimumRate = newMin;
        emit ConfigUpdated("minimumRate", newMin);
    }
    
    /**
     * @notice Set the time period between interest accruals
     * @dev Must be between 1 hour and 30 days for safety
     * @param newPeriod Time in seconds (e.g., 1 days = 86400)
     * @custom:gas ~30k gas (SSTORE + event)
     * @custom:emits ConfigUpdated
     * @custom:example 1 days = accrual happens daily, 1 hours = hourly
     */
    function setAccrualPeriod(uint256 newPeriod) external onlyOwner {
        if (newPeriod < 1 hours || newPeriod > 30 days) revert InvalidConfig();
        accrualPeriod = newPeriod;
        emit ConfigUpdated("accrualPeriod", newPeriod);
    }
    
    /**
     * @notice Set the maximum interest that can accrue in one period
     * @dev Prevents excessive supply inflation in single accrual
     * @param newCap Maximum interest in tokens (e.g., 1000 ether)
     * @custom:gas ~30k gas (SSTORE + event)
     * @custom:emits ConfigUpdated
     */
    function setDailyAccrualCap(uint256 newCap) external onlyOwner {
        if (newCap == 0) revert InvalidConfig();
        dailyAccrualCap = newCap;
        emit ConfigUpdated("dailyAccrualCap", newCap);
    }
    
    // ============= Emergency =============
    
    /**
     * @notice Pause all vault operations (deposits, withdrawals, interest accrual)
     * @dev Emergency function to halt operations during incidents
     * @custom:gas ~30k gas
     * @custom:security Owner-only, use during security incidents or upgrades
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @notice Unpause vault operations
     * @dev Resumes normal operations after pause
     * @custom:gas ~30k gas
     * @custom:security Owner-only, ensure issue is resolved before unpausing
     */
    function unpause() external onlyOwner {
        _unpause();
    }
    
    // ============= Storage Validation =============
    
    /**
     * @notice Get a hash of the current storage layout for upgrade validation
     * @dev Used by StorageLayoutValidator to detect storage collisions before upgrades
     * @dev Hash includes all storage variable names and gap size
     * @return Hash of storage layout (keccak256 of variable names)
     * @custom:gas Pure function - no gas cost externally
     * @custom:upgrade Critical for safe upgrades - verify hash before upgrading
     */
    function getStorageLayoutHash() external pure returns (bytes32) {
        return keccak256(abi.encodePacked(
            "v1",
            "rebaseToken", "totalDeposited", "lastAccrualTime",
            "accrualPeriod", "dailyAccrualCap",
            "baseInterestRate", "rateDecrement", "decrementThreshold", "minimumRate",
            "userDeposits", "userInterestRates", "lastDepositTime",
            "gap[40]"
        ));
    }
    
    function getStorageSlots() external pure returns (uint256) {
        // 1 (token) + 4 (config) + 4 (rates) + 3 (mappings) + 40 (gap) = 52 slots
        return 52;
    }
    
    // ============= View Functions =============
    
    function getUserInfo(address user) 
        external 
        view 
        returns (
            uint256 deposited,
            uint256 interestRate,
            uint256 tokenBalance,
            uint256 lastDeposit
        ) 
    {
        return (
            userDeposits[user],
            userInterestRates[user],
            rebaseToken.balanceOf(user),
            lastDepositTime[user]
        );
    }
    
    receive() external payable {
        // Allow receiving ETH
    }
}
