// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {RebaseTokenVault} from "../src/RebaseTokenVault.sol";
import {VotingEscrow} from "../src/governance/VotingEscrow.sol";
import {GovernorAlpha} from "../src/governance/GovernorAlpha.sol";
import {Timelock} from "../src/governance/Timelock.sol";
import {EnhancedCCIPBridge} from "../src/EnhancedCCIPBridge.sol";
import {AdvancedStrategyVault} from "../src/AdvancedStrategyVault.sol";

/**
 * @title GasProfiler
 * @notice Comprehensive gas profiling suite for all Basero operations
 * @dev Run with: forge test --match-contract GasProfiler --gas-report
 *      Generate snapshot: forge snapshot --match-contract GasProfiler
 */
contract GasProfiler is Test {
    
    RebaseToken public token;
    RebaseTokenVault public vault;
    VotingEscrow public votingEscrow;
    GovernorAlpha public governor;
    Timelock public timelock;
    EnhancedCCIPBridge public bridge;
    AdvancedStrategyVault public advancedVault;
    
    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    address public user3 = address(0x4);
    
    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy core contracts
        token = new RebaseToken("Rebase Token", "REBASE");
        vault = new RebaseTokenVault(address(token));
        
        // Deploy governance
        votingEscrow = new VotingEscrow(address(token));
        timelock = new Timelock(owner, 2 days);
        governor = new GovernorAlpha(
            address(timelock),
            address(votingEscrow),
            5760,
            40320,
            100 ether
        );
        
        // Set up timelock
        timelock.setPendingAdmin(address(governor));
        vm.stopPrank();
        
        vm.prank(address(governor));
        timelock.acceptAdmin();
        
        // Fund test users
        vm.deal(user1, 1000 ether);
        vm.deal(user2, 1000 ether);
        vm.deal(user3, 1000 ether);
        
        // Give users tokens
        vm.startPrank(owner);
        token.mint(user1, 10000 ether, 1000);
        token.mint(user2, 10000 ether, 1000);
        token.mint(user3, 10000 ether, 1000);
        vm.stopPrank();
        
        // Approve contracts
        vm.prank(user1);
        token.approve(address(votingEscrow), type(uint256).max);
        vm.prank(user2);
        token.approve(address(votingEscrow), type(uint256).max);
        vm.prank(user3);
        token.approve(address(votingEscrow), type(uint256).max);
    }
    
    // ============================================
    // VAULT OPERATIONS - Gas Profiling
    // ============================================
    
    /// @notice Profile: First deposit (cold storage)
    function testGas_VaultDeposit_First() public {
        vm.prank(user1);
        vault.deposit{value: 1 ether}();
    }
    
    /// @notice Profile: Subsequent deposit (warm storage)
    function testGas_VaultDeposit_Subsequent() public {
        vm.prank(user1);
        vault.deposit{value: 1 ether}();
        
        vm.prank(user1);
        vault.deposit{value: 1 ether}();
    }
    
    /// @notice Profile: Small deposit (0.01 ETH)
    function testGas_VaultDeposit_Small() public {
        vm.prank(user1);
        vault.deposit{value: 0.01 ether}();
    }
    
    /// @notice Profile: Large deposit (100 ETH)
    function testGas_VaultDeposit_Large() public {
        vm.prank(user1);
        vault.deposit{value: 100 ether}();
    }
    
    /// @notice Profile: First withdrawal
    function testGas_VaultWithdraw_First() public {
        vm.prank(user1);
        vault.deposit{value: 10 ether}();
        
        vm.prank(user1);
        vault.withdraw(5 ether);
    }
    
    /// @notice Profile: Full withdrawal
    function testGas_VaultWithdraw_Full() public {
        vm.prank(user1);
        vault.deposit{value: 10 ether}();
        
        vm.prank(user1);
        vault.withdraw(10 ether);
    }
    
    /// @notice Profile: Interest accrual
    function testGas_VaultAccrueInterest() public {
        vm.prank(user1);
        vault.deposit{value: 100 ether}();
        
        vm.warp(block.timestamp + 1 days);
        
        vm.prank(owner);
        vault.accrueInterest();
    }
    
    // ============================================
    // TOKEN OPERATIONS - Gas Profiling
    // ============================================
    
    /// @notice Profile: First transfer (cold storage)
    function testGas_TokenTransfer_First() public {
        vm.prank(user1);
        token.transfer(user2, 100 ether);
    }
    
    /// @notice Profile: Subsequent transfer (warm storage)
    function testGas_TokenTransfer_Subsequent() public {
        vm.prank(user1);
        token.transfer(user2, 100 ether);
        
        vm.prank(user1);
        token.transfer(user2, 100 ether);
    }
    
    /// @notice Profile: Transfer to new address
    function testGas_TokenTransfer_NewAddress() public {
        vm.prank(user1);
        token.transfer(address(0x999), 100 ether);
    }
    
    /// @notice Profile: Approve
    function testGas_TokenApprove() public {
        vm.prank(user1);
        token.approve(user2, 1000 ether);
    }
    
    /// @notice Profile: TransferFrom (with approval)
    function testGas_TokenTransferFrom() public {
        vm.prank(user1);
        token.approve(user2, 1000 ether);
        
        vm.prank(user2);
        token.transferFrom(user1, user3, 100 ether);
    }
    
    /// @notice Profile: Mint (owner operation)
    function testGas_TokenMint() public {
        vm.prank(owner);
        token.mint(user1, 100 ether, 1000);
    }
    
    /// @notice Profile: Rebase (positive)
    function testGas_TokenRebase_Positive() public {
        vm.prank(owner);
        token.rebase(1000 ether, 500); // +1000 ETH, 5% rate
    }
    
    /// @notice Profile: Rebase (negative)
    function testGas_TokenRebase_Negative() public {
        vm.prank(owner);
        token.rebase(-500 ether, 500);
    }
    
    // ============================================
    // GOVERNANCE OPERATIONS - Gas Profiling
    // ============================================
    
    /// @notice Profile: Create lock (first time)
    function testGas_VotingEscrowCreateLock_First() public {
        vm.prank(user1);
        votingEscrow.createLock(1000 ether, block.timestamp + 365 days);
    }
    
    /// @notice Profile: Increase lock amount
    function testGas_VotingEscrowIncreaseLock() public {
        vm.prank(user1);
        votingEscrow.createLock(1000 ether, block.timestamp + 365 days);
        
        vm.prank(user1);
        votingEscrow.increaseAmount(500 ether);
    }
    
    /// @notice Profile: Extend lock time
    function testGas_VotingEscrowExtendLock() public {
        vm.prank(user1);
        votingEscrow.createLock(1000 ether, block.timestamp + 365 days);
        
        vm.warp(block.timestamp + 30 days);
        
        vm.prank(user1);
        votingEscrow.increaseUnlockTime(block.timestamp + 365 days);
    }
    
    /// @notice Profile: Withdraw after lock expires
    function testGas_VotingEscrowWithdraw() public {
        vm.prank(user1);
        votingEscrow.createLock(1000 ether, block.timestamp + 365 days);
        
        vm.warp(block.timestamp + 366 days);
        
        vm.prank(user1);
        votingEscrow.withdraw();
    }
    
    /// @notice Profile: Delegate voting power
    function testGas_VotingEscrowDelegate() public {
        vm.prank(user1);
        votingEscrow.createLock(1000 ether, block.timestamp + 365 days);
        
        vm.prank(user1);
        votingEscrow.delegate(user2);
    }
    
    /// @notice Profile: Create proposal
    function testGas_GovernorCreateProposal() public {
        // User1 has enough voting power
        vm.prank(user1);
        votingEscrow.createLock(1000 ether, block.timestamp + 365 days);
        
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        string[] memory signatures = new string[](1);
        bytes[] memory calldatas = new bytes[](1);
        
        targets[0] = address(timelock);
        values[0] = 0;
        signatures[0] = "setDelay(uint256)";
        calldatas[0] = abi.encode(3 days);
        
        vm.roll(block.number + 1);
        
        vm.prank(user1);
        governor.propose(targets, values, signatures, calldatas, "Test Proposal");
    }
    
    /// @notice Profile: Cast vote (for)
    function testGas_GovernorVote_For() public {
        // Setup proposal
        vm.prank(user1);
        votingEscrow.createLock(1000 ether, block.timestamp + 365 days);
        
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        string[] memory signatures = new string[](1);
        bytes[] memory calldatas = new bytes[](1);
        
        targets[0] = address(timelock);
        values[0] = 0;
        signatures[0] = "setDelay(uint256)";
        calldatas[0] = abi.encode(3 days);
        
        vm.roll(block.number + 1);
        
        vm.prank(user1);
        uint256 proposalId = governor.propose(targets, values, signatures, calldatas, "Test");
        
        // Advance to voting period
        vm.roll(block.number + 5761);
        
        // Vote
        vm.prank(user1);
        governor.castVote(proposalId, true);
    }
    
    /// @notice Profile: Queue proposal
    function testGas_GovernorQueue() public {
        // Create and pass proposal
        vm.prank(user1);
        votingEscrow.createLock(10000 ether, block.timestamp + 365 days);
        
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        string[] memory signatures = new string[](1);
        bytes[] memory calldatas = new bytes[](1);
        
        targets[0] = address(timelock);
        values[0] = 0;
        signatures[0] = "setDelay(uint256)";
        calldatas[0] = abi.encode(3 days);
        
        vm.roll(block.number + 1);
        
        vm.prank(user1);
        uint256 proposalId = governor.propose(targets, values, signatures, calldatas, "Test");
        
        vm.roll(block.number + 5761);
        
        vm.prank(user1);
        governor.castVote(proposalId, true);
        
        vm.roll(block.number + 40321);
        
        governor.queue(proposalId);
    }
    
    /// @notice Profile: Execute proposal
    function testGas_GovernorExecute() public {
        // Full proposal flow
        vm.prank(user1);
        votingEscrow.createLock(10000 ether, block.timestamp + 365 days);
        
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        string[] memory signatures = new string[](1);
        bytes[] memory calldatas = new bytes[](1);
        
        targets[0] = address(timelock);
        values[0] = 0;
        signatures[0] = "setDelay(uint256)";
        calldatas[0] = abi.encode(3 days);
        
        vm.roll(block.number + 1);
        
        vm.prank(user1);
        uint256 proposalId = governor.propose(targets, values, signatures, calldatas, "Test");
        
        vm.roll(block.number + 5761);
        vm.prank(user1);
        governor.castVote(proposalId, true);
        
        vm.roll(block.number + 40321);
        governor.queue(proposalId);
        
        vm.warp(block.timestamp + 2 days + 1);
        
        governor.execute(proposalId);
    }
    
    // ============================================
    // BATCH OPERATIONS - Gas Comparison
    // ============================================
    
    /// @notice Profile: Individual deposits (baseline)
    function testGas_IndividualDeposits_3Users() public {
        vm.prank(user1);
        vault.deposit{value: 1 ether}();
        
        vm.prank(user2);
        vault.deposit{value: 1 ether}();
        
        vm.prank(user3);
        vault.deposit{value: 1 ether}();
    }
    
    /// @notice Profile: Individual transfers (baseline)
    function testGas_IndividualTransfers_3Txs() public {
        vm.startPrank(user1);
        token.transfer(user2, 100 ether);
        token.transfer(user3, 100 ether);
        token.transfer(owner, 100 ether);
        vm.stopPrank();
    }
    
    // ============================================
    // VIEW FUNCTIONS - Gas Profiling
    // ============================================
    
    /// @notice Profile: Balance query (cold)
    function testGas_TokenBalanceOf_Cold() public view {
        token.balanceOf(user1);
    }
    
    /// @notice Profile: Total supply query
    function testGas_TokenTotalSupply() public view {
        token.totalSupply();
    }
    
    /// @notice Profile: Vault deposit amount query
    function testGas_VaultDepositedAmount() public view {
        vault.depositedAmount(user1);
    }
    
    /// @notice Profile: Voting power query
    function testGas_VotingEscrowBalanceOf() public {
        vm.prank(user1);
        votingEscrow.createLock(1000 ether, block.timestamp + 365 days);
        
        vm.roll(block.number + 1);
        
        votingEscrow.balanceOf(user1);
    }
    
    /// @notice Profile: Historical voting power query
    function testGas_VotingEscrowBalanceOfAt() public {
        vm.prank(user1);
        votingEscrow.createLock(1000 ether, block.timestamp + 365 days);
        
        vm.roll(block.number + 100);
        
        votingEscrow.balanceOfAt(user1, block.number - 50);
    }
    
    /// @notice Profile: Proposal state query
    function testGas_GovernorProposalState() public {
        vm.prank(user1);
        votingEscrow.createLock(1000 ether, block.timestamp + 365 days);
        
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        string[] memory signatures = new string[](1);
        bytes[] memory calldatas = new bytes[](1);
        
        targets[0] = address(timelock);
        values[0] = 0;
        signatures[0] = "setDelay(uint256)";
        calldatas[0] = abi.encode(3 days);
        
        vm.roll(block.number + 1);
        
        vm.prank(user1);
        uint256 proposalId = governor.propose(targets, values, signatures, calldatas, "Test");
        
        governor.state(proposalId);
    }
}

