// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {AdvancedStrategyVault} from "src/AdvancedStrategyVault.sol";
import {RebaseToken} from "src/RebaseToken.sol";

/**
 * @title UtilizationRateTest
 * @notice Tests for utilization-based dynamic interest rates
 */
contract UtilizationRateTest is Test {
    AdvancedStrategyVault public vault;
    RebaseToken public token;
    address public owner = address(0x1);
    address public user1 = address(0x2);

    function setUp() public {
        vm.prank(owner);
        token = new RebaseToken("Rebase Token", "REBASE");

        vm.prank(owner);
        vault = new AdvancedStrategyVault(address(token));

        // Set max total deposits to enable utilization calculations
        vm.prank(owner);
        vault.setDepositCaps(type(uint256).max, 1000 ether);
    }

    function test_UtilizationRateZero() public {
        // No deposits = 0% utilization = base rate
        uint256 rate = vault.calculateUtilizationRate();
        assertTrue(rate >= 200); // At least base rate (2%)
    }

    function test_UtilizationRateLowUtilization() public {
        // 40% utilization (400 ETH / 1000 ETH capacity)
        vm.deal(user1, 400 ether);
        vm.prank(user1);
        vault.deposit{value: 400 ether}();

        uint256 rate = vault.calculateUtilizationRate();
        // Base rate (200 bps) + (40% * 5 bps per 1%) = 200 + 200 = 400 bps = 4%
        assertEq(rate, 400);
    }

    function test_UtilizationRateAtKink() public {
        // 80% utilization (at kink)
        vm.deal(user1, 800 ether);
        vm.prank(user1);
        vault.deposit{value: 800 ether}();

        uint256 rate = vault.calculateUtilizationRate();
        // Base rate (200) + (80% * 5) = 200 + 400 = 600 bps = 6%
        assertEq(rate, 600);
    }

    function test_UtilizationRateAboveKink() public {
        // 95% utilization (above kink)
        vm.deal(user1, 950 ether);
        vm.prank(user1);
        vault.deposit{value: 950 ether}();

        uint256 rate = vault.calculateUtilizationRate();
        // Kink rate (600) + (15% excess * 50 bps) = 600 + 750 = 1350 bps = 13.5%
        assertEq(rate, 1350);
    }

    function test_SetUtilizationConfig() public {
        vm.prank(owner);
        vault.setUtilizationConfig(
            9000, // 90% kink
            300, // 3% base rate
            10, // 0.1% per 1% utilization
            100 // 1% per 1% above kink
        );

        (uint256 kink, uint256 baseRate, uint256 lowSlope, uint256 highSlope) = vault.getUtilizationConfig();

        assertEq(kink, 9000);
        assertEq(baseRate, 300);
        assertEq(lowSlope, 10);
        assertEq(highSlope, 100);
    }

    function testFuzz_UtilizationRate(uint256 depositAmount) public {
        vm.assume(depositAmount > 0 && depositAmount <= 1000 ether);

        vm.deal(user1, depositAmount);
        vm.prank(user1);
        vault.deposit{value: depositAmount}();

        uint256 rate = vault.calculateUtilizationRate();
        assertTrue(rate >= 200); // At least base rate
    }
}

/**
 * @title TierRewardsTest
 * @notice Tests for tier-based deposit rewards
 */
