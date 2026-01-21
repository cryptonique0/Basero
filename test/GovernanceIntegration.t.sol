// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {BASEGovernanceToken} from "src/BASEGovernanceToken.sol";
import {BASEGovernor} from "src/BASEGovernor.sol";
import {BASETimelock} from "src/BASETimelock.sol";
import {RebaseToken} from "src/RebaseToken.sol";
import {RebaseTokenVault} from "src/RebaseTokenVault.sol";
import {BASEGovernanceHelpers} from "src/BASEGovernanceHelpers.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

/**
 * @title GovernanceTokenTest
 * @notice Tests for BASEGovernanceToken voting and minting
 */
contract GovernanceTokenTest is Test {
    BASEGovernanceToken public governanceToken;
    address public tokenOwner = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);

    function setUp() public {
        vm.prank(tokenOwner);
        governanceToken = new BASEGovernanceToken(tokenOwner, 10_000_000e18);
    }

    function test_InitialSupply() public {
        assertEq(governanceToken.balanceOf(tokenOwner), 10_000_000e18);
        assertEq(governanceToken.getCurrentSupply(), 10_000_000e18);
    }

    function test_Mint() public {
        vm.prank(tokenOwner);
        governanceToken.mint(user1, 1_000_000e18);

        assertEq(governanceToken.balanceOf(user1), 1_000_000e18);
        assertEq(governanceToken.getCurrentSupply(), 11_000_000e18);
    }

    function test_MintExceedsMaxSupply() public {
        uint256 maxSupply = 100_000_000e18;
        uint256 currentSupply = 10_000_000e18;
        uint256 excessAmount = maxSupply - currentSupply + 1;

        vm.prank(tokenOwner);
        vm.expectRevert(BASEGovernanceToken.ExceedsMaxSupply.selector);
        governanceToken.mint(user1, excessAmount);
    }

    function test_Burn() public {
        vm.prank(tokenOwner);
        governanceToken.burn(1_000_000e18);

        assertEq(governanceToken.balanceOf(tokenOwner), 9_000_000e18);
        assertEq(governanceToken.getCurrentSupply(), 9_000_000e18);
    }

    function test_BurnFrom() public {
        vm.prank(tokenOwner);
        governanceToken.transfer(user1, 1_000_000e18);

        vm.prank(tokenOwner);
        governanceToken.burnFrom(user1, 500_000e18);

        assertEq(governanceToken.balanceOf(user1), 500_000e18);
        assertEq(governanceToken.getCurrentSupply(), 9_500_000e18);
    }

    function test_Delegation() public {
        vm.prank(tokenOwner);
        governanceToken.transfer(user1, 1_000_000e18);

        vm.prank(user1);
        governanceToken.delegateSelf();

        assertEq(governanceToken.getVotes(user1), 1_000_000e18);
    }

    function test_GetVotingPower() public {
        vm.prank(tokenOwner);
        governanceToken.transfer(user1, 1_000_000e18);

        vm.prank(tokenOwner);
        governanceToken.transfer(user2, 2_000_000e18);

        vm.prank(user1);
        governanceToken.delegateSelf();

        vm.prank(user2);
        governanceToken.delegateSelf();

        assertEq(governanceToken.getVotes(user1), 1_000_000e18);
        assertEq(governanceToken.getVotes(user2), 2_000_000e18);
    }

    function test_RemainingMintable() public {
        assertEq(governanceToken.getRemainingMintable(), 90_000_000e18);

        vm.prank(tokenOwner);
        governanceToken.mint(user1, 50_000_000e18);

        assertEq(governanceToken.getRemainingMintable(), 40_000_000e18);
    }
}

/**
 * @title GovernorTest
 * @notice Tests for BASEGovernor voting and proposals
 */
