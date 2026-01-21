// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {GovernorSettings} from "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import {GovernorCountingSimple} from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import {GovernorVotes} from "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import {GovernorVotesQuorumFraction} from "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import {GovernorTimelockControl} from "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/**
 * @title BASEGovernor
 * @dev Governance contract for community voting on protocol changes
 * @notice Integrated with timelock for time-locked execution of approved proposals
 *
 * VOTING PARAMETERS:
 * - Voting Delay: 1 block (~12 seconds)
 * - Voting Period: 50,400 blocks (~1 week)
 * - Proposal Threshold: 100,000 tokens (1e23 wei)
 * - Quorum: 4% of voting power
 *
 * PROPOSAL TYPES:
 * - Fee updates (protocol, per-chain CCIP)
 * - Deposit/redemption cap changes
 * - Accrual period and rate adjustments
 * - Treasury management and distributions
 * - Contract upgrades (via timelock)
 */
contract BASEGovernor is
    Governor,
    GovernorSettings,
    GovernorCountingSimple,
    GovernorVotes,
    GovernorVotesQuorumFraction,
    GovernorTimelockControl
{
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    // Proposal counter for tracking
    uint256 private s_proposalCount;

    // Mapping of proposal ID to proposal metadata
    mapping(uint256 => ProposalMetadata) private s_proposalMetadata;

    /*//////////////////////////////////////////////////////////////
                              STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct ProposalMetadata {
        string title;
        string description;
        uint256 createdAt;
        address proposer;
        ProposalType proposalType;
    }

    enum ProposalType {
        FeeUpdate,
        CapUpdate,
        AccrualUpdate,
        TreasuryManagement,
        ContractUpgrade,
        Other
    }

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event ProposalCreatedWithMetadata(
        uint256 indexed proposalId,
        address indexed proposer,
        string title,
        ProposalType proposalType,
        uint256 timestamp
    );

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidTimelockAddress();
    error InvalidVotesAddress();

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Constructor for BASEGovernor
     * @param votesToken Address of the governance token (must implement IVotes)
     * @param timelockController Address of the timelock controller
     */
    constructor(IVotes votesToken, TimelockController timelockController)
        Governor("BASE Governor")
        GovernorSettings(
            1, // voting delay = 1 block
            50400, // voting period = 50,400 blocks (~1 week on Ethereum)
            100_000e18 // proposal threshold = 100,000 tokens
        )
        GovernorVotes(votesToken)
        GovernorVotesQuorumFraction(4) // 4% quorum
        GovernorTimelockControl(timelockController)
    {
        if (address(votesToken) == address(0)) revert InvalidVotesAddress();
        if (address(timelockController) == address(0)) revert InvalidTimelockAddress();
    }

    /*//////////////////////////////////////////////////////////////
                         PROPOSAL CREATION HELPERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Create a proposal with metadata
     * @dev Helper function to track proposal type and title
     * @param targets Array of target addresses
     * @param values Array of ETH values to send
     * @param calldatas Array of encoded function calls
     * @param title Human-readable proposal title
     * @param proposalType Type of proposal for categorization
     * @param description Full proposal description (IPFS hash or off-chain URL)
     * @return proposalId ID of the created proposal
     */
    function createProposalWithMetadata(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory title,
        ProposalType proposalType,
        string memory description
    ) external returns (uint256) {
        uint256 proposalId = propose(targets, values, calldatas, description);

        s_proposalMetadata[proposalId] = ProposalMetadata({
            title: title,
            description: description,
            createdAt: block.timestamp,
            proposer: msg.sender,
            proposalType: proposalType
        });

        s_proposalCount++;

        emit ProposalCreatedWithMetadata(proposalId, msg.sender, title, proposalType, block.timestamp);

        return proposalId;
    }

    /*//////////////////////////////////////////////////////////////
                           VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get total number of proposals created
     * @return Total proposal count
     */
    function getProposalCount() external view returns (uint256) {
        return s_proposalCount;
    }

    /**
     * @notice Get metadata for a proposal
     * @param proposalId ID of the proposal
     * @return metadata Proposal metadata
     */
    function getProposalMetadata(uint256 proposalId) external view returns (ProposalMetadata memory) {
        return s_proposalMetadata[proposalId];
    }

    /**
     * @notice Get voting parameters for reference
     * @return votingDelay Delay before voting starts (blocks)
     * @return votingPeriod Duration of voting period (blocks)
     * @return proposalThreshold Minimum tokens needed to propose
     * @return quorumPercentage Quorum as percentage of voting power
     */
    function getVotingParameters()
        external
        view
        returns (uint256 votingDelay, uint256 votingPeriod, uint256 proposalThreshold, uint256 quorumPercentage)
    {
        return (
            votingDelay(),
            votingPeriod(),
            proposalThreshold(),
            quorumNumerator()
        );
    }

    /**
     * @notice Calculate quorum for a given block number
     * @param blockNumber Block number to calculate quorum for
     * @return Quorum threshold in votes
     */
    function getQuorumVotes(uint256 blockNumber) external view returns (uint256) {
        return quorum(blockNumber);
    }

    /*//////////////////////////////////////////////////////////////
                    OVERRIDE FUNCTIONS (Multi-inheritance)
    //////////////////////////////////////////////////////////////*/

    function votingDelay() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.votingDelay();
    }

    function votingPeriod() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.votingPeriod();
    }

    function quorumNumerator() public view override(GovernorVotesQuorumFraction) returns (uint256) {
        return super.quorumNumerator();
    }

    function quorum(uint256 blockNumber)
        public
        view
        override(Governor, GovernorVotesQuorumFraction)
        returns (uint256)
    {
        return super.quorum(blockNumber);
    }

    function state(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (ProposalState)
    {
        return super.state(proposalId);
    }

    function proposalNeedsQueuing(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (bool)
    {
        return super.proposalNeedsQueuing(proposalId);
    }

    function proposalThreshold() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.proposalThreshold();
    }

    function _execute(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) {
        super._execute(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    function _executor() internal view override(Governor, GovernorTimelockControl) returns (address) {
        return super._executor();
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
