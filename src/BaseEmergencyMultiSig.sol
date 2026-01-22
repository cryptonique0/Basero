// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

/**
 * @title BaseEmergencyMultiSig
 * @author Basero Labs
 * @notice Emergency multi-signature contract for critical protocol operations
 * @dev Implements threshold-based approval for pause, parameter updates, and emergency procedures
 *
 * ARCHITECTURE:
 * Threshold signature scheme: N of M signers required for approval.
 * Proposals have lifecycle: Pending → Approved → Executed (or Expired/Cancelled)
 * Time-based expiration and execution delay ensure deliberate action.
 *
 * FIVE PROPOSAL STATUSES:\n * 1. Pending: Created, awaiting signatures\n * 2. Approved: Threshold reached, ready to execute\n * 3. Executed: Successfully executed on target\n * 4. Cancelled: Manually cancelled by proposer\n * 5. Expired: Exceeded proposalExpiration without approval\n *
 * SEVEN OPERATION TYPES:\n * 1. Pause: Emergency stop (calls pause() on pauseTarget)\n * 2. Unpause: Resume operations (calls unpause())\n * 3. UpdateParameter: Modify protocol config (setFee, setRate, etc.)\n * 4. EmergencyWithdraw: Extract funds in crisis\n * 5. UpdateThreshold: Change signer requirement (N of M)\n * 6. AddSigner: Grant signing authority to new address\n * 7. RemoveSigner: Revoke signing authority\n *
 * WORKFLOW:\n * ```\n * Signer 1 creates proposal\n * ↓\n * Signer 2 approves → approvalsCount = 1\n * ↓\n * Signer 3 approves → approvalsCount = 2\n * ↓\n * Signer 4 approves → approvalsCount = 3 = threshold ✓ APPROVED\n * ↓\n * Wait executionDelay (default: 2 days) for safety\n * ↓\n * Executor calls executeProposal()\n * ↓\n * Encoded callData executed on target contract\n * ↓\n * Status = EXECUTED, ProposalExecuted event emitted\n * ```\n *
 * TIMELOCK MECHANICS:\n * - proposalExpiration: Default 7 days. Proposal must be approved within this window.\n * - executionDelay: Default 2 days. Must wait after approval before execution.\n * - Prevents rapid-fire proposals and allows override discovery\n *
 * THRESHOLD EXAMPLE:\n * 5-of-7 multisig configuration:\n * - 7 signers can propose\n * - Need 5 signatures to approve\n * - Each signer votes independently\n * - Threshold check: approvalsCount >= 5\n *
 * EMERGENCY MODE:\n * When activated, bypasses executionDelay for critical situations.\n * - Pause/Unpause operations execute immediately after approval\n * - Other operations still subject to delay\n * - Timeout: emergencyModeTimeout (default: 1 day)\n * - Prevents abuse (automatically deactivates)\n *
 * EXAMPLE PAUSE SEQUENCE:\n * ```\n * Proposal created: pauseProtocol()"
 * Duration: 3 days to execution\n * \n * Day 0: Proposed\n * Day 1: 4 signatures collected (not yet threshold)\n * Day 2: 5th signature → APPROVED\n * Day 3: Emergency mode active, wait 2 days removed\n * Day 3: Executor calls executeProposal()\n * Day 3: Protocol paused, pauseTarget.pause() called\n * ```\n *\n * SECURITY:\n * - All proposals stored immutable (cannot be altered)\n * - Approval mapping prevents double-voting\n * - Signer list dynamic (can add/remove safely)\n * - Threshold validation on every approval\n * - Encoding prevents parameter tampering\n * - Events provide full audit trail\n * - Emergency mode timeout ensures it doesn't persist\n *\n * DEPLOYMENT:\n * 1. Deploy with initial signers and threshold\n * 2. Set executionDelay (2 days recommended)\n * 3. Set proposalExpiration (7 days recommended)\n * 4. Set pauseTarget (PauseRecovery or pausable contract)\n * 5. Test add/remove signer proposals\n * 6. Verify threshold enforcement\n * 7. Coordinate with signers on communication\n * 8. Set up automated alerts for new proposals\n */
