// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {RebaseTokenVault} from "../src/RebaseTokenVault.sol";

contract RebaseTokenVaultTest is Test {
    RebaseToken public token;
    RebaseTokenVault public vault;
    
    address public owner;
    address public alice;
    address public bob;
    address public carol;

    event Deposit(address indexed user, uint256 ethAmount, uint256 tokensReceived, uint256 interestRate);
    event Redeem(address indexed user, uint256 tokenAmount, uint256 ethReceived);
    event InterestAccrued(uint256 interestAmount, uint256 timestamp);

    function setUp() public {
        owner = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        carol = makeAddr("carol");

        // Deploy token and vault
        token = new RebaseToken("Cross-Chain Rebase Token", "CCRT");
        vault = new RebaseTokenVault(address(token));

        // Transfer token ownership to vault
        token.transferOwnership(address(vault));

        // Fund test accounts
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(carol, 100 ether);
    }

    function testInitialState() public view {
        assertEq(vault.getCurrentInterestRate(), 1000); // 10%
        assertEq(vault.getTotalEthDeposited(), 0);
        assertEq(token.totalSupply(), 0);
    }

    function testDeposit() public {
        uint256 depositAmount = 1 ether;

        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit Deposit(alice, depositAmount, depositAmount, 1000);
        vault.deposit{value: depositAmount}();

        assertEq(token.balanceOf(alice), depositAmount);
        assertEq(vault.getTotalEthDeposited(), depositAmount);
        assertEq(vault.getUserInterestRate(alice), 1000);
    }

    function testMultipleDeposits() public {
        // Alice deposits first
        vm.prank(alice);
        vault.deposit{value: 5 ether}();

        uint256 aliceRate = vault.getUserInterestRate(alice);
        assertEq(aliceRate, 1000); // 10%

        // Bob deposits second (should get same rate since tier hasn't changed)
        vm.prank(bob);
        vault.deposit{value: 3 ether}();

        uint256 bobRate = vault.getUserInterestRate(bob);
        assertEq(bobRate, 1000); // Still 10%
    }

    function testInterestRateDecreases() public {
        // Initial rate is 10% (1000 basis points)
        // Rate decreases by 1% (100 basis points) every 10 ETH

        // Deposit 11 ETH to trigger rate decrease
        vm.prank(alice);
        vault.deposit{value: 11 ether}();

        uint256 aliceRate = vault.getUserInterestRate(alice);
        assertEq(aliceRate, 1000); // Alice locked in 10% rate

        // Next depositor should get lower rate
        vm.prank(bob);
        vault.deposit{value: 1 ether}();

        uint256 bobRate = vault.getUserInterestRate(bob);
        assertEq(bobRate, 900); // Bob gets 9% rate
        assertLt(bobRate, aliceRate);
    }

    function testRedeem() public {
        uint256 depositAmount = 5 ether;

        // Alice deposits
        vm.prank(alice);
        vault.deposit{value: depositAmount}();

        uint256 aliceBalanceBefore = alice.balance;
        uint256 tokenBalance = token.balanceOf(alice);

        // Alice redeems all tokens
        vm.prank(alice);
        vault.redeem(tokenBalance);

        assertEq(token.balanceOf(alice), 0);
        assertEq(alice.balance, aliceBalanceBefore + depositAmount);
    }

    function testPartialRedeem() public {
        vm.prank(alice);
        vault.deposit{value: 10 ether}();

        uint256 tokenBalance = token.balanceOf(alice);
        uint256 redeemAmount = tokenBalance / 2;

        vm.prank(alice);
        vault.redeem(redeemAmount);

        assertApproxEqAbs(token.balanceOf(alice), tokenBalance - redeemAmount, 1);
    }

    function testInterestAccrual() public {
        // Alice deposits
        vm.prank(alice);
        vault.deposit{value: 10 ether}();

        uint256 initialBalance = token.balanceOf(alice);

        // Fast forward 1 day
        vm.warp(block.timestamp + 1 days);

        // Trigger interest accrual
        vault.accrueInterest();

        uint256 newBalance = token.balanceOf(alice);
        assertGt(newBalance, initialBalance);
    }

    function testMultipleUsersInterestAccrual() public {
        // Alice deposits 10 ETH at 10% rate
        vm.prank(alice);
        vault.deposit{value: 10 ether}();

        // Bob deposits 5 ETH
        vm.prank(bob);
        vault.deposit{value: 5 ether}();

        uint256 aliceBalanceBefore = token.balanceOf(alice);
        uint256 bobBalanceBefore = token.balanceOf(bob);

        // Fast forward 1 day
        vm.warp(block.timestamp + 1 days);

        // Trigger interest accrual
        vault.accrueInterest();

        uint256 aliceBalanceAfter = token.balanceOf(alice);
        uint256 bobBalanceAfter = token.balanceOf(bob);

        // Both should have earned interest
        assertGt(aliceBalanceAfter, aliceBalanceBefore);
        assertGt(bobBalanceAfter, bobBalanceBefore);
    }

    function testCannotRedeemMoreThanBalance() public {
        vm.prank(alice);
        vault.deposit{value: 1 ether}();

        vm.prank(alice);
        vm.expectRevert(RebaseTokenVault.InsufficientBalance.selector);
        vault.redeem(10 ether);
    }

    function testCannotDepositZero() public {
        vm.prank(alice);
        vm.expectRevert(RebaseTokenVault.InsufficientDeposit.selector);
        vault.deposit{value: 0}();
    }

    function testCannotRedeemZero() public {
        vm.prank(alice);
        vm.expectRevert(RebaseTokenVault.NoTokensToRedeem.selector);
        vault.redeem(0);
    }

    function testReceiveFunction() public {
        uint256 depositAmount = 1 ether;

        vm.prank(alice);
        (bool success,) = address(vault).call{value: depositAmount}("");
        
        assertTrue(success);
        assertEq(token.balanceOf(alice), depositAmount);
    }

    function testMinimumInterestRate() public {
        // Deposit enough to reduce rate to minimum (2%)
        // Need to deposit 81 ETH (8 tiers * 10 ETH + 1 ETH)
        vm.prank(alice);
        vault.deposit{value: 81 ether}();

        uint256 currentRate = vault.getCurrentInterestRate();
        assertEq(currentRate, 200); // Minimum 2%

        // Further deposits shouldn't reduce rate below minimum
        vm.prank(bob);
        vault.deposit{value: 100 ether}();

        currentRate = vault.getCurrentInterestRate();
        assertEq(currentRate, 200); // Still 2%
    }

    function testGetTimeUntilNextAccrual() public {
        uint256 timeUntilNext = vault.getTimeUntilNextAccrual();
        assertEq(timeUntilNext, 1 days);

        // Fast forward 12 hours
        vm.warp(block.timestamp + 12 hours);
        
        timeUntilNext = vault.getTimeUntilNextAccrual();
        assertEq(timeUntilNext, 12 hours);

        // Fast forward past accrual period
        vm.warp(block.timestamp + 13 hours);
        
        timeUntilNext = vault.getTimeUntilNextAccrual();
        assertEq(timeUntilNext, 0);
    }

    function testDepositAndRedeemAfterInterest() public {
        // Alice deposits
        vm.prank(alice);
        vault.deposit{value: 10 ether}();

        uint256 initialBalance = token.balanceOf(alice);

        // Fast forward and accrue interest
        vm.warp(block.timestamp + 1 days);
        vault.accrueInterest();

        uint256 balanceAfterInterest = token.balanceOf(alice);
        assertGt(balanceAfterInterest, initialBalance);

        // Alice redeems all
        uint256 aliceEthBefore = alice.balance;
        vm.prank(alice);
        vault.redeem(balanceAfterInterest);

        // Alice should get back more than initial deposit (due to interest)
        assertGt(alice.balance, aliceEthBefore);
    }

    function testFuzzDeposit(uint256 amount) public {
        vm.assume(amount > 0 && amount <= 100 ether);

        vm.deal(alice, amount);
        vm.prank(alice);
        vault.deposit{value: amount}();

        assertEq(token.balanceOf(alice), amount);
        assertEq(vault.getTotalEthDeposited(), amount);
    }

    function testFuzzRedeem(uint256 depositAmount, uint256 redeemAmount) public {
        vm.assume(depositAmount > 0 && depositAmount <= 100 ether);
        vm.assume(redeemAmount > 0 && redeemAmount <= depositAmount);

        vm.deal(alice, depositAmount);
        vm.prank(alice);
        vault.deposit{value: depositAmount}();

        vm.prank(alice);
        vault.redeem(redeemAmount);

        assertApproxEqAbs(token.balanceOf(alice), depositAmount - redeemAmount, 2);
    }
}