/**
 * @title GasOptimizationComparison
 * @notice Compare gas costs of optimized vs unoptimized implementations
 */
contract GasOptimizationComparison is Test {
    
    RebaseToken public token;
    RebaseTokenVault public vault;
    
    address public owner = address(0x1);
    address public user1 = address(0x2);
    
    function setUp() public {
        vm.startPrank(owner);
        token = new RebaseToken("Rebase Token", "REBASE");
        vault = new RebaseTokenVault(address(token));
        vm.stopPrank();
        
        vm.deal(user1, 1000 ether);
    }
    
    /// @notice Baseline: Uncached storage reads
    function testGas_UncachedStorageReads() public view {
        uint256 total = 0;
        for (uint256 i = 0; i < 5; i++) {
            total += token.totalSupply(); // 5 SLOAD operations
        }
    }
    
    /// @notice Optimized: Cached storage reads
    function testGas_CachedStorageReads() public view {
        uint256 cached = token.totalSupply(); // 1 SLOAD
        uint256 total = 0;
        for (uint256 i = 0; i < 5; i++) {
            total += cached; // Memory reads
        }
    }
    
    /// @notice Baseline: Multiple external calls
    function testGas_MultipleExternalCalls() public view {
        token.balanceOf(user1);
        token.balanceOf(user1);
        token.balanceOf(user1);
    }
    
    /// @notice Optimized: Single external call
    function testGas_SingleExternalCall() public view {
        uint256 balance = token.balanceOf(user1);
        // Use balance multiple times
    }
    
    /// @notice Baseline: Array iteration without caching length
    function testGas_ArrayIterationUncachedLength() public pure {
        uint256[] memory arr = new uint256[](100);
        uint256 sum = 0;
        for (uint256 i = 0; i < arr.length; i++) {
            sum += arr[i];
        }
    }
    
    /// @notice Optimized: Array iteration with cached length
    function testGas_ArrayIterationCachedLength() public pure {
        uint256[] memory arr = new uint256[](100);
        uint256 sum = 0;
        uint256 length = arr.length;
        for (uint256 i = 0; i < length; i++) {
            sum += arr[i];
        }
    }
    
    /// @notice Baseline: Uint256 for small numbers
    function testGas_Uint256ForSmallNumbers() public pure {
        uint256 a = 1;
        uint256 b = 2;
        uint256 c = a + b;
    }
    
    /// @notice Optimized: Uint8 for small numbers (when packed)
    function testGas_PackedUints() public pure {
        uint8 a = 1;
        uint8 b = 2;
        uint8 c = a + b;
    }
}

