// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {AdvancedInterestStrategy} from "src/AdvancedInterestStrategy.sol";
import {RebaseToken} from "src/RebaseToken.sol";
import {RebaseTokenVault} from "src/RebaseTokenVault.sol";

/**
 * @title UtilizationRatesTest
 * @notice Tests for utilization-based interest rates
 */
contract UtilizationRatesTest is Test {
    AdvancedInterestStrategy public strategy;
    RebaseToken public rebaseToken;
    RebaseTokenVault public vault;
    address public owner = address(0x1);

    function setUp() public {
        vm.prank(owner);
        rebaseToken = new RebaseToken("Rebase Token", "REBASE");

        vm.prank(owner);
        vault = new RebaseTokenVault(address(rebaseToken));

        vm.prank(owner);
        strategy = new AdvancedInterestStrategy(address(vault));
    }

    function test_DefaultUtilizationRates() public {
        (uint256 kink, uint256 rateAtZero, uint256 rateAtKink, uint256 rateAtMax) = strategy.getUtilizationConfig();

        assertEq(kink, 8000); // 80%
        assertEq(rateAtZero, 200); // 2%
        assertEq(rateAtKink, 800); // 8%
        assertEq(rateAtMax, 1200); // 12%
    }

    function test_RateAtZeroUtilization() public {
        uint256 rate = strategy.calculateUtilizationRate(0);
        assertEq(rate, 200); // 2%
    }

    function test_RateAtKinkUtilization() public {
        uint256 rate = strategy.calculateUtilizationRate(8000); // 80%
        assertEq(rate, 800); // 8%
    }

    function test_RateAtMaxUtilization() public {
        uint256 rate = strategy.calculateUtilizationRate(10000); // 100%
        assertEq(rate, 1200); // 12%
    }

    function test_RateBelowKink() public {
        // Linear interpolation from 0% to 80%
        uint256 rate = strategy.calculateUtilizationRate(4000); // 40%
        // Rate should be 2% + (6% * 40% / 80%) = 2% + 3% = 5%
        assertEq(rate, 500);
    }

    function test_RateAboveKink() public {
        // Linear interpolation from 80% to 100%
        uint256 rate = strategy.calculateUtilizationRate(9000); // 90%
        // Rate should be 8% + (4% * 10% / 20%) = 8% + 2% = 10%
        assertEq(rate, 1000);
    }

    function test_UpdateUtilizationRates() public {
        vm.prank(owner);
        strategy.setUtilizationRates(7500, 300, 900, 1500);

        (uint256 kink, uint256 rateAtZero, uint256 rateAtKink, uint256 rateAtMax) = strategy.getUtilizationConfig();

        assertEq(kink, 7500);
        assertEq(rateAtZero, 300);
        assertEq(rateAtKink, 900);
        assertEq(rateAtMax, 1500);
    }

    function test_InvalidUtilizationKink() public {
        vm.prank(owner);
        vm.expectRevert(AdvancedInterestStrategy.InvalidUtilizationRate.selector);
        strategy.setUtilizationRates(500, 200, 800, 1200); // Kink < 10%
    }

    function test_InvalidRateOrdering() public {
        vm.prank(owner);
        vm.expectRevert(AdvancedInterestStrategy.InvalidUtilizationRate.selector);
        strategy.setUtilizationRates(8000, 800, 800, 1200); // rateAtZero >= rateAtKink
    }

    function fuzz_UtilizationRateMonotonicity(uint256 util1, uint256 util2) public {
        util1 = bound(util1, 0, 10000);
        util2 = bound(util2, 0, 10000);

        uint256 rate1 = strategy.calculateUtilizationRate(util1);
        uint256 rate2 = strategy.calculateUtilizationRate(util2);

        if (util1 < util2) {
            assertLe(rate1, rate2, "Rate should increase with utilization");
        } else if (util1 > util2) {
            assertGe(rate1, rate2, "Rate should decrease with lower utilization");
        }
    }
}

/**
 * @title TierRewardsTest
 * @notice Tests for tier-based deposit rewards
 */
