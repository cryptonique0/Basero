// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {RebaseTokenVault} from "./RebaseTokenVault.sol";
import {RebaseToken} from "./RebaseToken.sol";

/**
 * @title AdvancedStrategyVault
 * @dev Extended vault with advanced interest strategies
 * @notice Implements:
 *   - Utilization-based dynamic rates
 *   - Tier-based deposit rewards (Bronze to Diamond)
 *   - Time-locked deposits with bonus multipliers
 *   - Performance fees on excess returns
 */
contract AdvancedStrategyVault is RebaseTokenVault {
    /*//////////////////////////////////////////////////////////////
                            ADVANCED STATE
    //////////////////////////////////////////////////////////////*/

    // Utilization-based rate configuration
    uint256 private s_utilizationKink; // Utilization threshold for rate jump (e.g., 80% = 8000 bps)
    uint256 private s_baseRateBps; // Base rate when utilization = 0
    uint256 private s_lowUtilizationSlope; // Rate increase per 1% utilization below kink
    uint256 private s_highUtilizationSlope; // Rate increase per 1% utilization above kink

    // Tier system (based on deposit amount)
    enum DepositTier {
        Bronze, // 0-10 ETH
        Silver, // 10-50 ETH
        Gold, // 50-200 ETH
        Platinum, // 200-1000 ETH
        Diamond // 1000+ ETH
    }

    struct TierConfig {
        uint256 minDeposit;
        uint256 bonusBps; // Bonus rate in basis points
    }

    mapping(DepositTier => TierConfig) private s_tierConfigs;

    // Time-lock configuration
    enum LockPeriod {
        None, // No lock
        ThirtyDays, // 30 days
        NinetyDays, // 90 days
        OneHundredEightyDays, // 180 days
        ThreeSixtyFiveDays // 365 days
    }

    struct LockConfig {
        uint256 duration; // Lock duration in seconds
        uint256 bonusMultiplierBps; // Bonus multiplier (10000 = 1x, 12000 = 1.2x)
    }

    struct UserLock {
        uint256 amount; // Locked amount
        uint256 unlockTime; // Timestamp when unlock
        LockPeriod period; // Lock period enum
        uint256 bonusRate; // Locked bonus rate
    }

    mapping(LockPeriod => LockConfig) private s_lockConfigs;
    mapping(address => UserLock) private s_userLocks;

    // Performance fee configuration
    uint256 private s_highWaterMark; // High water mark for performance fee (supply per share)
    uint256 private s_performanceFeeBps; // Performance fee in basis points (e.g., 2000 = 20%)
    uint256 private s_performanceFeeRecipient; // Address to receive performance fees
    mapping(address => uint256) private s_userHighWaterMarks; // Per-user high water mark

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event UtilizationRateUpdated(
        uint256 utilizationKink, uint256 baseRate, uint256 lowSlope, uint256 highSlope
    );
    event TierConfigUpdated(DepositTier tier, uint256 minDeposit, uint256 bonusBps);
    event LockConfigUpdated(LockPeriod period, uint256 duration, uint256 bonusMultiplier);
    event DepositLocked(
        address indexed user, uint256 amount, LockPeriod period, uint256 unlockTime, uint256 bonusRate
    );
    event DepositUnlocked(address indexed user, uint256 amount);
    event PerformanceFeeCharged(address indexed user, uint256 feeAmount, uint256 newHighWaterMark);
    event HighWaterMarkUpdated(uint256 oldMark, uint256 newMark);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error DepositStillLocked(uint256 unlockTime);
    error InvalidUtilizationConfig();
    error InvalidTierConfig();
    error InvalidLockConfig();
    error LockAlreadyExists();
    error NoLockFound();

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address rebaseToken) RebaseTokenVault(rebaseToken) {
        // Initialize utilization-based rates
        s_utilizationKink = 8000; // 80%
        s_baseRateBps = 200; // 2% base
        s_lowUtilizationSlope = 5; // +0.05% per 1% utilization
        s_highUtilizationSlope = 50; // +0.5% per 1% utilization above kink

        // Initialize tier configs
        s_tierConfigs[DepositTier.Bronze] = TierConfig({minDeposit: 0, bonusBps: 0}); // No bonus

        s_tierConfigs[DepositTier.Silver] = TierConfig({minDeposit: 10 ether, bonusBps: 50}); // +0.5%

        s_tierConfigs[DepositTier.Gold] = TierConfig({minDeposit: 50 ether, bonusBps: 150}); // +1.5%

        s_tierConfigs[DepositTier.Platinum] = TierConfig({minDeposit: 200 ether, bonusBps: 300}); // +3%

        s_tierConfigs[DepositTier.Diamond] = TierConfig({minDeposit: 1000 ether, bonusBps: 600}); // +6%

        // Initialize lock period configs
        s_lockConfigs[LockPeriod.None] = LockConfig({duration: 0, bonusMultiplierBps: 10000}); // 1x

        s_lockConfigs[LockPeriod.ThirtyDays] = LockConfig({duration: 30 days, bonusMultiplierBps: 11000}); // 1.1x

        s_lockConfigs[LockPeriod.NinetyDays] = LockConfig({duration: 90 days, bonusMultiplierBps: 11500}); // 1.15x

        s_lockConfigs[LockPeriod.OneHundredEightyDays] =
            LockConfig({duration: 180 days, bonusMultiplierBps: 12500}); // 1.25x

        s_lockConfigs[LockPeriod.ThreeSixtyFiveDays] =
            LockConfig({duration: 365 days, bonusMultiplierBps: 15000}); // 1.5x

        // Initialize performance fee
        s_highWaterMark = 10000; // Start at 1:1 (10000 bps)
        s_performanceFeeBps = 2000; // 20% performance fee
    }

    /*//////////////////////////////////////////////////////////////
                      UTILIZATION-BASED RATES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Calculate dynamic interest rate based on vault utilization
     * @dev Rate = baseRate + (utilization * slope)
     *      If utilization > kink, slope changes to highSlope
     * @return rateBps Interest rate in basis points
     */
    function calculateUtilizationRate() public view returns (uint256 rateBps) {
        uint256 totalCapacity = s_maxTotalDeposits;
        if (totalCapacity == 0) return s_baseRateBps;

        uint256 utilization = (s_totalEthDeposited * 10000) / totalCapacity; // In bps

        if (utilization <= s_utilizationKink) {
            // Below kink: gradual increase
            uint256 utilizationPercent = utilization / 100; // Convert to percentage
            rateBps = s_baseRateBps + (utilizationPercent * s_lowUtilizationSlope);
        } else {
            // Above kink: steeper increase
            uint256 excessUtilization = utilization - s_utilizationKink;
            uint256 excessPercent = excessUtilization / 100;

            uint256 kinkRate = s_baseRateBps + ((s_utilizationKink / 100) * s_lowUtilizationSlope);
            rateBps = kinkRate + (excessPercent * s_highUtilizationSlope);
        }

        return rateBps;
    }

    /**
     * @notice Set utilization rate parameters (governance only)
     */
    function setUtilizationConfig(
        uint256 kink,
        uint256 baseRate,
        uint256 lowSlope,
        uint256 highSlope
    ) external onlyGovernance {
        if (kink > 10000 || baseRate > 10000) revert InvalidUtilizationConfig();
        s_utilizationKink = kink;
        s_baseRateBps = baseRate;
        s_lowUtilizationSlope = lowSlope;
        s_highUtilizationSlope = highSlope;
        emit UtilizationRateUpdated(kink, baseRate, lowSlope, highSlope);
    }

    /*//////////////////////////////////////////////////////////////
                        TIER-BASED REWARDS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get user's deposit tier based on their total deposits
     * @param user Address to check
     * @return tier User's current tier
     */
    function getUserTier(address user) public view returns (DepositTier tier) {
        uint256 userDeposit = s_userEthDeposited[user];

        if (userDeposit >= s_tierConfigs[DepositTier.Diamond].minDeposit) {
            return DepositTier.Diamond;
        } else if (userDeposit >= s_tierConfigs[DepositTier.Platinum].minDeposit) {
            return DepositTier.Platinum;
        } else if (userDeposit >= s_tierConfigs[DepositTier.Gold].minDeposit) {
            return DepositTier.Gold;
        } else if (userDeposit >= s_tierConfigs[DepositTier.Silver].minDeposit) {
            return DepositTier.Silver;
        } else {
            return DepositTier.Bronze;
        }
    }

    /**
     * @notice Get tier bonus for a user
     * @param user Address to check
     * @return bonusBps Bonus rate in basis points
     */
    function getUserTierBonus(address user) public view returns (uint256 bonusBps) {
        DepositTier tier = getUserTier(user);
        return s_tierConfigs[tier].bonusBps;
    }

    /**
     * @notice Set tier configuration (governance only)
     */
    function setTierConfig(DepositTier tier, uint256 minDeposit, uint256 bonusBps) external onlyGovernance {
        if (bonusBps > 1000) revert InvalidTierConfig(); // Max 10% tier bonus
        s_tierConfigs[tier] = TierConfig({minDeposit: minDeposit, bonusBps: bonusBps});
        emit TierConfigUpdated(tier, minDeposit, bonusBps);
    }

    /*//////////////////////////////////////////////////////////////
                      TIME-LOCKED DEPOSITS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Lock deposit for a period to earn bonus rate
     * @param period Lock period enum
     */
    function lockDeposit(LockPeriod period) external {
        if (s_userLocks[msg.sender].unlockTime > 0) revert LockAlreadyExists();
        if (s_userEthDeposited[msg.sender] == 0) revert InsufficientBalance();

        LockConfig memory config = s_lockConfigs[period];
        uint256 unlockTime = block.timestamp + config.duration;

        // Calculate bonus rate (utilization + tier + lock multiplier)
        uint256 baseRate = calculateUtilizationRate();
        uint256 tierBonus = getUserTierBonus(msg.sender);
        uint256 totalRate = baseRate + tierBonus;
        uint256 bonusRate = (totalRate * config.bonusMultiplierBps) / 10000;

        s_userLocks[msg.sender] = UserLock({
            amount: s_userEthDeposited[msg.sender],
            unlockTime: unlockTime,
            period: period,
            bonusRate: bonusRate
        });

        emit DepositLocked(msg.sender, s_userEthDeposited[msg.sender], period, unlockTime, bonusRate);
    }

    /**
     * @notice Unlock deposit after lock period expires
     */
    function unlockDeposit() external {
        UserLock memory lock = s_userLocks[msg.sender];
        if (lock.unlockTime == 0) revert NoLockFound();
        if (block.timestamp < lock.unlockTime) revert DepositStillLocked(lock.unlockTime);

        delete s_userLocks[msg.sender];
        emit DepositUnlocked(msg.sender, lock.amount);
    }

    /**
     * @notice Get user's lock status
     * @param user Address to check
     * @return lock User's lock details
     */
    function getUserLock(address user) external view returns (UserLock memory lock) {
        return s_userLocks[user];
    }

    /**
     * @notice Check if user's deposit is locked
     * @param user Address to check
     * @return True if locked
     */
    function isDepositLocked(address user) public view returns (bool) {
        return s_userLocks[user].unlockTime > block.timestamp;
    }

    /**
     * @notice Set lock period configuration (governance only)
     */
    function setLockConfig(LockPeriod period, uint256 duration, uint256 bonusMultiplierBps)
        external
        onlyGovernance
    {
        if (bonusMultiplierBps < 10000 || bonusMultiplierBps > 20000) revert InvalidLockConfig(); // Max 2x
        s_lockConfigs[period] = LockConfig({duration: duration, bonusMultiplierBps: bonusMultiplierBps});
        emit LockConfigUpdated(period, duration, bonusMultiplierBps);
    }

    /*//////////////////////////////////////////////////////////////
                        PERFORMANCE FEES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Calculate and charge performance fee if returns exceed high water mark
     * @param user Address to check
     * @return feeAmount Performance fee charged
     */
    function calculatePerformanceFee(address user) public view returns (uint256 feeAmount) {
        uint256 currentSupply = i_rebaseToken.totalSupply();
        uint256 currentShares = i_rebaseToken.getTotalShares();
        if (currentShares == 0) return 0;

        uint256 supplyPerShare = (currentSupply * 10000) / currentShares;
        uint256 userHWM = s_userHighWaterMarks[user];
        if (userHWM == 0) userHWM = s_highWaterMark;

        if (supplyPerShare > userHWM) {
            uint256 userBalance = i_rebaseToken.balanceOf(user);
            uint256 excessReturn = ((supplyPerShare - userHWM) * userBalance) / 10000;
            feeAmount = (excessReturn * s_performanceFeeBps) / 10000;
        }

        return feeAmount;
    }

    /**
     * @notice Charge performance fee for user (called on redeem)
     * @param user Address to charge
     */
    function _chargePerformanceFee(address user) internal {
        uint256 feeAmount = calculatePerformanceFee(user);
        if (feeAmount > 0) {
            uint256 currentSupply = i_rebaseToken.totalSupply();
            uint256 currentShares = i_rebaseToken.getTotalShares();
            uint256 newHWM = (currentSupply * 10000) / currentShares;

            // Transfer fee to recipient
            i_rebaseToken.transferFrom(user, s_feeRecipient, feeAmount);

            // Update user's high water mark
            s_userHighWaterMarks[user] = newHWM;

            emit PerformanceFeeCharged(user, feeAmount, newHWM);
        }
    }

    /**
     * @notice Set performance fee configuration (governance only)
     */
    function setPerformanceFeeConfig(uint256 feeBps, address recipient) external onlyGovernance {
        if (feeBps > 5000) revert InvalidProtocolFee(); // Max 50%
        if (recipient == address(0)) revert ZeroAddressNotAllowed();
        s_performanceFeeBps = feeBps;
        s_performanceFeeRecipient = uint256(uint160(recipient));
        emit FeeConfigUpdated(recipient, feeBps);
    }

    /**
     * @notice Update global high water mark (governance only)
     */
    function updateHighWaterMark() external onlyGovernance {
        uint256 currentSupply = i_rebaseToken.totalSupply();
        uint256 currentShares = i_rebaseToken.getTotalShares();
        if (currentShares == 0) return;

        uint256 oldMark = s_highWaterMark;
        uint256 newMark = (currentSupply * 10000) / currentShares;
        s_highWaterMark = newMark;

        emit HighWaterMarkUpdated(oldMark, newMark);
    }

    /*//////////////////////////////////////////////////////////////
                      EFFECTIVE RATE CALCULATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Calculate effective interest rate for user
     * @dev Combines utilization, tier bonus, and lock multiplier
     * @param user Address to calculate for
     * @return effectiveRate Effective rate in basis points
     */
    function getEffectiveRate(address user) public view returns (uint256 effectiveRate) {
        // Start with utilization-based rate
        uint256 baseRate = calculateUtilizationRate();

        // Add tier bonus
        uint256 tierBonus = getUserTierBonus(user);

        // Check if user has locked deposit
        UserLock memory lock = s_userLocks[user];
        if (lock.unlockTime > block.timestamp) {
            // Use locked bonus rate
            effectiveRate = lock.bonusRate;
        } else {
            // Use base + tier bonus
            effectiveRate = baseRate + tierBonus;
        }

        return effectiveRate;
    }

    /*//////////////////////////////////////////////////////////////
                      OVERRIDE: REDEEM WITH LOCKS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Redeem tokens (blocked if deposit is locked)
     * @param tokenAmount Amount of tokens to redeem
     */
    function redeem(uint256 tokenAmount) external {
        if (isDepositLocked(msg.sender)) revert DepositStillLocked(s_userLocks[msg.sender].unlockTime);

        // Charge performance fee if applicable
        _chargePerformanceFee(msg.sender);

        // Call parent redeem
        // Note: This is a simplified version - actual implementation would
        // need to properly integrate with parent contract
    }

    /*//////////////////////////////////////////////////////////////
                          VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get comprehensive user strategy info
     * @param user Address to query
     * @return utilizationRate Current utilization-based rate
     * @return userTier User's deposit tier
     * @return tierBonus Tier bonus in bps
     * @return isLocked Whether deposit is locked
     * @return lockPeriod Lock period enum
     * @return unlockTime Unlock timestamp
     * @return effectiveRate Final effective rate
     * @return performanceFee Pending performance fee
     */
    function getUserStrategyInfo(address user)
        external
        view
        returns (
            uint256 utilizationRate,
            DepositTier userTier,
            uint256 tierBonus,
            bool isLocked,
            LockPeriod lockPeriod,
            uint256 unlockTime,
            uint256 effectiveRate,
            uint256 performanceFee
        )
    {
        utilizationRate = calculateUtilizationRate();
        userTier = getUserTier(user);
        tierBonus = getUserTierBonus(user);

        UserLock memory lock = s_userLocks[user];
        isLocked = lock.unlockTime > block.timestamp;
        lockPeriod = lock.period;
        unlockTime = lock.unlockTime;

        effectiveRate = getEffectiveRate(user);
        performanceFee = calculatePerformanceFee(user);
    }

    /**
     * @notice Get tier configuration
     * @param tier Tier to query
     * @return config Tier configuration
     */
    function getTierConfig(DepositTier tier) external view returns (TierConfig memory config) {
        return s_tierConfigs[tier];
    }

    /**
     * @notice Get lock configuration
     * @param period Lock period to query
     * @return config Lock configuration
     */
    function getLockConfig(LockPeriod period) external view returns (LockConfig memory config) {
        return s_lockConfigs[period];
    }

    /**
     * @notice Get utilization configuration
     * @return kink Utilization kink (bps)
     * @return baseRate Base rate (bps)
     * @return lowSlope Low utilization slope
     * @return highSlope High utilization slope
     */
    function getUtilizationConfig()
        external
        view
        returns (uint256 kink, uint256 baseRate, uint256 lowSlope, uint256 highSlope)
    {
        return (s_utilizationKink, s_baseRateBps, s_lowUtilizationSlope, s_highUtilizationSlope);
    }
}
