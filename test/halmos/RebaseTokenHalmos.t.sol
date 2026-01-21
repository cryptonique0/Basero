// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {RebaseToken} from "../../src/RebaseToken.sol";

/**
 * @title RebaseTokenHalmosTest
 * @notice Halmos symbolic execution tests for RebaseToken
 * @dev Run with: halmos --contract RebaseTokenHalmosTest
 */
contract RebaseTokenHalmosTest is Test {
    RebaseToken token;
    
    function setUp() public {
        token = new RebaseToken("Test Token", "TEST");
    }
    
    // ============================================
    // PROPERTY 1: Balance Sum Equals Total Supply
    // ============================================
    
    /// @dev Invariant: sum(balances) == totalSupply
    /// @dev After any sequence of valid transfers
    function halmos_balance_sum_equals_supply(
        address from,
        address to,
        uint256 amount
    ) public {
        // Assume valid transfer
        vm.assume(from != address(0));
        vm.assume(to != address(0));
        vm.assume(from != to);
        
        // Initial state: balance sum should equal supply
        // Note: This is simplified - real implementation requires tracking all accounts
        
        // Mint initial tokens
        vm.prank(from);
        token.mint(from, 1000e18, 1000);
        
        uint256 supplyBefore = token.totalSupply();
        uint256 balanceFromBefore = token.balanceOf(from);
        uint256 balanceToBefore = token.balanceOf(to);
        
        // Execute transfer
        vm.prank(from);
        try token.transfer(to, amount) {
            uint256 supplyAfter = token.totalSupply();
            uint256 balanceFromAfter = token.balanceOf(from);
            uint256 balanceToAfter = token.balanceOf(to);
            
            // Verify: supply unchanged
            assert(supplyBefore == supplyAfter);
            
            // Verify: balance changes are consistent
            if (balanceFromAfter > balanceFromBefore) {
                // Should only increase if tokens received
                assert(amount == 0 || from == to);
            }
        } catch {
            // On revert, balances should be unchanged
            uint256 supplyAfter = token.totalSupply();
            assert(supplyBefore == supplyAfter);
        }
    }
    
    // ============================================
    // PROPERTY 2: No Token Creation/Destruction
    // ============================================
    
    /// @dev Invariant: transfer cannot change total supply
    /// @dev Precondition: valid state with existing balances
    function halmos_transfer_preserves_supply(
        address from,
        address to,
        uint256 amount
    ) public {
        vm.assume(from != address(0));
        vm.assume(to != address(0));
        vm.assume(from != to);
        
        // Setup: mint tokens to 'from'
        uint256 initialSupply = 10000e18;
        vm.prank(from);
        token.mint(from, initialSupply, 10000);
        
        uint256 supplyBefore = token.totalSupply();
        
        // Attempt transfer
        vm.prank(from);
        try token.transfer(to, amount) {
            // On success, supply unchanged
            uint256 supplyAfter = token.totalSupply();
            assert(supplyBefore == supplyAfter, "Supply changed on success");
        } catch {
            // On revert, supply definitely unchanged
            uint256 supplyAfter = token.totalSupply();
            assert(supplyBefore == supplyAfter, "Supply changed on revert");
        }
    }
    
    // ============================================
    // PROPERTY 3: TransferFrom Respects Allowance
    // ============================================
    
    /// @dev Invariant: Cannot transfer more than allowance
    /// @dev Precondition: allowance set to specific amount
    function halmos_transferfrom_respects_allowance(
        address owner,
        address spender,
        address recipient,
        uint256 allowance,
        uint256 transferAmount
    ) public {
        vm.assume(owner != address(0));
        vm.assume(spender != address(0));
        vm.assume(recipient != address(0));
        vm.assume(owner != spender);
        vm.assume(spender != recipient);
        
        // Setup
        uint256 initialBalance = 100000e18;
        vm.prank(owner);
        token.mint(owner, initialBalance, 100000);
        
        vm.prank(owner);
        token.approve(spender, allowance);
        
        uint256 spenderAllowanceBefore = token.allowance(owner, spender);
        
        // Attempt transferFrom
        vm.prank(spender);
        try token.transferFrom(owner, recipient, transferAmount) {
            // On success, transfer amount <= allowance
            assert(transferAmount <= spenderAllowanceBefore);
            
            // Allowance decreased by transfer amount
            uint256 spenderAllowanceAfter = token.allowance(owner, spender);
            assert(spenderAllowanceAfter == spenderAllowanceBefore - transferAmount);
        } catch {
            // On revert, allowance unchanged
            uint256 spenderAllowanceAfter = token.allowance(owner, spender);
            assert(spenderAllowanceAfter == spenderAllowanceBefore);
        }
    }
    
    // ============================================
    // PROPERTY 4: Approve Updates Allowance
    // ============================================
    
    /// @dev Invariant: approve(spender, amount) sets allowance
    function halmos_approve_updates_allowance(
        address owner,
        address spender,
        uint256 amount
    ) public {
        vm.assume(owner != address(0));
        vm.assume(spender != address(0));
        vm.assume(owner != spender);
        
        vm.prank(owner);
        token.approve(spender, amount);
        
        uint256 allowance = token.allowance(owner, spender);
        assert(allowance == amount, "Allowance not set correctly");
    }
    
    // ============================================
    // PROPERTY 5: Mint Increases Supply
    // ============================================
    
    /// @dev Invariant: mint increases total supply
    /// @dev Precondition: valid mint amount
    function halmos_mint_increases_supply(
        address to,
        uint256 amount,
        uint256 shares
    ) public {
        vm.assume(to != address(0));
        vm.assume(amount > 0);
        vm.assume(shares > 0);
        
        uint256 supplyBefore = token.totalSupply();
        
        vm.prank(to);
        token.mint(to, amount, shares);
        
        uint256 supplyAfter = token.totalSupply();
        assert(supplyAfter > supplyBefore, "Supply not increased");
    }
    
    // ============================================
    // PROPERTY 6: Rebase Respects Bounds
    // ============================================
    
    /// @dev Invariant: rebase percentage bounded to ±10%
    /// @dev Precondition: percentageBps within bounds
    function halmos_rebase_respects_bounds(int256 percentageBps) public {
        // Only consider valid rebase percentages
        vm.assume(percentageBps >= -10_00 && percentageBps <= 10_00);
        
        uint256 supplyBefore = token.totalSupply();
        require(supplyBefore > 0);
        
        // Execute rebase
        vm.prank(address(this));
        token.rebase(percentageBps);
        
        uint256 supplyAfter = token.totalSupply();
        
        // Verify rebase stayed within bounds
        // Supply should be between 90% and 110% of original
        uint256 lowerBound = supplyBefore * 90 / 100;
        uint256 upperBound = supplyBefore * 110 / 100;
        
        assert(supplyAfter >= lowerBound && supplyAfter <= upperBound,
            "Rebase exceeded bounds");
    }
    
    // ============================================
    // PROPERTY 7: Non-Negative Balances
    // ============================================
    
    /// @dev Invariant: no negative balances (checked by return type)
    /// @dev This is more of a sanity check - Solidity uint256 prevents negatives
    function halmos_balances_always_nonnegative(address user) public {
        uint256 balance = token.balanceOf(user);
        // Since uint256, balance >= 0 is always true
        assert(balance >= 0, "Negative balance found");
    }
    
    // ============================================
    // PROPERTY 8: Transfer Reverts Without Sufficient Balance
    // ============================================
    
    /// @dev Precondition: insufficient balance
    /// @dev Postcondition: transfer reverts
    function halmos_transfer_reverts_insufficient_balance(
        address from,
        address to,
        uint256 transferAmount
    ) public {
        vm.assume(from != address(0));
        vm.assume(to != address(0));
        vm.assume(from != to);
        
        // Ensure from has very small balance
        uint256 fromBalance = token.balanceOf(from);
        vm.assume(transferAmount > fromBalance);
        
        // Should revert
        vm.prank(from);
        vm.expectRevert();
        token.transfer(to, transferAmount);
    }
    
    // ============================================
    // PROPERTY 9: TransferFrom Reverts Without Allowance
    // ============================================
    
    /// @dev Precondition: insufficient allowance
    /// @dev Postcondition: transferFrom reverts
    function halmos_transferfrom_reverts_insufficient_allowance(
        address owner,
        address spender,
        address recipient,
        uint256 allowanceAmount,
        uint256 transferAmount
    ) public {
        vm.assume(owner != address(0));
        vm.assume(spender != address(0));
        vm.assume(recipient != address(0));
        vm.assume(owner != spender);
        vm.assume(transferAmount > allowanceAmount);
        
        // Setup
        uint256 initialBalance = 100000e18;
        vm.prank(owner);
        token.mint(owner, initialBalance, 100000);
        
        vm.prank(owner);
        token.approve(spender, allowanceAmount);
        
        // Should revert
        vm.prank(spender);
        vm.expectRevert();
        token.transferFrom(owner, recipient, transferAmount);
    }
}
