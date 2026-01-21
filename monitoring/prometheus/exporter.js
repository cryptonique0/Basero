#!/usr/bin/env node

/**
 * @title Basero Prometheus Metrics Exporter
 * @notice Exports blockchain metrics to Prometheus format
 */

const { ethers } = require('ethers');
const express = require('express');
const client = require('prom-client');

// ============================================
// CONFIGURATION
// ============================================

const PORT = process.env.PORT || 9090;
const RPC_URL = process.env.RPC_URL || 'https://sepolia.drpc.org';
const HEALTH_CHECKER_ADDRESS = process.env.HEALTH_CHECKER_ADDRESS;
const SCRAPE_INTERVAL = parseInt(process.env.SCRAPE_INTERVAL || '30000'); // 30 seconds

// Contract addresses (loaded from env)
const ADDRESSES = {
  token: process.env.TOKEN_ADDRESS,
  vault: process.env.VAULT_ADDRESS,
  bridge: process.env.BRIDGE_ADDRESS,
  governor: process.env.GOVERNOR_ADDRESS,
  timelock: process.env.TIMELOCK_ADDRESS,
  votingEscrow: process.env.VOTING_ESCROW_ADDRESS,
  healthChecker: HEALTH_CHECKER_ADDRESS,
};

// ============================================
// PROMETHEUS METRICS
// ============================================

const register = new client.Registry();

// System metrics
const systemOperational = new client.Gauge({
  name: 'basero_system_operational',
  help: 'System operational status (1=operational, 0=down)',
  registers: [register],
});

const componentsOperational = new client.Gauge({
  name: 'basero_components_operational',
  help: 'Number of operational components (out of 6)',
  registers: [register],
});

const componentsPaused = new client.Gauge({
  name: 'basero_components_paused',
  help: 'Number of paused components',
  registers: [register],
});

const activeAlerts = new client.Gauge({
  name: 'basero_active_alerts',
  help: 'Number of active alerts',
  registers: [register],
});

// Token metrics
const tokenOperational = new client.Gauge({
  name: 'basero_token_operational',
  help: 'Token contract operational (1=yes, 0=no)',
  registers: [register],
});

const tokenTotalSupply = new client.Gauge({
  name: 'basero_token_total_supply',
  help: 'Total token supply (wei)',
  registers: [register],
});

const tokenRebaseIndex = new client.Gauge({
  name: 'basero_token_rebase_index',
  help: 'Current rebase index',
  registers: [register],
});

const tokenTimeSinceRebase = new client.Gauge({
  name: 'basero_token_time_since_rebase',
  help: 'Seconds since last rebase',
  registers: [register],
});

const tokenRebaseHealthy = new client.Gauge({
  name: 'basero_token_rebase_healthy',
  help: 'Rebase health status (1=healthy, 0=overdue)',
  registers: [register],
});

// Vault metrics
const vaultOperational = new client.Gauge({
  name: 'basero_vault_operational',
  help: 'Vault contract operational (1=yes, 0=no)',
  registers: [register],
});

const vaultPaused = new client.Gauge({
  name: 'basero_vault_is_paused',
  help: 'Vault paused status (1=paused, 0=active)',
  registers: [register],
});

const vaultTotalAssets = new client.Gauge({
  name: 'basero_vault_total_assets',
  help: 'Total assets in vault (wei)',
  registers: [register],
});

const vaultTotalShares = new client.Gauge({
  name: 'basero_vault_total_shares',
  help: 'Total vault shares',
  registers: [register],
});

const vaultUtilizationBps = new client.Gauge({
  name: 'basero_vault_utilization_bps',
  help: 'Vault utilization rate (basis points)',
  registers: [register],
});

const vaultSharePrice = new client.Gauge({
  name: 'basero_vault_share_price',
  help: 'Vault share price',
  registers: [register],
});

const vaultUtilizationHealthy = new client.Gauge({
  name: 'basero_vault_utilization_healthy',
  help: 'Vault utilization health (1=healthy, 0=critical)',
  registers: [register],
});

// Bridge metrics
const bridgeOperational = new client.Gauge({
  name: 'basero_bridge_operational',
  help: 'Bridge operational (1=yes, 0=no)',
  registers: [register],
});

const bridgePaused = new client.Gauge({
  name: 'basero_bridge_is_paused',
  help: 'Bridge paused status (1=paused, 0=active)',
  registers: [register],
});

const bridgePendingMessages = new client.Gauge({
  name: 'basero_bridge_pending_messages',
  help: 'Number of pending bridge messages',
  registers: [register],
});

const bridgeFailedMessages = new client.Gauge({
  name: 'basero_bridge_failed_messages',
  help: 'Number of failed bridge messages',
  registers: [register],
});

