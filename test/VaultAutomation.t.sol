// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {RebaseTokenVault} from "../src/RebaseTokenVault.sol";

contract VaultAutomationTest is Test {
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

    // ===== checkUpkeep Tests =====

    function testCheckUpkeepReturnsFalseBeforePeriod() public view {
        (bool upkeepNeeded,) = vault.checkUpkeep("");
        assertFalse(upkeepNeeded);
    }

    function testCheckUpkeepReturnsTrueAfterPeriod() public {
        vm.prank(alice);
        vault.deposit{value: 10 ether}();

        vm.warp(block.timestamp + 1 days);

        (bool upkeepNeeded,) = vault.checkUpkeep("");
        assertTrue(upkeepNeeded);
    }

    function testCheckUpkeepWithCustomPeriod() public {
        vault.setAccrualConfig(12 hours, 1000);

        vm.warp(block.timestamp + 11 hours);
        (bool upkeep1,) = vault.checkUpkeep("");
        assertFalse(upkeep1);

        vm.warp(block.timestamp + 2 hours);
        (bool upkeep2,) = vault.checkUpkeep("");
        assertTrue(upkeep2);
    }

    // ===== performUpkeep Tests =====

    function testPerformUpkeepTriggersAccrual() public {
        vm.prank(alice);
        vault.deposit{value: 100 ether}();

        uint256 balanceBefore = token.balanceOf(alice);

        vm.warp(block.timestamp + 1 days);
        vault.performUpkeep("");

        uint256 balanceAfter = token.balanceOf(alice);
        assertGt(balanceAfter, balanceBefore);
    }

    function testPerformUpkeepOnlyAccrualsIfPeriodPassed() public {
        vm.prank(alice);
        vault.deposit{value: 100 ether}();

        uint256 balanceBefore = token.balanceOf(alice);

        // Perform upkeep before period
        vault.performUpkeep("");

        uint256 balanceAfter = token.balanceOf(alice);
        assertEq(balanceBefore, balanceAfter);
    }

    function testPerformUpkeepMultipleTimes() public {
        vm.prank(alice);
        vault.deposit{value: 100 ether}();

        uint256 balance1 = token.balanceOf(alice);

        vm.warp(block.timestamp + 1 days);
        vault.performUpkeep("");
        uint256 balance2 = token.balanceOf(alice);

        vm.warp(block.timestamp + 1 days);
        vault.performUpkeep("");
        uint256 balance3 = token.balanceOf(alice);

        assertGt(balance2, balance1);
        assertGt(balance3, balance2);
    }

    // ===== Chainlink Automation Flow Tests =====

    function testAutomationFlowCheckThenPerform() public {
        vm.prank(alice);
        vault.deposit{value: 50 ether}();

        vm.warp(block.timestamp + 1 days);

        (bool upkeepNeeded,) = vault.checkUpkeep("");
        assertTrue(upkeepNeeded);

        uint256 balanceBefore = token.balanceOf(alice);
        vault.performUpkeep("");
        uint256 balanceAfter = token.balanceOf(alice);

        assertGt(balanceAfter, balanceBefore);
    }

    function testAutomationWithZeroSupply() public view {
        (bool upkeepNeeded,) = vault.checkUpkeep("");
        assertFalse(upkeepNeeded);
    }

    // ===== Fuzz Tests for Automation =====

    function testFuzzAutomationTiming(uint256 warpTime) public {
        vm.assume(warpTime < 365 days);

        vm.prank(alice);
        vault.deposit{value: 50 ether}();

        vm.warp(block.timestamp + warpTime);

        (bool upkeepNeeded,) = vault.checkUpkeep("");

        if (warpTime >= 1 days) {
            assertTrue(upkeepNeeded);
        } else {
            assertFalse(upkeepNeeded);
        }
    }
}
