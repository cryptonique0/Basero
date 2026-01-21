// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {RebaseTokenVault} from "../src/RebaseTokenVault.sol";

contract VaultAccrualTest is Test {
    RebaseToken public token;
    RebaseTokenVault public vault;

    address public owner;
    address public alice;

    function setUp() public {
        owner = address(this);
        alice = makeAddr("alice");

        token = new RebaseToken("Cross-Chain Rebase Token", "CCRT");
        vault = new RebaseTokenVault(address(token));
        token.transferOwnership(address(vault));

        vm.deal(alice, 1000 ether);
    }

    // ===== Circuit Breaker (Daily Accrual Cap) Tests =====

    function testMaxDailyAccrualCapEnforced() public {
        vm.prank(alice);
        vault.deposit{value: 100 ether}();

        uint256 balanceBefore = token.balanceOf(alice);

        // Set circuit breaker to 10% per day
        vault.setAccrualConfig(1 days, 1000);

        vm.warp(block.timestamp + 1 days);
        vault.accrueInterest();

        uint256 balanceAfter = token.balanceOf(alice);

        // Accrual should be capped at 10% of supply
        uint256 maxAccrual = (balanceBefore * 1000) / 10_000;
        assertLe(balanceAfter - balanceBefore, maxAccrual + 1); // +1 for rounding
    }

    function testAccrualRespectsDailyLimit() public {
        vault.setAccrualConfig(1 days, 500); // 5% max daily

        vm.prank(alice);
        vault.deposit{value: 100 ether}();

        uint256 supplyBefore = token.totalSupply();

        vm.warp(block.timestamp + 1 days);
        vault.accrueInterest();

        uint256 supplyAfter = token.totalSupply();
        uint256 accrued = supplyAfter - supplyBefore;

        uint256 maxAccrual = (supplyBefore * 500) / 10_000;
        assertLe(accrued, maxAccrual + 1);
    }

    // ===== Configurable Accrual Period Tests =====

    function testAccrualPeriodCanBeConfigured() public {
        uint256 customPeriod = 12 hours;
        vault.setAccrualConfig(customPeriod, 1000);

        assertEq(vault.getAccrualPeriod(), customPeriod);
    }

    function testAccrualPeriodBoundsCheked() public {
        vm.expectRevert(RebaseTokenVault.InvalidAccrualPeriod.selector);
        vault.setAccrualConfig(30 minutes, 1000); // Below minimum (1 hour)

        vm.expectRevert(RebaseTokenVault.InvalidAccrualPeriod.selector);
        vault.setAccrualConfig(10 days, 1000); // Above maximum (7 days)
    }

    function testAccrualTriggersOnCustomPeriod() public {
        vault.setAccrualConfig(12 hours, 1000);

        vm.prank(alice);
        vault.deposit{value: 100 ether}();

        uint256 balanceBefore = token.balanceOf(alice);

        // Forward 11 hours (not enough)
        vm.warp(block.timestamp + 11 hours);
        vault.accrueInterest();

        uint256 afterShortWarp = token.balanceOf(alice);
        assertEq(balanceBefore, afterShortWarp); // No accrual yet

        // Forward 1 more hour (now 12 hours total)
        vm.warp(block.timestamp + 1 hours);
        vault.accrueInterest();

        uint256 afterFullPeriod = token.balanceOf(alice);
        assertGt(afterFullPeriod, balanceBefore); // Accrual happened
    }

    // ===== Protocol Fee Tests =====

    function testProtocolFeeDeductedFromAccrual() public {
        vault.setFeeConfig(owner, 2000); // 20% fee
        vault.setAccrualConfig(1 days, 10000);

        vm.prank(alice);
        vault.deposit{value: 100 ether}();

        uint256 tokensBefore = token.totalSupply();

        vm.warp(block.timestamp + 1 days);
        vault.accrueInterest();

        uint256 tokensAfter = token.totalSupply();
        uint256 totalAccrued = tokensAfter - tokensBefore;

        // Owner should have ~20% of accrued tokens
        uint256 ownerBalance = token.balanceOf(owner);
        assertGt(ownerBalance, 0);
        assertLe(ownerBalance, (totalAccrued * 2000) / 10_000 + 1);
    }

    function testFeeRecipientReceivesTokens() public {
        address feeRecipient = makeAddr("feeRecipient");
        vault.setFeeConfig(feeRecipient, 1000); // 10% fee

        vm.prank(alice);
        vault.deposit{value: 100 ether}();

        vm.warp(block.timestamp + 1 days);
        vault.accrueInterest();

        uint256 recipientBalance = token.balanceOf(feeRecipient);
        assertGt(recipientBalance, 0);
    }

    function testZeroFeeConfigWorks() public {
        vault.setFeeConfig(owner, 0); // No fee

        vm.prank(alice);
        vault.deposit{value: 100 ether}();

        uint256 userBalanceBefore = token.balanceOf(alice);
        uint256 ownerBalanceBefore = token.balanceOf(owner);

        vm.warp(block.timestamp + 1 days);
        vault.accrueInterest();

        uint256 userBalanceAfter = token.balanceOf(alice);
        uint256 ownerBalanceAfter = token.balanceOf(owner);

        assertGt(userBalanceAfter, userBalanceBefore);
        assertEq(ownerBalanceAfter, ownerBalanceBefore);
    }

    // ===== Fuzz Tests for Accrual Math =====

    function testFuzzAccrualMath(uint256 depositAmount, uint256 rateBps) public {
        vm.assume(depositAmount > 0.1 ether && depositAmount < 1000 ether);
        vm.assume(rateBps > 0 && rateBps <= 10_000);

        vm.prank(alice);
        vault.deposit{value: depositAmount}();

        uint256 supplyBefore = token.totalSupply();

        vm.warp(block.timestamp + 1 days);
        vault.accrueInterest();

        uint256 supplyAfter = token.totalSupply();

        // Supply should have increased (or stayed same)
        assertGe(supplyAfter, supplyBefore);
    }

    function testFuzzCapApplication(uint256 dailyCapBps) public {
        vm.assume(dailyCapBps > 0 && dailyCapBps <= 10_000);

        vault.setAccrualConfig(1 days, dailyCapBps);

        vm.prank(alice);
        vault.deposit{value: 100 ether}();

        uint256 supplyBefore = token.totalSupply();

        vm.warp(block.timestamp + 1 days);
        vault.accrueInterest();

        uint256 supplyAfter = token.totalSupply();
        uint256 accrued = supplyAfter - supplyBefore;

        uint256 maxAllowed = (supplyBefore * dailyCapBps) / 10_000;
        assertLe(accrued, maxAllowed + 1);
    }
}
