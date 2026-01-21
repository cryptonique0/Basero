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
    
    event Deposited(address indexed user, uint256 amount, uint256 tokens, uint256 interestRate);
    event Withdrawn(address indexed user, uint256 amount, uint256 tokens);
    event InterestAccrued(uint256 amount, uint256 timestamp);
    event ConfigUpdated(string parameter, uint256 newValue);
    event Upgraded(address indexed implementation, uint256 version);
    
    // ============= Errors =============
    
    error ZeroAmount();
    error InsufficientBalance();
    error TransferFailed();
    error TooSoon();
    error ExceedsCap();
    error InvalidConfig();
    
    // ============= Initialization =============
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    /**
     * @dev Initialize the upgradeable vault
     * @param rebaseToken_ Address of rebase token
     * @param owner_ Initial owner
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
    
    function _authorizeUpgrade(address newImplementation) 
        internal 
        override 
        onlyOwner 
    {
        emit Upgraded(newImplementation, getVersion());
    }
    
    function getVersion() public pure returns (uint256) {
        return 1;
    }
    
    // ============= Deposit & Withdraw =============
    
    /**
     * @dev Deposit ETH and mint rebase tokens
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
     * @dev Withdraw ETH by burning tokens
     * @param amount Amount to withdraw
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
     * @dev Calculate current interest rate based on total deposited
     * @return Current interest rate in basis points
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
     * @dev Accrue interest (rebase supply)
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
     * @dev Calculate average interest rate (simplified)
     * @return Average rate in basis points
     */
    function _calculateAverageRate() internal view returns (uint256) {
        // Simplified: use current rate
        return getCurrentInterestRate();
    }
    
    // ============= Configuration =============
    
    function setBaseInterestRate(uint256 newRate) external onlyOwner {
        if (newRate == 0 || newRate > 10000) revert InvalidConfig();
        baseInterestRate = newRate;
        emit ConfigUpdated("baseInterestRate", newRate);
    }
    
    function setRateDecrement(uint256 newDecrement) external onlyOwner {
        if (newDecrement > 1000) revert InvalidConfig();
        rateDecrement = newDecrement;
        emit ConfigUpdated("rateDecrement", newDecrement);
    }
    
    function setDecrementThreshold(uint256 newThreshold) external onlyOwner {
        if (newThreshold == 0) revert InvalidConfig();
        decrementThreshold = newThreshold;
        emit ConfigUpdated("decrementThreshold", newThreshold);
    }
    
    function setMinimumRate(uint256 newMin) external onlyOwner {
        if (newMin == 0 || newMin > baseInterestRate) revert InvalidConfig();
        minimumRate = newMin;
        emit ConfigUpdated("minimumRate", newMin);
    }
    
    function setAccrualPeriod(uint256 newPeriod) external onlyOwner {
        if (newPeriod < 1 hours || newPeriod > 30 days) revert InvalidConfig();
        accrualPeriod = newPeriod;
        emit ConfigUpdated("accrualPeriod", newPeriod);
    }
    
    function setDailyAccrualCap(uint256 newCap) external onlyOwner {
        if (newCap == 0) revert InvalidConfig();
        dailyAccrualCap = newCap;
        emit ConfigUpdated("dailyAccrualCap", newCap);
    }
    
    // ============= Emergency =============
    
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }
    
    // ============= Storage Validation =============
    
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
