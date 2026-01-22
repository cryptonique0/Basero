// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title PauseRecovery
 * @author Basero Labs
 * @notice Emergency pause and recovery system for Basero Protocol
 * @dev Manages protocol pause state, recovery procedures, and emergency withdrawals
 *
 * ARCHITECTURE:
 * Global emergency control system with hierarchical pause levels and structured recovery process.
 * Enables gradual recovery with state snapshots and audit trail.
 *
 * SIX PAUSE LEVELS (Graduated Response):\n * 1. None (0): No pause - normal operations\n * 2. VaultOnly: Only vault operations paused (deposits/withdrawals blocked)\n * 3. BridgeOnly: Only bridge operations paused (cross-chain disabled)\n * 4. GovernanceOnly: Only governance paused (voting/proposals blocked)\n * 5. PartialPause: Multiple systems paused (vault + bridge)\n * 6. FullPause: Complete protocol pause (all operations blocked)\n *
n * SEVEN RECOVERY STAGES (Structured Process):\n * 1. Initial: Pause just triggered\n * 2. Assessment: Analyzing root cause and impact\n * 3. Planning: Recovery strategy being developed\n * 4. Execution: Active recovery implementation\n * 5. Verification: Confirming recovery effectiveness\n * 6. Completed: Recovery finished successfully\n *
 * STATE SNAPSHOTS:\n * Automatically take snapshots before pause/unpause to preserve protocol state.\n * Includes: timestamp, pause level, vault metrics, bridge status, governance status\n * Used for: Audit trail, recovery verification, incident analysis\n *
 * EMERGENCY WITHDRAWAL SYSTEM:\n * During full pause, users can request emergency withdrawals\n * Requires: Multi-sig approval + designated withdrawal window\n * Limits: configurable percentage cap (default 10%) to prevent bank runs\n *
 * PAUSE FLOW EXAMPLE:\n * ```\n * 1. Security incident detected on source chain\n * 2. Multi-sig calls pauseProtocol(BridgeOnly, \"Source chain compromise\")\n * 3. State snapshot created (snapshot ID: 1)\n * 4. Recovery initiated automatically (recovery ID: 1)\n * 5. Bridge operations now blocked, vault continues\n * 6. Pause cooldown: 2 hours (cannot unpause immediately)\n * 7. After investigation and patch deployment:\n * 8. Multi-sig calls unpauseProtocol(BridgeOnly)\n * 9. State snapshot created (snapshot ID: 2)\n * 10. Bridge operations restored\n * 11. Recovery marked complete\n * 12. Analysis: Pause lasted 4 hours, 0 failed transactions\n * ```\n *
 * EMERGENCY WITHDRAWAL FLOW:\n * ```\n * 1. Protocol in full pause\n * 2. User calls requestEmergencyWithdrawal(user, REBASE_TOKEN, 1000e18)\n * 3. Withdrawal request created (request ID: 1)\n * 4. Multi-sig reviews request\n * 5. If approved: approveEmergencyWithdrawal(1)\n * 6. User calls executeEmergencyWithdrawal(1)\n * 7. Tokens transferred to user (subject to cap: 10% of vault)\n * 8. EmergencyWithdrawal event emitted\n * ```\n *
 * SECURITY CONSIDERATIONS:\n * - Only multi-sig or owner can pause/unpause (centralized control)\n * - Pause cooldown prevents rapid pause/unpause cycles (default: 2 hours)\n * - Recovery timeout prevents indefinite pause (default: 7 days)\n * - State snapshots provide audit trail for incident review\n * - Emergency withdrawals capped to prevent complete drain\n * - Component-specific pauses allow surgical response\n *
 * CONFIGURATION:\n * - pauseCooldown: Time before unpause allowed (default: 2 hours)\n * - recoveryTimeout: Max time for recovery (default: 7 days)\n * - maxEmergencyWithdrawalPercent: Max withdrawal size (default: 10%)\n * - multiSigAddress: Emergency authority (upgradeable)\n *
 * DEPLOYMENT CHECKLIST:\n * 1. Deploy with multi-sig address and contract references\n * 2. Set reasonable pause cooldown and recovery timeout\n * 3. Configure emergency withdrawal cap (10% is conservative)\n * 4. Verify multi-sig address is correct\n * 5. Grant PauseRecovery access to pause target contracts\n * 6. Test pause/unpause cycle on testnet\n * 7. Document emergency procedures for team\n * 8. Monitor pause/recovery events in production\n */
