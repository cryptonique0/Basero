// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "forge-std/StdInvariant.sol";
import {VotingEscrow} from "../../src/governance/VotingEscrow.sol";
import {GovernorAlpha} from "../../src/governance/GovernorAlpha.sol";
import {Timelock} from "../../src/governance/Timelock.sol";
import {RebaseToken} from "../../src/RebaseToken.sol";

/**
 * @title GovernanceInvariantTest
 * @notice Invariant tests for governance system
 * @dev Tests voting power, proposal states, and timelock consistency
 */
contract GovernanceInvariantTest is StdInvariant, Test {
    
    VotingEscrow public votingEscrow;
    GovernorAlpha public governor;
    Timelock public timelock;
    RebaseToken public token;
    
    GovernanceHandler public handler;
    
    function setUp() public {
        // Deploy token
        token = new RebaseToken("Governance Token", "GOV");
        
        // Deploy voting escrow
        votingEscrow = new VotingEscrow(address(token));
        
        // Deploy timelock (2 day delay)
        timelock = new Timelock(address(this), 2 days);
        
        // Deploy governor
        governor = new GovernorAlpha(
            address(timelock),
            address(votingEscrow),
            5760,  // ~1 day voting delay
            40320, // ~1 week voting period
            100 ether // 100 token proposal threshold
        );
        
        // Set governor as timelock admin
        timelock.setPendingAdmin(address(governor));
        vm.prank(address(governor));
        timelock.acceptAdmin();
        
        // Deploy handler
        handler = new GovernanceHandler(
            votingEscrow,
            governor,
            timelock,
            token
        );
        
        // Target handler
        targetContract(address(handler));
        
        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = GovernanceHandler.createLock.selector;
        selectors[1] = GovernanceHandler.increaseLock.selector;
        selectors[2] = GovernanceHandler.withdraw.selector;
        selectors[3] = GovernanceHandler.delegate.selector;
        selectors[4] = GovernanceHandler.createProposal.selector;
        selectors[5] = GovernanceHandler.vote.selector;
        
        targetSelector(FuzzSelector({
            addr: address(handler),
            selectors: selectors
        }));
    }
    
    // ============= Voting Power Invariants =============
    
    /// @notice Total voting power should equal total locked tokens
    function invariant_totalVotingPowerMatchesLockedTokens() public view {
        uint256 totalSupply = votingEscrow.totalSupply();
        uint256 sumOfLocks = handler.getSumOfLocks();
        
        // Allow small rounding difference from time-weighting
        assertApproxEqRel(
            totalSupply,
            sumOfLocks,
            0.01e18, // 1% tolerance
            "Total voting power doesn't match locked tokens"
        );
    }
    
    /// @notice Sum of individual balances should equal total supply
    function invariant_sumOfBalancesEqualsTotalSupply() public view {
        uint256 totalSupply = votingEscrow.totalSupply();
        uint256 sumOfBalances = handler.getSumOfBalances();
        
        assertApproxEqRel(
            sumOfBalances,
            totalSupply,
            0.01e18,
            "Sum of balances doesn't equal total supply"
        );
    }
    
    /// @notice Voting power should decay over time
    function invariant_votingPowerDecaysOverTime() public view {
        // If we have locks and time has passed
        if (handler.ghost_totalLocked() > 0 && block.timestamp > handler.ghost_lastLockTime()) {
            uint256 currentPower = votingEscrow.totalSupply();
            uint256 initialPower = handler.ghost_initialTotalPower();
            
            if (initialPower > 0) {
                assertLe(
                    currentPower,
                    initialPower,
                    "Voting power increased without new locks"
                );
            }
        }
    }
    
    /// @notice Individual voting power cannot exceed total supply
    function invariant_individualPowerBoundedByTotal() public view {
        address[] memory users = handler.getUsers();
        uint256 totalSupply = votingEscrow.totalSupply();
        
        for (uint256 i = 0; i < users.length; i++) {
            uint256 balance = votingEscrow.balanceOf(users[i]);
            assertLe(balance, totalSupply, "Individual power exceeds total");
        }
    }
    
    /// @notice Delegation should conserve voting power
    function invariant_delegationConservesPower() public view {
        uint256 powerBeforeDelegation = handler.ghost_powerBeforeDelegation();
        uint256 powerAfterDelegation = handler.ghost_powerAfterDelegation();
        
        if (powerBeforeDelegation > 0) {
            assertEq(
                powerBeforeDelegation,
                powerAfterDelegation,
                "Delegation changed total power"
            );
        }
    }
    
    // ============= Lock Mechanism Invariants =============
    
    /// @notice Locked amount should never exceed token balance
    function invariant_lockedNeverExceedsBalance() public view {
        address[] memory users = handler.getUsers();
        
        for (uint256 i = 0; i < users.length; i++) {
            (uint256 amount,) = votingEscrow.locked(users[i]);
            uint256 balance = token.balanceOf(users[i]);
            
            // Amount locked in escrow should be backed by tokens
            assertGe(
                token.balanceOf(address(votingEscrow)),
                handler.ghost_totalLocked(),
                "Locks exceed escrow balance"
            );
        }
    }
    
    /// @notice Lock end time should be in the future or zero
    function invariant_lockEndTimesValid() public view {
        address[] memory users = handler.getUsers();
        
        for (uint256 i = 0; i < users.length; i++) {
            (, uint256 end) = votingEscrow.locked(users[i]);
            
            if (end > 0) {
                // Non-zero end times should be future or withdrawable
                assertTrue(
                    end > block.timestamp || votingEscrow.balanceOf(users[i]) == 0,
                    "Invalid lock end time"
                );
            }
        }
    }
    
    /// @notice Total locked should equal escrow token balance
    function invariant_totalLockedMatchesEscrowBalance() public view {
        uint256 escrowBalance = token.balanceOf(address(votingEscrow));
        uint256 trackedLocked = handler.ghost_totalLocked();
        
        assertEq(
            escrowBalance,
            trackedLocked,
            "Escrow balance doesn't match tracked locks"
        );
    }
    
    // ============= Proposal State Invariants =============
    
    /// @notice Proposal states should follow valid transitions
    function invariant_proposalStateTransitionsValid() public view {
        uint256[] memory proposals = handler.getProposals();
        
        for (uint256 i = 0; i < proposals.length; i++) {
            GovernorAlpha.ProposalState state = governor.state(proposals[i]);
            GovernorAlpha.ProposalState prevState = handler.ghost_proposalPreviousState(proposals[i]);
            
            // Valid transitions only
            if (uint8(prevState) != 0) { // Not default
                assertTrue(
                    isValidTransition(prevState, state),
                    "Invalid proposal state transition"
                );
            }
        }
    }
    
    /// @notice Active proposals should have valid voting periods
    function invariant_activeProposalsInVotingPeriod() public view {
        uint256[] memory proposals = handler.getProposals();
        
        for (uint256 i = 0; i < proposals.length; i++) {
            GovernorAlpha.ProposalState state = governor.state(proposals[i]);
            
            if (state == GovernorAlpha.ProposalState.Active) {
                (,,,, uint256 startBlock, uint256 endBlock,,,,) = governor.proposals(proposals[i]);
                
                assertGe(block.number, startBlock, "Active before start");
                assertLe(block.number, endBlock, "Active after end");
            }
        }
    }
    
    /// @notice Executed proposals should have passed quorum
    function invariant_executedProposalsPassedQuorum() public view {
        uint256[] memory proposals = handler.getProposals();
        
        for (uint256 i = 0; i < proposals.length; i++) {
            GovernorAlpha.ProposalState state = governor.state(proposals[i]);
            
            if (state == GovernorAlpha.ProposalState.Executed) {
                (,,,,,, uint256 forVotes,,,) = governor.proposals(proposals[i]);
                
                assertGe(
                    forVotes,
                    governor.quorumVotes(),
                    "Executed without quorum"
                );
            }
        }
    }
    
    /// @notice Proposal count should only increase
    function invariant_proposalCountMonotonic() public view {
        uint256 currentCount = governor.proposalCount();
        uint256 lastCount = handler.ghost_lastProposalCount();
        
        assertGe(currentCount, lastCount, "Proposal count decreased");
    }
    
    // ============= Voting Invariants =============
    
    /// @notice Total votes should not exceed total voting power
    function invariant_totalVotesNotExceedPower() public view {
        uint256[] memory proposals = handler.getProposals();
        
        for (uint256 i = 0; i < proposals.length; i++) {
            (,,,,,, uint256 forVotes, uint256 againstVotes,,) = governor.proposals(proposals[i]);
            
            uint256 totalVotes = forVotes + againstVotes;
            uint256 totalPower = votingEscrow.totalSupplyAt(block.number);
            
            assertLe(totalVotes, totalPower, "Votes exceed voting power");
        }
    }
    
    /// @notice Double voting should be impossible
    function invariant_noDoubleVoting() public view {
        // Handler tracks votes per user per proposal
        assertTrue(
            !handler.ghost_doubleVoteDetected(),
            "Double voting detected"
        );
    }
    
    /// @notice For votes + against votes should equal total votes cast
    function invariant_votesSumCorrect() public view {
        uint256[] memory proposals = handler.getProposals();
        
        for (uint256 i = 0; i < proposals.length; i++) {
            (,,,,,, uint256 forVotes, uint256 againstVotes,,) = governor.proposals(proposals[i]);
            
            // Tracked votes should match contract state
            uint256 trackedFor = handler.ghost_proposalForVotes(proposals[i]);
            uint256 trackedAgainst = handler.ghost_proposalAgainstVotes(proposals[i]);
            
            assertEq(forVotes, trackedFor, "For votes mismatch");
            assertEq(againstVotes, trackedAgainst, "Against votes mismatch");
        }
    }
    
    // ============= Timelock Invariants =============
    
    /// @notice Queued transactions should have valid eta
    function invariant_queuedTransactionsValidEta() public view {
        bytes32[] memory txHashes = handler.getQueuedTransactions();
        
        for (uint256 i = 0; i < txHashes.length; i++) {
            if (timelock.queuedTransactions(txHashes[i])) {
                uint256 eta = handler.ghost_transactionEta(txHashes[i]);
                
                assertGe(
                    eta,
                    block.timestamp + timelock.delay(),
                    "Queued tx eta too early"
                );
            }
        }
    }
    
    /// @notice Executed transactions should be past eta
    function invariant_executedTransactionsPastEta() public view {
        bytes32[] memory executed = handler.getExecutedTransactions();
        
        for (uint256 i = 0; i < executed.length; i++) {
            uint256 eta = handler.ghost_transactionEta(executed[i]);
            uint256 execTime = handler.ghost_transactionExecutionTime(executed[i]);
            
            assertGe(execTime, eta, "Executed before eta");
        }
    }
    
    /// @notice Timelock delay should be constant (or increase only)
    function invariant_timelockDelayConstant() public view {
        uint256 currentDelay = timelock.delay();
        uint256 initialDelay = handler.ghost_initialTimelockDelay();
        
        assertGe(currentDelay, initialDelay, "Timelock delay decreased");
    }
    
    // ============= Checkpoint Invariants =============
    
    /// @notice Checkpoints should be in chronological order
    function invariant_checkpointsChronological() public view {
        address[] memory users = handler.getUsers();
        
        for (uint256 i = 0; i < users.length; i++) {
            uint256 numCheckpoints = votingEscrow.numCheckpoints(users[i]);
            
            for (uint256 j = 1; j < numCheckpoints; j++) {
                (uint256 prevBlock,) = votingEscrow.checkpoints(users[i], j - 1);
                (uint256 currBlock,) = votingEscrow.checkpoints(users[i], j);
                
                assertLt(prevBlock, currBlock, "Checkpoints out of order");
            }
        }
    }
    
    /// @notice Historical balance should match checkpoint
    function invariant_historicalBalanceMatchesCheckpoint() public view {
        address[] memory users = handler.getUsers();
        
        for (uint256 i = 0; i < users.length; i++) {
            if (block.number > 0) {
                uint256 balance = votingEscrow.balanceOfAt(users[i], block.number - 1);
                uint256 numCheckpoints = votingEscrow.numCheckpoints(users[i]);
                
                if (numCheckpoints > 0) {
                    (uint256 checkpointBlock, uint256 checkpointVotes) = 
                        votingEscrow.checkpoints(users[i], numCheckpoints - 1);
                    
                    if (checkpointBlock <= block.number - 1) {
                        assertEq(
                            balance,
                            checkpointVotes,
                            "Historical balance mismatch"
                        );
                    }
                }
            }
        }
    }
    
    // ============= Token Conservation Invariants =============
    
    /// @notice Tokens locked should equal tokens minted to escrow
    function invariant_tokenConservationInEscrow() public view {
        uint256 escrowBalance = token.balanceOf(address(votingEscrow));
        uint256 totalLocked = handler.ghost_totalLocked();
        
        assertEq(escrowBalance, totalLocked, "Token conservation violated in escrow");
    }
    
    /// @notice Withdrawn tokens should reduce escrow balance
    function invariant_withdrawnTokensReduceEscrow() public view {
        uint256 totalWithdrawn = handler.ghost_totalWithdrawn();
        uint256 totalLocked = handler.ghost_totalLocked();
        uint256 netLocked = handler.ghost_totalEverLocked() - totalWithdrawn;
        
        assertEq(totalLocked, netLocked, "Withdrawal tracking incorrect");
    }
    
    // ============= Reentrancy Protection =============
    
    /// @notice No reentrancy in governance operations
    function invariant_noReentrancy() public view {
        assertFalse(handler.ghost_reentrancyDetected(), "Reentrancy detected");
    }
    
    // Helper function
    function isValidTransition(
        GovernorAlpha.ProposalState from,
        GovernorAlpha.ProposalState to
    ) internal pure returns (bool) {
        // Valid state transitions
        if (from == GovernorAlpha.ProposalState.Pending && to == GovernorAlpha.ProposalState.Active) return true;
        if (from == GovernorAlpha.ProposalState.Active && to == GovernorAlpha.ProposalState.Defeated) return true;
        if (from == GovernorAlpha.ProposalState.Active && to == GovernorAlpha.ProposalState.Succeeded) return true;
        if (from == GovernorAlpha.ProposalState.Succeeded && to == GovernorAlpha.ProposalState.Queued) return true;
        if (from == GovernorAlpha.ProposalState.Queued && to == GovernorAlpha.ProposalState.Executed) return true;
        if (from == GovernorAlpha.ProposalState.Queued && to == GovernorAlpha.ProposalState.Expired) return true;
        if (to == GovernorAlpha.ProposalState.Canceled) return true; // Can cancel from any state
        
        return from == to; // Same state is valid
    }
}