// Governance metrics
const governanceOperational = new client.Gauge({
  name: 'basero_governance_operational',
  help: 'Governance operational (1=yes, 0=no)',
  registers: [register],
});

const governanceActiveProposals = new client.Gauge({
  name: 'basero_governance_active_proposals',
  help: 'Number of active proposals',
  registers: [register],
});

const governanceTotalProposals = new client.Gauge({
  name: 'basero_governance_total_proposals',
  help: 'Total number of proposals',
  registers: [register],
});

const governanceVotingPower = new client.Gauge({
  name: 'basero_governance_voting_power',
  help: 'Total voting power',
  registers: [register],
});

// Timelock metrics
const timelockOperational = new client.Gauge({
  name: 'basero_timelock_operational',
  help: 'Timelock operational (1=yes, 0=no)',
  registers: [register],
});

const timelockMinDelay = new client.Gauge({
  name: 'basero_timelock_min_delay',
  help: 'Timelock minimum delay (seconds)',
  registers: [register],
});

// Voting Escrow metrics
const votingEscrowOperational = new client.Gauge({
  name: 'basero_voting_escrow_operational',
  help: 'VotingEscrow operational (1=yes, 0=no)',
  registers: [register],
});

const votingEscrowTotalLocked = new client.Gauge({
  name: 'basero_voting_escrow_total_locked',
  help: 'Total tokens locked in voting escrow',
  registers: [register],
});

// ============================================
// CONTRACT ABI (minimal)
// ============================================

const HEALTH_CHECKER_ABI = [
  'function getSystemHealth() external view returns (tuple(bool allSystemsOperational, tuple(bool isOperational, uint256 totalSupply, uint256 rebaseIndex, uint256 lastRebaseTime, uint256 timeSinceRebase, bool rebaseHealthy, uint256 holderCount) token, tuple(bool isOperational, bool isPaused, uint256 totalAssets, uint256 totalShares, uint256 utilizationRate, uint256 sharePrice, bool utilizationHealthy, bool sharePriceHealthy, uint256 userCount) vault, tuple(bool isOperational, bool isPaused, uint256 pendingMessages, uint256 failedMessages, uint256 lastMessageTime, uint256 timeSinceMessage, bool messageFlowHealthy, uint256 totalBridged) bridge, tuple(bool isOperational, uint256 activeProposals, uint256 queuedProposals, uint256 totalProposals, uint256 votingPower, uint256 participationRate, bool quorumHealthy) governance, tuple(bool isOperational, uint256 queuedOperations, uint256 readyOperations, uint256 minDelay, bool delayHealthy) timelock, tuple(bool isOperational, uint256 totalLocked, uint256 averageLockTime, uint256 activeLockers, bool lockingHealthy) votingEscrow, uint256 timestamp, uint256 blockNumber))',
  'function getQuickMetrics() external view returns (uint256 operational, uint256 paused, uint256 utilizationBps)',
  'function getAlerts() external view returns (string[] memory alerts)',
];

// ============================================
// METRICS COLLECTOR
// ============================================

class MetricsCollector {
  constructor() {
    this.provider = new ethers.JsonRpcProvider(RPC_URL);
    this.healthChecker = null;
    
    if (HEALTH_CHECKER_ADDRESS) {
      this.healthChecker = new ethers.Contract(
        HEALTH_CHECKER_ADDRESS,
        HEALTH_CHECKER_ABI,
        this.provider
      );
    }
  }