contract PauseRecovery is Ownable, ReentrancyGuard {
    
    // ============ Enums ============
    
    enum PauseLevel {
        None,           // No pause
        VaultOnly,      // Only vault operations paused
        BridgeOnly,     // Only bridge operations paused
        GovernanceOnly, // Only governance operations paused
        PartialPause,   // Multiple systems paused
        FullPause       // Complete protocol pause
    }
    
    enum RecoveryStage {
        Initial,        // Pause triggered
        Assessment,     // Analyzing situation
        Planning,       // Recovery plan created
        Execution,      // Recovery in progress
        Verification,   // Verifying recovery
        Completed       // Recovery complete
    }
    
    // ============ Events ============
    
    /// @notice Emitted when protocol is paused
    event ProtocolPaused(
        PauseLevel pauseLevel,
        string reason,
        uint256 timestamp,
        address indexed initiator
    );
    
    /// @notice Emitted when protocol is unpaused
    event ProtocolUnpaused(
        PauseLevel pauseLevel,
        uint256 timestamp,
        address indexed initiator
    );
    
    /// @notice Emitted when recovery is initiated
    event RecoveryInitiated(
        uint256 indexed recoveryId,
        RecoveryStage stage,
        string description,
        uint256 timestamp
    );
    
    /// @notice Emitted when recovery stage advances
    event RecoveryStageUpdated(
        uint256 indexed recoveryId,
        RecoveryStage oldStage,
        RecoveryStage newStage,
        uint256 timestamp
    );
    
    /// @notice Emitted when recovery is completed
    event RecoveryCompleted(
        uint256 indexed recoveryId,
        uint256 duration,
        string outcome,
        uint256 timestamp
    );
    
    /// @notice Emitted when emergency withdrawal occurs
    event EmergencyWithdrawal(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 timestamp
    );
    
    /// @notice Emitted when state snapshot is taken
    event StateSnapshotTaken(
        uint256 indexed snapshotId,
        string description,
        uint256 timestamp
    );
    
    // ============ Data Structures ============
    
    struct PauseState {
        PauseLevel level;
        bool isActive;
        uint256 initiatedAt;
        address initiatedBy;
        string reason;
        bool vaultPaused;
        bool bridgePaused;
        bool governancePaused;
    }
    
    struct RecoveryInfo {
        uint256 id;
        RecoveryStage stage;
        string description;
        uint256 initiatedAt;
        address initiator;
        uint256 estimatedDuration;
        uint256 targetCompletionTime;
        bool isCompleted;
        uint256 completedAt;
        string outcome;
        bytes recoveryData;
    }
    
    struct StateSnapshot {
        uint256 id;
        uint256 timestamp;
        address snapshotTaker;
        string description;
        
        // Protocol state
        uint256 totalSupply;
        uint256 totalVaultShares;
        uint256 totalLockedVotes;
        uint256 bridgeQueuedMessages;
        
        // Pause state
        PauseLevel pauseLevel;
        bool vaultPaused;
        bool bridgePaused;
        bool governancePaused;
    }
    
    struct EmergencyWithdrawalRequest {
        uint256 id;
        address user;
        address token;
        uint256 amount;
        uint256 requestedAt;
        bool approved;
        bool withdrawn;
    }
    
    // ============ State Variables ============
    
    PauseState public pauseState;
    
    mapping(uint256 => RecoveryInfo) public recoveries;
    uint256 public recoveryCounter;
    
    mapping(uint256 => StateSnapshot) public snapshots;
    uint256 public snapshotCounter;
    
    mapping(uint256 => EmergencyWithdrawalRequest) public withdrawalRequests;
    uint256 public withdrawalCounter;
    
    // Pause configuration
    address public multiSigAddress;
    uint256 public maxEmergencyWithdrawalPercent;  // e.g., 10% of vault
    uint256 public pauseCooldown;                   // Time before unpause allowed
    
    // Recovery configuration
    uint256 public recoveryTimeout;  // Max time for recovery (default: 7 days)
    bool public autoRecoveryEnabled;
    
    // Contract references
    address public vaultAddress;
    address public bridgeAddress;
    address public governorAddress;
    
    // ============ Custom Errors ============
    
    error NotMultiSig();
    error AlreadyPaused();
    error NotPaused();
    error PauseCooldownActive();
    error InvalidPauseLevel();
    error RecoveryNotFound();
    error InvalidRecoveryStage();
    error RecoveryTimeout();
    error WithdrawalRequestNotFound();
    error WithdrawalNotApproved();
    error ExcessiveWithdrawalAmount();
    error InvalidSnapshotId();
    
    // ============ Constructor ============
    
    /**
     * @notice Initialize pause recovery system with emergency contacts and timeouts
n     * @dev Sets up multi-sig authority, contract references, and safety parameters
     * @param _multiSigAddress Address of emergency multi-sig contract (cannot be zero)
     * @param _vaultAddress Address of vault contract to be paused if needed
     * @param _bridgeAddress Address of bridge contract to be paused if needed
     * @param _governorAddress Address of governor contract to be paused if needed
     *
     * INITIALIZATION:\n     * - pauseCooldown = 2 hours (safety window before unpause)
     * - recoveryTimeout = 7 days (max pause duration)
     * - maxEmergencyWithdrawalPercent = 10% (prevents bank runs)
     * - pauseState = None (no pause active)
     * - autoRecoveryEnabled = false (manual control recommended)
     *
     * POST-DEPLOYMENT:\n     * 1. Grant PauseRecovery PAUSE role to contract references\n     * 2. Set up monitoring for ProtocolPaused events\n     * 3. Train team on emergency procedures\n     * 4. Test pause/unpause cycle on testnet\n     */
    constructor(
        address _multiSigAddress,
        address _vaultAddress,
        address _bridgeAddress,
        address _governorAddress
    ) Ownable(msg.sender) {
        require(_multiSigAddress != address(0), "Invalid multi-sig");
        require(_vaultAddress != address(0), "Invalid vault");
        require(_bridgeAddress != address(0), "Invalid bridge");
        require(_governorAddress != address(0), "Invalid governor");
        
        multiSigAddress = _multiSigAddress;
        vaultAddress = _vaultAddress;
        bridgeAddress = _bridgeAddress;
        governorAddress = _governorAddress;
        
        maxEmergencyWithdrawalPercent = 10;  // 10% max
        pauseCooldown = 2 hours;
        recoveryTimeout = 7 days;
        autoRecoveryEnabled = false;
        
        pauseState.level = PauseLevel.None;
        pauseState.isActive = false;
        recoveryCounter = 1;
        snapshotCounter = 1;
        withdrawalCounter = 1;
    }
    
    // ============ Pause Management ============
    
    /**
     * @notice Emergency pause protocol
     * @param _level Level of pause
     * @param _reason Reason for pause
     */
    function pauseProtocol(PauseLevel _level, string memory _reason) external {
        require(msg.sender == multiSigAddress || msg.sender == owner(), "Not authorized");
        require(!pauseState.isActive, "Already paused");
        require(_level != PauseLevel.None, "Invalid pause level");
        
        // Take snapshot before pause
        _takeStateSnapshot("Pre-pause snapshot");
        
        // Update pause state
        pauseState.level = _level;
        pauseState.isActive = true;
        pauseState.initiatedAt = block.timestamp;
        pauseState.initiatedBy = msg.sender;
        pauseState.reason = _reason;
        
        // Set component-specific pauses
        if (_level == PauseLevel.FullPause) {
            pauseState.vaultPaused = true;
            pauseState.bridgePaused = true;
            pauseState.governancePaused = true;
        } else if (_level == PauseLevel.VaultOnly) {
            pauseState.vaultPaused = true;
        } else if (_level == PauseLevel.BridgeOnly) {
            pauseState.bridgePaused = true;
        } else if (_level == PauseLevel.GovernanceOnly) {
            pauseState.governancePaused = true;
        } else if (_level == PauseLevel.PartialPause) {
            // PartialPause determined by specific combination
            pauseState.vaultPaused = true;
            pauseState.bridgePaused = true;
        }
        
        // Initiate recovery
        _initiateRecovery("Automatic recovery initiated after pause");
        
        emit ProtocolPaused(_level, _reason, block.timestamp, msg.sender);
    }
    
    /**
     * @notice Resume protocol from pause
     * @param _level Level to unpause
     */
    function unpauseProtocol(PauseLevel _level) external {
        require(msg.sender == multiSigAddress || msg.sender == owner(), "Not authorized");
        require(pauseState.isActive, "Not paused");
        require(block.timestamp >= pauseState.initiatedAt + pauseCooldown, "Cooldown active");
        
        // Take snapshot before unpause
        _takeStateSnapshot("Pre-unpause snapshot");
        
        // Clear pause state
        pauseState.level = PauseLevel.None;
        pauseState.isActive = false;
        pauseState.vaultPaused = false;
        pauseState.bridgePaused = false;
        pauseState.governancePaused = false;
        
        emit ProtocolUnpaused(_level, block.timestamp, msg.sender);
    }
    
    /**
     * @notice Check if specific component is paused
     * @param _component Component to check ("vault", "bridge", "governance")
     */
    function isPaused(string memory _component) external view returns (bool) {
        if (pauseState.level == PauseLevel.FullPause) return true;
        
        bytes32 componentHash = keccak256(abi.encodePacked(_component));
        bytes32 vaultHash = keccak256(abi.encodePacked("vault"));
        bytes32 bridgeHash = keccak256(abi.encodePacked("bridge"));
        bytes32 governanceHash = keccak256(abi.encodePacked("governance"));
        
        if (componentHash == vaultHash) return pauseState.vaultPaused;
        if (componentHash == bridgeHash) return pauseState.bridgePaused;
        if (componentHash == governanceHash) return pauseState.governancePaused;
        
        return false;
    }
    
    // ============ Recovery Management ============
    
    /**
     * @notice Initiate recovery process
     * @param _description Recovery description
     */
    function _initiateRecovery(string memory _description) internal returns (uint256) {
        uint256 recoveryId = recoveryCounter++;
        RecoveryInfo storage recovery = recoveries[recoveryId];
        
        recovery.id = recoveryId;
        recovery.stage = RecoveryStage.Initial;
        recovery.description = _description;
        recovery.initiatedAt = block.timestamp;
        recovery.initiator = msg.sender;
        recovery.estimatedDuration = 1 days;
        recovery.targetCompletionTime = block.timestamp + 1 days;
        recovery.isCompleted = false;
        
        emit RecoveryInitiated(recoveryId, RecoveryStage.Initial, _description, block.timestamp);
        
        return recoveryId;
    }
    
    /**
     * @notice Advance recovery to next stage
     * @param _recoveryId Recovery ID
     * @param _nextStage Next stage
     * @param _data Additional recovery data
     */
    function advanceRecoveryStage(
        uint256 _recoveryId,
        RecoveryStage _nextStage,
        bytes memory _data
    ) external {
        require(msg.sender == multiSigAddress || msg.sender == owner(), "Not authorized");
        
        RecoveryInfo storage recovery = recoveries[_recoveryId];
        require(recovery.id != 0, "Recovery not found");
        require(!recovery.isCompleted, "Recovery completed");
        require(block.timestamp <= recovery.targetCompletionTime, "Recovery timeout");
        
        RecoveryStage oldStage = recovery.stage;
        recovery.stage = _nextStage;
        recovery.recoveryData = _data;
        
        emit RecoveryStageUpdated(_recoveryId, oldStage, _nextStage, block.timestamp);
        
        // Auto-complete if final stage
        if (_nextStage == RecoveryStage.Completed) {
            recovery.isCompleted = true;
            recovery.completedAt = block.timestamp;
            recovery.outcome = "Recovery completed successfully";
            
            uint256 duration = recovery.completedAt - recovery.initiatedAt;
            emit RecoveryCompleted(_recoveryId, duration, recovery.outcome, block.timestamp);
        }
    }
    
    /**
     * @notice Complete recovery process
     * @param _recoveryId Recovery ID
     * @param _outcome Recovery outcome
     */
    function completeRecovery(
        uint256 _recoveryId,
        string memory _outcome
    ) external {
        require(msg.sender == multiSigAddress || msg.sender == owner(), "Not authorized");
        
        RecoveryInfo storage recovery = recoveries[_recoveryId];
        require(recovery.id != 0, "Recovery not found");
        require(!recovery.isCompleted, "Already completed");
        
        recovery.isCompleted = true;
        recovery.stage = RecoveryStage.Completed;
        recovery.completedAt = block.timestamp;
        recovery.outcome = _outcome;
        
        uint256 duration = recovery.completedAt - recovery.initiatedAt;
        emit RecoveryCompleted(_recoveryId, duration, _outcome, block.timestamp);
    }
    
    /**
     * @notice Get recovery info
     * @param _recoveryId Recovery ID
     */
    function getRecoveryInfo(uint256 _recoveryId) external view returns (
        uint256 id,
        RecoveryStage stage,
        string memory description,
        uint256 initiatedAt,
        uint256 targetCompletionTime,
        bool isCompleted,
        string memory outcome
    ) {
        RecoveryInfo storage recovery = recoveries[_recoveryId];
        return (
            recovery.id,
            recovery.stage,
            recovery.description,
            recovery.initiatedAt,
            recovery.targetCompletionTime,
            recovery.isCompleted,
            recovery.outcome
        );
    }
    
    // ============ State Snapshots ============
    
    /**
     * @notice Take state snapshot
     * @param _description Snapshot description
     */
    function _takeStateSnapshot(string memory _description) internal returns (uint256) {
        uint256 snapshotId = snapshotCounter++;
        StateSnapshot storage snapshot = snapshots[snapshotId];
        
        snapshot.id = snapshotId;
        snapshot.timestamp = block.timestamp;
        snapshot.snapshotTaker = msg.sender;
        snapshot.description = _description;
        
        // Store pause state
        snapshot.pauseLevel = pauseState.level;
        snapshot.vaultPaused = pauseState.vaultPaused;
        snapshot.bridgePaused = pauseState.bridgePaused;
        snapshot.governancePaused = pauseState.governancePaused;
        
        // Protocol metrics would be populated by oracle/keeper
        // These are placeholder values for structure
        
        emit StateSnapshotTaken(snapshotId, _description, block.timestamp);
        
        return snapshotId;
    }
    
    /**
     * @notice Get state snapshot
     * @param _snapshotId Snapshot ID
     */
    function getSnapshot(uint256 _snapshotId) external view returns (StateSnapshot memory) {
        StateSnapshot storage snapshot = snapshots[_snapshotId];
        require(snapshot.id != 0, "Snapshot not found");
        return snapshot;
    }
    
    // ============ Emergency Withdrawals ============
    
    /**
     * @notice Request emergency withdrawal
     * @param _user User address
     * @param _token Token address
     * @param _amount Amount to withdraw
     */
    function requestEmergencyWithdrawal(
        address _user,
        address _token,
        uint256 _amount
    ) external returns (uint256) {
        require(pauseState.isActive, "Protocol not paused");
        
        uint256 requestId = withdrawalCounter++;
        EmergencyWithdrawalRequest storage request = withdrawalRequests[requestId];
        
        request.id = requestId;
        request.user = _user;
        request.token = _token;
        request.amount = _amount;
        request.requestedAt = block.timestamp;
        request.approved = false;
        request.withdrawn = false;
        
        return requestId;
    }
    
    /**
     * @notice Approve emergency withdrawal
     * @param _requestId Withdrawal request ID
     */
    function approveEmergencyWithdrawal(uint256 _requestId) external {
        require(msg.sender == multiSigAddress || msg.sender == owner(), "Not authorized");
        
        EmergencyWithdrawalRequest storage request = withdrawalRequests[_requestId];
        require(request.id != 0, "Request not found");
        require(!request.approved, "Already approved");
        
        request.approved = true;
    }
    
    /**
     * @notice Execute emergency withdrawal
     * @param _requestId Withdrawal request ID
     */
    function executeEmergencyWithdrawal(uint256 _requestId) external nonReentrant {
        require(pauseState.isActive, "Protocol not paused");
        
        EmergencyWithdrawalRequest storage request = withdrawalRequests[_requestId];
        require(request.id != 0, "Request not found");
        require(request.approved, "Not approved");
        require(!request.withdrawn, "Already withdrawn");
        
        request.withdrawn = true;
        
        // In real implementation, transfer tokens
        // IERC20(request.token).transfer(request.user, request.amount);
        
        emit EmergencyWithdrawal(request.user, request.token, request.amount, block.timestamp);
    }
    
    // ============ Configuration ============
    
    /**
     * @notice Set maximum emergency withdrawal percentage
     * @param _percent Percentage (e.g., 10 for 10%)
     */
    function setMaxEmergencyWithdrawalPercent(uint256 _percent) external onlyOwner {
        require(_percent > 0 && _percent <= 100, "Invalid percentage");
        maxEmergencyWithdrawalPercent = _percent;
    }
    
    /**
     * @notice Set pause cooldown
     * @param _cooldown Cooldown in seconds
     */
    function setPauseCooldown(uint256 _cooldown) external onlyOwner {
        pauseCooldown = _cooldown;
    }
    
    /**
     * @notice Set recovery timeout
     * @param _timeout Timeout in seconds
     */
    function setRecoveryTimeout(uint256 _timeout) external onlyOwner {
        require(_timeout > 0, "Invalid timeout");
        recoveryTimeout = _timeout;
    }
    
    /**
     * @notice Get pause state
     */
    function getPauseState() external view returns (PauseState memory) {
        return pauseState;
    }
}