contract TierRewardsTest is Test {
    AdvancedStrategyVault public vault;
    RebaseToken public token;
    address public owner = address(0x1);
    address public user1 = address(0x2);

    function setUp() public {
        vm.prank(owner);
        token = new RebaseToken("Rebase Token", "REBASE");

        vm.prank(owner);
        vault = new AdvancedStrategyVault(address(token));

        vm.prank(owner);
        vault.setDepositCaps(type(uint256).max, 10000 ether);
    }

    function test_TierBronze() public {
        vm.deal(user1, 5 ether);
        vm.prank(user1);
        vault.deposit{value: 5 ether}();

        AdvancedStrategyVault.DepositTier tier = vault.getUserTier(user1);
        uint256 bonus = vault.getUserTierBonus(user1);

        assertEq(uint256(tier), uint256(AdvancedStrategyVault.DepositTier.Bronze));
        assertEq(bonus, 0); // No bonus for bronze
    }

    function test_TierSilver() public {
        vm.deal(user1, 15 ether);
        vm.prank(user1);
        vault.deposit{value: 15 ether}();

        AdvancedStrategyVault.DepositTier tier = vault.getUserTier(user1);
        uint256 bonus = vault.getUserTierBonus(user1);

        assertEq(uint256(tier), uint256(AdvancedStrategyVault.DepositTier.Silver));
        assertEq(bonus, 50); // +0.5% bonus
    }

    function test_TierGold() public {
        vm.deal(user1, 75 ether);
        vm.prank(user1);
        vault.deposit{value: 75 ether}();

        AdvancedStrategyVault.DepositTier tier = vault.getUserTier(user1);
        uint256 bonus = vault.getUserTierBonus(user1);

        assertEq(uint256(tier), uint256(AdvancedStrategyVault.DepositTier.Gold));
        assertEq(bonus, 150); // +1.5% bonus
    }

    function test_TierPlatinum() public {
        vm.deal(user1, 500 ether);
        vm.prank(user1);
        vault.deposit{value: 500 ether}();

        AdvancedStrategyVault.DepositTier tier = vault.getUserTier(user1);
        uint256 bonus = vault.getUserTierBonus(user1);

        assertEq(uint256(tier), uint256(AdvancedStrategyVault.DepositTier.Platinum));
        assertEq(bonus, 300); // +3% bonus
    }

    function test_TierDiamond() public {
        vm.deal(user1, 2000 ether);
        vm.prank(user1);
        vault.deposit{value: 2000 ether}();

        AdvancedStrategyVault.DepositTier tier = vault.getUserTier(user1);
        uint256 bonus = vault.getUserTierBonus(user1);

        assertEq(uint256(tier), uint256(AdvancedStrategyVault.DepositTier.Diamond));
        assertEq(bonus, 600); // +6% bonus
    }

    function test_TierProgression() public {
        // Start at Bronze
        vm.deal(user1, 5 ether);
        vm.prank(user1);
        vault.deposit{value: 5 ether}();

        assertEq(uint256(vault.getUserTier(user1)), uint256(AdvancedStrategyVault.DepositTier.Bronze));

        // Progress to Silver
        vm.deal(user1, 10 ether);
        vm.prank(user1);
        vault.deposit{value: 10 ether}();

        assertEq(uint256(vault.getUserTier(user1)), uint256(AdvancedStrategyVault.DepositTier.Silver));
        assertEq(vault.getUserTierBonus(user1), 50);
    }

    function test_SetTierConfig() public {
        vm.prank(owner);
        vault.setTierConfig(AdvancedStrategyVault.DepositTier.Gold, 100 ether, 200);

        AdvancedStrategyVault.TierConfig memory config =
            vault.getTierConfig(AdvancedStrategyVault.DepositTier.Gold);

        assertEq(config.minDeposit, 100 ether);
        assertEq(config.bonusBps, 200);
    }
}

/**
 * @title LockDepositTest
 * @notice Tests for time-locked deposit bonuses
 */
