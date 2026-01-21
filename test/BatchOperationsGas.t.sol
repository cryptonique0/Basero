// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {BatchVaultOperations, BatchTokenOperations, BatchGovernanceOperations, MultiCall} from "../src/libraries/BatchOperations.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {RebaseTokenVault} from "../src/RebaseTokenVault.sol";
import {VotingEscrow} from "../src/governance/VotingEscrow.sol";

/**
 * @title BatchOperationsGasTest
 * @notice Compare gas costs: batch operations vs individual transactions
 * @dev Run with: forge test --match-contract BatchOperationsGasTest --gas-report
 */
contract BatchOperationsGasTest is Test {
    
    BatchVaultOperations public batchVault;
    BatchTokenOperations public batchToken;
    BatchGovernanceOperations public batchGov;
    MultiCall public multiCall;
    
    RebaseToken public token;
    RebaseTokenVault public vault;
    VotingEscrow public votingEscrow;
    
    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    address public user3 = address(0x4);
    address public user4 = address(0x5);
    address public user5 = address(0x6);
    
    function setUp() public {
        // Deploy batch operation contracts
        batchVault = new BatchVaultOperations();
        batchToken = new BatchTokenOperations();
        batchGov = new BatchGovernanceOperations();
        multiCall = new MultiCall();
        
        // Deploy protocol contracts
        vm.startPrank(owner);
        token = new RebaseToken("Rebase Token", "REBASE");
        vault = new RebaseTokenVault(address(token));
        votingEscrow = new VotingEscrow(address(token));
        vm.stopPrank();
        
        // Fund users
        vm.deal(user1, 1000 ether);
        vm.deal(user2, 1000 ether);
        vm.deal(user3, 1000 ether);
        vm.deal(user4, 1000 ether);
        vm.deal(user5, 1000 ether);
        
        // Mint tokens
        vm.startPrank(owner);
        token.mint(user1, 10000 ether, 1000);
        token.mint(user2, 10000 ether, 1000);
        token.mint(user3, 10000 ether, 1000);
        vm.stopPrank();
    }
    
    // ============================================
    // VAULT BATCH OPERATIONS - Gas Comparison
    // ============================================
    
    /// @notice Baseline: 5 individual deposits
    /// @dev Expected: ~21k * 5 = 105k gas overhead + operation costs
    function testGas_IndividualDeposits_5Users() public {
        vm.prank(user1);
        vault.deposit{value: 1 ether}();
        
        vm.prank(user2);
        vault.deposit{value: 1 ether}();
        
        vm.prank(user3);
        vault.deposit{value: 1 ether}();
        
        vm.prank(user4);
        vault.deposit{value: 1 ether}();
        
        vm.prank(user5);
        vault.deposit{value: 1 ether}();
    }
    
    /// @notice Optimized: Batch deposit for 5 users
    /// @dev Expected: ~21k gas overhead + operation costs
    /// @dev Savings: ~84k gas (4 * 21k transaction overhead)
    function testGas_BatchDeposit_5Users() public {
        address[] memory recipients = new address[](5);
        recipients[0] = user1;
        recipients[1] = user2;
        recipients[2] = user3;
        recipients[3] = user4;
        recipients[4] = user5;
        
        uint256[] memory amounts = new uint256[](5);
        amounts[0] = 1 ether;
        amounts[1] = 1 ether;
        amounts[2] = 1 ether;
        amounts[3] = 1 ether;
        amounts[4] = 1 ether;
        
        vm.prank(user1);
        batchVault.batchDepositFor{value: 5 ether}(
            payable(address(vault)),
            recipients,
            amounts
        );
    }
    
    /// @notice Baseline: 10 individual withdrawals
    function testGas_IndividualWithdrawals_10Times() public {
        // Setup: deposit first
        vm.prank(user1);
        vault.deposit{value: 100 ether}();
        
        // 10 individual withdrawals
        vm.startPrank(user1);
        for (uint256 i = 0; i < 10; i++) {
            vault.withdraw(1 ether);
        }
        vm.stopPrank();
    }
    
    /// @notice Optimized: Batch withdrawal
    function testGas_BatchWithdrawal_10Times() public {
        // Setup: deposit first
        vm.prank(user1);
        vault.deposit{value: 100 ether}();
        
        // Batch withdrawal
        uint256[] memory amounts = new uint256[](10);
        for (uint256 i = 0; i < 10; i++) {
            amounts[i] = 1 ether;
        }
        
        vm.prank(user1);
        batchVault.batchWithdraw(address(vault), amounts);
    }
    
    // ============================================
    // TOKEN BATCH OPERATIONS - Gas Comparison
    // ============================================
    
    /// @notice Baseline: 10 individual transfers
    function testGas_IndividualTransfers_10Recipients() public {
        vm.startPrank(user1);
        
        token.transfer(user2, 10 ether);
        token.transfer(user3, 10 ether);
        token.transfer(user4, 10 ether);
        token.transfer(user5, 10 ether);
        token.transfer(address(0x10), 10 ether);
        token.transfer(address(0x11), 10 ether);
        token.transfer(address(0x12), 10 ether);
        token.transfer(address(0x13), 10 ether);
        token.transfer(address(0x14), 10 ether);
        token.transfer(address(0x15), 10 ether);
        
        vm.stopPrank();
    }
    
    /// @notice Optimized: Batch transfer to 10 recipients
    function testGas_BatchTransfer_10Recipients() public {
        address[] memory recipients = new address[](10);
        recipients[0] = user2;
        recipients[1] = user3;
        recipients[2] = user4;
        recipients[3] = user5;
        recipients[4] = address(0x10);
        recipients[5] = address(0x11);
        recipients[6] = address(0x12);
        recipients[7] = address(0x13);
        recipients[8] = address(0x14);
        recipients[9] = address(0x15);
        
        uint256[] memory amounts = new uint256[](10);
        for (uint256 i = 0; i < 10; i++) {
            amounts[i] = 10 ether;
        }
        
        // Approve batch contract
        vm.prank(user1);
        token.approve(address(batchToken), 100 ether);
        
        vm.prank(user1);
        batchToken.batchTransfer(address(token), recipients, amounts);
    }
    
    /// @notice Baseline: 5 individual approvals
    function testGas_IndividualApprovals_5Spenders() public {
        vm.startPrank(user1);
        
        token.approve(user2, 100 ether);
        token.approve(user3, 100 ether);
        token.approve(user4, 100 ether);
        token.approve(user5, 100 ether);
        token.approve(address(batchToken), 100 ether);
        
        vm.stopPrank();
    }
    
    /// @notice Optimized: Batch approval
    function testGas_BatchApproval_5Spenders() public {
        address[] memory spenders = new address[](5);
        spenders[0] = user2;
        spenders[1] = user3;
        spenders[2] = user4;
        spenders[3] = user5;
        spenders[4] = address(batchToken);
        
        uint256[] memory amounts = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            amounts[i] = 100 ether;
        }
        
        vm.prank(user1);
        batchToken.batchApprove(address(token), spenders, amounts);
    }
    
    // ============================================
    // MULTICALL - Gas Comparison
    // ============================================
    
    /// @notice Baseline: 3 separate view calls
    function testGas_IndividualViewCalls_3Calls() public view {
        token.balanceOf(user1);
        token.balanceOf(user2);
        token.balanceOf(user3);
    }
    
    /// @notice Optimized: MultiCall for 3 view calls
    function testGas_MultiCall_3ViewCalls() public {
        MultiCall.Call[] memory calls = new MultiCall.Call[](3);
        
        calls[0] = MultiCall.Call({
            target: address(token),
            callData: abi.encodeWithSignature("balanceOf(address)", user1)
        });
        
        calls[1] = MultiCall.Call({
            target: address(token),
            callData: abi.encodeWithSignature("balanceOf(address)", user2)
        });
        
        calls[2] = MultiCall.Call({
            target: address(token),
            callData: abi.encodeWithSignature("balanceOf(address)", user3)
        });
        
        multiCall.aggregate(calls);
    }
    
    /// @notice MultiCall: 10 mixed operations
    function testGas_MultiCall_10MixedOperations() public {
        MultiCall.Call[] memory calls = new MultiCall.Call[](10);
        
        // 5 balance queries
        for (uint256 i = 0; i < 5; i++) {
            calls[i] = MultiCall.Call({
                target: address(token),
                callData: abi.encodeWithSignature("balanceOf(address)", address(uint160(i + 2)))
            });
        }
        
        // 5 allowance queries
        for (uint256 i = 5; i < 10; i++) {
            calls[i] = MultiCall.Call({
                target: address(token),
                callData: abi.encodeWithSignature("allowance(address,address)", user1, address(uint160(i)))
            });
        }
        
        multiCall.aggregate(calls);
    }
    
    // ============================================
    // GAS SAVINGS ANALYSIS
    // ============================================
    
    /// @notice Calculate gas savings for batch deposits
    function testGasSavings_BatchDeposit() public {
        uint256 gasIndividual;
        uint256 gasBatch;
        
        // Measure individual deposits (5 users)
        uint256 gasBefore = gasleft();
        
        vm.prank(user1);
        vault.deposit{value: 1 ether}();
        vm.prank(user2);
        vault.deposit{value: 1 ether}();
        vm.prank(user3);
        vault.deposit{value: 1 ether}();
        vm.prank(user4);
        vault.deposit{value: 1 ether}();
        vm.prank(user5);
        vault.deposit{value: 1 ether}();
        
        gasIndividual = gasBefore - gasleft();
        
        // Reset vault state
        vm.startPrank(user1);
        vault.withdraw(vault.depositedAmount(user1));
        vm.stopPrank();
        vm.startPrank(user2);
        vault.withdraw(vault.depositedAmount(user2));
        vm.stopPrank();
        vm.startPrank(user3);
        vault.withdraw(vault.depositedAmount(user3));
        vm.stopPrank();
        vm.startPrank(user4);
        vault.withdraw(vault.depositedAmount(user4));
        vm.stopPrank();
        vm.startPrank(user5);
        vault.withdraw(vault.depositedAmount(user5));
        vm.stopPrank();
        
        // Measure batch deposit
        address[] memory recipients = new address[](5);
        recipients[0] = user1;
        recipients[1] = user2;
        recipients[2] = user3;
        recipients[3] = user4;
        recipients[4] = user5;
        
        uint256[] memory amounts = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            amounts[i] = 1 ether;
        }
        
        gasBefore = gasleft();
        
        vm.prank(user1);
        batchVault.batchDepositFor{value: 5 ether}(
            payable(address(vault)),
            recipients,
            amounts
        );
        
        gasBatch = gasBefore - gasleft();
        
        // Log results
        emit log_named_uint("Individual deposits gas", gasIndividual);
        emit log_named_uint("Batch deposit gas", gasBatch);
        emit log_named_uint("Gas saved", gasIndividual - gasBatch);
        emit log_named_uint("Savings percentage", ((gasIndividual - gasBatch) * 100) / gasIndividual);
    }
}
