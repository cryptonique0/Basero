// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {RebaseTokenVault} from "../src/RebaseTokenVault.sol";

contract VaultCapsTest is Test {
    RebaseToken public token;
    RebaseTokenVault public vault;

    address public owner;
    address public alice;
    address public bob;

    function setUp() public {
        owner = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        token = new RebaseToken("Cross-Chain Rebase Token", "CCRT");
        vault = new RebaseTokenVault(address(token));
        token.transferOwnership(address(vault));

        vm.deal(alice, 1000 ether);
        vm.deal(bob, 1000 ether);
    }

    // ===== Per-User Deposit Cap Tests =====

    function testPerUserDepositCapEnforced() public {
        vault.setDepositCaps(10 ether, 1000 ether);

        vm.prank(alice);
        vault.deposit{value: 10 ether}();

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(RebaseTokenVault.DepositCapExceeded.selector, 11 ether, 10 ether)
        );
        vault.deposit{value: 1 ether}();
    }

    function testPerUserDepositCapCanBeIncreased() public {
        vault.setDepositCaps(10 ether, 1000 ether);

        vm.prank(alice);
        vault.deposit{value: 10 ether}();

        vault.setDepositCaps(20 ether, 1000 ether);

        vm.prank(alice);
        vault.deposit{value: 10 ether}();

        assertEq(token.balanceOf(alice), 20 ether);
    }

    // ===== Global TVL Cap Tests =====

    function testGlobalTvlCapEnforced() public {
        vault.setDepositCaps(100 ether, 25 ether);

        vm.prank(alice);
        vault.deposit{value: 15 ether}();

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(RebaseTokenVault.TvlCapExceeded.selector, 25 ether, 25 ether)
        );
        vault.deposit{value: 10 ether}();

        vm.prank(bob);
        vault.deposit{value: 10 ether}(); // This succeeds: 15 + 10 = 25
        assertEq(vault.getTotalEthDeposited(), 25 ether);
    }

    function testGlobalTvlCapCanBeIncreased() public {
        vault.setDepositCaps(100 ether, 20 ether);

        vm.prank(alice);
        vault.deposit{value: 15 ether}();

        vault.setDepositCaps(100 ether, 50 ether);

        vm.prank(bob);
        vault.deposit{value: 30 ether}();

        assertEq(vault.getTotalEthDeposited(), 45 ether);
    }

    // ===== Min Deposit Tests =====

    function testMinDepositEnforced() public {
        vault.setMinDeposit(0.5 ether);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(RebaseTokenVault.MinDepositNotMet.selector, 0.1 ether, 0.5 ether)
        );
        vault.deposit{value: 0.1 ether}();

        vm.prank(alice);
        vault.deposit{value: 0.5 ether}();

        assertEq(token.balanceOf(alice), 0.5 ether);
    }

    function testMinDepositZeroAllowsAny() public {
        vault.setMinDeposit(0);

        vm.prank(alice);
        vault.deposit{value: 0.001 ether}();

        assertEq(token.balanceOf(alice), 0.001 ether);
    }

    // ===== Allowlist Tests =====

    function testAllowlistToggle() public {
        vault.setAllowlistStatus(true);

        vm.prank(alice);
        vm.expectRevert(RebaseTokenVault.NotAllowlisted.selector);
        vault.deposit{value: 1 ether}();

        vault.setAllowlist(alice, true);

        vm.prank(alice);
        vault.deposit{value: 1 ether}();

        assertEq(token.balanceOf(alice), 1 ether);
    }

    function testAllowlistDisabledByDefault() public {
        vault.setAllowlistStatus(false);

        vm.prank(alice);
        vault.deposit{value: 1 ether}();

        assertEq(token.balanceOf(alice), 1 ether);
    }

    function testAllowlistMultipleUsers() public {
        vault.setAllowlistStatus(true);
        vault.setAllowlist(alice, true);
        vault.setAllowlist(bob, true);

        vm.prank(alice);
        vault.deposit{value: 1 ether}();

        vm.prank(bob);
        vault.deposit{value: 1 ether}();

        address carol = makeAddr("carol");
        vm.prank(carol);
        vm.expectRevert(RebaseTokenVault.NotAllowlisted.selector);
        vault.deposit{value: 1 ether}();
    }

    function testAllowlistCanBeRemoved() public {
        vault.setAllowlistStatus(true);
        vault.setAllowlist(alice, true);

        vm.prank(alice);
        vault.deposit{value: 1 ether}();

        vault.setAllowlist(alice, false);

        vm.prank(alice);
        vm.expectRevert(RebaseTokenVault.NotAllowlisted.selector);
        vault.deposit{value: 1 ether}();
    }

    // ===== Combined Cap & Allowlist Tests =====

    function testCapsAndAllowlistTogether() public {
        vault.setAllowlistStatus(true);
        vault.setAllowlist(alice, true);
        vault.setAllowlist(bob, true);
        vault.setDepositCaps(10 ether, 15 ether);
        vault.setMinDeposit(0.5 ether);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(RebaseTokenVault.MinDepositNotMet.selector, 0.1 ether, 0.5 ether)
        );
        vault.deposit{value: 0.1 ether}();

        vm.prank(alice);
        vault.deposit{value: 10 ether}();

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(RebaseTokenVault.TvlCapExceeded.selector, 5 ether, 15 ether)
        );
        vault.deposit{value: 5 ether}();

        vm.prank(bob);
        vault.deposit{value: 5 ether}();

        assertEq(vault.getTotalEthDeposited(), 15 ether);
    }

    // ===== Cap Edge Cases =====

    function testCapBoundaryConditions() public {
        vault.setDepositCaps(10 ether, 20 ether);

        vm.prank(alice);
        vault.deposit{value: 10 ether}();

        vm.prank(bob);
        vault.deposit{value: 10 ether}();

        assertEq(vault.getTotalEthDeposited(), 20 ether);

        // Next deposit should fail
        address carol = makeAddr("carol");
        vm.deal(carol, 100 ether);
        vm.prank(carol);
        vm.expectRevert(RebaseTokenVault.TvlCapExceeded.selector);
        vault.deposit{value: 0.1 ether}();
    }
}