/**
 * @title CalldataAnalysis
 * @notice Analyze calldata costs for different encoding strategies
 */
contract CalldataAnalysis is Test {
    
    /// @notice Baseline: Uncompressed addresses
    function testGas_CalldataAddresses_Uncompressed(
        address addr1,
        address addr2,
        address addr3
    ) public pure {
        // 3 addresses = 3 * 32 bytes = 96 bytes
    }
    
    /// @notice Optimized: Packed addresses (not standard but for analysis)
    function testGas_CalldataAddresses_Packed(
        address[3] calldata addrs
    ) public pure {
        // Array packing analysis
    }
    
    /// @notice Baseline: Uncompressed amounts
    function testGas_CalldataAmounts_Full(
        uint256 amount1,
        uint256 amount2,
        uint256 amount3
    ) public pure {
        // 3 * 32 bytes = 96 bytes
    }
    
    /// @notice Optimized: Smaller uint sizes
    function testGas_CalldataAmounts_Compressed(
        uint128 amount1,
        uint128 amount2,
        uint128 amount3
    ) public pure {
        // 3 * 16 bytes = 48 bytes (50% reduction)
    }
    
    /// @notice Baseline: Multiple bool parameters
    function testGas_CalldataBools_Separate(
        bool flag1,
        bool flag2,
        bool flag3,
        bool flag4
    ) public pure {
        // 4 * 32 bytes = 128 bytes
    }
    
    /// @notice Optimized: Packed bools in uint8
    function testGas_CalldataBools_Packed(
        uint8 flags // bits 0-3 represent bools
    ) public pure {
        // 1 * 32 bytes = 32 bytes (75% reduction)
        bool flag1 = (flags & 0x01) != 0;
        bool flag2 = (flags & 0x02) != 0;
        bool flag3 = (flags & 0x04) != 0;
        bool flag4 = (flags & 0x08) != 0;
    }
    
    /// @notice Baseline: String parameter
    function testGas_CalldataString(
        string calldata description
    ) public pure {
        // Variable length
    }
    
    /// @notice Optimized: Bytes32 (for fixed-length strings)
    function testGas_CalldataBytes32(
        bytes32 description
    ) public pure {
        // Fixed 32 bytes
    }
}
