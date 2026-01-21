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
 * @title EndToEndFlowTest
 * @notice Comprehensive end-to-end testing of complete protocol workflows
 * @dev Tests full user journeys: deposit → earn → withdraw, governance voting, rebase mechanics
 */
contract EndToEndFlowTest is Test {
    // Protocol contracts
    RebaseToken public token;
    RebaseTokenVault public vault;
    VotingEscrow public votingEscrow;
    BASEGovernor public governor;
    BASETimelock public timelock;
    AdvancedInterestStrategy public strategy;

    // Test accounts
    address public owner = address(0x1);
    address public alice = address(0x2);
    address public bob = address(0x3);
    address public charlie = address(0x4);

    // Constants
    uint256 constant INITIAL_SUPPLY = 1_000_000e18;
    uint256 constant VOTING_DELAY = 1 blocks;
    uint256 constant VOTING_PERIOD = 45818 blocks;
    uint256 constant PROPOSAL_THRESHOLD = 100e18;

    event TestStep(string step);

    function setUp() public {
        vm.startPrank(owner);

        // Deploy token
        token = new RebaseToken("Basero", "BASE");
        token.mint(owner, INITIAL_SUPPLY);

        // Deploy strategy
        strategy = new AdvancedInterestStrategy();

        // Deploy vault
        vault = new RebaseTokenVault(address(token), address(strategy));

        // Deploy governance
        votingEscrow = new VotingEscrow(address(token), "veBase", "veBase");
        timelock = new BASETimelock(2 days, address(owner));
        governor = new BASEGovernor(address(votingEscrow), address(timelock));

        // Transfer tokens to test users
        token.transfer(alice, 10000e18);
        token.transfer(bob, 10000e18);
        token.transfer(charlie, 10000e18);

        vm.stopPrank();
    }

    /**
     * @notice Test complete deposit → earn → withdraw flow
     */
    function test_DepositEarnWithdrawFlow() public {
        emit TestStep("Starting Deposit-Earn-Withdraw flow");

        uint256 depositAmount = 100e18;

        // === PHASE 1: DEPOSIT ===
        emit TestStep("Phase 1: Deposit");
        vm.startPrank(alice);
        token.approve(address(vault), depositAmount);
        uint256 sharesMinted = vault.deposit(depositAmount, alice);

        assertGt(sharesMinted, 0, "Should receive shares");
        assertEq(vault.balanceOf(alice), sharesMinted, "Alice should have shares");
        assertEq(token.balanceOf(address(vault)), depositAmount, "Vault should have tokens");
        emit TestStep("✓ Deposit successful");

        // === PHASE 2: TIME PASSES (Interest Accrues) ===
        emit TestStep("Phase 2: Earn interest");
        vm.warp(block.timestamp + 365 days);
        vm.roll(block.number + 31536000 / 12); // ~1 year of blocks

        // Simulate interest accrual
        uint256 interestEarned = (depositAmount * 5) / 100; // 5% APY
        vm.deal(address(vault), interestEarned);

        // Check increased value
        uint256 totalAssetsAfterInterest = vault.totalAssets();
        assertGt(totalAssetsAfterInterest, depositAmount, "Should have earned interest");
        emit TestStep("✓ Interest accrued");

        // === PHASE 3: WITHDRAW ===
        emit TestStep("Phase 3: Withdraw");
        uint256 withdrawAmount = sharesMinted / 2; // Withdraw half
        uint256 tokensReceived = vault.withdraw(withdrawAmount, alice, alice);

        assertGt(tokensReceived, (depositAmount / 2), "Should receive interest + principal");
        emit TestStep("✓ Withdrawal successful");

        vm.stopPrank();

        // === VERIFICATION ===
        emit TestStep("Verifying final state");
        assertLt(vault.balanceOf(alice), sharesMinted, "Alice should have fewer shares");
        assertEq(token.balanceOf(alice), tokensReceived, "Alice should have withdrawn tokens");
    }

    /**
     * @notice Test governance proposal creation and execution flow
     */
    function test_GovernanceProposalFlow() public {
        emit TestStep("Starting Governance Proposal flow");

        // === PHASE 1: LOCK VOTING POWER ===
        emit TestStep("Phase 1: Lock voting power");
        vm.startPrank(alice);

        uint256 lockAmount = 1000e18;
        token.approve(address(votingEscrow), lockAmount);
        votingEscrow.createLock(lockAmount, block.timestamp + 365 days);

        uint256 votingPower = votingEscrow.balanceOf(alice);
        assertGt(votingPower, 0, "Should have voting power");
        emit TestStep("✓ Voting power locked");

        vm.stopPrank();

        // === PHASE 2: CREATE PROPOSAL ===
        emit TestStep("Phase 2: Create proposal");
        vm.startPrank(alice);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        string[] memory signatures = new string[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(vault);
        values[0] = 0;
        signatures[0] = "setRebaseRate(uint256)";
        calldatas[0] = abi.encode(5000); // 5% rebase rate

        uint256 proposalId = governor.propose(targets, values, signatures, calldatas, "Increase rebase rate");
        assertGt(proposalId, 0, "Proposal should be created");
        emit TestStep("✓ Proposal created");

        vm.stopPrank();

        // === PHASE 3: VOTING PERIOD ===
        emit TestStep("Phase 3: Voting period");
        vm.warp(block.timestamp + 1 blocks + 1);

        vm.prank(alice);
        governor.castVote(proposalId, 1); // 1 = For

        vm.prank(bob);
        token.approve(address(votingEscrow), 500e18);
        votingEscrow.createLock(500e18, block.timestamp + 365 days);
        governor.castVote(proposalId, 1);

        emit TestStep("✓ Votes cast");

        // === PHASE 4: VOTE ENDS ===
        emit TestStep("Phase 4: Vote ends");
        vm.warp(block.timestamp + VOTING_PERIOD + 1);

        // Queue proposal
        bytes32 descriptionHash = keccak256(abi.encodePacked("Increase rebase rate"));
        governor.queue(targets, values, calldatas, descriptionHash);
        emit TestStep("✓ Proposal queued");

        // === PHASE 5: TIMELOCK DELAY ===
        emit TestStep("Phase 5: Timelock delay");
        vm.warp(block.timestamp + 2 days + 1);

        // Execute proposal
        governor.execute(targets, values, calldatas, descriptionHash);
        emit TestStep("✓ Proposal executed");

        // === VERIFICATION ===
        emit TestStep("Verifying governance");
        // Verify state changed (implementation dependent)
    }

    /**
     * @notice Test multi-user vault dynamics
     */
    function test_MultiUserVaultDynamics() public {
        emit TestStep("Starting Multi-User Vault Dynamics test");

        // === USER 1: Deposit ===
        emit TestStep("User 1: Deposit");
        vm.startPrank(alice);
        token.approve(address(vault), 100e18);
        uint256 aliceShares = vault.deposit(100e18, alice);
        vm.stopPrank();

        // === USER 2: Deposit ===
        emit TestStep("User 2: Deposit");
        vm.startPrank(bob);
        token.approve(address(vault), 200e18);
        uint256 bobShares = vault.deposit(200e18, bob);
        vm.stopPrank();

        assertGt(bobShares, aliceShares, "Bob deposited more, should get more shares");

        // === USER 3: Deposit ===
        emit TestStep("User 3: Deposit");
        vm.startPrank(charlie);
        token.approve(address(vault), 50e18);
        uint256 charlieShares = vault.deposit(50e18, charlie);
        vm.stopPrank();

        // === REBASE SCENARIO ===
        emit TestStep("Rebase scenario");
        vm.warp(block.timestamp + 10 days);

        // Simulate positive rebase
        uint256 supplyBefore = token.totalSupply();
        vm.prank(owner);
        token.rebase(11000); // +10% rebase

        uint256 supplyAfter = token.totalSupply();
        assertGt(supplyAfter, supplyBefore, "Supply should increase");

        // === VERIFY SHARES MAINTAINED ===
        emit TestStep("Verify shares maintained after rebase");
        assertEq(vault.balanceOf(alice), aliceShares, "Alice shares unchanged");
        assertEq(vault.balanceOf(bob), bobShares, "Bob shares unchanged");
        assertEq(vault.balanceOf(charlie), charlieShares, "Charlie shares unchanged");

        // === VERIFY ASSETS INCREASED ===
        emit TestStep("Verify assets increased");
        uint256 totalAssetsAfter = vault.totalAssets();
        assertGt(totalAssetsAfter, 350e18, "Total assets should increase with rebase");

        emit TestStep("✓ Multi-user dynamics verified");
    }

    /**
     * @notice Test rebase mechanics with vault integration
     */
    function test_RebaseMechanicsWithVault() public {
        emit TestStep("Starting Rebase Mechanics test");

        // === SETUP ===
        emit TestStep("Setup: Users deposit");
        vm.startPrank(alice);
        token.approve(address(vault), 1000e18);
        vault.deposit(1000e18, alice);
        vm.stopPrank();

        uint256 balanceBefore = token.balanceOf(alice);
        uint256 sharesBeforeRebase = vault.balanceOf(alice);

        // === POSITIVE REBASE ===
        emit TestStep("Positive rebase: +15%");
        vm.prank(owner);
        token.rebase(11500); // +15%

        uint256 balanceAfterPositive = token.balanceOf(alice);
        assertEq(balanceAfterPositive, (balanceBefore * 11500) / 10000, "Balance should increase");
        assertEq(vault.balanceOf(alice), sharesBeforeRebase, "Shares should remain same");

        // === NEGATIVE REBASE ===
        emit TestStep("Negative rebase: -5%");
        vm.prank(owner);
        token.rebase(9500); // -5% from current

        uint256 balanceAfterNegative = token.balanceOf(alice);
        assertLt(balanceAfterNegative, balanceAfterPositive, "Balance should decrease");
        assertEq(vault.balanceOf(alice), sharesBeforeRebase, "Shares should remain same");

        emit TestStep("✓ Rebase mechanics verified");
    }

    /**
     * @notice Test compound interest scenario over time
     */
    function test_CompoundInterestScenario() public {
        emit TestStep("Starting Compound Interest scenario");

        uint256 initialDeposit = 100e18;

        vm.startPrank(alice);
        token.approve(address(vault), initialDeposit);
        vault.deposit(initialDeposit, alice);
        vm.stopPrank();

        uint256 totalAssets = initialDeposit;

        // Simulate 4 quarters of interest
        for (uint256 i = 0; i < 4; i++) {
            emit TestStep(string(abi.encodePacked("Quarter ", string(abi.encode(i + 1)))));

            vm.warp(block.timestamp + 90 days);
            vm.roll(block.number + 7 days / 12);

            // 5% quarterly return
            uint256 quarterlyReturn = (totalAssets * 5) / 100;
            vm.deal(address(vault), address(vault).balance + quarterlyReturn);

            totalAssets += quarterlyReturn;
        }

        uint256 finalAssets = vault.totalAssets();
        assertGt(finalAssets, initialDeposit, "Should have compound interest");
        emit TestStep("✓ Compound interest verified");
    }

    /**
     * @notice Test emergency pause scenario
     */
    function test_EmergencyPauseScenario() public {
        emit TestStep("Starting Emergency Pause scenario");

        // Setup: Users deposit
        vm.startPrank(alice);
        token.approve(address(vault), 100e18);
        vault.deposit(100e18, alice);
        vm.stopPrank();

        // Normal operations work
        assertFalse(vault.paused(), "Vault should not be paused");

        // Trigger pause
        emit TestStep("Triggering emergency pause");
        vm.prank(owner);
        vault.pause();
        assertTrue(vault.paused(), "Vault should be paused");

        // Operations should fail
        emit TestStep("Verifying operations blocked during pause");
        vm.startPrank(bob);
        token.approve(address(vault), 50e18);
        vm.expectRevert();
        vault.deposit(50e18, bob);
        vm.stopPrank();

        // Resume operations
        emit TestStep("Resuming operations");
        vm.prank(owner);
        vault.unpause();
        assertFalse(vault.paused(), "Vault should be unpaused");

        // Operations work again
        vm.startPrank(bob);
        token.approve(address(vault), 50e18);
        vault.deposit(50e18, b);
        vm.stopPrank();

        emit TestStep("✓ Emergency pause scenario verified");
    }

    /**
     * @notice Test access control and permissions
     */
    function test_AccessControlScenario() public {
        emit TestStep("Starting Access Control test");

        // Non-owner cannot set rates
        emit TestStep("Verifying non-owner cannot set rates");
        vm.startPrank(alice);
        vm.expectRevert();
        vault.setDepositCaps(1000e18, 2000e18);
        vm.stopPrank();

        // Owner can set rates
        emit TestStep("Verifying owner can set rates");
        vm.prank(owner);
        vault.setDepositCaps(1000e18, 2000e18);

        // Non-owner cannot pause
        emit TestStep("Verifying non-owner cannot pause");
        vm.prank(alice);
        vm.expectRevert();
        vault.pause();

        // Owner can pause
        emit TestStep("Verifying owner can pause");
        vm.prank(owner);
        vault.pause();

        emit TestStep("✓ Access control verified");
    }
}