contract LockDepositTest is Test {
    AdvancedStrategyVault public vault;
    RebaseToken public token;
    address public owner = address(0x1);
    address public user1 = address(0x2);

    function setUp() public {
        vm.prank(owner);
        token = new RebaseToken("Rebase Token", "REBASE");

        vm.prank(owner);
        vault = new AdvancedStrategyVault(address(token));

        vm.prank(owner);
        vault.setDepositCaps(type(uint256).max, 10000 ether);

        // User deposits first
        vm.deal(user1, 100 ether);
        vm.prank(user1);
        vault.deposit{value: 100 ether}();
    }

    function test_Lock30Days() public {
        vm.prank(user1);
        vault.lockDeposit(AdvancedStrategyVault.LockPeriod.ThirtyDays);

        AdvancedStrategyVault.UserLock memory lock = vault.getUserLock(user1);

        assertEq(lock.amount, 100 ether);
        assertEq(lock.unlockTime, block.timestamp + 30 days);
        assertEq(uint256(lock.period), uint256(AdvancedStrategyVault.LockPeriod.ThirtyDays));
    }

    function test_Lock90Days() public {
        vm.prank(user1);
        vault.lockDeposit(AdvancedStrategyVault.LockPeriod.NinetyDays);

        AdvancedStrategyVault.UserLock memory lock = vault.getUserLock(user1);

        assertEq(lock.unlockTime, block.timestamp + 90 days);
        assertEq(uint256(lock.period), uint256(AdvancedStrategyVault.LockPeriod.NinetyDays));
    }

    function test_Lock365Days() public {
        vm.prank(user1);
        vault.lockDeposit(AdvancedStrategyVault.LockPeriod.ThreeSixtyFiveDays);

        AdvancedStrategyVault.UserLock memory lock = vault.getUserLock(user1);

        assertEq(lock.unlockTime, block.timestamp + 365 days);
        assertEq(uint256(lock.period), uint256(AdvancedStrategyVault.LockPeriod.ThreeSixtyFiveDays));
    }

    function test_LockIncreasesBonusRate() public {
        // Get rate before locking
        uint256 rateBefore = vault.getEffectiveRate(user1);

        // Lock for 365 days (1.5x multiplier)
        vm.prank(user1);
        vault.lockDeposit(AdvancedStrategyVault.LockPeriod.ThreeSixtyFiveDays);

        // Get rate after locking
        uint256 rateAfter = vault.getEffectiveRate(user1);

        // Should be higher (1.5x)
        assertTrue(rateAfter > rateBefore);
    }

    function test_DepositIsLocked() public {
        vm.prank(user1);
        vault.lockDeposit(AdvancedStrategyVault.LockPeriod.ThirtyDays);

        bool isLocked = vault.isDepositLocked(user1);
        assertTrue(isLocked);
    }

    function test_CannotLockTwice() public {
        vm.prank(user1);
        vault.lockDeposit(AdvancedStrategyVault.LockPeriod.ThirtyDays);

        vm.prank(user1);
        vm.expectRevert(AdvancedStrategyVault.LockAlreadyExists.selector);
        vault.lockDeposit(AdvancedStrategyVault.LockPeriod.NinetyDays);
    }

    function test_UnlockAfterPeriod() public {
        vm.prank(user1);
        vault.lockDeposit(AdvancedStrategyVault.LockPeriod.ThirtyDays);

        // Fast forward 30 days
        vm.warp(block.timestamp + 30 days + 1);

        vm.prank(user1);
        vault.unlockDeposit();

        bool isLocked = vault.isDepositLocked(user1);
        assertFalse(isLocked);
    }

    function test_CannotUnlockEarly() public {
        vm.prank(user1);
        vault.lockDeposit(AdvancedStrategyVault.LockPeriod.ThirtyDays);

        // Try to unlock after 1 day
        vm.warp(block.timestamp + 1 days);

        vm.prank(user1);
        vm.expectRevert();
        vault.unlockDeposit();
    }

    function test_SetLockConfig() public {
        vm.prank(owner);
        vault.setLockConfig(AdvancedStrategyVault.LockPeriod.ThirtyDays, 45 days, 11500);

        AdvancedStrategyVault.LockConfig memory config =
            vault.getLockConfig(AdvancedStrategyVault.LockPeriod.ThirtyDays);

        assertEq(config.duration, 45 days);
        assertEq(config.bonusMultiplierBps, 11500); // 1.15x
    }
}

/**
 * @title PerformanceFeeTest
 * @notice Tests for performance fees on excess returns
 */
contract PerformanceFeeTest is Test {
    AdvancedStrategyVault public vault;
    RebaseToken public token;
    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public feeRecipient = address(0x3);

    function setUp() public {
        vm.prank(owner);
        token = new RebaseToken("Rebase Token", "REBASE");

        vm.prank(owner);
        vault = new AdvancedStrategyVault(address(token));

        vm.prank(owner);
        vault.setDepositCaps(type(uint256).max, 10000 ether);

        vm.prank(owner);
        vault.setPerformanceFeeConfig(2000, feeRecipient); // 20% performance fee

        // User deposits
        vm.deal(user1, 100 ether);
        vm.prank(user1);
        vault.deposit{value: 100 ether}();
    }

    function test_NoPerformanceFeeWhenBelowHighWaterMark() public {
        uint256 fee = vault.calculatePerformanceFee(user1);
        assertEq(fee, 0);
    }

    function test_SetPerformanceFeeConfig() public {
        vm.prank(owner);
        vault.setPerformanceFeeConfig(3000, feeRecipient); // 30%

        // Verify (would need getter function)
    }

    function test_UpdateHighWaterMark() public {
        vm.prank(owner);
        vault.updateHighWaterMark();

        // Verify via event or getter
    }
}

/**
 * @title EffectiveRateTest
 * @notice Tests for combined effective rate calculation
 */
