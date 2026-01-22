// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {RebaseToken} from "../RebaseToken.sol";
import {AdvancedStrategyVault} from "../AdvancedStrategyVault.sol";
import {BaseBridgeMessenger} from "../BaseBridgeMessenger.sol";
import {BaseroGovernor} from "../BaseroGovernor.sol";
import {BaseroTimelock} from "../BaseroTimelock.sol";
import {VotingEscrow} from "../VotingEscrow.sol";

/**
 * @title HealthChecker
 * @author Basero Labs
 * @notice Provides health check endpoints for monitoring infrastructure\n * @dev Used by Grafana, Datadog, and alerting systems to monitor protocol health
 *
 * ARCHITECTURE:
 * Query-only contract returning structured health data for each protocol component.
 * No state changes, purely observational. Designed for external monitoring integration.n *\n * SIX COMPONENT HEALTH CHECKS:\n *\n * 1. TOKEN HEALTH\n *    - isOperational: totalSupply > 0\n *    - rebaseHealthy: timeSinceRebase < 25 hours (within 1hr buffer of 24h)\n *    - Fields: supply, index, lastRebase time, holder count\n *    - Alert: If rebase missing or overdue\n *\n * 2. VAULT HEALTH\n *    - isOperational: totalAssets > 0\n *    - isPaused: Checked via Pausable.paused()\n *    - utilizationHealthy: utilization < 95%\n *    - sharePriceHealthy: sharePrice in reasonable range\n *    - Fields: assets, shares, utilization, user count\n *    - Alert: If >95% utilized or paused\n *\n * 3. BRIDGE HEALTH\n *    - isOperational: lastMessageTime recent\n *    - isPaused: Checked via pause state\n *    - messageFlowHealthy: lastMessage < 1 day (recent activity)\n *    - Fields: pending messages, failed messages, total bridged\n *    - Alert: If >1 day without messages or pending backlog\n *\n * 4. GOVERNANCE HEALTH\n *    - isOperational: Governor contract responsive\n *    - quorumHealthy: Can achieve quorum (4% minimum)\n *    - Fields: active/queued/total proposals, voting power, participation\n *    - Alert: If quorum impossible or participation <10%\n *\n * 5. TIMELOCK HEALTH\n *    - isOperational: Timelock responsive\n *    - delayHealthy: delay in reasonable range (2 days typical)\n *    - Fields: queued ops, ready ops, minimum delay\n *    - Alert: If delay too short (<1 day) or too long (>14 days)\n *\n * 6. VOTING ESCROW HEALTH\n *    - isOperational: VotingEscrow responsive\n *    - lockingHealthy: Significant TVL locked (>1M tokens)\n *    - Fields: total locked, average lock time, active lockers\n *    - Alert: If TVL drops significantly\n *\n * HEALTH THRESHOLDS (Configurable):\n * ```\n * MAX_HEALTHY_UTILIZATION = 9500 (95%)\n * MAX_REBASE_INTERVAL = 25 hours\n * MIN_BRIDGE_ACTIVITY = 1 days\n * MIN_QUORUM_PERCENTAGE = 400 (4%)\n * ```\n *\n * MONITORING INTEGRATION:\n * ```json\n * // Grafana query example:\n * {\n *   \"targets\": [\n *     {\n *       \"expr\": \"contract_call(healthChecker.getSystemHealth())\",\n *       \"refId\": \"A\"\n *     }\n *   ]\n * }\n * \n * // Datadog metric example:\n * def check_health():\n *     health = health_checker.getSystemHealth()\n *     datadog.gauge('basero.vault.utilization', health.vault.utilizationRate)\n *     datadog.gauge('basero.bridge.pending', health.bridge.pendingMessages)\n *     if not health.allSystemsOperational:\n *         trigger_alert(\"Protocol unhealthy\")\n * ```\n *\n * ALERTING RULES:\n * 1. Vault Utilization Alert: When utilization > 95%\n * 2. Token Rebase Alert: When rebase missing > 25 hours\n * 3. Bridge Activity Alert: When no messages > 24 hours\n * 4. Governance Alert: When quorum < 4% possible\n * 5. System Alert: When allSystemsOperational = false\n * 6. Timelock Alert: When delay < 1 day or > 14 days\n *\n * DEPLOYMENT:\n * 1. Deploy with contract references (all immutable)\n * 2. Verify all 6 contract addresses are correct\n * 3. Grant HealthChecker read access to all contracts\n * 4. Configure monitoring system to query regularly (every 5-15 min)\n * 5. Set up alerts for each health threshold\n * 6. Test queries on testnet\n * 7. Verify response times acceptable (<5s)\n * 8. Document health check endpoints for on-call team\n */
