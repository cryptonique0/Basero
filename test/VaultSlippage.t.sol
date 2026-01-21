// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {RebaseTokenVault} from "../src/RebaseTokenVault.sol";

contract VaultSlippageTest is Test {
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

    // ===== Slippage Protection Tests =====

    function testRedeemWithMinOutEnforcesSlippage() public {
        vm.prank(alice);
        vault.deposit{value: 10 ether}();

        uint256 previewAmount = vault.previewRedeem(10 ether);

        vm.prank(alice);
        vault.redeemWithMinOut(10 ether, previewAmount);

        assertEq(token.balanceOf(alice), 0);
    }

    function testRedeemWithMinOutFailsWhenSlippageTooHigh() public {
        vm.prank(alice);
        vault.deposit{value: 10 ether}();

        uint256 previewAmount = vault.previewRedeem(10 ether);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                RebaseTokenVault.SlippageTooHigh.selector,
                previewAmount,
                previewAmount + 1 ether
            )
        );
        vault.redeemWithMinOut(10 ether, previewAmount + 1 ether);
    }

    function testRedeemWithMinOutZeroAllows() public {
        vm.prank(alice);
        vault.deposit{value: 10 ether}();

        vm.prank(alice);
        vault.redeemWithMinOut(10 ether, 0);

        assertEq(token.balanceOf(alice), 0);
    }

    function testRedeemWrapperCallsRedeemWithMinOut() public {
        vm.prank(alice);
        vault.deposit{value: 10 ether}();

        uint256 balanceBefore = alice.balance;

        vm.prank(alice);
        vault.redeem(10 ether);

        assertGt(alice.balance, balanceBefore);
        assertEq(token.balanceOf(alice), 0);
    }

    // ===== Edge Cases for Slippage =====

    function testPartialRedeemWithSlippage() public {
        vm.prank(alice);
        vault.deposit{value: 20 ether}();

        uint256 previewAmount = vault.previewRedeem(10 ether);

        vm.prank(alice);
        vault.redeemWithMinOut(10 ether, previewAmount);

        assertEq(token.balanceOf(alice), 10 ether);
    }

    function testFuzzSlippageProtection(uint256 slippageBps) public {
        vm.assume(slippageBps <= 10_000);

        vm.prank(alice);
        vault.deposit{value: 100 ether}();

        uint256 previewAmount = vault.previewRedeem(100 ether);
        uint256 minOut = (previewAmount * (10_000 - slippageBps)) / 10_000;

        if (slippageBps == 0) {
            vm.prank(alice);
            vault.redeemWithMinOut(100 ether, minOut);
        } else if (slippageBps < 10_000) {
            vm.prank(alice);
            vault.redeemWithMinOut(100 ether, minOut);
        } else {
            vm.prank(alice);
            vm.expectRevert(RebaseTokenVault.SlippageTooHigh.selector);
            vault.redeemWithMinOut(100 ether, minOut);
        }
    }
}
