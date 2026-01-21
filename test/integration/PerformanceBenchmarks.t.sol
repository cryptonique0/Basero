// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {RebaseToken} from "src/RebaseToken.sol";
import {RebaseTokenVault} from "src/RebaseTokenVault.sol";
import {VotingEscrow} from "src/VotingEscrow.sol";
import {BASEGovernor} from "src/BASEGovernor.sol";
import {BASETimelock} from "src/BASETimelock.sol";
import {AdvancedInterestStrategy} from "src/AdvancedInterestStrategy.sol";

/**
 * @title PerformanceBenchmarks
 * @notice Comprehensive gas and performance profiling for Basero Protocol
 * 
 * **Metrics:**
 * - Gas costs per operation
 * - Throughput (transactions per block)
 * - Latency (block confirmations needed)
 * - Batch operation efficiency
 * - State update overhead
 * 
 * **Baselines (target):**
 * - Deposit: < 150K gas
 * - Withdraw: < 150K gas
 * - Rebase: < 100K gas + state overhead
 * - Vote: < 100K gas
 * - Propose: < 200K gas
 */
contract PerformanceBenchmarks is Test {
    // Contracts
    RebaseToken public token;
    RebaseTokenVault public vault;
    VotingEscrow public votingEscrow;
    BASEGovernor public governor;
    BASETimelock public timelock;
    AdvancedInterestStrategy public interestStrategy;

    // Test users
    address public owner = address(0x1);
    address public alice = address(0x2);
    address public bob = address(0x3);
    address public charlie = address(0x4);

    // Benchmark results
    struct BenchmarkResult {
        string operation;
        uint256 gasUsed;
        uint256 averageGas;
        uint256 minGas;
        uint256 maxGas;
        uint256 samples;
    }

    BenchmarkResult[] public results;

    function setUp() public {
        vm.startPrank(owner);

        // Deploy protocol contracts
        token = new RebaseToken("Basero", "BASE");
        vault = new RebaseTokenVault(address(token));
        votingEscrow = new VotingEscrow(address(token));
        interestStrategy = new AdvancedInterestStrategy();

        // Governor setup
        timelock = new BASETimelock(2 days, new address[](0), new address[](0), owner);
        governor = new BASEGovernor(
            votingEscrow,
            timelock,
            owner,
            1 days,
            1 days,
            100e18
        );

        // Mint test balances
        token.mint(alice, 1_000_000e18);
        token.mint(bob, 1_000_000e18);
        token.mint(charlie, 1_000_000e18);

        vm.stopPrank();
    }

    // ============= DEPOSIT BENCHMARKS =============

    /**
     * @notice Benchmark: Single deposit
     */
    function bench_SingleDeposit() public {
        uint256 depositAmount = 1000e18;

        vm.startPrank(alice);
        token.approve(address(vault), depositAmount);

        uint256 gasBefore = gasleft();
        vault.deposit(depositAmount, alice);
        uint256 gasUsed = gasBefore - gasleft();

        require(gasUsed < 200000, "Deposit gas too high");

        _recordResult("Single Deposit", gasUsed);
        vm.stopPrank();
    }

    /**
     * @notice Benchmark: Multi-user deposits (batch)
     */
    function bench_MultiUserDeposits() public {
        uint256 depositAmount = 1000e18;
        address[] memory users = new address[](10);
        uint256[] memory amounts = new uint256[](10);

        for (uint256 i = 0; i < 10; i++) {
            users[i] = address(uint160(0x2000 + i));
            amounts[i] = depositAmount;
            vm.prank(owner);
            token.mint(users[i], depositAmount * 2);
        }

        uint256 gasBefore = gasleft();

        for (uint256 i = 0; i < 10; i++) {
            vm.startPrank(users[i]);
            token.approve(address(vault), amounts[i]);
            vault.deposit(amounts[i], users[i]);
            vm.stopPrank();
        }

        uint256 totalGasUsed = gasBefore - gasleft();
        uint256 averagePerDeposit = totalGasUsed / 10;

        _recordResult("Multi-User Deposit (avg)", averagePerDeposit);
    }

    /**
     * @notice Benchmark: Deposits with different amounts
     */
    function bench_DepositSizes() public {
        uint256[] memory sizes = new uint256[](4);
        sizes[0] = 100e18;
        sizes[1] = 1000e18;
        sizes[2] = 10000e18;
        sizes[3] = 100000e18;

        for (uint256 i = 0; i < sizes.length; i++) {
            vm.startPrank(alice);
            token.approve(address(vault), sizes[i]);

            uint256 gasBefore = gasleft();
            vault.deposit(sizes[i], alice);
            uint256 gasUsed = gasBefore - gasleft();

            string memory label = string(
                abi.encodePacked("Deposit ", _uint2str(sizes[i] / 1e18), " tokens")
            );
            _recordResult(label, gasUsed);

            vm.stopPrank();
        }
    }

    // ============= WITHDRAWAL BENCHMARKS =============

    /**
     * @notice Benchmark: Single withdrawal
     */
    function bench_SingleWithdrawal() public {
        uint256 depositAmount = 1000e18;

        vm.startPrank(alice);
        token.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, alice);

        uint256 gasBefore = gasleft();
        vault.withdraw(shares, alice, alice);
        uint256 gasUsed = gasBefore - gasleft();

        _recordResult("Single Withdrawal", gasUsed);
        vm.stopPrank();
    }

    /**
     * @notice Benchmark: Partial withdrawal
     */
    function bench_PartialWithdrawal() public {
        uint256 depositAmount = 10000e18;

        vm.startPrank(alice);
        token.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, alice);

        // Withdraw 50%
        uint256 gasBefore = gasleft();
        vault.withdraw(shares / 2, alice, alice);
        uint256 gasUsed = gasBefore - gasleft();

        _recordResult("Partial Withdrawal (50%)", gasUsed);
        vm.stopPrank();
    }

    /**
     * @notice Benchmark: Multi-user withdrawals
     */
    function bench_MultiUserWithdrawals() public {
        // First: deposit for multiple users
        address[] memory users = new address[](5);
        uint256[] memory shares = new uint256[](5);

        for (uint256 i = 0; i < 5; i++) {
            users[i] = address(uint160(0x3000 + i));
            vm.prank(owner);
            token.mint(users[i], 10000e18);

            vm.startPrank(users[i]);
            token.approve(address(vault), 5000e18);
            shares[i] = vault.deposit(5000e18, users[i]);
            vm.stopPrank();
        }

        // Now: withdraw from all
        uint256 gasBefore = gasleft();

        for (uint256 i = 0; i < 5; i++) {
            vm.startPrank(users[i]);
            vault.withdraw(shares[i], users[i], users[i]);
            vm.stopPrank();
        }

        uint256 totalGasUsed = gasBefore - gasleft();
        uint256 averagePerWithdraw = totalGasUsed / 5;

        _recordResult("Multi-User Withdrawal (avg)", averagePerWithdraw);
    }

    // ============= REBASE BENCHMARKS =============

    /**
     * @notice Benchmark: Positive rebase
     */
    function bench_PositiveRebase() public {
        // Setup: deposit first
        vm.startPrank(alice);
        token.approve(address(vault), 10000e18);
        vault.deposit(10000e18, alice);
        vm.stopPrank();

        // Benchmark: +10% rebase
        vm.prank(owner);
        uint256 gasBefore = gasleft();
        token.rebase(10000000000000000); // +10%
        uint256 gasUsed = gasBefore - gasleft();

        _recordResult("Positive Rebase (+10%)", gasUsed);
    }

    /**
     * @notice Benchmark: Negative rebase
     */
    function bench_NegativeRebase() public {
        // Setup: deposit first
        vm.startPrank(alice);
        token.approve(address(vault), 10000e18);
        vault.deposit(10000e18, alice);
        vm.stopPrank();

        // Benchmark: -5% rebase
        vm.prank(owner);
        uint256 gasBefore = gasleft();
        token.rebase(-5000000000000000); // -5%
        uint256 gasUsed = gasBefore - gasleft();

        _recordResult("Negative Rebase (-5%)", gasUsed);
    }

    /**
     * @notice Benchmark: Large rebase (many holders)
     */
    function bench_LargeRebaseMultipleHolders() public {
        // Setup: Many holders
        for (uint256 i = 0; i < 20; i++) {
            address holder = address(uint160(0x4000 + i));
            vm.prank(owner);
            token.mint(holder, 5000e18);

            vm.startPrank(holder);
            token.approve(address(vault), 5000e18);
            vault.deposit(5000e18, holder);
            vm.stopPrank();
        }

        // Benchmark: rebase with 20 holders
        vm.prank(owner);
        uint256 gasBefore = gasleft();
        token.rebase(5000000000000000); // +5%
        uint256 gasUsed = gasBefore - gasleft();

        _recordResult("Rebase (20 holders)", gasUsed);
    }

    // ============= VOTING BENCHMARKS =============

    /**
     * @notice Benchmark: Lock voting power
     */
    function bench_LockVotingPower() public {
        uint256 lockAmount = 10000e18;

        vm.startPrank(alice);
        token.approve(address(votingEscrow), lockAmount);

        uint256 gasBefore = gasleft();
        votingEscrow.lock(lockAmount, 365 days);
        uint256 gasUsed = gasBefore - gasleft();

        _recordResult("Lock Voting Power", gasUsed);
        vm.stopPrank();
    }

    /**
     * @notice Benchmark: Cast vote
     */
    function bench_CastVote() public {
        // Setup: lock voting power first
        vm.startPrank(alice);
        token.approve(address(votingEscrow), 10000e18);
        votingEscrow.lock(10000e18, 365 days);
        vm.stopPrank();

        // Create a proposal first
        bytes memory proposalData = _createProposalData();

        // Benchmark: cast vote
        uint256 gasBefore = gasleft();
        vm.prank(alice);
        governor.castVote(1, 1); // Support: 1=For
        uint256 gasUsed = gasBefore - gasleft();

        _recordResult("Cast Vote", gasUsed);
    }

    /**
     * @notice Benchmark: Multi-user voting
     */
    function bench_MultiUserVoting() public {
        // Setup: multiple voters with locked power
        address[] memory voters = new address[](10);
        for (uint256 i = 0; i < 10; i++) {
            voters[i] = address(uint160(0x5000 + i));
            vm.prank(owner);
            token.mint(voters[i], 10000e18);

            vm.startPrank(voters[i]);
            token.approve(address(votingEscrow), 10000e18);
            votingEscrow.lock(10000e18, 365 days);
            vm.stopPrank();
        }

        // Benchmark: all vote
        uint256 gasBefore = gasleft();
        for (uint256 i = 0; i < 10; i++) {
            vm.prank(voters[i]);
            governor.castVote(1, 1);
        }
        uint256 totalGasUsed = gasBefore - gasleft();
        uint256 averagePerVote = totalGasUsed / 10;

        _recordResult("Multi-User Vote (avg)", averagePerVote);
    }

    // ============= GOVERNANCE BENCHMARKS =============

    /**
     * @notice Benchmark: Create proposal
     */
    function bench_CreateProposal() public {
        // Setup: voting power needed
        vm.startPrank(alice);
        token.approve(address(votingEscrow), 100000e18);
        votingEscrow.lock(100000e18, 365 days);
        vm.stopPrank();

        bytes memory proposalData = _createProposalData();

        uint256 gasBefore = gasleft();
        vm.prank(alice);
        governor.propose(new address[](0), new uint256[](0), new bytes[](0), "");
        uint256 gasUsed = gasBefore - gasleft();

        _recordResult("Create Proposal", gasUsed);
    }

    /**
     * @notice Benchmark: Queue proposal (timelock)
     */
    function bench_QueueProposal() public {
        // Create and pass a proposal first
        // For now, just benchmark the queue operation

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(token);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSignature("setRebaseRate(uint256)", 1000);

        uint256 gasBefore = gasleft();
        vm.prank(owner);
        timelock.scheduleBatch(targets, values, calldatas, bytes32(0), bytes32(0), 2 days);
        uint256 gasUsed = gasBefore - gasleft();

        _recordResult("Queue Proposal (Timelock)", gasUsed);
    }

    /**
     * @notice Benchmark: Execute proposal (timelock)
     */
    function bench_ExecuteProposal() public {
        // Setup: schedule first
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(token);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSignature("setRebaseRate(uint256)", 1000);

        vm.prank(owner);
        timelock.scheduleBatch(targets, values, calldatas, bytes32(0), bytes32(0), 1 seconds);

        // Wait for delay
        vm.warp(block.timestamp + 2 seconds);

        // Benchmark: execute
        uint256 gasBefore = gasleft();
        vm.prank(owner);
        timelock.executeBatch(targets, values, calldatas, bytes32(0), bytes32(0));
        uint256 gasUsed = gasBefore - gasleft();

        _recordResult("Execute Proposal (Timelock)", gasUsed);
    }

    // ============= BATCH OPERATION BENCHMARKS =============

    /**
     * @notice Benchmark: Batch deposits vs individual
     */
    function bench_BatchDepositEfficiency() public {
        uint256[] memory amounts = new uint256[](10);
        for (uint256 i = 0; i < 10; i++) {
            amounts[i] = 1000e18;
        }

        // Test individual deposits
        vm.startPrank(alice);
        token.approve(address(vault), 10000e18);

        uint256 gasBefore = gasleft();
        for (uint256 i = 0; i < 10; i++) {
            vault.deposit(amounts[i], alice);
        }
        uint256 individualGas = gasBefore - gasleft();

        vm.stopPrank();

        // Note: Solidity doesn't support native batching in deposit
        // This measures sequential calls
        _recordResult("Batch Deposits (10x) Individual", individualGas);
    }

    /**
     * @notice Benchmark: Interest calculation overhead
     */
    function bench_InterestCalculation() public {
        // Setup: deposit with interest accrual
        vm.startPrank(alice);
        token.approve(address(vault), 10000e18);
        vault.deposit(10000e18, alice);
        vm.stopPrank();

        // Warp time
        vm.warp(block.timestamp + 365 days);

        // Benchmark: accrual
        uint256 gasBefore = gasleft();
        uint256 earned = interestStrategy.calculateAccruedInterest(10000e18, 365 days, 1000);
        uint256 gasUsed = gasBefore - gasleft();

        _recordResult("Interest Calculation", gasUsed);
    }

    // ============= UTILITY FUNCTIONS =============

    function _createProposalData() internal pure returns (bytes memory) {
        address[] memory targets = new address[](0);
        uint256[] memory values = new uint256[](0);
        bytes[] memory calldatas = new bytes[](0);
        string memory description = "Test proposal";

        return abi.encode(targets, values, calldatas, description);
    }

    function _recordResult(string memory operation, uint256 gasUsed) internal {
        BenchmarkResult memory result;
        result.operation = operation;
        result.gasUsed = gasUsed;
        result.averageGas = gasUsed;
        result.minGas = gasUsed;
        result.maxGas = gasUsed;
        result.samples = 1;

        results.push(result);
    }

    function _uint2str(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - (_i / 10) * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }

    // ============= REPORTING =============

    /**
     * @notice Get all benchmark results
     */
    function getAllResults() public view returns (BenchmarkResult[] memory) {
        return results;
    }

    /**
     * @notice Print benchmark summary
     */
    function printSummary() public view {
        emit log("=== BASERO PROTOCOL PERFORMANCE BENCHMARKS ===");
        emit log("");

        for (uint256 i = 0; i < results.length; i++) {
            string memory output = string(
                abi.encodePacked(
                    results[i].operation,
                    ": ",
                    _uint2str(results[i].gasUsed),
                    " gas"
                )
            );
            emit log(output);
        }
    }
}

/**
 * @title PerformanceComparison
 * @notice Compare performance metrics across contract versions
 */
library PerformanceComparison {
    struct VersionMetrics {
        string version;
        uint256 depositGas;
        uint256 withdrawGas;
        uint256 rebaseGas;
        uint256 voteGas;
    }

    /**
     * @notice Calculate efficiency improvement
     */
    function calculateImprovement(
        VersionMetrics memory v1,
        VersionMetrics memory v2
    ) internal pure returns (uint256 improvementPercent) {
        uint256 totalV1 = v1.depositGas + v1.withdrawGas + v1.rebaseGas + v1.voteGas;
        uint256 totalV2 = v2.depositGas + v2.withdrawGas + v2.rebaseGas + v2.voteGas;

        improvementPercent = ((totalV1 - totalV2) * 100) / totalV1;
    }
}