contract TierRewardsTest is Test {
    AdvancedInterestStrategy public strategy;
    RebaseToken public rebaseToken;
    RebaseTokenVault public vault;
    address public owner = address(0x1);

    function setUp() public {
        vm.prank(owner);
        rebaseToken = new RebaseToken("Rebase Token", "REBASE");

        vm.prank(owner);
        vault = new RebaseTokenVault(address(rebaseToken));

        vm.prank(owner);
        strategy = new AdvancedInterestStrategy(address(vault));
    }

    function test_AddTier() public {
        vm.prank(owner);
        strategy.addTier(10 ether, 100);

        assertEq(strategy.getTierCount(), 1);
    }

    function test_AddMultipleTiers() public {
        vm.prank(owner);
        strategy.addTier(10 ether, 100);

        vm.prank(owner);
        strategy.addTier(100 ether, 200);

        vm.prank(owner);
        strategy.addTier(1000 ether, 300);

        assertEq(strategy.getTierCount(), 3);
    }

    function test_TierBonusCalculation() public {
        vm.prank(owner);
        strategy.addTier(10 ether, 100);

        vm.prank(owner);
        strategy.addTier(100 ether, 200);

        vm.prank(owner);
        strategy.addTier(1000 ether, 300);

        // Below tier 1: 0 bonus
        assertEq(strategy.getTierBonus(5 ether), 0);

        // In tier 1: 100 bonus
        assertEq(strategy.getTierBonus(10 ether), 100);
        assertEq(strategy.getTierBonus(50 ether), 100);

        // In tier 2: 200 bonus
        assertEq(strategy.getTierBonus(100 ether), 200);
        assertEq(strategy.getTierBonus(500 ether), 200);

        // In tier 3: 300 bonus
        assertEq(strategy.getTierBonus(1000 ether), 300);
        assertEq(strategy.getTierBonus(10000 ether), 300);
    }

    function test_RemoveTier() public {
        vm.prank(owner);
        strategy.addTier(10 ether, 100);

        vm.prank(owner);
        strategy.addTier(100 ether, 200);

        vm.prank(owner);
        strategy.removeTier(0);

        assertEq(strategy.getTierCount(), 1);

        // Remaining tier should be the second one
        uint256 bonus = strategy.getTierBonus(100 ether);
        assertEq(bonus, 200);
    }

    function test_InvalidTierOrdering() public {
        vm.prank(owner);
        strategy.addTier(10 ether, 100);

        vm.prank(owner);
        vm.expectRevert(AdvancedInterestStrategy.InvalidTierConfiguration.selector);
        strategy.addTier(10 ether, 200); // Same min as previous
    }

    function test_GetTiers() public {
        vm.prank(owner);
        strategy.addTier(10 ether, 100);

        vm.prank(owner);
        strategy.addTier(100 ether, 200);

        AdvancedInterestStrategy.TierConfig[] memory tiers = strategy.getTiers();

        assertEq(tiers.length, 2);
        assertEq(tiers[0].minDeposit, 10 ether);
        assertEq(tiers[0].bonusRateBps, 100);
        assertEq(tiers[1].minDeposit, 100 ether);
        assertEq(tiers[1].bonusRateBps, 200);
    }
}

/**
 * @title LockMechanismTest
 * @notice Tests for deposit locking mechanisms
 */
