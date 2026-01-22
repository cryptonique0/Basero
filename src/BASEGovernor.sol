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
 * @author Basero Protocol
 * @notice Decentralized governance contract for community voting on protocol changes
 * @dev OpenZeppelin Governor with timelock for time-delayed execution
 * 
 * @dev Architecture:
 * - Voting based on BASEGovernanceToken (VotingEscrow-style voting power)
 * - Time-locked execution via BASETimelock (2-day delay minimum)
 * - Community governance of protocol parameters and upgrades
 * 
 * @dev Voting Parameters:
 * - Voting Delay: 1 block (~12 seconds on Ethereum)
 * - Voting Period: 50,400 blocks (~1 week on Ethereum)
 * - Proposal Threshold: 100,000 BASE tokens
 * - Quorum: 4% of total voting power
 * 
 * @dev Proposal Lifecycle:
 * 1. Propose: Caller with 100k+ tokens creates proposal
 * 2. Voting Delay: 1 block wait before voting starts
 * 3. Voting: 7 days for community to vote
 * 4. Queue: Approved proposal queued in timelock
 * 5. Wait: 2-day delay in timelock (security buffer)
 * 6. Execute: Proposal executed after delay
 * 
 * @dev Supported Proposal Types:
 * - FeeUpdate: Protocol fee adjustments
 * - CapUpdate: Deposit/TVL cap changes
 * - AccrualUpdate: Interest rates and accrual periods
 * - TreasuryManagement: Fund transfers and treasury updates
 * - ContractUpgrade: Smart contract upgrades
 * - Other: Miscellaneous governance actions
 * 
 * @dev Security:
 * - Quorum prevents small groups from controlling protocol
 * - Timelock prevents instant execution (2-day delay)
 * - Voting power snapshot prevents flash-loan attacks
 * - Multi-sig can cancel urgent proposals
 * 
 * @dev Vote Counting (Simple):
 * - Against: No votes
 * - For: Yes votes
 * - Abstain: Abstention votes
 * - Passes if For > Against AND quorum reached
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
     * @notice Initialize BASE Governor with voting token and timelock
     * @dev Sets up voting parameters and integrates with timelock
     * 
     * @param votesToken Address of BASEGovernanceToken (must implement IVotes)
     * @param timelockController Address of BASETimelock contract
     * 
     * Requirements:
     * - votesToken must not be zero address
     * - timelockController must not be zero address
     * - Both must be properly initialized
     * 
     * Initial Settings:
     * - Name: "BASE Governor"
     * - Voting Delay: 1 block
     * - Voting Period: 50,400 blocks (~1 week)
     * - Proposal Threshold: 100,000 tokens (100_000e18 wei)
     * - Quorum: 4% (400 basis points)
     * 
     * Effects:
     * - Enables community governance
     * - Links voting power to token holders
     * - Integrates timelock for security delay
     * 
     * Example:
     * new BASEGovernor(
     *   0xBASEGovernanceToken,
     *   0xBASETimelock
     * )
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
     * @notice Create a governance proposal with metadata for categorization
     * @dev Wrapper around propose() that tracks proposal type and title
     * 
     * @param targets Array of target contract addresses (functions to call)
     * @param values Array of ETH values to send with each call (typically 0)
     * @param calldatas Array of encoded function calls (abi.encodeWithSelector)
     * @param title Human-readable proposal title (50-200 characters)
     * @param proposalType Category of proposal (FeeUpdate, CapUpdate, etc.)
     * @param description Proposal description (IPFS hash or URL)
     * @return proposalId Unique identifier for this proposal
     * 
     * Requirements:
     * - msg.sender must have 100,000+ BASE tokens (proposal threshold)
     * - All array lengths must match (targets.length == values.length == calldatas.length)
     * - Cannot reuse exact same proposal description (prevents duplicates)
     * 
     * Effects:
     * - Creates proposal via Governor.propose()
     * - Stores metadata (title, type, timestamp, proposer)
     * - Increments proposal counter
     * - Voting starts after 1 block delay
     * 
     * Emits:
     * - ProposalCreatedWithMetadata(proposalId, proposer, title, type, timestamp)
     * - Governor.ProposalCreated (from parent contract)
     * 
     * Example:
     * // Update deposit cap
     * address[] memory targets = [vaultAddress];
     * uint256[] memory values = [0];
     * bytes[] memory calldatas = [abi.encodeWithSelector(
     *   IVault.setDepositCaps.selector,
     *   100 ether,  // maxPerAddress
     *   10000 ether // maxTotal
     * )];
     * createProposalWithMetadata(
     *   targets,
     *   values,
     *   calldatas,
     *   "Update Deposit Caps",
     *   ProposalType.CapUpdate,
     *   "ipfs://QmXxxx..."
     * );
     * 
     * Voting Timeline:
     * - Block 0: Proposal created
     * - Block 1: Voting starts (1 block delay)
     * - Block 50401: Voting ends (50,400 block period)
     * - Then: Queued in timelock → 2-day wait → Execute
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
     * @notice Get total number of proposals ever created
     * @dev Used for indexing and governance statistics
     * 
     * @return Total count of proposals (includes failed/cancelled)
     * 
     * Example:
     * uint256 count = getProposalCount();
     * // Returns 42 if 42 proposals have been created
     */
    function getProposalCount() external view returns (uint256) {
        return s_proposalCount;
    }

    /**
     * @notice Get stored metadata for a proposal
     * @dev Returns custom metadata (not available in base Governor)
     * 
     * @param proposalId ID of the proposal to retrieve
     * @return metadata ProposalMetadata struct containing:
     *   - title: Proposal title
     *   - description: Full description
     *   - createdAt: Timestamp when proposal was created
     *   - proposer: Address that created proposal
     *   - proposalType: Category (FeeUpdate, CapUpdate, etc.)
     * 
     * Example:
     * ProposalMetadata memory meta = getProposalMetadata(1);
     * console.log(meta.title); // "Update Deposit Caps"
     * console.log(meta.proposalType); // CapUpdate
     */
    function getProposalMetadata(uint256 proposalId) external view returns (ProposalMetadata memory) {
        return s_proposalMetadata[proposalId];
    }

    /**
     * @notice Get current governance voting parameters
     * @dev Snapshot of all governance settings for reference
     * 
     * @return votingDelay Blocks before voting starts (1 block = ~12 sec)
     * @return votingPeriod Duration of voting period (50,400 blocks = ~1 week)
     * @return proposalThreshold Minimum tokens to create proposal (100,000)
     * @return quorumPercentage Quorum as percentage (4 = 4%)
     * 
     * Formula:
     * votingDelay = 1 block
     * votingPeriod = 50,400 blocks
     * proposalThreshold = 100,000 * 10^18 wei
     * quorumPercentage = 4
     * quorumVotes = totalVotingPower * quorumPercentage / 100
     * 
     * Example:
     * (uint256 delay, uint256 period, uint256 thresh, uint256 quorum) = getVotingParameters();
     * // Returns: (1, 50400, 100000000000000000000000, 4)
     * 
     * Interpretation:
     * - 1 block delay before voting starts
     * - ~1 week voting period
     * - 100k tokens needed to propose
     * - 4% quorum required to pass
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
     * @notice Calculate minimum votes needed for proposal to pass at block height
     * @dev Quorum can change if total voting power changes
     * 
     * @param blockNumber Block height to calculate quorum for
     * @return Minimum votes required (4% of total voting power at block)
     * 
     * Formula:
     * quorumVotes = totalVotingPower(blockNumber) * 4% / 100%
     * 
     * Example:
     * // If total voting power at block 100 is 1,000,000 tokens
     * uint256 quorum = getQuorumVotes(100);
     * // Returns: 40,000 (4% of 1,000,000)
     * // Proposal passes if For votes >= 40,000 AND For > Against
     * 
     * Note:
     * Uses voting power snapshot at specified block (not current)
     * Prevents voting power manipulation between proposal creation and voting
     */
    function getQuorumVotes(uint256 blockNumber) external view returns (uint256) {
        return quorum(blockNumber);
    }

    /*//////////////////////////////////////////////////////////////
                    OVERRIDE FUNCTIONS (Multi-inheritance)
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get voting delay in blocks
     * @dev Resolves conflict between Governor and GovernorSettings
     * @return Blocks before voting starts (1)
     */
    function votingDelay() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.votingDelay();
    }

    /**
     * @notice Get voting period in blocks
     * @dev Resolves conflict between Governor and GovernorSettings
     * @return Duration of voting period in blocks (50,400 = ~1 week)
     */
    function votingPeriod() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.votingPeriod();
    }

    /**
     * @notice Get quorum numerator (percentage)
     * @dev Resolves conflict in multi-inheritance
     * @return Quorum as numerator (4 = 4% since denominator is 100)
     */
    function quorumNumerator() public view override(GovernorVotesQuorumFraction) returns (uint256) {
        return super.quorumNumerator();
    }

    /**
     * @notice Calculate quorum votes at specific block
     * @dev Resolves conflict between Governor and GovernorVotesQuorumFraction
     * 
     * @param blockNumber Block height for voting power snapshot
     * @return Minimum votes needed for proposal to pass
     */
    function quorum(uint256 blockNumber)
        public
        view
        override(Governor, GovernorVotesQuorumFraction)
        returns (uint256)
    {
        return super.quorum(blockNumber);
    }

    /**
     * @notice Get current state of a proposal
     * @dev Resolves conflict between Governor and GovernorTimelockControl
     * 
     * @param proposalId Proposal ID to check state
     * @return Current state (Pending, Active, Cancelled, Defeated, Succeeded, Queued, Expired, Executed)
     */
    function state(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (ProposalState)
    {
        return super.state(proposalId);
    }

    /**
     * @notice Check if proposal needs to be queued before execution
     * @dev Resolves conflict between Governor and GovernorTimelockControl
     * 
     * @param proposalId Proposal ID to check
     * @return True if proposal needs timelock queuing, false otherwise
     * 
     * Note:
     * With timelock integration, all proposals must be queued
     */
    function proposalNeedsQueuing(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (bool)
    {
        return super.proposalNeedsQueuing(proposalId);
    }

    /**
     * @notice Get minimum tokens needed to create a proposal
     * @dev Resolves conflict between Governor and GovernorSettings
     * 
     * @return Tokens required (100,000 * 10^18 wei)
     * 
     * Note:
     * Prevents spam proposals while allowing community participation
     */
    function proposalThreshold() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.proposalThreshold();
    }

    /**
     * @notice Execute a proposal after timelock delay
     * @dev Resolves conflict between Governor and GovernorTimelockControl
     * 
     * @param proposalId Proposal ID to execute
     * @param targets Target contract addresses
     * @param values ETH values for each call
     * @param calldatas Function calls to execute
     * @param descriptionHash Hash of proposal description
     * 
     * Effects:
     * - Executes all target functions with provided parameters
     * - Transfers any ETH specified in values
     * - Marks proposal as executed
     */
    function _execute(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) {
        super._execute(proposalId, targets, values, calldatas, descriptionHash);
    }

    /**
     * @notice Cancel a proposal
     * @dev Resolves conflict between Governor and GovernorTimelockControl
     * 
     * @param targets Target contract addresses
     * @param values ETH values for each call
     * @param calldatas Function calls (for cancellation)
     * @param descriptionHash Hash of proposal description
     * @return Proposal ID of cancelled proposal
     * 
     * Use Case:
     * Multi-sig can cancel critical proposals if vulnerability found
     */
    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    /**
     * @notice Get address that executes proposals
     * @dev Resolves conflict between Governor and GovernorTimelockControl
     * 
     * @return Address of timelock controller (executor)
     */
    function _executor() internal view override(Governor, GovernorTimelockControl) returns (address) {
        return super._executor();
    }

    /**
     * @notice Check if contract supports an interface
     * @dev Resolves conflict between Governor and GovernorTimelockControl
     * 
     * @param interfaceId Interface ID to check (ERC165)
     * @return True if interface is supported
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