contract GovernorTest is Test {
    BASEGovernanceToken public governanceToken;
    BASETimelock public timelock;
    BASEGovernor public governor;

    address public multisig = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    address public user3 = address(0x4);

    function setUp() public {
        // Setup governance token
        vm.prank(multisig);
        governanceToken = new BASEGovernanceToken(multisig, 50_000_000e18);

        // Setup timelock
        address[] memory proposers = new address[](1);
        address[] memory executors = new address[](1);
        proposers[0] = address(0); // Will be set to governor later
        executors[0] = address(0); // Public executor

        vm.prank(multisig);
        timelock = new BASETimelock(address(0), multisig, proposers, executors, multisig);

        // Setup governor
        vm.prank(multisig);
        governor = new BASEGovernor(governanceToken, timelock);

        // Grant proposer role to governor
        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        vm.prank(multisig);
        timelock.grantRole(proposerRole, address(governor));

        // Grant executor role to governor
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        vm.prank(multisig);
        timelock.grantRole(executorRole, address(governor));
    }

    function test_VotingParameters() public {
        (
            uint256 votingDelay,
            uint256 votingPeriod,
            uint256 proposalThreshold,
            uint256 quorumPercentage
        ) = governor.getVotingParameters();

        assertEq(votingDelay, 1);
        assertEq(votingPeriod, 50400);
        assertEq(proposalThreshold, 100_000e18);
        assertEq(quorumPercentage, 4);
    }

    function test_ProposeRequiresThreshold() public {
        // Give user1 less than threshold tokens
        vm.prank(multisig);
        governanceToken.transfer(user1, 50_000e18);

        vm.prank(user1);
        governanceToken.delegateSelf();

        address[] memory targets = new address[](0);
        uint256[] memory values = new uint256[](0);
        bytes[] memory calldatas = new bytes[](0);
        string memory description = "Test proposal";

        vm.prank(user1);
        vm.expectRevert("Governor: proposer votes below proposal threshold");
        governor.propose(targets, values, calldatas, description);
    }

    function test_CreateProposal() public {
        // Give user1 threshold tokens
        vm.prank(multisig);
        governanceToken.transfer(user1, 100_000e18);

        vm.prank(user1);
        governanceToken.delegateSelf();

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(0);
        values[0] = 0;
        calldatas[0] = "";

        vm.prank(user1);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test proposal");

        assertTrue(proposalId > 0);
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Pending));
    }

    function test_VotingFlow() public {
        // Setup voters
        vm.prank(multisig);
        governanceToken.transfer(user1, 100_000e18);
        vm.prank(multisig);
        governanceToken.transfer(user2, 200_000e18);
        vm.prank(multisig);
        governanceToken.transfer(user3, 300_000e18);

        vm.prank(user1);
        governanceToken.delegateSelf();
        vm.prank(user2);
        governanceToken.delegateSelf();
        vm.prank(user3);
        governanceToken.delegateSelf();

        // Create proposal
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(0);
        values[0] = 0;
        calldatas[0] = "";

        vm.prank(user1);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test proposal");

        // Wait for voting to start
        vm.roll(block.number + 2);

        // Vote
        vm.prank(user1);
        governor.castVote(proposalId, 1); // For

        vm.prank(user2);
        governor.castVote(proposalId, 1); // For

        vm.prank(user3);
        governor.castVote(proposalId, 0); // Against

        // Check voting results
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = governor.proposalVotes(proposalId);

        assertEq(againstVotes, 300_000e18);
        assertEq(forVotes, 300_000e18);
        assertEq(abstainVotes, 0);
    }

    function test_ProposalStateProgression() public {
        vm.prank(multisig);
        governanceToken.transfer(user1, 100_000e18);

        vm.prank(user1);
        governanceToken.delegateSelf();

        address[] memory targets = new address[](0);
        uint256[] memory values = new uint256[](0);
        bytes[] memory calldatas = new bytes[](0);

        vm.prank(user1);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test proposal");

        // Pending
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Pending));

        // Active
        vm.roll(block.number + 2);
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Active));
    }

    function test_GetQuorumVotes() public {
        uint256 quorum = governor.getQuorumVotes(block.number);
        assertTrue(quorum > 0);
    }
}

/**
 * @title TimelockTest
 * @notice Tests for BASETimelock functionality
 */
contract TimelockTest is Test {
    BASETimelock public timelock;
    BASEGovernor public governor;
    address public multisig = address(0x1);
    address public newGovernor = address(0x2);

    function setUp() public {
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0);

        vm.prank(multisig);
        timelock = new BASETimelock(multisig, multisig, proposers, executors, multisig);
    }

    function test_MinimumDelay() public {
        assertEq(timelock.getMinDelay(), 2 days);
    }

    function test_GetTreasuryBalance() public {
        vm.deal(address(timelock), 10 ether);
        assertEq(timelock.getTreasuryBalance(), 10 ether);
    }

    function test_ReceiveETH() public {
        vm.deal(address(this), 10 ether);
        (bool success,) = address(timelock).call{value: 10 ether}("");
        assertTrue(success);
        assertEq(timelock.getTreasuryBalance(), 10 ether);
    }

    function test_EmergencyWithdrawETH() public {
        address recipient = address(0x3);
        vm.deal(address(timelock), 10 ether);

        vm.prank(multisig);
        timelock.emergencyWithdrawETH(payable(recipient), 5 ether);

        assertEq(recipient.balance, 5 ether);
        assertEq(timelock.getTreasuryBalance(), 5 ether);
    }

    function test_UpdateGovernor() public {
        vm.prank(multisig);
        timelock.updateGovernor(newGovernor);

        assertEq(timelock.governorAddress(), newGovernor);
    }

    function test_UpdateTreasuryMultisig() public {
        address newMultisig = address(0x4);

        vm.prank(multisig);
        timelock.updateTreasuryMultisig(newMultisig);

        assertEq(timelock.treasuryMultisig(), newMultisig);
    }
}