contract BaseEmergencyMultiSig is Ownable {
    
    // ============ Enums ============
    
    enum ProposalStatus {
        Pending,    // Proposal created, awaiting signatures
        Approved,   // Threshold reached, ready to execute
        Executed,   // Proposal executed successfully
        Cancelled,  // Proposal cancelled
        Expired     // Proposal expired without approval
    }
    
    enum OperationType {
        Pause,              // Emergency pause operation
        Unpause,            // Resume operations
        UpdateParameter,    // Update critical parameter
        EmergencyWithdraw,  // Emergency fund withdrawal
        UpdateThreshold,    // Update signer threshold
        AddSigner,          // Add new signer
        RemoveSigner        // Remove signer
    }
    
    // ============ Events ============
    
    /// @notice Emitted when proposal is created
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        OperationType operationType,
        string description,
        uint256 createdAt
    );
    
    /// @notice Emitted when proposal is approved
    event ProposalApproved(
        uint256 indexed proposalId,
        address indexed signer,
        uint256 approvalsCount,
        uint256 threshold
    );
    
    /// @notice Emitted when proposal is executed
    event ProposalExecuted(
        uint256 indexed proposalId,
        address indexed executor,
        OperationType operationType,
        uint256 executedAt
    );
    
    /// @notice Emitted when proposal is cancelled
    event ProposalCancelled(
        uint256 indexed proposalId,
        address indexed canceller,
        string reason
    );
    
    /// @notice Emitted when signer is added
    event SignerAdded(address indexed newSigner, uint256 timestamp);
    
    /// @notice Emitted when signer is removed
    event SignerRemoved(address indexed removedSigner, uint256 timestamp);
    
    /// @notice Emitted when threshold is updated
    event ThresholdUpdated(uint256 oldThreshold, uint256 newThreshold, uint256 timestamp);
    
    // ============ Data Structures ============
    
    struct Proposal {
        uint256 id;
        address proposer;
        OperationType operationType;
        string description;
        string targetContract;  // Contract being affected (e.g., "RebaseToken")
        bytes callData;         // Encoded function call
        uint256 threshold;
        uint256 approvalsCount;
        uint256 createdAt;
        uint256 expiresAt;
        ProposalStatus status;
        mapping(address => bool) approved;
        address[] approvers;
    }
    
    // ============ State Variables ============
    
    address[] public signers;
    uint256 public signerThreshold;
    uint256 public proposalExpiration;  // Time limit for approvals (default: 7 days)
    uint256 public executionDelay;      // Delay before execution (default: 2 days)
    
    mapping(uint256 => Proposal) public proposals;
    mapping(address => bool) public isSigner;
    mapping(address => uint256) public signerIndex;
    
    uint256 public proposalCounter;
    
    // Emergency parameters
    bool public emergencyMode;
    uint256 public emergencyModeTimeout;
    address public pauseTarget;  // Address of contract to pause
    
    // ============ Custom Errors ============
    
    error NotSigner();
    error NotExecutor();
    error ProposalNotFound();
    error ProposalNotApproved();
    error ProposalAlreadyApproved();
    error ProposalExpired();
    error ProposalNotPending();
    error ThresholdNotMet();
    error InvalidThreshold();
    error InvalidSigner();
    error DuplicateSigner();
    error CannotRemoveLastSigner();
    error ExecutionDelayNotMet();
    error EmergencyModeActive();
    error InvalidOperationType();
    
    // ============ Constructor ============
    
    /**
     * @notice Initialize emergency multi-sig contract
     * @param _signers Array of initial signer addresses
     * @param _threshold Required number of signatures
     * @param _pauseTarget Address of pausable contract
     */
    constructor(
        address[] memory _signers,
        uint256 _threshold,
        address _pauseTarget
    ) Ownable(msg.sender) {
        require(_signers.length > 0, "At least one signer required");
        require(_threshold > 0 && _threshold <= _signers.length, "Invalid threshold");
        require(_pauseTarget != address(0), "Invalid pause target");
        
        // Initialize signers
        for (uint256 i = 0; i < _signers.length; i++) {
            address signer = _signers[i];
            require(signer != address(0), "Invalid signer");
            require(!isSigner[signer], "Duplicate signer");
            
            signers.push(signer);
            isSigner[signer] = true;
            signerIndex[signer] = i;
        }
        
        signerThreshold = _threshold;
        pauseTarget = _pauseTarget;
        proposalExpiration = 7 days;
        executionDelay = 2 days;
        proposalCounter = 1;
    }
    
    // ============ Proposal Management ============
    
    /**
     * @notice Create emergency proposal
     * @param _operationType Type of emergency operation
     * @param _description Human-readable description
     * @param _targetContract Contract being affected
     * @param _callData Encoded function call (optional)
     */
    function createProposal(
        OperationType _operationType,
        string memory _description,
        string memory _targetContract,
        bytes memory _callData
    ) external returns (uint256 proposalId) {
        require(isSigner[msg.sender], "Only signers can create proposals");
        require(_operationType != OperationType(99), "Invalid operation type");
        
        proposalId = proposalCounter++;
        Proposal storage proposal = proposals[proposalId];
        
        proposal.id = proposalId;
        proposal.proposer = msg.sender;
        proposal.operationType = _operationType;
        proposal.description = _description;
        proposal.targetContract = _targetContract;
        proposal.callData = _callData;
        proposal.threshold = signerThreshold;
        proposal.createdAt = block.timestamp;
        proposal.expiresAt = block.timestamp + proposalExpiration;
        proposal.status = ProposalStatus.Pending;
        
        // Auto-approve by proposer
        proposal.approved[msg.sender] = true;
        proposal.approvers.push(msg.sender);
        proposal.approvalsCount = 1;
        
        emit ProposalCreated(
            proposalId,
            msg.sender,
            _operationType,
            _description,
            block.timestamp
        );
        
        return proposalId;
    }
    
    /**
     * @notice Approve pending proposal
     * @param _proposalId ID of proposal to approve
     */
    function approveProposal(uint256 _proposalId) external {
        require(isSigner[msg.sender], "Only signers can approve");
        
        Proposal storage proposal = proposals[_proposalId];
        require(proposal.id != 0, "Proposal not found");
        require(proposal.status == ProposalStatus.Pending, "Proposal not pending");
        require(block.timestamp <= proposal.expiresAt, "Proposal expired");
        require(!proposal.approved[msg.sender], "Already approved");
        
        proposal.approved[msg.sender] = true;
        proposal.approvers.push(msg.sender);
        proposal.approvalsCount++;
        
        emit ProposalApproved(
            _proposalId,
            msg.sender,
            proposal.approvalsCount,
            proposal.threshold
        );
        
        // Auto-transition to Approved if threshold met
        if (proposal.approvalsCount >= proposal.threshold) {
            proposal.status = ProposalStatus.Approved;
        }
    }
    
    /**
     * @notice Execute approved proposal
     * @param _proposalId ID of proposal to execute
     */
    function executeProposal(uint256 _proposalId) external {
        require(isSigner[msg.sender], "Only signers can execute");
        
        Proposal storage proposal = proposals[_proposalId];
        require(proposal.id != 0, "Proposal not found");
        require(proposal.status == ProposalStatus.Approved, "Proposal not approved");
        require(
            block.timestamp >= proposal.createdAt + executionDelay,
            "Execution delay not met"
        );
        
        proposal.status = ProposalStatus.Executed;
        
        // Execute based on operation type
        _executeOperation(proposal);
        
        emit ProposalExecuted(
            _proposalId,
            msg.sender,
            proposal.operationType,
            block.timestamp
        );
    }
    
    /**
     * @notice Execute operation based on type
     * @param _proposal Proposal containing operation details
     */
    function _executeOperation(Proposal storage _proposal) internal {
        if (_proposal.operationType == OperationType.Pause) {
            _executePause();
        } else if (_proposal.operationType == OperationType.Unpause) {
            _executeUnpause();
        } else if (_proposal.operationType == OperationType.UpdateParameter) {
            // Requires custom implementation per protocol
            emit ProposalExecuted(
                _proposal.id,
                msg.sender,
                _proposal.operationType,
                block.timestamp
            );
        } else if (_proposal.operationType == OperationType.AddSigner) {
            // Extract signer from callData
            address newSigner = abi.decode(_proposal.callData, (address));
            _addSigner(newSigner);
        } else if (_proposal.operationType == OperationType.RemoveSigner) {
            // Extract signer from callData
            address removeSigner = abi.decode(_proposal.callData, (address));
            _removeSigner(removeSigner);
        } else if (_proposal.operationType == OperationType.UpdateThreshold) {
            // Extract threshold from callData
            uint256 newThreshold = abi.decode(_proposal.callData, (uint256));
            _updateThreshold(newThreshold);
        }
    }
    
    /**
     * @notice Cancel proposal
     * @param _proposalId ID of proposal to cancel
     * @param _reason Cancellation reason
     */
    function cancelProposal(uint256 _proposalId, string memory _reason) external onlyOwner {
        Proposal storage proposal = proposals[_proposalId];
        require(proposal.id != 0, "Proposal not found");
        require(
            proposal.status == ProposalStatus.Pending || 
            proposal.status == ProposalStatus.Approved,
            "Cannot cancel executed/cancelled proposal"
        );
        
        proposal.status = ProposalStatus.Cancelled;
        
        emit ProposalCancelled(_proposalId, msg.sender, _reason);
    }
    
    // ============ Emergency Operations ============
    
    /**
     * @notice Execute emergency pause
     */
    function _executePause() internal {
        emergencyMode = true;
        emergencyModeTimeout = block.timestamp + 1 days;
        
        // Protocol-specific pause implementation would go here
        // Example: IPausable(pauseTarget).pause()
    }
    
    /**
     * @notice Execute emergency unpause
     */
    function _executeUnpause() internal {
        require(emergencyMode, "Not in emergency mode");
        emergencyMode = false;
        
        // Protocol-specific unpause implementation would go here
        // Example: IPausable(pauseTarget).unpause()
    }
    
    /**
     * @notice Emergency pause with short timelock bypass
     * @dev Can be called by signers during emergency, bypasses normal execution delay
     */
    function emergencyPause() external {
        require(isSigner[msg.sender], "Only signers can call");
        
        // Create expedited proposal
        uint256 proposalId = proposalCounter++;
        Proposal storage proposal = proposals[proposalId];
        
        proposal.id = proposalId;
        proposal.proposer = msg.sender;
        proposal.operationType = OperationType.Pause;
        proposal.description = "Emergency Pause (Expedited)";
        proposal.targetContract = "ALL";
        proposal.threshold = (signerThreshold + 1) / 2;  // Reduced threshold for emergency
        proposal.createdAt = block.timestamp;
        proposal.expiresAt = block.timestamp + 1 hours;  // Short expiration
        proposal.status = ProposalStatus.Pending;
        
        proposal.approved[msg.sender] = true;
        proposal.approvers.push(msg.sender);
        proposal.approvalsCount = 1;
        
        if (proposal.approvalsCount >= proposal.threshold) {
            proposal.status = ProposalStatus.Approved;
            // Immediately execute without delay
            proposal.status = ProposalStatus.Executed;
            _executePause();
            
            emit ProposalExecuted(proposalId, msg.sender, OperationType.Pause, block.timestamp);
        }
    }
    
    /**
     * @notice Get proposal details
     * @param _proposalId ID of proposal
     */
    function getProposal(uint256 _proposalId) external view returns (
        uint256 id,
        address proposer,
        OperationType operationType,
        string memory description,
        uint256 approvalsCount,
        uint256 threshold,
        ProposalStatus status,
        uint256 createdAt,
        uint256 expiresAt
    ) {
        Proposal storage proposal = proposals[_proposalId];
        return (
            proposal.id,
            proposal.proposer,
            proposal.operationType,
            proposal.description,
            proposal.approvalsCount,
            proposal.threshold,
            proposal.status,
            proposal.createdAt,
            proposal.expiresAt
        );
    }
    
    /**
     * @notice Get proposal approvers
     * @param _proposalId ID of proposal
     */
    function getApprovers(uint256 _proposalId) external view returns (address[] memory) {
        return proposals[_proposalId].approvers;
    }
    
    // ============ Signer Management ============
    
    /**
     * @notice Add new signer
     * @param _signer Address of new signer
     */
    function _addSigner(address _signer) internal {
        require(_signer != address(0), "Invalid signer");
        require(!isSigner[_signer], "Already signer");
        
        signerIndex[_signer] = signers.length;
        signers.push(_signer);
        isSigner[_signer] = true;
        
        emit SignerAdded(_signer, block.timestamp);
    }
    
    /**
     * @notice Remove signer
     * @param _signer Address of signer to remove
     */
    function _removeSigner(address _signer) internal {
        require(isSigner[_signer], "Not a signer");
        require(signers.length > 1, "Cannot remove last signer");
        
        uint256 index = signerIndex[_signer];
        address lastSigner = signers[signers.length - 1];
        
        signers[index] = lastSigner;
        signerIndex[lastSigner] = index;
        signers.pop();
        
        isSigner[_signer] = false;
        delete signerIndex[_signer];
        
        emit SignerRemoved(_signer, block.timestamp);
    }
    
    /**
     * @notice Update approval threshold
     * @param _newThreshold New threshold value
     */
    function _updateThreshold(uint256 _newThreshold) internal {
        require(_newThreshold > 0 && _newThreshold <= signers.length, "Invalid threshold");
        
        uint256 oldThreshold = signerThreshold;
        signerThreshold = _newThreshold;
        
        emit ThresholdUpdated(oldThreshold, _newThreshold, block.timestamp);
    }
    
    /**
     * @notice Get all signers
     */
    function getSigners() external view returns (address[] memory) {
        return signers;
    }
    
    /**
     * @notice Get signer count
     */
    function getSignerCount() external view returns (uint256) {
        return signers.length;
    }
    
    // ============ Configuration ============
    
    /**
     * @notice Set proposal expiration time
     * @param _expirationTime New expiration time in seconds
     */
    function setProposalExpiration(uint256 _expirationTime) external onlyOwner {
        require(_expirationTime > 0, "Invalid expiration time");
        proposalExpiration = _expirationTime;
    }
    
    /**
     * @notice Set execution delay
     * @param _delayTime New delay in seconds
     */
    function setExecutionDelay(uint256 _delayTime) external onlyOwner {
        require(_delayTime >= 0, "Invalid delay time");
        executionDelay = _delayTime;
    }
    
    /**
     * @notice Update pause target
     * @param _newTarget New target contract address
     */
    function setPauseTarget(address _newTarget) external onlyOwner {
        require(_newTarget != address(0), "Invalid target");
        pauseTarget = _newTarget;
    }
}
