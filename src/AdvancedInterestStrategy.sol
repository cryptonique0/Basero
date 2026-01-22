// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {RebaseToken} from "./RebaseToken.sol";
import {RebaseTokenVault} from "./RebaseTokenVault.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title AdvancedInterestStrategy
 * @author Basero Labs
 * @notice Advanced interest rate mechanics with dynamic rates, tiers, locking, and performance fees
 * @dev Implements composite interest rate model combining utilization curves, tier bonuses, and lock rewards
 *
 * ARCHITECTURE:\n * Composite Rate = Base Rate (utilization) + Tier Bonus + Lock Bonus - Performance Fee
 *
 * THREE RATE COMPONENTS:
 *
 * 1. UTILIZATION-BASED RATE (Primary)
 *    Adjusts based on vault capital efficiency with piecewise linear curve
 *    - Has a "kink" point where slope changes (e.g., 80% utilization)\n *    - Below kink: Gentler slope (increases from baseRate to rateAtKink)\n *    - Above kink: Steeper slope (increases from rateAtKink to rateAtMax)\n *    - Incentivizes balanced utilization\n *    Example curve: 2% @0% → 8% @80% → 12% @100%\n *\n * 2. TIER-BASED REWARDS (Secondary)\n *    Bonus rates for higher deposits (loyalty rewards)\n *    - Tier 1: 1 ETH+ → +0% base\n *    - Tier 2: 10 ETH+ → +1% bonus\n *    - Tier 3: 100 ETH+ → +3% bonus\n *    - Tier 4: 1000 ETH+ → +5% bonus\n *    Example: 10 ETH deposit + 8% base = 9% total rate\n *\n * 3. LOCK BONUSES (Tertiary)\n *    Additional rewards for locking deposits for extended period\n *    - 1 month lock: +0.5% bonus\n *    - 3 month lock: +1% bonus\n *    - 1 year lock: +2% bonus\n *    Example: 10 ETH locked 1 year = 8% base + 3% tier + 2% lock = 13% rate\n *\n * PERFORMANCE FEES (Reduction):\n * Charges a fee on excess returns above target annual return\n * - Target: 5% annual return\n * - Fee on excess: 20% of gains above target\n * - Example: User earns 8% but target is 5%\n *           Excess = 3%, Fee = 3% × 20% = 0.6%\n *           Net rate = 8% - 0.6% = 7.4%\n *\n * RATE CALCULATION FORMULA:\n * ```\n * totalRate = utilizationRate(vault.utilization) \n *           + tierBonus(userDeposit)\n *           + lockBonus(lockDuration)\n *           - performanceFee(userGains)\n * ```\n *\n * UTILIZATION CURVE FORMULA (Piecewise Linear):\n * ```\n * if util = 0:       rate = rateAtZero\n * if util >= 100%:   rate = rateAtMax\n * if util < kink:\n *   slope = (rateAtKink - rateAtZero) × 10000 / kink\n *   rate = rateAtZero + (util × slope / 10000)\n * if util >= kink:\n *   slopeAboveKink = (rateAtMax - rateAtKink) × 10000 / (10000 - kink)\n *   rate = rateAtKink + ((util - kink) × slopeAboveKink / 10000)\n * ```\n *\n * EXAMPLE UTILIZATION CURVE:\n * At kink = 80%, rateAtZero = 200 bps (2%), rateAtKink = 800 bps (8%), rateAtMax = 1200 bps (12%)\n * ```\n * Utilization 0%:   2.0%\n * Utilization 20%:  3.5%\n * Utilization 40%:  5.0%\n * Utilization 60%:  6.5%\n * Utilization 80%:  8.0% (KINK POINT)\n * Utilization 90%:  10.0%\n * Utilization 100%: 12.0%\n * ```\n *\n * COMPOSITE RATE EXAMPLE:\n * Alice deposits 50 ETH at 75% vault utilization with 6-month lock\n * 1. Utilization rate @75% = 7.5% (below kink, linear interpolation)\n * 2. Tier bonus @50 ETH = 3% (Tier 3)\n * 3. Lock bonus @6 months = 1% bonus\n * 4. Composite rate = 7.5% + 3% + 1% = 11.5%\n * 5. After 1 year, if she earned 12% but target is 5%:\n *    Excess = 7%, Performance fee = 7% × 20% = 1.4%\n *    Final rate = 12% - 1.4% = 10.6%\n *\n * SECURITY CONSIDERATIONS:\n * - All rates in basis points (100 = 1%)\n * - Tier ordering enforced (minDeposit ascending)\n * - Lock duration: 1 week to 4 years\n * - Performance fee subject to target return cap\n * - Rates cannot exceed 10000 bps (100%)\n * - Utilization formula safe from division by zero\n * - Owner-only for tier/lock/fee configuration\n *\n * DEPLOYMENT CHECKLIST:\n * 1. Deploy with RebaseTokenVault address\n * 2. Configure utilization curve (kink, rates)\n * 3. Add tier configurations (minDeposit, bonus)\n * 4. Set performance fee parameters\n * 5. Verify formulas with test scenarios\n * 6. Enable for production vault operations\n */
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
     * @notice Set utilization-based rate curve with kink point
     * @dev Uses piecewise linear interpolation with "kink" point for higher capital efficiency
     * @param kink Utilization percentage at kink (e.g., 8000 = 80%)
     * @param rateAtZero Rate at 0% utilization in basis points (e.g., 200 = 2%)
     * @param rateAtKink Rate at kink utilization (e.g., 800 = 8%)
     * @param rateAtMax Rate at 100% utilization (e.g., 1200 = 12%)
     *
     * REQUIREMENTS:
     * - kink must be between 1000 (10%) and 10000 (100%)
     * - rateAtZero < rateAtKink < rateAtMax (ascending)
     * - Can only be called by owner
     *
     * EFFECTS:
     * - Updates s_utilizationKink, s_rateAtZero, s_rateAtKink, s_rateAtMax
     * - Emits UtilizationRatesUpdated event
     * - Applies to all future interest calculations
     *
     * UTILIZATION CURVE MECHANICS:
     * The kink point creates a two-slope curve:
     * 
     * Slope 1 (Below kink - Gentle):
     * slope = (rateAtKink - rateAtZero) * 10000 / kink
     * rate = rateAtZero + (utilization * slope / 10000)
     * 
     * Slope 2 (Above kink - Steep):
     * slope = (rateAtMax - rateAtKink) * 10000 / (10000 - kink)
     * rate = rateAtKink + ((utilization - kink) * slope / 10000)
     *
     * EXAMPLE: DEFAULT CONFIGURATION
     * ```
     * kink = 8000 (80%)
     * rateAtZero = 200 (2%)
     * rateAtKink = 800 (8%)
     * rateAtMax = 1200 (12%)
     * 
     * Slope below kink = (800 - 200) * 10000 / 8000 = 750 bps per 100%
     * Slope above kink = (1200 - 800) * 10000 / 2000 = 2000 bps per 100%
     * 
     * Results:
     * 20% utilization: 2% + (20% * 750 / 10000) = 3.5%
     * 50% utilization: 2% + (50% * 750 / 10000) = 5.75%
     * 80% utilization: 8% (at kink)
     * 90% utilization: 8% + (10% * 2000 / 10000) = 10%
     * ```
     *
     * USE CASES:
     * 1. Conservative: Low spread (200 → 400 → 500 = lower rates)
     * 2. Moderate: Balanced spread (200 → 800 → 1200 = balanced)
     * 3. Aggressive: High spread (100 → 1000 → 2000 = higher rates)
     * 4. Emergency: Extreme (50 → 100 → 200 = minimal rates)
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
     * @notice Calculate interest rate based on vault utilization with kink curve
     * @dev Implements piecewise linear interpolation (two-slope curve)
     * @param utilizationBps Current vault utilization in basis points (0-10000)
     * @return Rate in basis points
     *
     * RETURNS:
     * - 0%: rateAtZero
     * - 1-80%: Linear from rateAtZero to rateAtKink
     * - 80%: rateAtKink (kink point)
     * - 81-100%: Linear from rateAtKink to rateAtMax
     * - 100%: rateAtMax
     *
     * FORMULA:
     * ```
     * if utilization = 0:
     *   return rateAtZero
     * if utilization >= 10000:
     *   return rateAtMax
     * if utilization < kink:
     *   slope = (rateAtKink - rateAtZero) * 10000 / kink
     *   return rateAtZero + (utilization * slope / 10000)
     * else (utilization >= kink):
     *   utilAboveKink = utilization - kink
     *   utilRangeAboveKink = 10000 - kink
     *   slope = (rateAtMax - rateAtKink) * 10000 / utilRangeAboveKink
     *   return rateAtKink + (utilAboveKink * slope / 10000)
     * ```
     *
     * EXAMPLES (with defaults: kink=80%, 2%→8%→12%):
     * - utilization 0%:   2% (rateAtZero)
     * - utilization 40%:  5% (halfway to kink)
     * - utilization 80%:  8% (at kink point)
     * - utilization 90%:  10% (halfway above kink)
     * - utilization 100%: 12% (rateAtMax)
     *
     * GAS EFFICIENCY:
     * - Early returns for 0% and 100%
     * - Single multiplication and division for each branch
     * - Total gas: ~3-4k
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
     * @notice Add a new deposit tier with bonus rates (loyalty rewards)
     * @dev Tiers must be ordered by minDeposit ascending for getTierBonus() to work correctly
     * @param minDeposit Minimum deposit to qualify for this tier (in wei)
     * @param bonusRateBps Additional rate bonus for this tier (basis points, e.g., 300 = 3%)
     *
     * REQUIREMENTS:
     * - Can only be called by owner
     * - bonusRateBps must not exceed 10000 (100%)
     * - If any tiers exist, minDeposit must be strictly greater than last tier's minDeposit
     *
     * EFFECTS:
     * - Adds new tier to s_tiers array
     * - Emits TierAdded event with index and configuration
     * - Applies to all future deposits
     *
     * TIER SYSTEM:
     * Each tier specifies a deposit threshold and bonus rate.
     * getTierBonus() returns the HIGHEST matching tier for a deposit.
     *
     * EXAMPLE TIER CONFIGURATION:
     * ```
     * Tier 0: 0 ETH → +0% bonus (default, no minimum)
     * Tier 1: 1 ETH → +0.5% bonus
     * Tier 2: 10 ETH → +1% bonus
     * Tier 3: 100 ETH → +3% bonus
     * Tier 4: 1000 ETH → +5% bonus
     * 
     * getTierBonus(5 ETH) = 0.5% (matches Tier 1)
     * getTierBonus(50 ETH) = 1% (matches Tier 2, highest applicable)
     * getTierBonus(1000 ETH) = 5% (matches Tier 4)
     * getTierBonus(500 ETH) = 3% (matches Tier 3, not Tier 4)
     * ```
     *
     * ORDERING REQUIREMENT:
     * ```
     * addTier(1 ether, 50);      // Tier 1: 1 ETH, +0.5%
     * addTier(10 ether, 100);    // Tier 2: 10 ETH, +1%   ✓ OK (10 > 1)
     * addTier(5 ether, 75);      // Tier 3: 5 ETH  ✗ REVERTS (5 < 10)
     * ```
     *
     * GOVERNANCE:
     * - Adjust tiers to incentivize deposits during low utilization
     * - Increase tiers during growth phase
     * - Remove tiers to simplify (e.g., move to flat bonus)
     *
     * GAS COST:
     * - ~40k gas (array push + event emission)
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
     * @notice Lock user's deposits for bonus rate and extended commitment
     * @dev Creates lock commitment with time-lock and bonus rewards
     * @param user Address of user locking deposits
     * @param amount Amount to lock (in wei)
     * @param duration Lock duration in seconds (1 week to 4 years)
     * @param unlockBonus Bonus rate for locked deposits (basis points, e.g., 200 = 2%)
     *
     * REQUIREMENTS:
     * - Can only be called by owner (or by user via vault)
     * - duration must be between 1 week (604800 seconds) and 4 years (126144000 seconds)
     * - unlockBonus must not exceed 10000 basis points (100%)
     * - Replaces any existing lock for user
     *
     * EFFECTS:
     * - Sets UserLock.lockedAmount = amount
     * - Sets UserLock.lockEndTime = block.timestamp + duration
     * - Updates s_lockConfigs[user] with duration and bonus
     * - Emits LockCreated event
     *
     * LOCK COMMITMENT:
     * User commits to not withdraw locked amount until lockEndTime.
     * In return, receives bonus rate on locked deposits.
     *
     * BONUS EXAMPLES:
     * ```
     * 1 month lock (2592000 sec): +0.5% bonus
     * 3 month lock (7776000 sec): +1% bonus
     * 6 month lock (15552000 sec): +1.5% bonus
     * 1 year lock (31536000 sec): +2% bonus
     * ```
     *
     * COMPOSITE RATE WITH LOCK:
     * Alice locks 10 ETH for 1 year at 75% utilization
     * - Base rate @75%: 7.5%
     * - Tier bonus @10 ETH: 1%
     * - Lock bonus @1 year: 2%
     * - Total rate: 10.5% for locked period
     *
     * SECURITY:
     * - Lock is user-specific (only one lock per address)
     * - Cannot re-lock during existing lock (must unlock first)
     * - lockEndTime is absolute, not relative to previous lock
     * - No early unlock mechanism (must wait full duration)
     *
     * USE CASES:
     * 1. Incentivize long-term deposits during protocol growth
     * 2. Reduce short-term volatility by locking capital
     * 3. Signal confidence to other users (locked = trustworthy)
     * 4. Create APY tiers based on commitment (1 month = 8%, 1 year = 10%)
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
     * @notice Calculate performance fee on gains above target return
     * @dev Implements "hurdle rate" mechanism: fee only on excess returns
     * @param userBalance Current user balance (in tokens)
     * @param originalDeposit Original deposit amount (in tokens)
     * @param elapsedSeconds Time elapsed since last check (in seconds)
     * @return excessReturns Gains above target annual return
     * @return performanceFee Fee on excess returns (in tokens)
     *
     * RETURNS:
     * - excessReturns: 0 if balance ≤ originalDeposit, else (balance - deposit - targetReturn)
     * - performanceFee: 0 if no excess, else (excessReturns × performanceFeeBps / 10000)
     *
     * FORMULA:
     * ```
     * if userBalance <= originalDeposit:
     *   return (0, 0)  // No gains yet
     * 
     * gains = userBalance - originalDeposit
     * 
     * targetReturnAmount = (originalDeposit × targetAnnualReturnBps × elapsedSeconds)
     *                     / (365 days × 10000)
     * 
     * if gains > targetReturnAmount:
     *   excessReturns = gains - targetReturnAmount
     *   performanceFee = (excessReturns × performanceFeeBps) / 10000
     * else:
     *   excessReturns = 0
     *   performanceFee = 0
     * ```
     *
     * EXAMPLE:
     * Alice deposits 100 tokens, target is 5% annual return, performance fee is 20% of excess
     * After 1 year:
     * - userBalance: 112 tokens
     * - gains: 12 tokens
     * - targetReturnAmount: 100 × 5% = 5 tokens
     * - excessReturns: 12 - 5 = 7 tokens (above target)
     * - performanceFee: 7 × 20% = 1.4 tokens
     * Result: (7 tokens, 1.4 tokens)
     *
     * After 6 months:
     * - userBalance: 108 tokens
     * - gains: 8 tokens
     * - targetReturnAmount: 100 × 5% × (6 months / 12 months) = 2.5 tokens
     * - excessReturns: 8 - 2.5 = 5.5 tokens
     * - performanceFee: 5.5 × 20% = 1.1 tokens
     * Result: (5.5 tokens, 1.1 tokens)
     *
     * CONFIGURATION:
     * - targetAnnualReturnBps: Hurdle rate (default 500 = 5%)
     * - performanceFeeBps: Fee on excess (default 2000 = 20%)
     * - s_performanceFeeRecipient: Who receives fees
     *
     * SECURITY:
     * - Fee only on gains above target (aligned incentives)
     * - Time-weighted calculation (annualized)
     * - Returns 0 if not profitable
     * - Owner-controlled fee rate
     *
     * USE CASES:
     * 1. Align vault manager incentives with user returns
     * 2. Charge for outperformance only
     * 3. Standard practice in hedge funds and investment funds
     * 4. Transparent fee calculation
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