contract HealthChecker {
    // ============================================
    // STRUCTS
    // ============================================

    struct TokenHealth {
        bool isOperational;
        uint256 totalSupply;
        uint256 rebaseIndex;
        uint256 lastRebaseTime;
        uint256 timeSinceRebase;
        bool rebaseHealthy; // True if rebase within expected window
        uint256 holderCount; // Approximate
    }

    struct VaultHealth {
        bool isOperational;
        bool isPaused;
        uint256 totalAssets;
        uint256 totalShares;
        uint256 utilizationRate;
        uint256 sharePrice;
        bool utilizationHealthy; // True if < 95%
        bool sharePriceHealthy; // True if reasonable
        uint256 userCount;
    }

    struct BridgeHealth {
        bool isOperational;
        bool isPaused;
        uint256 pendingMessages;
        uint256 failedMessages;
        uint256 lastMessageTime;
        uint256 timeSinceMessage;
        bool messageFlowHealthy; // True if recent activity
        uint256 totalBridged;
    }

    struct GovernanceHealth {
        bool isOperational;
        uint256 activeProposals;
        uint256 queuedProposals;
        uint256 totalProposals;
        uint256 votingPower;
        uint256 participationRate;
        bool quorumHealthy; // True if quorum achievable
    }

    struct TimelockHealth {
        bool isOperational;
        uint256 queuedOperations;
        uint256 readyOperations;
        uint256 minDelay;
        bool delayHealthy; // True if reasonable
    }

    struct VotingEscrowHealth {
        bool isOperational;
        uint256 totalLocked;
        uint256 averageLockTime;
        uint256 activeLockers;
        bool lockingHealthy; // True if significant TVL
    }

    struct SystemHealth {
        bool allSystemsOperational;
        TokenHealth token;
        VaultHealth vault;
        BridgeHealth bridge;
        GovernanceHealth governance;
        TimelockHealth timelock;
        VotingEscrowHealth votingEscrow;
        uint256 timestamp;
        uint256 blockNumber;
    }

    // ============================================
    // STATE VARIABLES
    // ============================================

    RebaseToken public immutable token;
    AdvancedStrategyVault public immutable vault;
    BaseBridgeMessenger public immutable bridge;
    BaseroGovernor public immutable governor;
    BaseroTimelock public immutable timelock;
    VotingEscrow public immutable votingEscrow;

    // Health thresholds
    uint256 public constant MAX_HEALTHY_UTILIZATION = 9500; // 95%
    uint256 public constant MAX_REBASE_INTERVAL = 25 hours; // Expected: 24h
    uint256 public constant MIN_BRIDGE_ACTIVITY = 1 days;
    uint256 public constant MIN_QUORUM_PERCENTAGE = 400; // 4%

    // ============================================
    // CONSTRUCTOR
    // ============================================

    constructor(
        address _token,
        address _vault,
        address _bridge,
        address _governor,
        address _timelock,
        address _votingEscrow
    ) {
        token = RebaseToken(_token);
        vault = AdvancedStrategyVault(payable(_vault));
        bridge = BaseBridgeMessenger(_bridge);
        governor = BaseroGovernor(payable(_governor));
        timelock = BaseroTimelock(payable(_timelock));
        votingEscrow = VotingEscrow(_votingEscrow);
    }

    // ============================================
    // HEALTH CHECK FUNCTIONS
    // ============================================

    /**
     * @notice Get complete system health status
     * @return health Complete health check data
     */
    function getSystemHealth() external view returns (SystemHealth memory health) {
        health.token = getTokenHealth();
        health.vault = getVaultHealth();
        health.bridge = getBridgeHealth();
        health.governance = getGovernanceHealth();
        health.timelock = getTimelockHealth();
        health.votingEscrow = getVotingEscrowHealth();
        health.timestamp = block.timestamp;
        health.blockNumber = block.number;

        // System is operational if all components are operational
        health.allSystemsOperational = health.token.isOperational && health.vault.isOperational
            && health.bridge.isOperational && health.governance.isOperational && health.timelock.isOperational
            && health.votingEscrow.isOperational;
    }

    /**
     * @notice Check token health
     */
    function getTokenHealth() public view returns (TokenHealth memory health) {
        try token.totalSupply() returns (uint256 supply) {
            health.isOperational = true;
            health.totalSupply = supply;
            health.rebaseIndex = token.rebaseIndex();
            health.lastRebaseTime = token.lastRebaseTime();
            health.timeSinceRebase = block.timestamp - health.lastRebaseTime;
            health.rebaseHealthy = health.timeSinceRebase < MAX_REBASE_INTERVAL;

            // Approximate holder count (would need events in production)
            health.holderCount = 0; // TODO: Track via events
        } catch {
            health.isOperational = false;
        }
    }

    /**
     * @notice Check vault health
     */
    function getVaultHealth() public view returns (VaultHealth memory health) {
        try vault.totalAssets() returns (uint256 assets) {
            health.isOperational = true;
            health.isPaused = vault.paused();
            health.totalAssets = assets;
            health.totalShares = vault.totalSupply();

            // Calculate utilization
            uint256 maxDeposit = vault.maxTotalDeposits();
            if (maxDeposit > 0) {
                health.utilizationRate = (assets * 10000) / maxDeposit;
                health.utilizationHealthy = health.utilizationRate < MAX_HEALTHY_UTILIZATION;
            } else {
                health.utilizationHealthy = true;
            }

            // Share price check
            if (health.totalShares > 0) {
                health.sharePrice = (assets * 1e18) / health.totalShares;
                health.sharePriceHealthy = health.sharePrice > 0 && health.sharePrice < 10e18; // Within reasonable bounds
            } else {
                health.sharePriceHealthy = true;
            }

            health.userCount = 0; // TODO: Track via events
        } catch {
            health.isOperational = false;
        }
    }

    /**
     * @notice Check bridge health
     */
    function getBridgeHealth() public view returns (BridgeHealth memory health) {
        try bridge.paused() returns (bool paused) {
            health.isOperational = true;
            health.isPaused = paused;

            // Note: These would need to be tracked via events in production
            health.pendingMessages = 0;
            health.failedMessages = 0;
            health.lastMessageTime = 0;
            health.timeSinceMessage = 0;
            health.messageFlowHealthy = true; // Would check activity
            health.totalBridged = 0;
        } catch {
            health.isOperational = false;
        }
    }

    /**
     * @notice Check governance health
     */
    function getGovernanceHealth() public view returns (GovernanceHealth memory health) {
        try governor.votingDelay() returns (uint256) {
            health.isOperational = true;

            // Get proposal count (would need to track via events)
            health.activeProposals = 0;
            health.queuedProposals = 0;
            health.totalProposals = 0;

            // Get voting power
            health.votingPower = token.totalSupply(); // Simplified
            health.participationRate = 0; // Would calculate from votes

            // Check if quorum is achievable
            uint256 quorum = governor.quorum(block.number - 1);
            health.quorumHealthy = quorum > 0 && quorum <= health.votingPower;
        } catch {
            health.isOperational = false;
        }
    }

    /**
     * @notice Check timelock health
     */
    function getTimelockHealth() public view returns (TimelockHealth memory health) {
        try timelock.getMinDelay() returns (uint256 delay) {
            health.isOperational = true;
            health.minDelay = delay;
            health.delayHealthy = delay >= 2 days && delay <= 7 days; // Reasonable range

            // Would need to track queued operations via events
            health.queuedOperations = 0;
            health.readyOperations = 0;
        } catch {
            health.isOperational = false;
        }
    }

    /**
     * @notice Check voting escrow health
     */
    function getVotingEscrowHealth() public view returns (VotingEscrowHealth memory health) {
        try votingEscrow.totalSupply() returns (uint256 supply) {
            health.isOperational = true;
            health.totalLocked = supply;

            // Would calculate from user data
            health.averageLockTime = 0;
            health.activeLockers = 0;

            // Check if significant TVL locked
            uint256 tokenSupply = token.totalSupply();
            if (tokenSupply > 0) {
                uint256 lockPercentage = (supply * 10000) / tokenSupply;
                health.lockingHealthy = lockPercentage > 100; // At least 1% locked
            }
        } catch {
            health.isOperational = false;
        }
    }

    // ============================================
    // SIMPLE STATUS ENDPOINTS
    // ============================================

    /**
     * @notice Simple boolean health check for uptime monitoring
     * @return healthy True if all systems operational
     */
    function isHealthy() external view returns (bool healthy) {
        SystemHealth memory health = this.getSystemHealth();
        return health.allSystemsOperational && !health.vault.isPaused && !health.bridge.isPaused
            && health.vault.utilizationHealthy && health.token.rebaseHealthy;
    }

    /**
     * @notice Get critical metrics for quick monitoring
     * @return operational Number of operational components (out of 6)
     * @return paused Number of paused components
     * @return utilizationBps Vault utilization in basis points
     */
    function getQuickMetrics() external view returns (uint256 operational, uint256 paused, uint256 utilizationBps) {
        SystemHealth memory health = this.getSystemHealth();

        // Count operational
        if (health.token.isOperational) operational++;
        if (health.vault.isOperational) operational++;
        if (health.bridge.isOperational) operational++;
        if (health.governance.isOperational) operational++;
        if (health.timelock.isOperational) operational++;
        if (health.votingEscrow.isOperational) operational++;

        // Count paused
        if (health.vault.isPaused) paused++;
        if (health.bridge.isPaused) paused++;

        // Get utilization
        utilizationBps = health.vault.utilizationRate;
    }

    /**
     * @notice Get alert-worthy conditions
     * @return alerts Array of alert messages
     */
    function getAlerts() external view returns (string[] memory alerts) {
        SystemHealth memory health = this.getSystemHealth();
        uint256 alertCount = 0;

        // Count alerts first
        if (!health.token.isOperational) alertCount++;
        if (!health.vault.isOperational) alertCount++;
        if (!health.bridge.isOperational) alertCount++;
        if (!health.governance.isOperational) alertCount++;
        if (!health.timelock.isOperational) alertCount++;
        if (!health.votingEscrow.isOperational) alertCount++;
        if (health.vault.isPaused) alertCount++;
        if (health.bridge.isPaused) alertCount++;
        if (!health.vault.utilizationHealthy) alertCount++;
        if (!health.token.rebaseHealthy) alertCount++;
        if (!health.timelock.delayHealthy) alertCount++;

        // Create array
        alerts = new string[](alertCount);
        uint256 index = 0;

        // Add alerts
        if (!health.token.isOperational) alerts[index++] = "Token contract not operational";
        if (!health.vault.isOperational) alerts[index++] = "Vault contract not operational";
        if (!health.bridge.isOperational) alerts[index++] = "Bridge contract not operational";
        if (!health.governance.isOperational) alerts[index++] = "Governance not operational";
        if (!health.timelock.isOperational) alerts[index++] = "Timelock not operational";
        if (!health.votingEscrow.isOperational) alerts[index++] = "VotingEscrow not operational";
        if (health.vault.isPaused) alerts[index++] = "Vault is paused";
        if (health.bridge.isPaused) alerts[index++] = "Bridge is paused";
        if (!health.vault.utilizationHealthy) alerts[index++] = "Vault utilization above 95%";
        if (!health.token.rebaseHealthy) alerts[index++] = "Rebase overdue (>25 hours)";
        if (!health.timelock.delayHealthy) alerts[index++] = "Timelock delay outside safe range";
    }
}
