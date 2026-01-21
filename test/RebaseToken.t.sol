// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";

contract RebaseTokenTest is Test {
    RebaseToken public token;
    address public owner;
    address public alice;
    address public bob;

    uint256 constant INITIAL_SUPPLY = 1_000_000 * 10 ** 18;

    event Rebase(uint256 oldTotalSupply, uint256 newTotalSupply, uint256 timestamp);
    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        owner = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        token = new RebaseToken("Cross-Chain Rebase Token", "CCRT", INITIAL_SUPPLY);
    }

    function testInitialState() public view {
        assertEq(token.totalSupply(), INITIAL_SUPPLY);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY);
        assertEq(token.getTotalShares(), INITIAL_SUPPLY);
        assertEq(token.sharesOf(owner), INITIAL_SUPPLY);
    }

    function testTransfer() public {
        uint256 transferAmount = 100_000 * 10 ** 18;

        token.transfer(alice, transferAmount);

        assertEq(token.balanceOf(alice), transferAmount);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY - transferAmount);
    }

    function testTransferFrom() public {
        uint256 transferAmount = 100_000 * 10 ** 18;

        token.approve(alice, transferAmount);

        vm.prank(alice);
        token.transferFrom(owner, bob, transferAmount);

        assertEq(token.balanceOf(bob), transferAmount);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY - transferAmount);
    }

    function testRebase() public {
        uint256 newSupply = 2_000_000 * 10 ** 18;

        // Give alice 50% of tokens
        token.transfer(alice, INITIAL_SUPPLY / 2);

        // Rebase to double the supply
        vm.expectEmit(true, true, false, true);
        emit Rebase(INITIAL_SUPPLY, newSupply, block.timestamp);
        token.rebase(newSupply);

        // Total supply should be doubled
        assertEq(token.totalSupply(), newSupply);

        // Shares remain the same
        assertEq(token.getTotalShares(), INITIAL_SUPPLY);

        // Balances should be doubled
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY);
        assertEq(token.balanceOf(alice), INITIAL_SUPPLY);
    }

    function testRebaseByPercentageIncrease() public {
        // Give alice 50% of tokens
        token.transfer(alice, INITIAL_SUPPLY / 2);

        uint256 ownerBalanceBefore = token.balanceOf(owner);
        uint256 aliceBalanceBefore = token.balanceOf(alice);

        // Increase by 10% (1000 basis points)
        token.rebaseByPercentage(1000, true);

        uint256 expectedTotalSupply = INITIAL_SUPPLY + (INITIAL_SUPPLY * 1000) / 10_000;
        assertEq(token.totalSupply(), expectedTotalSupply);

        // Balances should increase by 10%
        assertEq(token.balanceOf(owner), ownerBalanceBefore + (ownerBalanceBefore * 1000) / 10_000);
        assertEq(token.balanceOf(alice), aliceBalanceBefore + (aliceBalanceBefore * 1000) / 10_000);
    }

    function testRebaseByPercentageDecrease() public {
        // Give alice 50% of tokens
        token.transfer(alice, INITIAL_SUPPLY / 2);

        uint256 ownerBalanceBefore = token.balanceOf(owner);
        uint256 aliceBalanceBefore = token.balanceOf(alice);

        // Decrease by 5% (500 basis points)
        token.rebaseByPercentage(500, false);

        uint256 expectedTotalSupply = INITIAL_SUPPLY - (INITIAL_SUPPLY * 500) / 10_000;
        assertEq(token.totalSupply(), expectedTotalSupply);

        // Balances should decrease by 5%
        assertEq(token.balanceOf(owner), ownerBalanceBefore - (ownerBalanceBefore * 500) / 10_000);
        assertEq(token.balanceOf(alice), aliceBalanceBefore - (aliceBalanceBefore * 500) / 10_000);
    }

    function testMint() public {
        uint256 mintAmount = 100_000 * 10 ** 18;

        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), alice, mintAmount);
        token.mint(alice, mintAmount);

        assertEq(token.balanceOf(alice), mintAmount);
        assertEq(token.totalSupply(), INITIAL_SUPPLY + mintAmount);
    }

    function testBurn() public {
        uint256 burnAmount = 100_000 * 10 ** 18;

        vm.expectEmit(true, true, false, true);
        emit Transfer(owner, address(0), burnAmount);
        token.burn(owner, burnAmount);

        assertEq(token.balanceOf(owner), INITIAL_SUPPLY - burnAmount);
        assertEq(token.totalSupply(), INITIAL_SUPPLY - burnAmount);
    }

    function testSharesConversion() public {
        uint256 tokenAmount = 100_000 * 10 ** 18;
        uint256 shares = token.getSharesByTokenAmount(tokenAmount);

        // Before rebase, 1 token = 1 share
        assertEq(shares, tokenAmount);

        // After rebase, conversion should change
        token.rebase(2_000_000 * 10 ** 18);

        uint256 newShares = token.getSharesByTokenAmount(tokenAmount);
        assertEq(newShares, tokenAmount / 2); // Shares should be half for same token amount
    }

    function testOnlyOwnerCanRebase() public {
        vm.prank(alice);
        vm.expectRevert();
        token.rebase(2_000_000 * 10 ** 18);
    }

    function testOnlyOwnerCanMint() public {
        vm.prank(alice);
        vm.expectRevert();
        token.mint(alice, 100_000 * 10 ** 18);
    }

    function testOnlyOwnerCanBurn() public {
        vm.prank(alice);
        vm.expectRevert();
        token.burn(owner, 100_000 * 10 ** 18);
    }

    function testCannotRebaseToZero() public {
        vm.expectRevert("New supply must be positive");
        token.rebase(0);
    }

    function testCannotBurnMoreThanBalance() public {
        uint256 burnAmount = INITIAL_SUPPLY + 1;
        vm.expectRevert("Burn amount exceeds balance");
        token.burn(owner, burnAmount);
    }

    function testFuzzTransfer(uint256 amount) public {
        vm.assume(amount > 0 && amount <= INITIAL_SUPPLY);

        token.transfer(alice, amount);

        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY - amount);
        assertEq(token.totalSupply(), INITIAL_SUPPLY);
    }

    function testFuzzRebase(uint256 newSupply) public {
        vm.assume(newSupply > 0 && newSupply < type(uint128).max);

        token.transfer(alice, INITIAL_SUPPLY / 2);

        uint256 ownerSharesBefore = token.sharesOf(owner);
        uint256 aliceSharesBefore = token.sharesOf(alice);

        token.rebase(newSupply);

        // Shares should remain unchanged
        assertEq(token.sharesOf(owner), ownerSharesBefore);
        assertEq(token.sharesOf(alice), aliceSharesBefore);

        // But balances should reflect new supply
        assertEq(token.totalSupply(), newSupply);
    }
}