contract LockMechanismTest is Test {
    AdvancedInterestStrategy public strategy;
    RebaseToken public rebaseToken;
    RebaseTokenVault public vault;
    address public owner = address(0x1);
    address public user = address(0x2);

    function setUp() public {
        vm.prank(owner);
        rebaseToken = new RebaseToken("Rebase Token", "REBASE");

        vm.prank(owner);
        vault = new RebaseTokenVault(address(rebaseToken));

        vm.prank(owner);
        strategy = new AdvancedInterestStrategy(address(vault));
    }

    function test_LockDeposit() public {
        uint256 lockDuration = 52 weeks;
        uint256 lockBonus = 500; // 5%

        vm.prank(owner);
        strategy.lockDeposit(user, 100 ether, lockDuration, lockBonus);

        (uint256 lockedAmount, uint256 lockEndTime, bool isLocked) = strategy.getLockStatus(user);

        assertEq(lockedAmount, 100 ether);
        assertEq(lockEndTime, block.timestamp + lockDuration);
        assertTrue(isLocked);
    }

    function test_LockBonusActive() public {
        uint256 lockDuration = 52 weeks;
        uint256 lockBonus = 500;

        vm.prank(owner);
        strategy.lockDeposit(user, 100 ether, lockDuration, lockBonus);

        assertEq(strategy.getLockBonus(user), lockBonus);
    }

    function test_ExtendLock() public {
        uint256 lockDuration = 52 weeks;
        uint256 lockBonus = 500;

        vm.prank(owner);
        strategy.lockDeposit(user, 100 ether, lockDuration, lockBonus);

        uint256 originalEndTime;
        (, originalEndTime, ) = strategy.getLockStatus(user);

        // Extend by 26 weeks
        vm.warp(block.timestamp + 1 weeks);

        vm.prank(owner);
        strategy.extendLock(user, 26 weeks);

        (, uint256 newEndTime, ) = strategy.getLockStatus(user);

        assertGt(newEndTime, originalEndTime);
    }

    function test_UnlockAfterExpiry() public {
        uint256 lockDuration = 52 weeks;
        uint256 lockBonus = 500;

        vm.prank(owner);
        strategy.lockDeposit(user, 100 ether, lockDuration, lockBonus);

        // Try to unlock before expiry
        vm.prank(owner);
        vm.expectRevert(AdvancedInterestStrategy.LockNotExpired.selector);
        strategy.unlockDeposit(user);

        // Move time past lock expiry
        vm.warp(block.timestamp + lockDuration + 1);

        vm.prank(owner);
        strategy.unlockDeposit(user);

        (uint256 lockedAmount, , bool isLocked) = strategy.getLockStatus(user);

        assertEq(lockedAmount, 0);
        assertFalse(isLocked);
    }

    function test_LockBonusExpiredAfterUnlock() public {
        uint256 lockDuration = 52 weeks;
        uint256 lockBonus = 500;

        vm.prank(owner);
        strategy.lockDeposit(user, 100 ether, lockDuration, lockBonus);

        vm.warp(block.timestamp + lockDuration + 1);

        vm.prank(owner);
        strategy.unlockDeposit(user);

        assertEq(strategy.getLockBonus(user), 0);
    }

    function test_InvalidLockDuration() public {
        vm.prank(owner);
        vm.expectRevert(AdvancedInterestStrategy.InvalidLockDuration.selector);
        strategy.lockDeposit(user, 100 ether, 3 days, 500); // Too short
    }

    function test_NoLockInitially() public {
        (uint256 lockedAmount, , bool isLocked) = strategy.getLockStatus(user);

        assertEq(lockedAmount, 0);
        assertFalse(isLocked);
    }
}

/**
 * @title PerformanceFeeTest
 * @notice Tests for performance fees on excess returns
 */