  async collectMetrics() {
    try {
      if (!this.healthChecker) {
        console.warn('HealthChecker address not configured');
        return;
      }

      // Get system health
      const health = await this.healthChecker.getSystemHealth();
      
      // Update system metrics
      systemOperational.set(health.allSystemsOperational ? 1 : 0);
      
      // Count operational components
      let operational = 0;
      if (health.token.isOperational) operational++;
      if (health.vault.isOperational) operational++;
      if (health.bridge.isOperational) operational++;
      if (health.governance.isOperational) operational++;
      if (health.timelock.isOperational) operational++;
      if (health.votingEscrow.isOperational) operational++;
      
      componentsOperational.set(operational);
      
      // Count paused components
      let paused = 0;
      if (health.vault.isPaused) paused++;
      if (health.bridge.isPaused) paused++;
      componentsPaused.set(paused);
      
      // Get alerts
      const alerts = await this.healthChecker.getAlerts();
      activeAlerts.set(alerts.length);
      
      // Token metrics
      tokenOperational.set(health.token.isOperational ? 1 : 0);
      tokenTotalSupply.set(Number(health.token.totalSupply));
      tokenRebaseIndex.set(Number(health.token.rebaseIndex));
      tokenTimeSinceRebase.set(Number(health.token.timeSinceRebase));
      tokenRebaseHealthy.set(health.token.rebaseHealthy ? 1 : 0);
      
      // Vault metrics
      vaultOperational.set(health.vault.isOperational ? 1 : 0);
      vaultPaused.set(health.vault.isPaused ? 1 : 0);
      vaultTotalAssets.set(Number(health.vault.totalAssets));
      vaultTotalShares.set(Number(health.vault.totalShares));
      vaultUtilizationBps.set(Number(health.vault.utilizationRate));
      vaultSharePrice.set(Number(health.vault.sharePrice));
      vaultUtilizationHealthy.set(health.vault.utilizationHealthy ? 1 : 0);
      
      // Bridge metrics
      bridgeOperational.set(health.bridge.isOperational ? 1 : 0);
      bridgePaused.set(health.bridge.isPaused ? 1 : 0);
      bridgePendingMessages.set(Number(health.bridge.pendingMessages));
      bridgeFailedMessages.set(Number(health.bridge.failedMessages));
      
      // Governance metrics
      governanceOperational.set(health.governance.isOperational ? 1 : 0);
      governanceActiveProposals.set(Number(health.governance.activeProposals));
      governanceTotalProposals.set(Number(health.governance.totalProposals));
      governanceVotingPower.set(Number(health.governance.votingPower));
      
      // Timelock metrics
      timelockOperational.set(health.timelock.isOperational ? 1 : 0);
      timelockMinDelay.set(Number(health.timelock.minDelay));
      
      // Voting Escrow metrics
      votingEscrowOperational.set(health.votingEscrow.isOperational ? 1 : 0);
      votingEscrowTotalLocked.set(Number(health.votingEscrow.totalLocked));
      
      console.log(`[${new Date().toISOString()}] Metrics collected successfully`);
      if (alerts.length > 0) {
        console.warn(`Active alerts: ${alerts.length}`);
        alerts.forEach(alert => console.warn(`  - ${alert}`));
      }
      
    } catch (error) {
      console.error('Error collecting metrics:', error);
    }
  }

  async startCollecting() {
    // Collect immediately
    await this.collectMetrics();
    
    // Then collect at intervals
    setInterval(() => {
      this.collectMetrics();
    }, SCRAPE_INTERVAL);
  }
}

// ============================================
// EXPRESS SERVER
// ============================================

const app = express();

// Health check endpoint
app.get('/health', (req, res) => {
  res.status(200).send('OK');
});

// Metrics endpoint
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  const metrics = await register.metrics();
  res.end(metrics);
});

// Info endpoint
app.get('/', (req, res) => {
  res.json({
    service: 'Basero Prometheus Exporter',
    version: '1.0.0',
    endpoints: {
      health: '/health',
      metrics: '/metrics',
    },
    config: {
      rpcUrl: RPC_URL,
      healthChecker: HEALTH_CHECKER_ADDRESS || 'NOT_CONFIGURED',
      scrapeInterval: SCRAPE_INTERVAL,
    },
  });
});

// ============================================
// START SERVER
// ============================================

async function main() {
  // Validate configuration
  if (!HEALTH_CHECKER_ADDRESS) {
    console.error('ERROR: HEALTH_CHECKER_ADDRESS environment variable not set');
    console.log('Please set the following environment variables:');
    console.log('  - HEALTH_CHECKER_ADDRESS (required)');
    console.log('  - RPC_URL (optional, default: https://sepolia.drpc.org)');
    console.log('  - PORT (optional, default: 9090)');
    console.log('  - SCRAPE_INTERVAL (optional, default: 30000ms)');
    process.exit(1);
  }

  console.log('='.repeat(60));
  console.log('Basero Prometheus Metrics Exporter');
  console.log('='.repeat(60));
  console.log(`RPC URL: ${RPC_URL}`);
  console.log(`HealthChecker: ${HEALTH_CHECKER_ADDRESS}`);
  console.log(`Scrape Interval: ${SCRAPE_INTERVAL}ms`);
  console.log(`Port: ${PORT}`);
  console.log('='.repeat(60));

  // Start metrics collector
  const collector = new MetricsCollector();
  await collector.startCollecting();

  // Start HTTP server
  app.listen(PORT, () => {
    console.log(`\nMetrics server listening on http://localhost:${PORT}`);
    console.log(`Metrics endpoint: http://localhost:${PORT}/metrics`);
    console.log(`Health endpoint: http://localhost:${PORT}/health\n`);
  });
}

// Handle errors
process.on('unhandledRejection', (error) => {
  console.error('Unhandled rejection:', error);
});

process.on('SIGTERM', () => {
  console.log('SIGTERM received, shutting down gracefully');
  process.exit(0);
});

// Run
main().catch((error) => {
  console.error('Fatal error:', error);
  process.exit(1);
});