/**
 * @title GovernanceHelpersTest
 * @notice Tests for BASEGovernanceHelpers proposal encoding
 */
contract GovernanceHelpersTest is Test {
    RebaseToken public rebaseToken;
    RebaseTokenVault public vault;
    BASEGovernanceHelpers public helpers;
    address public owner = address(0x1);

    function setUp() public {
        vm.prank(owner);
        rebaseToken = new RebaseToken("Rebase Token", "REBASE");

        vm.prank(owner);
        vault = new RebaseTokenVault(address(rebaseToken));

        helpers = new BASEGovernanceHelpers(address(vault), address(0), address(0));
    }

    function test_EncodeFeeProposal() public {
        address feeRecipient = address(0x2);
        uint16 feeBps = 500;

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            helpers.encodeVaultFeeProposal(feeRecipient, feeBps);

        assertEq(targets.length, 1);
        assertEq(targets[0], address(vault));
        assertEq(values[0], 0);
        assertEq(calldatas.length, 1);
        assertTrue(bytes(description).length > 0);
    }

    function test_EncodeCapProposal() public {
        uint256 minDeposit = 1 ether;
        uint256 maxPerUser = 1000 ether;
        uint256 maxTotal = 10000 ether;

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            helpers.encodeVaultCapProposal(minDeposit, maxPerUser, maxTotal);

        assertEq(targets.length, 1);
        assertEq(targets[0], address(vault));
        assertEq(values[0], 0);
        assertTrue(bytes(description).length > 0);
    }

    function test_EncodeAccrualProposal() public {
        uint256 accrualPeriod = 1 days;
        uint16 maxDailyAccrual = 500;

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            helpers.encodeVaultAccrualProposal(accrualPeriod, maxDailyAccrual);

        assertEq(targets.length, 1);
        assertEq(targets[0], address(vault));
        assertEq(values[0], 0);
        assertTrue(bytes(description).length > 0);
    }

    function test_EncodeTreasuryDistribution() public {
        address[] memory recipients = new address[](2);
        uint256[] memory amounts = new uint256[](2);

        recipients[0] = address(0x2);
        recipients[1] = address(0x3);
        amounts[0] = 1 ether;
        amounts[1] = 2 ether;

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            helpers.encodeTreasuryDistributionProposal(recipients, amounts, address(vault));

        assertEq(targets.length, 2);
        assertEq(values[0], 1 ether);
        assertEq(values[1], 2 ether);
        assertTrue(bytes(description).length > 0);
    }
}

/**
 * @title VaultGovernanceIntegrationTest
 * @notice Tests for vault integration with governance
 */
contract VaultGovernanceIntegrationTest is Test {
    RebaseToken public rebaseToken;
    RebaseTokenVault public vault;
    BASETimelock public timelock;
    address public owner = address(0x1);
    address public multisig = address(0x2);

    function setUp() public {
        vm.prank(owner);
        rebaseToken = new RebaseToken("Rebase Token", "REBASE");

        vm.prank(owner);
        vault = new RebaseTokenVault(address(rebaseToken));

        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0);

        vm.prank(multisig);
        timelock = new BASETimelock(address(0), multisig, proposers, executors, multisig);

        // Set governance timelock on vault
        vm.prank(owner);
        vault.setGovernanceTimelock(address(timelock));
    }

    function test_SetGovernanceTimelock() public {
        assertEq(vault.getGovernanceTimelock(), address(timelock));
    }

    function test_FeeConfigByGovernance() public {
        address feeRecipient = address(0x3);
        uint16 feeBps = 500;

        vm.prank(address(timelock));
        vault.setFeeConfig(feeRecipient, feeBps);

        // Verify through getter (would need to add public getter in vault)
    }

    function test_AccrualConfigByGovernance() public {
        uint256 accrualPeriod = 2 days;
        uint16 maxDailyAccrual = 750;

        vm.prank(address(timelock));
        vault.setAccrualConfig(accrualPeriod, maxDailyAccrual);

        // Verify through getter
    }

    function test_OnlyGovernanceCanUpdateParams() public {
        address attacker = address(0x4);

        vm.prank(attacker);
        vm.expectRevert(RebaseTokenVault.OnlyGovernance.selector);
        vault.setFeeConfig(attacker, 100);
    }

    function test_OwnerCanStillUpdateParams() public {
        address feeRecipient = address(0x5);

        vm.prank(owner);
        vault.setFeeConfig(feeRecipient, 300);

        // Should succeed
    }
}