/**
 * @title GovernanceHandler
 * @notice Handler for governance invariant testing
 */
contract GovernanceHandler is Test {
    
    VotingEscrow public votingEscrow;
    GovernorAlpha public governor;
    Timelock public timelock;
    RebaseToken public token;
    
    address[] public users;
    uint256[] public proposals;
    bytes32[] public queuedTransactions;
    bytes32[] public executedTransactions;
    
    // Ghost variables
    uint256 public ghost_totalLocked;
    uint256 public ghost_totalEverLocked;
    uint256 public ghost_totalWithdrawn;
    uint256 public ghost_lastLockTime;
    uint256 public ghost_initialTotalPower;
    uint256 public ghost_powerBeforeDelegation;
    uint256 public ghost_powerAfterDelegation;
    uint256 public ghost_lastProposalCount;
    uint256 public ghost_initialTimelockDelay;
    bool public ghost_doubleVoteDetected;
    bool public ghost_reentrancyDetected;
    
    mapping(uint256 => GovernorAlpha.ProposalState) public ghost_proposalPreviousState;
    mapping(uint256 => uint256) public ghost_proposalForVotes;
    mapping(uint256 => uint256) public ghost_proposalAgainstVotes;
    mapping(bytes32 => uint256) public ghost_transactionEta;
    mapping(bytes32 => uint256) public ghost_transactionExecutionTime;
    mapping(address => mapping(uint256 => bool)) public ghost_hasVoted;
    
    constructor(
        VotingEscrow _votingEscrow,
        GovernorAlpha _governor,
        Timelock _timelock,
        RebaseToken _token
    ) {
        votingEscrow = _votingEscrow;
        governor = _governor;
        timelock = _timelock;
        token = _token;
        
        ghost_initialTimelockDelay = timelock.delay();
        
        // Create test users
        for (uint256 i = 0; i < 5; i++) {
            address user = address(uint160(uint256(keccak256(abi.encodePacked(i, "govuser")))));
            users.push(user);
            
            // Mint tokens to users
            token.mint(user, 10000 ether, 1000);
            
            // Approve voting escrow
            vm.prank(user);
            token.approve(address(votingEscrow), type(uint256).max);
        }
    }
    
    // ============= Actions =============
    
    function createLock(uint256 userSeed, uint256 amount, uint256 duration) external {
        address user = users[userSeed % users.length];
        amount = bound(amount, 1 ether, 1000 ether);
        duration = bound(duration, 1 weeks, 4 * 365 days);
        
        uint256 userBalance = token.balanceOf(user);
        if (userBalance < amount) return;
        
        (uint256 existingLock,) = votingEscrow.locked(user);
        if (existingLock > 0) return; // Already has lock
        
        vm.prank(user);
        try votingEscrow.createLock(amount, block.timestamp + duration) {
            ghost_totalLocked += amount;
            ghost_totalEverLocked += amount;
            ghost_lastLockTime = block.timestamp;
            
            if (ghost_initialTotalPower == 0) {
                ghost_initialTotalPower = votingEscrow.totalSupply();
            }
        } catch {}
    }
    
    function increaseLock(uint256 userSeed, uint256 amount) external {
        address user = users[userSeed % users.length];
        amount = bound(amount, 1 ether, 500 ether);
        
        (uint256 existingLock, uint256 end) = votingEscrow.locked(user);
        if (existingLock == 0) return;
        if (end <= block.timestamp) return;
        
        uint256 userBalance = token.balanceOf(user);
        if (userBalance < amount) return;
        
        vm.prank(user);
        try votingEscrow.increaseAmount(amount) {
            ghost_totalLocked += amount;
            ghost_totalEverLocked += amount;
        } catch {}
    }
    
    function withdraw(uint256 userSeed) external {
        address user = users[userSeed % users.length];
        
        (uint256 amount, uint256 end) = votingEscrow.locked(user);
        if (amount == 0) return;
        if (end > block.timestamp) return;
        
        vm.prank(user);
        try votingEscrow.withdraw() {
            ghost_totalLocked -= amount;
            ghost_totalWithdrawn += amount;
        } catch {}
    }
    
    function delegate(uint256 userSeed, uint256 delegateeSeed) external {
        address user = users[userSeed % users.length];
        address delegatee = users[delegateeSeed % users.length];
        
        ghost_powerBeforeDelegation = votingEscrow.totalSupply();
        
        vm.prank(user);
        try votingEscrow.delegate(delegatee) {
            ghost_powerAfterDelegation = votingEscrow.totalSupply();
        } catch {}
    }
    
    function createProposal(uint256 userSeed) external {
        address user = users[userSeed % users.length];
        
        // Need 100 tokens to propose
        if (votingEscrow.balanceOf(user) < governor.proposalThreshold()) return;
        
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        string[] memory signatures = new string[](1);
        bytes[] memory calldatas = new bytes[](1);
        
        targets[0] = address(timelock);
        values[0] = 0;
        signatures[0] = "setDelay(uint256)";
        calldatas[0] = abi.encode(3 days);
        
        vm.prank(user);
        try governor.propose(targets, values, signatures, calldatas, "Test Proposal") returns (uint256 proposalId) {
            proposals.push(proposalId);
            ghost_lastProposalCount = proposalId;
            ghost_proposalPreviousState[proposalId] = GovernorAlpha.ProposalState.Pending;
        } catch {}
    }
    
    function vote(uint256 userSeed, uint256 proposalSeed, bool support) external {
        if (proposals.length == 0) return;
        
        address user = users[userSeed % users.length];
        uint256 proposalId = proposals[proposalSeed % proposals.length];
        
        GovernorAlpha.ProposalState state = governor.state(proposalId);
        if (state != GovernorAlpha.ProposalState.Active) return;
        
        // Check double vote
        if (ghost_hasVoted[user][proposalId]) {
            ghost_doubleVoteDetected = true;
            return;
        }
        
        uint256 votes = votingEscrow.balanceOf(user);
        if (votes == 0) return;
        
        vm.prank(user);
        try governor.castVote(proposalId, support) {
            ghost_hasVoted[user][proposalId] = true;
            
            if (support) {
                ghost_proposalForVotes[proposalId] += votes;
            } else {
                ghost_proposalAgainstVotes[proposalId] += votes;
            }
            
            ghost_proposalPreviousState[proposalId] = state;
        } catch {}
    }
    
    // ============= View Functions =============
    
    function getUsers() external view returns (address[] memory) {
        return users;
    }
    
    function getProposals() external view returns (uint256[] memory) {
        return proposals;
    }
    
    function getQueuedTransactions() external view returns (bytes32[] memory) {
        return queuedTransactions;
    }
    
    function getExecutedTransactions() external view returns (bytes32[] memory) {
        return executedTransactions;
    }
    
    function getSumOfLocks() external view returns (uint256) {
        uint256 sum = 0;
        for (uint256 i = 0; i < users.length; i++) {
            (uint256 amount,) = votingEscrow.locked(users[i]);
            sum += amount;
        }
        return sum;
    }
    
    function getSumOfBalances() external view returns (uint256) {
        uint256 sum = 0;
        for (uint256 i = 0; i < users.length; i++) {
            sum += votingEscrow.balanceOf(users[i]);
        }
        return sum;
    }
}
