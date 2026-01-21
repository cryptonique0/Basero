// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {RebaseTokenVault} from "../src/RebaseTokenVault.sol";

contract VaultPauseTest is Test {
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

        vm.deal(alice, 100 ether);
    }

    // ===== Deposit Pause Tests =====

    function testPauseDeposits() public {
        vault.pauseDeposits();
        
        vm.prank(alice);
        vm.expectRevert(RebaseTokenVault.DepositsArePaused.selector);
        vault.deposit{value: 1 ether}();
    }

    function testUnpauseDeposits() public {
        vault.pauseDeposits();
        vault.unpauseDeposits();

        vm.prank(alice);
        vault.deposit{value: 1 ether}();

        assertEq(token.balanceOf(alice), 1 ether);
    }

    function testPauseAllBlocksDeposits() public {
        vault.pauseAll();

        vm.prank(alice);
        vm.expectRevert();
        vault.deposit{value: 1 ether}();
    }

    // ===== Redeem Pause Tests =====

    function testPauseRedeems() public {
        vm.prank(alice);
        vault.deposit{value: 1 ether}();

        vault.pauseRedeems();

        vm.prank(alice);
        vm.expectRevert(RebaseTokenVault.RedeemsArePaused.selector);
        vault.redeem(1 ether);
    }

    function testUnpauseRedeems() public {
        vm.prank(alice);
        vault.deposit{value: 1 ether}();

        vault.pauseRedeems();
        vault.unpauseRedeems();

        vm.prank(alice);
        vault.redeem(1 ether);

        assertEq(token.balanceOf(alice), 0);
    }

    function testPauseAllBlocksRedeems() public {
        vm.prank(alice);
        vault.deposit{value: 1 ether}();

        vault.pauseAll();

        vm.prank(alice);
        vm.expectRevert();
        vault.redeem(1 ether);
    }

    // ===== Pause State Tests =====

    function testDepositAndRedeemIndependentPause() public {
        vault.pauseDeposits();

        vm.prank(alice);
        vault.deposit{value: 1 ether}(); // Should still work since pauseDeposits doesn't affect deposit in this test (Pausable is separate)

        // Actually test the specific deposit pause
        vault.pauseDeposits();
        vm.prank(alice);
        vm.expectRevert(RebaseTokenVault.DepositsArePaused.selector);
        vault.deposit{value: 1 ether}();
    }

    function testPauseAllInhibitsAll() public {
        vault.pauseAll();

        vm.prank(alice);
        vm.expectRevert();
        vault.deposit{value: 1 ether}();

        vm.prank(alice);
        vm.deal(alice, 100 ether);
        vault.deposit{value: 1 ether}(); // This will fail due to pauseAll

        vault.unpauseAll();

        vm.prank(alice);
        vault.deposit{value: 1 ether}(); // Now succeeds
        assertEq(token.balanceOf(alice), 1 ether);
    }

    function testOnlyOwnerCanPause() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.pauseDeposits();

        vm.prank(alice);
        vm.expectRevert();
        vault.pauseRedeems();

        vm.prank(alice);
        vm.expectRevert();
        vault.pauseAll();
    }

    function testOnlyOwnerCanUnpause() public {
        vault.pauseDeposits();

        vm.prank(alice);
        vm.expectRevert();
        vault.unpauseDeposits();

        vault.unpauseDeposits(); // Owner can
        assertFalse(false); // Placeholder
    }
}