contract EffectiveRateTest is Test {
    AdvancedStrategyVault public vault;
    RebaseToken public token;
    address public owner = address(0x1);
    address public user1 = address(0x2);

    function setUp() public {
        vm.prank(owner);
        token = new RebaseToken("Rebase Token", "REBASE");

        vm.prank(owner);
        vault = new AdvancedStrategyVault(address(token));

        vm.prank(owner);
        vault.setDepositCaps(type(uint256).max, 1000 ether);
    }

    function test_EffectiveRateCombinesUtilizationAndTier() public {
        // Deposit 100 ETH (10% utilization + Silver tier)
        vm.deal(user1, 100 ether);
        vm.prank(user1);
        vault.deposit{value: 100 ether}();

        uint256 effectiveRate = vault.getEffectiveRate(user1);

        // Base rate (200) + utilization (10% * 5) + tier bonus (50 for Silver)
        // = 200 + 50 + 50 = 300 bps = 3%
        assertEq(effectiveRate, 300);
    }

    function test_EffectiveRateWithLock() public {
        // Deposit and lock
        vm.deal(user1, 100 ether);
        vm.prank(user1);
        vault.deposit{value: 100 ether}();

        vm.prank(user1);
        vault.lockDeposit(AdvancedStrategyVault.LockPeriod.ThreeSixtyFiveDays);

        uint256 effectiveRate = vault.getEffectiveRate(user1);

        // Should use locked bonus rate (higher than base + tier)
        assertTrue(effectiveRate > 300);
    }

    function test_GetUserStrategyInfo() public {
        vm.deal(user1, 100 ether);
        vm.prank(user1);
        vault.deposit{value: 100 ether}();

        (
            uint256 utilizationRate,
            AdvancedStrategyVault.DepositTier userTier,
            uint256 tierBonus,
            bool isLocked,
            AdvancedStrategyVault.LockPeriod lockPeriod,
            uint256 unlockTime,
            uint256 effectiveRate,
            uint256 performanceFee
        ) = vault.getUserStrategyInfo(user1);

        assertTrue(utilizationRate > 0);
        assertEq(uint256(userTier), uint256(AdvancedStrategyVault.DepositTier.Silver));
        assertEq(tierBonus, 50);
        assertFalse(isLocked);
        assertEq(effectiveRate, 300); // Base + utilization + tier
    }
}

/**
 * @title IntegrationTest
 * @notice End-to-end tests for advanced strategies
 */
contract IntegrationTest is Test {
    AdvancedStrategyVault public vault;
    RebaseToken public token;
    address public owner = address(0x1);
    address public alice = address(0x2);
    address public bob = address(0x3);
    address public charlie = address(0x4);

    function setUp() public {
        vm.prank(owner);
        token = new RebaseToken("Rebase Token", "REBASE");

        vm.prank(owner);
        vault = new AdvancedStrategyVault(address(token));

        vm.prank(owner);
        vault.setDepositCaps(type(uint256).max, 10000 ether);
    }

    function test_MultipleUsersDifferentStrategies() public {
        // Alice: Small deposit, no lock (Bronze tier)
        vm.deal(alice, 5 ether);
        vm.prank(alice);
        vault.deposit{value: 5 ether}();

        // Bob: Medium deposit, 90-day lock (Gold tier)
        vm.deal(bob, 75 ether);
        vm.prank(bob);
        vault.deposit{value: 75 ether}();
        vm.prank(bob);
        vault.lockDeposit(AdvancedStrategyVault.LockPeriod.NinetyDays);

        // Charlie: Large deposit, 365-day lock (Diamond tier)
        vm.deal(charlie, 1500 ether);
        vm.prank(charlie);
        vault.deposit{value: 1500 ether}();
        vm.prank(charlie);
        vault.lockDeposit(AdvancedStrategyVault.LockPeriod.ThreeSixtyFiveDays);

        // Verify rates (Charlie should have highest)
        uint256 aliceRate = vault.getEffectiveRate(alice);
        uint256 bobRate = vault.getEffectiveRate(bob);
        uint256 charlieRate = vault.getEffectiveRate(charlie);

        assertTrue(bobRate > aliceRate);
        assertTrue(charlieRate > bobRate);
    }

    function test_UtilizationChangesAffectRates() public {
        // Low utilization
        vm.deal(alice, 100 ether);
        vm.prank(alice);
        vault.deposit{value: 100 ether}();

        uint256 rateLow = vault.getEffectiveRate(alice);

        // High utilization
        vm.deal(bob, 800 ether);
        vm.prank(bob);
        vault.deposit{value: 800 ether}();

        uint256 rateHigh = vault.getEffectiveRate(alice);

        // Rate should increase with utilization
        assertTrue(rateHigh > rateLow);
    }
}
