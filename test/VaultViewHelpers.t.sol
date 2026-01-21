// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {RebaseTokenVault} from "../src/RebaseTokenVault.sol";

contract VaultViewHelpersTest is Test {
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

    // ===== previewDeposit Tests =====

    function testPreviewDepositReturnsCorrectAmount() public {
        (uint256 expectedTokens, uint256 rate) = vault.previewDeposit(10 ether);

        assertEq(expectedTokens, 10 ether);
        assertEq(rate, 1000); // Initial 10%
    }

    function testPreviewDepositUpdatesWithRate() public {
        (uint256 tokens1, uint256 rate1) = vault.previewDeposit(5 ether);
        assertEq(rate1, 1000);

        // Deposit to trigger rate decrease
        vm.prank(alice);
        vault.deposit{value: 15 ether}();

        (uint256 tokens2, uint256 rate2) = vault.previewDeposit(5 ether);
        assertEq(tokens2, 5 ether); // Tokens still 1:1
        assertLe(rate2, rate1); // Rate should not increase
    }

    // ===== previewRedeem Tests =====

    function testPreviewRedeemReturnsZeroWhenEmpty() public {
        uint256 ethAmount = vault.previewRedeem(10 ether);
        assertEq(ethAmount, 0);
    }

    function testPreviewRedeemAfterDeposit() public {
        vm.prank(alice);
        vault.deposit{value: 10 ether}();

        uint256 previewAmount = vault.previewRedeem(10 ether);
        assertEq(previewAmount, 10 ether);
    }

    function testPreviewRedeemPartial() public {
        vm.prank(alice);
        vault.deposit{value: 10 ether}();

        uint256 previewAmount = vault.previewRedeem(5 ether);
        assertEq(previewAmount, 5 ether);
    }

    // ===== estimateInterest Tests =====

    function testEstimateInterestBasedOnHorizon() public {
        vm.prank(alice);
        vault.deposit{value: 100 ether}();

        uint256 interest30Days = vault.estimateInterest(alice, 30);
        uint256 interest365Days = vault.estimateInterest(alice, 365);

        assertGt(interest365Days, interest30Days);
        assertEq(interest30Days, (100 ether * 1000 * 30) / 10_000 / 365);
    }

    function testEstimateInterestZeroHorizon() public {
        vm.prank(alice);
        vault.deposit{value: 100 ether}();

        uint256 interest = vault.estimateInterest(alice, 0);
        assertEq(interest, 0);
    }

    function testEstimateInterestNoBalance() public {
        uint256 interest = vault.estimateInterest(alice, 30);
        assertEq(interest, 0);
    }

    // ===== getUserInfo Tests =====

    function testGetUserInfoAfterDeposit() public {
        vm.prank(alice);
        vault.deposit{value: 10 ether}();

        (uint256 shares, uint256 balance, uint256 rate, uint256 lastAccrual) = vault.getUserInfo(alice);

        assertEq(balance, 10 ether);
        assertEq(rate, 1000);
        assertGt(shares, 0);
        assertEq(lastAccrual, block.timestamp);
    }

    function testGetUserInfoMultipleDeposits() public {
        vm.prank(alice);
        vault.deposit{value: 5 ether}();

        uint256 sharesAfter1 = vault.getUserInfo(alice).shares;

        vm.prank(alice);
        vault.deposit{value: 5 ether}();

        (uint256 sharesAfter2, uint256 balance2, uint256 rate2,) = vault.getUserInfo(alice);

        assertEq(balance2, 10 ether);
        assertEq(sharesAfter2, sharesAfter1 + sharesAfter1); // Should double
    }

    function testGetUserInfoZeroBalance() public {
        (uint256 shares, uint256 balance, uint256 rate, uint256 lastAccrual) = vault.getUserInfo(alice);

        assertEq(shares, 0);
        assertEq(balance, 0);
        assertEq(rate, 0);
        assertEq(lastAccrual, 0);
    }

    // ===== getAccrualPeriod Tests =====

    function testGetAccrualPeriodDefault() public {
        uint256 period = vault.getAccrualPeriod();
        assertEq(period, 1 days);
    }

    function testGetAccrualPeriodAfterUpdate() public {
        vault.setAccrualConfig(12 hours, 1000);
        assertEq(vault.getAccrualPeriod(), 12 hours);
    }

    // ===== View Helpers Consistency Tests =====

    function testPreviewRedeemConsistency() public {
        vm.prank(alice);
        vault.deposit{value: 20 ether}();

        uint256 previewEth1 = vault.previewRedeem(10 ether);

        vm.prank(alice);
        vault.redeem(10 ether);

        // Check that remaining balance prediction is consistent
        uint256 previewEth2 = vault.previewRedeem(10 ether);
        assertEq(previewEth1, 10 ether);
    }

    function testUserInfoConsistencyWithBalanceOf() public {
        vm.prank(alice);
        vault.deposit{value: 15 ether}();

        (,uint256 infoBalance,,) = vault.getUserInfo(alice);
        uint256 directBalance = token.balanceOf(alice);

        assertEq(infoBalance, directBalance);
    }
}
