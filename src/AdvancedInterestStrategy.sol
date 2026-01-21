// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {RebaseToken} from "./RebaseToken.sol";
import {RebaseTokenVault} from "./RebaseTokenVault.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title AdvancedInterestStrategy
 * @dev Advanced interest rate mechanics with dynamic rates, tiers, locking, and performance fees
 * @notice Provides:
 *   - Variable rates based on vault utilization
 *   - Tier-based rewards (higher deposits = higher rates)
 *   - Bonus accrual for locked deposits
 *   - Performance fees on excess returns
 */
contract AdvancedInterestStrategy is Ownable {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    RebaseTokenVault public vault;

    // Utilization-based rate configuration
    uint256 private s_utilizationKink; // 80% = 8000 bps
    uint256 private s_rateAtZero; // Rate at 0% utilization (bps)
    uint256 private s_rateAtKink; // Rate at kink utilization (bps)
    uint256 private s_rateAtMax; // Rate at 100% utilization (bps)

    // Tier-based rewards
    struct TierConfig {
        uint256 minDeposit; // Minimum deposit to reach tier
        uint256 bonusRateBps; // Bonus rate in basis points
    }

    TierConfig[] private s_tiers;

    // Lock mechanism
    struct LockConfig {
        uint256 lockDuration; // Seconds user must lock
        uint256 unlockBonus; // Bonus rate for locked deposits (bps)
    }

    mapping(address => LockConfig) private s_lockConfigs; // Per-user lock settings

    struct UserLock {
        uint256 lockedAmount;
        uint256 lockEndTime;
        uint256 lockDuration;
    }

    mapping(address => UserLock) private s_userLocks;

    // Performance fee configuration
    uint256 private s_targetAnnualReturnBps; // Target return (e.g., 500 bps = 5%)
    uint256 private s_performanceFeeBps; // Fee on excess (e.g., 200 bps = 20% of excess)
    address private s_performanceFeeRecipient;

    // Tracking for performance
    mapping(address => uint256) private s_lastPerformanceCheck; // Per-user timestamp
    mapping(address => uint256) private s_accumulatedReturns; // Per-user accumulated gains

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event UtilizationRatesUpdated(uint256 kink, uint256 rateAtZero, uint256 rateAtKink, uint256 rateAtMax);
    event TierAdded(uint256 indexed tierIndex, uint256 minDeposit, uint256 bonusRate);
    event TierRemoved(uint256 indexed tierIndex);
    event LockCreated(address indexed user, uint256 amount, uint256 duration, uint256 unlockBonus);
    event LockExtended(address indexed user, uint256 newEndTime);
    event LockUnlocked(address indexed user, uint256 amount);
    event PerformanceFeeConfigUpdated(uint256 targetReturn, uint256 performanceFee);
    event PerformanceFeeCharged(address indexed user, uint256 excessReturns, uint256 fee);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidUtilizationRate();
    error InvalidTierConfiguration();
    error TierNotFound();
    error InvalidLockDuration();
    error DepositsNotLocked();
    error LockNotExpired();
    error InvalidPerformanceFee();
    error InvalidVaultAddress();

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _vault) Ownable(msg.sender) {
        if (_vault == address(0)) revert InvalidVaultAddress();
        vault = RebaseTokenVault(_vault);

        // Default utilization-based rates
        // At 0% utilization: 2% (200 bps)
        // At 80% utilization: 8% (800 bps)
        // At 100% utilization: 12% (1200 bps)
        s_utilizationKink = 8000; // 80%
        s_rateAtZero = 200; // 2%
        s_rateAtKink = 800; // 8%
        s_rateAtMax = 1200; // 12%

        // Default performance fee
        s_targetAnnualReturnBps = 500; // 5% target
        s_performanceFeeBps = 2000; // 20% of excess
        s_performanceFeeRecipient = msg.sender;
    }

    /*//////////////////////////////////////////////////////////////
                  UTILIZATION-BASED RATE CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set utilization-based rate curve
     * @dev Uses linear interpolation between kink and max
     * @param kink Utilization percentage at kink (e.g., 8000 = 80%)
     * @param rateAtZero Rate at 0% utilization (bps)
     * @param rateAtKink Rate at kink (bps)
     * @param rateAtMax Rate at 100% utilization (bps)
     */
    function setUtilizationRates(
        uint256 kink,
        uint256 rateAtZero,
        uint256 rateAtKink,
        uint256 rateAtMax
    ) external onlyOwner {
        if (kink > 10000 || kink < 1000) revert InvalidUtilizationRate(); // 10%-100%
        if (rateAtZero >= rateAtKink) revert InvalidUtilizationRate();
        if (rateAtKink >= rateAtMax) revert InvalidUtilizationRate();

        s_utilizationKink = kink;
        s_rateAtZero = rateAtZero;
        s_rateAtKink = rateAtKink;
        s_rateAtMax = rateAtMax;

        emit UtilizationRatesUpdated(kink, rateAtZero, rateAtKink, rateAtMax);
    }

    /**
     * @notice Calculate interest rate based on utilization
     * @dev Linear interpolation between kink and max rates
     * @param utilizationBps Current utilization in basis points
     * @return Rate in basis points
     */
    function calculateUtilizationRate(uint256 utilizationBps) public view returns (uint256) {
        if (utilizationBps == 0) {
            return s_rateAtZero;
        }

        if (utilizationBps >= 10000) {
            return s_rateAtMax;
        }

        if (utilizationBps < s_utilizationKink) {
            // Linear from zero to kink
            uint256 slope = (s_rateAtKink - s_rateAtZero) * 10000 / s_utilizationKink;
            return s_rateAtZero + (utilizationBps * slope / 10000);
        } else {
            // Linear from kink to max
            uint256 utilizationAboveKink = utilizationBps - s_utilizationKink;
            uint256 utilizationRangeAboveKink = 10000 - s_utilizationKink;
            uint256 slope = (s_rateAtMax - s_rateAtKink) * 10000 / utilizationRangeAboveKink;
            return s_rateAtKink + (utilizationAboveKink * slope / 10000);
        }
    }

    /*//////////////////////////////////////////////////////////////
                         TIER-BASED REWARDS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Add a new deposit tier with bonus rates
     * @dev Tiers should be ordered by minDeposit ascending
     * @param minDeposit Minimum deposit to reach this tier
     * @param bonusRateBps Additional rate bonus for this tier (bps)
     */
    function addTier(uint256 minDeposit, uint256 bonusRateBps) external onlyOwner {
        if (bonusRateBps > 10000) revert InvalidTierConfiguration();

        // Verify ordering
        if (s_tiers.length > 0) {
            TierConfig storage lastTier = s_tiers[s_tiers.length - 1];
            if (minDeposit <= lastTier.minDeposit) revert InvalidTierConfiguration();
        }

        s_tiers.push(TierConfig({minDeposit: minDeposit, bonusRateBps: bonusRateBps}));

        emit TierAdded(s_tiers.length - 1, minDeposit, bonusRateBps);
    }

    /**
     * @notice Remove a tier (replaces with last tier, reduces length)
     * @param tierIndex Index of tier to remove
     */
    function removeTier(uint256 tierIndex) external onlyOwner {
        if (tierIndex >= s_tiers.length) revert TierNotFound();

        s_tiers[tierIndex] = s_tiers[s_tiers.length - 1];
        s_tiers.pop();

        emit TierRemoved(tierIndex);
    }

    /**
     * @notice Get tier bonus for a given deposit amount
     * @param depositAmount Amount being deposited
     * @return Bonus rate in basis points
     */
    function getTierBonus(uint256 depositAmount) public view returns (uint256) {
        uint256 maxBonus = 0;

        for (uint256 i = 0; i < s_tiers.length; i++) {
            if (depositAmount >= s_tiers[i].minDeposit) {
                maxBonus = s_tiers[i].bonusRateBps;
            } else {
                break;
            }
        }

        return maxBonus;
    }

    /**
     * @notice Get all tiers
     * @return Array of tier configurations
     */
    function getTiers() external view returns (TierConfig[] memory) {
        return s_tiers;
    }

    /*//////////////////////////////////////////////////////////////
                         LOCK MECHANISMS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Lock deposits for bonus rate
     * @param amount Amount to lock
     * @param duration Lock duration in seconds
     * @param unlockBonus Bonus rate for locked amount (bps)
     */
    function lockDeposit(address user, uint256 amount, uint256 duration, uint256 unlockBonus) external onlyOwner {
        if (duration < 1 weeks || duration > 4 * 365 days) revert InvalidLockDuration();
        if (unlockBonus > 10000) revert InvalidTierConfiguration();

        UserLock storage lock = s_userLocks[user];
        lock.lockedAmount = amount;
        lock.lockEndTime = block.timestamp + duration;
        lock.lockDuration = duration;

        s_lockConfigs[user] = LockConfig({lockDuration: duration, unlockBonus: unlockBonus});

        emit LockCreated(user, amount, duration, unlockBonus);
    }

    /**
     * @notice Extend an existing lock
     * @param user User with existing lock
     * @param additionalDuration Additional time to lock
     */
    function extendLock(address user, uint256 additionalDuration) external onlyOwner {
        UserLock storage lock = s_userLocks[user];
        if (lock.lockedAmount == 0) revert DepositsNotLocked();

        uint256 newDuration = (lock.lockEndTime - block.timestamp) + additionalDuration;
        if (newDuration > 4 * 365 days) revert InvalidLockDuration();

        lock.lockEndTime = block.timestamp + newDuration;
        lock.lockDuration = newDuration;

        emit LockExtended(user, lock.lockEndTime);
    }

    /**
     * @notice Unlock deposits (callable when lock expires)
     * @param user User with locked deposit
     */
    function unlockDeposit(address user) external onlyOwner {
        UserLock storage lock = s_userLocks[user];
        if (lock.lockedAmount == 0) revert DepositsNotLocked();
        if (block.timestamp < lock.lockEndTime) revert LockNotExpired();

        uint256 unlockedAmount = lock.lockedAmount;
        lock.lockedAmount = 0;
        lock.lockEndTime = 0;

        emit LockUnlocked(user, unlockedAmount);
    }

    /**
     * @notice Get lock status for user
     * @param user User to check
     * @return lockedAmount Amount locked
     * @return lockEndTime When lock expires
     * @return isLocked Whether deposits are currently locked
     */
    function getLockStatus(address user)
        external
        view
        returns (uint256 lockedAmount, uint256 lockEndTime, bool isLocked)
    {
        UserLock storage lock = s_userLocks[user];
        return (lock.lockedAmount, lock.lockEndTime, lock.lockedAmount > 0 && block.timestamp < lock.lockEndTime);
    }

    /**
     * @notice Get lock bonus for user
     * @param user User to check
     * @return Bonus rate in basis points (0 if not locked or expired)
     */
    function getLockBonus(address user) public view returns (uint256) {
        UserLock storage lock = s_userLocks[user];

        if (lock.lockedAmount == 0) return 0;
        if (block.timestamp >= lock.lockEndTime) return 0;

        return s_lockConfigs[user].unlockBonus;
    }

    /*//////////////////////////////////////////////////////////////
                        PERFORMANCE FEES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set performance fee configuration
     * @param targetReturnBps Target annual return (bps)
     * @param performanceFeeBps Fee on excess returns (bps)
     * @param feeRecipient Address to receive performance fees
     */
    function setPerformanceFeeConfig(uint256 targetReturnBps, uint256 performanceFeeBps, address feeRecipient)
        external
        onlyOwner
    {
        if (targetReturnBps > 10000) revert InvalidUtilizationRate();
        if (performanceFeeBps > 10000) revert InvalidPerformanceFee();

        s_targetAnnualReturnBps = targetReturnBps;
        s_performanceFeeBps = performanceFeeBps;
        s_performanceFeeRecipient = feeRecipient;

        emit PerformanceFeeConfigUpdated(targetReturnBps, performanceFeeBps);
    }

    /**
     * @notice Calculate performance fee on gains
     * @param userBalance Current user balance
     * @param originalDeposit Original deposit amount
     * @param elapsedSeconds Time since last check
     * @return excessReturns Returns above target
     * @return performanceFee Fee on excess returns
     */
    function calculatePerformanceFee(uint256 userBalance, uint256 originalDeposit, uint256 elapsedSeconds)
        public
        view
        returns (uint256 excessReturns, uint256 performanceFee)
    {
        if (userBalance <= originalDeposit) {
            return (0, 0);
        }

        uint256 gains = userBalance - originalDeposit;

        // Calculate target return for elapsed time
        // Target per year * (elapsed / 365 days)
        uint256 secondsPerYear = 365 days;
        uint256 targetReturnAmount = (originalDeposit * s_targetAnnualReturnBps * elapsedSeconds) / (secondsPerYear * 10000);

        // Excess is gains above target
        if (gains > targetReturnAmount) {
            excessReturns = gains - targetReturnAmount;
            performanceFee = (excessReturns * s_performanceFeeBps) / 10000;
        }

        return (excessReturns, performanceFee);
    }

    /**
     * @notice Record performance check for user
     * @param user User to record
     */
    function recordPerformanceCheck(address user) external onlyOwner {
        s_lastPerformanceCheck[user] = block.timestamp;
    }

    /**
     * @notice Get performance fee info for user
     * @param user User to check
     * @return targetReturn Target annual return (bps)
     * @return performanceFee Current performance fee rate (bps)
     * @return accumulatedReturns User's accumulated returns
     */
    function getPerformanceFeeInfo(address user)
        external
        view
        returns (uint256 targetReturn, uint256 performanceFee, uint256 accumulatedReturns)
    {
        return (s_targetAnnualReturnBps, s_performanceFeeBps, s_accumulatedReturns[user]);
    }

    /*//////////////////////////////////////////////////////////////
                      COMPOSITE RATE CALCULATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Calculate composite interest rate for a user
     * @dev Combines: utilization rate + tier bonus + lock bonus
     * @param userDeposit User's deposit amount
     * @param utilizationBps Current vault utilization
     * @return Total rate in basis points
     */
    function calculateUserRate(uint256 userDeposit, uint256 utilizationBps) external view returns (uint256) {
        // Base rate from utilization
        uint256 baseRate = calculateUtilizationRate(utilizationBps);

        // Add tier bonus
        uint256 tierBonus = getTierBonus(userDeposit);

        // Add lock bonus (if locked)
        uint256 lockBonus = 0; // Would need user address to check

        return baseRate + tierBonus + lockBonus;
    }

    /**
     * @notice Calculate composite rate with lock bonus
     * @param user User address (to check lock status)
     * @param userDeposit User's deposit amount
     * @param utilizationBps Current vault utilization
     * @return Total rate in basis points
     */
    function calculateUserRateWithLock(address user, uint256 userDeposit, uint256 utilizationBps)
        external
        view
        returns (uint256)
    {
        // Base rate from utilization
        uint256 baseRate = calculateUtilizationRate(utilizationBps);

        // Add tier bonus
        uint256 tierBonus = getTierBonus(userDeposit);

        // Add lock bonus
        uint256 lockBonus = getLockBonus(user);

        return baseRate + tierBonus + lockBonus;
    }

    /*//////////////////////////////////////////////////////////////
                           VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get utilization rate configuration
     * @return kink Utilization at kink (bps)
     * @return rateAtZero Rate at 0% (bps)
     * @return rateAtKink Rate at kink (bps)
     * @return rateAtMax Rate at 100% (bps)
     */
    function getUtilizationConfig()
        external
        view
        returns (uint256 kink, uint256 rateAtZero, uint256 rateAtKink, uint256 rateAtMax)
    {
        return (s_utilizationKink, s_rateAtZero, s_rateAtKink, s_rateAtMax);
    }

    /**
     * @notice Get number of tiers
     * @return Number of configured tiers
     */
    function getTierCount() external view returns (uint256) {
        return s_tiers.length;
    }

    /**
     * @notice Get specific tier
     * @param tierIndex Tier index
     * @return Tier configuration
     */
    function getTier(uint256 tierIndex) external view returns (TierConfig memory) {
        if (tierIndex >= s_tiers.length) revert TierNotFound();
        return s_tiers[tierIndex];
    }
}