contract PerformanceFeeTest is Test {
    AdvancedInterestStrategy public strategy;
    RebaseToken public rebaseToken;
    RebaseTokenVault public vault;
    address public owner = address(0x1);
    address public feeRecipient = address(0x2);

    function setUp() public {
        vm.prank(owner);
        rebaseToken = new RebaseToken("Rebase Token", "REBASE");

        vm.prank(owner);
        vault = new RebaseTokenVault(address(rebaseToken));

        vm.prank(owner);
        strategy = new AdvancedInterestStrategy(address(vault));

        // Set target 5%, performance fee 20% of excess
        vm.prank(owner);
        strategy.setPerformanceFeeConfig(500, 2000, feeRecipient);
    }

    function test_NoPerformanceFeeIfNoGains() public {
        uint256 originalDeposit = 100 ether;
        uint256 userBalance = 100 ether;
        uint256 elapsedSeconds = 365 days;

        (uint256 excessReturns, uint256 performanceFee) =
            strategy.calculatePerformanceFee(userBalance, originalDeposit, elapsedSeconds);

        assertEq(excessReturns, 0);
        assertEq(performanceFee, 0);
    }

    function test_PerformanceFeeOnSmallGains() public {
        uint256 originalDeposit = 100 ether;
        uint256 userBalance = 103 ether; // 3% gain
        uint256 elapsedSeconds = 365 days; // 1 year

        (uint256 excessReturns, uint256 performanceFee) =
            strategy.calculatePerformanceFee(userBalance, originalDeposit, elapsedSeconds);

        // Target 5% on 100 ether = 5 ether
        // Actual gain = 3 ether
        // No excess, so no fee
        assertEq(excessReturns, 0);
        assertEq(performanceFee, 0);
    }

    function test_PerformanceFeeOnExcessGains() public {
        uint256 originalDeposit = 100 ether;
        uint256 userBalance = 108 ether; // 8% gain
        uint256 elapsedSeconds = 365 days; // 1 year

        (uint256 excessReturns, uint256 performanceFee) =
            strategy.calculatePerformanceFee(userBalance, originalDeposit, elapsedSeconds);

        // Target 5% = 5 ether
        // Actual gain = 8 ether
        // Excess = 3 ether
        // Performance fee = 3 ether * 20% = 0.6 ether
        assertEq(excessReturns, 3 ether);
        assertEq(performanceFee, 0.6 ether);
    }

    function test_PerformanceFeeHalfYear() public {
        uint256 originalDeposit = 100 ether;
        uint256 userBalance = 105 ether; // 5% gain
        uint256 elapsedSeconds = 182.5 days; // 0.5 year

        (uint256 excessReturns, uint256 performanceFee) =
            strategy.calculatePerformanceFee(userBalance, originalDeposit, elapsedSeconds);

        // Target 5% per year * 0.5 = 2.5 ether
        // Actual gain = 5 ether
        // Excess = 2.5 ether
        // Performance fee = 2.5 ether * 20% = 0.5 ether
        assertEq(excessReturns, 2.5 ether);
        assertEq(performanceFee, 0.5 ether);
    }

    function test_GetPerformanceFeeInfo() public {
        (uint256 targetReturn, uint256 performanceFee, uint256 accumulatedReturns) = strategy.getPerformanceFeeInfo(address(0x3));

        assertEq(targetReturn, 500); // 5%
        assertEq(performanceFee, 2000); // 20%
        assertEq(accumulatedReturns, 0);
    }

    function test_UpdatePerformanceFeeConfig() public {
        vm.prank(owner);
        strategy.setPerformanceFeeConfig(600, 2500, feeRecipient);

        (uint256 targetReturn, uint256 performanceFee, ) = strategy.getPerformanceFeeInfo(address(0x3));

        assertEq(targetReturn, 600);
        assertEq(performanceFee, 2500);
    }
}

/**
 * @title CompositeRateTest
 * @notice Tests for composite rate calculation combining all factors
 */
contract CompositeRateTest is Test {
    AdvancedInterestStrategy public strategy;
    RebaseToken public rebaseToken;
    RebaseTokenVault public vault;
    address public owner = address(0x1);
    address public user = address(0x2);

    function setUp() public {
        vm.prank(owner);
        rebaseToken = new RebaseToken("Rebase Token", "REBASE");

        vm.prank(owner);
        vault = new RebaseTokenVault(address(rebaseToken));

        vm.prank(owner);
        strategy = new AdvancedInterestStrategy(address(vault));

        // Setup tiers
        vm.prank(owner);
        strategy.addTier(10 ether, 100); // 1% bonus

        vm.prank(owner);
        strategy.addTier(100 ether, 200); // 2% bonus
    }

    function test_CompositeRateWithoutLock() public {
        // At 50% utilization
        // Base rate: ~5% (interpolated)
        // Tier bonus for 100 ether: 2%
        // No lock: 0%
        // Total: ~7%

        uint256 rate = strategy.calculateUserRate(100 ether, 5000); // 50%

        // Base at 50% should be 5% (interpolated between 2% at 0% and 8% at 80%)
        // Plus tier bonus 2% = 7%
        assertGt(rate, 600); // At least 6%
        assertLt(rate, 800); // At most 8%
    }

    function test_CompositeRateWithLock() public {
        vm.prank(owner);
        strategy.lockDeposit(user, 100 ether, 52 weeks, 300); // 3% lock bonus

        uint256 rate = strategy.calculateUserRateWithLock(user, 100 ether, 5000); // 50%

        // Base: ~5%
        // Tier: 2%
        // Lock: 3%
        // Total: ~10%
        assertGt(rate, 900); // At least 9%
        assertLt(rate, 1100); // At most 11%
    }
}
