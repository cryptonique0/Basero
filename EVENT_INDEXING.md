# Event Indexing Guide

## Overview

Basero emits comprehensive events across all protocol operations. This guide explains how to index these events for monitoring, analytics, and building user interfaces.

**Event Categories:** 8  
**Total Events:** 40+  
**Indexing Methods:** The Graph, Ethers.js, Alchemy/QuickNode webhooks  
**Use Cases:** Dashboards, alerts, analytics, UI state management  

## Table of Contents

1. [Event Categories](#event-categories)
2. [Core Protocol Events](#core-protocol-events)
3. [Governance Events](#governance-events)
4. [Bridge Events](#bridge-events)
5. [Indexing Strategies](#indexing-strategies)
6. [The Graph Integration](#the-graph-integration)
7. [Real-Time Monitoring](#real-time-monitoring)
8. [Query Patterns](#query-patterns)
9. [Best Practices](#best-practices)

---

## Event Categories

### 1. Token Operations (RebaseToken)
- Transfers, approvals
- Minting, burning
- Rebases, interest rate updates
- Share conversions

### 2. Vault Operations (RebaseTokenVault)
- Deposits, withdrawals
- Interest accrual
- Configuration changes
- Emergency actions (pause/unpause)

### 3. Governance (VotingEscrow, GovernorAlpha, Timelock)
- Lock creation, modifications
- Proposal lifecycle (created, voted, queued, executed)
- Delegation changes
- Timelock operations

### 4. Cross-Chain Bridge (EnhancedCCIPBridge)
- Token bridging (sent, received)
- Batch transfers
- Rate limiting
- Chain configuration

### 5. Advanced Strategies (AdvancedStrategyVault)
- Tier changes
- Lock operations
- Utilization updates
- Performance fees

### 6. Upgrades (UUPS Proxies)
- Implementation upgrades
- Admin changes
- Storage validation

### 7. Access Control
- Role grants/revocations
- Owner transfers
- Admin changes

### 8. Emergency Events
- Circuit breaker triggers
- Pauses/unpauses
- Recovery operations

---

## Core Protocol Events

### RebaseToken Events

```solidity
// ERC20 Standard
event Transfer(address indexed from, address indexed to, uint256 value);
event Approval(address indexed owner, address indexed spender, uint256 value);

// Rebase Operations
event Rebase(uint256 epoch, uint256 prevTotalSupply, uint256 newTotalSupply, int256 delta);
event InterestRateUpdated(address indexed account, uint256 oldRate, uint256 newRate);

// Mint/Burn
event Mint(address indexed to, uint256 amount, uint256 shares);
event Burn(address indexed from, uint256 amount, uint256 shares);

// Share Conversions
event SharesTransferred(address indexed from, address indexed to, uint256 shares);
```

**Indexing Priority:** ⭐⭐⭐⭐⭐ (Critical)

**Key Fields:**
- `from`, `to` - User addresses for balance tracking
- `value` - Token amounts for analytics
- `epoch` - Rebase cycle tracking
- `delta` - Positive/negative rebase amounts
- `shares` - Share conversion tracking

**Use Cases:**
- User balance history
- Rebase analytics (APY calculation)
- Token supply tracking
- Interest rate distribution

### RebaseTokenVault Events

```solidity
// Deposits & Withdrawals
event Deposited(address indexed user, uint256 amount, uint256 shares, uint256 interestRate);
event Withdrawn(address indexed user, uint256 amount, uint256 shares);

// Interest Accrual
event InterestAccrued(uint256 amount, uint256 newTotalSupply, uint256 timestamp);

// Configuration
event ConfigUpdated(
    uint256 minDeposit,
    uint256 maxDeposit,
    uint256 minInterestRate,
    uint256 maxInterestRate,
    uint256 baseInterestRate
);

// Emergency
event Paused(address account);
event Unpaused(address account);
```

**Indexing Priority:** ⭐⭐⭐⭐⭐ (Critical)

**Key Fields:**
- `user` - Depositor tracking
- `amount` - Deposit/withdrawal amounts
- `shares` - Vault share tracking
- `interestRate` - Rate at deposit time
- `timestamp` - Time-series analytics

**Use Cases:**
- TVL (Total Value Locked) tracking
- User deposit history
- Interest rate trends
- Vault health monitoring

---

## Governance Events

### VotingEscrow Events

```solidity
// Lock Operations
event LockCreated(address indexed user, uint256 amount, uint256 unlockTime, uint256 votingPower);
event LockIncreased(address indexed user, uint256 additionalAmount, uint256 newVotingPower);
event LockExtended(address indexed user, uint256 newUnlockTime, uint256 newVotingPower);
event Withdrawn(address indexed user, uint256 amount);

// Delegation
event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);
event DelegateVotesChanged(address indexed delegate, uint256 previousBalance, uint256 newBalance);

// Checkpoints
event CheckpointCreated(address indexed user, uint256 block, uint256 votes);
```

**Indexing Priority:** ⭐⭐⭐⭐ (High)

**Key Fields:**
- `user` - Lock holder
- `amount` - Locked tokens
- `unlockTime` - Lock expiry
- `votingPower` - Time-weighted power
- `delegate` - Delegation tracking

**Use Cases:**
- Voting power distribution
- Lock expiry tracking
- Delegation graph
- Governance participation metrics

### GovernorAlpha Events

```solidity
// Proposal Lifecycle
event ProposalCreated(
    uint256 indexed proposalId,
    address indexed proposer,
    address[] targets,
    uint256[] values,
    string[] signatures,
    bytes[] calldatas,
    uint256 startBlock,
    uint256 endBlock,
    string description
);

event VoteCast(
    address indexed voter,
    uint256 indexed proposalId,
    bool support,
    uint256 votes
);

event ProposalQueued(uint256 indexed proposalId, uint256 eta);
event ProposalExecuted(uint256 indexed proposalId);
event ProposalCanceled(uint256 indexed proposalId);

// State Changes
event QuorumUpdated(uint256 oldQuorum, uint256 newQuorum);
event ProposalThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);
```

**Indexing Priority:** ⭐⭐⭐⭐⭐ (Critical)

**Key Fields:**
- `proposalId` - Unique identifier
- `proposer` - Proposal creator
- `targets`, `signatures`, `calldatas` - Execution data
- `startBlock`, `endBlock` - Voting period
- `voter`, `support`, `votes` - Vote tracking
- `eta` - Execution time

**Use Cases:**
- Proposal timeline UI
- Vote tracking (for/against)
- Quorum monitoring
- Voter participation analytics

### Timelock Events

```solidity
// Transaction Queue
event TransactionQueued(
    bytes32 indexed txHash,
    address indexed target,
    uint256 value,
    string signature,
    bytes data,
    uint256 eta
);

event TransactionExecuted(
    bytes32 indexed txHash,
    address indexed target,
    uint256 value,
    string signature,
    bytes data,
    uint256 eta
);

event TransactionCanceled(bytes32 indexed txHash);

// Admin
event NewAdmin(address indexed newAdmin);
event NewPendingAdmin(address indexed newPendingAdmin);
event NewDelay(uint256 indexed newDelay);
```

**Indexing Priority:** ⭐⭐⭐⭐ (High)

**Key Fields:**
- `txHash` - Transaction identifier
- `target` - Contract to call
- `signature` - Function signature
- `eta` - Execution time
- `newAdmin` - Admin tracking

**Use Cases:**
- Timelock queue monitoring
- Execution timeline
- Admin action tracking
- Security monitoring

---

## Bridge Events

### EnhancedCCIPBridge Events

```solidity
// Bridging Operations
event TokensBridged(
    uint64 indexed destinationChain,
    address indexed sender,
    address indexed recipient,
    uint256 amount,
    bytes32 messageId
);

event TokensReceived(
    uint64 indexed sourceChain,
    address indexed sender,
    address indexed recipient,
    uint256 amount,
    bytes32 messageId
);

// Batch Transfers
event BatchTransferCreated(
    uint256 indexed batchId,
    uint64 indexed destinationChain,
    address indexed creator,
    uint256 totalAmount,
    uint256 recipientCount
);

event BatchExecuted(
    uint256 indexed batchId,
    bytes32 messageId,
    uint256 totalAmount
);

// Rate Limiting
event RateLimitUpdated(
    uint64 indexed chainSelector,
    uint256 tokensPerSecond,
    uint256 maxBurstSize
);

event RateLimitConsumed(
    uint64 indexed chainSelector,
    uint256 amount,
    uint256 tokensAvailable
);

// Configuration
event ChainConfigured(
    uint64 indexed chainSelector,
    address receiver,
    uint256 minAmount,
    uint256 maxAmount,
    bool enabled
);

// Emergency
event BridgePaused(address indexed admin);
event BridgeUnpaused(address indexed admin);
```

**Indexing Priority:** ⭐⭐⭐⭐⭐ (Critical)

**Key Fields:**
- `destinationChain`, `sourceChain` - Chain tracking
- `sender`, `recipient` - User tracking
- `amount` - Bridge volume
- `messageId` - CCIP message correlation
- `batchId` - Batch tracking

**Use Cases:**
- Cross-chain volume analytics
- Bridge health monitoring
- Rate limit tracking
- Failed bridge detection
- User bridge history

---

## Indexing Strategies

### Strategy 1: The Graph (Recommended)

**Best For:** Complex queries, historical data, production apps

**Pros:**
- ✅ Decentralized indexing
- ✅ GraphQL queries
- ✅ Automatic re-org handling
- ✅ Built-in caching

**Cons:**
- ❌ Deployment complexity
- ❌ Subgraph development required
- ❌ Query cost (hosted service)

**Setup Time:** 4-6 hours  
**Recommended Use:** Production dashboards, public APIs

See [The Graph Integration](#the-graph-integration) section.

### Strategy 2: Ethers.js Event Listeners

**Best For:** Real-time alerts, lightweight monitoring

**Pros:**
- ✅ Simple setup
- ✅ Real-time updates
- ✅ No external dependencies
- ✅ Full control

**Cons:**
- ❌ No historical data (without sync)
- ❌ Re-org handling manual
- ❌ Requires persistent connection

**Setup Time:** 30 minutes  
**Recommended Use:** Internal monitoring, alerts

```javascript
import { ethers } from 'ethers';

const provider = new ethers.providers.JsonRpcProvider(RPC_URL);
const vault = new ethers.Contract(VAULT_ADDRESS, VAULT_ABI, provider);

// Listen for deposits
vault.on('Deposited', (user, amount, shares, interestRate, event) => {
  console.log(`Deposit: ${user} deposited ${ethers.utils.formatEther(amount)} ETH`);
  
  // Store in database
  db.deposits.insert({
    user,
    amount: amount.toString(),
    shares: shares.toString(),
    interestRate: interestRate.toNumber(),
    blockNumber: event.blockNumber,
    transactionHash: event.transactionHash,
    timestamp: Date.now()
  });
  
  // Trigger alerts if large deposit
  if (amount.gt(ethers.utils.parseEther('1000'))) {
    sendAlert(`Large deposit: ${ethers.utils.formatEther(amount)} ETH from ${user}`);
  }
});

// Listen for rebases
vault.on('Rebase', (epoch, prevSupply, newSupply, delta, event) => {
  const percentChange = delta.mul(10000).div(prevSupply).toNumber() / 100;
  
  console.log(`Rebase ${epoch}: ${percentChange}% change`);
  
  // Calculate APY
  const apy = calculateAPY(percentChange, timeSinceLastRebase);
  
  db.rebases.insert({
    epoch: epoch.toNumber(),
    percentChange,
    apy,
    blockNumber: event.blockNumber,
    timestamp: Date.now()
  });
});
```

### Strategy 3: Alchemy/QuickNode Webhooks

**Best For:** Specific event notifications, integrations

**Pros:**
- ✅ Managed infrastructure
- ✅ HTTP webhooks (serverless friendly)
- ✅ Automatic retries
- ✅ Filter by address/topic

**Cons:**
- ❌ Vendor lock-in
- ❌ Limited historical queries
- ❌ Webhook endpoint required

**Setup Time:** 1 hour  
**Recommended Use:** Notifications, webhooks, serverless

**Alchemy Notify Setup:**
```javascript
// Configure webhook in Alchemy dashboard
{
  "webhook_url": "https://your-api.com/hooks/basero",
  "network": "BASE_MAINNET",
  "addresses": [
    "0x..." // Vault address
  ],
  "event_filters": [
    {
      "event": "Deposited(address,uint256,uint256,uint256)"
    }
  ]
}
```

**Webhook Handler:**
```javascript
// Express.js endpoint
app.post('/hooks/basero', async (req, res) => {
  const { event } = req.body;
  
  // Parse event
  const { name, args, blockNumber, transactionHash } = event;
  
  if (name === 'Deposited') {
    const [user, amount, shares, rate] = args;
    
    // Process deposit
    await processDeposit({
      user,
      amount,
      shares,
      rate,
      blockNumber,
      transactionHash
    });
  }
  
  res.status(200).send('OK');
});
```

### Strategy 4: Custom Indexer (Advanced)

**Best For:** High-performance, custom logic

**Pros:**
- ✅ Full control
- ✅ Custom data structures
- ✅ Optimized for your use case

**Cons:**
- ❌ High development cost
- ❌ Infrastructure management
- ❌ Re-org handling complexity

**Setup Time:** 40+ hours  
**Recommended Use:** Large-scale production systems

**Stack Example:**
- **Node.js** - Event processing
- **PostgreSQL** - Storage
- **Redis** - Caching
- **TimescaleDB** - Time-series data

---

## The Graph Integration

### Subgraph Schema

See `subgraph/schema.graphql` for full schema.

**Key Entities:**

```graphql
type User @entity {
  id: ID!                          # Address
  deposits: [Deposit!]! @derivedFrom(field: "user")
  withdrawals: [Withdrawal!]! @derivedFrom(field: "user")
  votes: [Vote!]! @derivedFrom(field: "voter")
  locks: [Lock!]! @derivedFrom(field: "user")
  bridgeTransfers: [BridgeTransfer!]! @derivedFrom(field: "sender")
  
  totalDeposited: BigInt!
  totalWithdrawn: BigInt!
  currentBalance: BigInt!
  votingPower: BigInt!
}

type Deposit @entity {
  id: ID!                          # tx hash + log index
  user: User!
  amount: BigInt!
  shares: BigInt!
  interestRate: Int!
  timestamp: BigInt!
  blockNumber: BigInt!
  transactionHash: Bytes!
}

type Rebase @entity {
  id: ID!                          # epoch
  epoch: BigInt!
  previousSupply: BigInt!
  newSupply: BigInt!
  delta: BigInt!
  percentChange: BigDecimal!
  timestamp: BigInt!
  blockNumber: BigInt!
}

type Proposal @entity {
  id: ID!                          # proposal ID
  proposer: User!
  targets: [Bytes!]!
  values: [BigInt!]!
  signatures: [String!]!
  calldatas: [Bytes!]!
  startBlock: BigInt!
  endBlock: BigInt!
  description: String!
  
  state: ProposalState!
  forVotes: BigInt!
  againstVotes: BigInt!
  votes: [Vote!]! @derivedFrom(field: "proposal")
  
  queuedAt: BigInt
  executedAt: BigInt
  canceledAt: BigInt
}

type BridgeTransfer @entity {
  id: ID!                          # message ID
  sender: User!
  recipient: Bytes!
  amount: BigInt!
  sourceChain: BigInt!
  destinationChain: BigInt!
  status: BridgeStatus!
  timestamp: BigInt!
  completedAt: BigInt
}
```

### Example Queries

**User Dashboard:**
```graphql
query UserDashboard($user: ID!) {
  user(id: $user) {
    totalDeposited
    totalWithdrawn
    currentBalance
    votingPower
    
    deposits(first: 10, orderBy: timestamp, orderDirection: desc) {
      amount
      interestRate
      timestamp
    }
    
    locks(first: 1, orderBy: createdAt, orderDirection: desc) {
      amount
      unlockTime
      votingPower
    }
    
    votes(first: 10, orderBy: timestamp, orderDirection: desc) {
      proposal {
        id
        description
      }
      support
      votes
    }
  }
}
```

**Protocol Analytics:**
```graphql
query ProtocolStats {
  vaultStats(id: "global") {
    totalDeposited
    totalWithdrawn
    activeUsers
    totalShares
  }
  
  rebases(first: 30, orderBy: epoch, orderDirection: desc) {
    epoch
    percentChange
    timestamp
  }
  
  proposals(where: { state: ACTIVE }) {
    id
    description
    forVotes
    againstVotes
    endBlock
  }
}
```

**Bridge Analytics:**
```graphql
query BridgeVolume($chain: BigInt!) {
  bridgeTransfers(
    where: { destinationChain: $chain }
    first: 100
    orderBy: timestamp
    orderDirection: desc
  ) {
    amount
    sender { id }
    recipient
    status
    timestamp
  }
  
  chainStats(id: $chain) {
    totalBridged
    totalReceived
    activeUsers
  }
}
```

---

## Real-Time Monitoring

### WebSocket Connection

```javascript
import { ethers } from 'ethers';

const provider = new ethers.providers.WebSocketProvider(WSS_URL);

// Monitor vault health
const vault = new ethers.Contract(VAULT_ADDRESS, VAULT_ABI, provider);

vault.on('Deposited', async (user, amount, shares, rate) => {
  // Update TVL
  const tvl = await vault.totalDeposited();
  metrics.tvl.set(parseFloat(ethers.utils.formatEther(tvl)));
  
  // Track deposit count
  metrics.deposits.inc();
  
  // Large deposit alert
  if (amount.gt(ethers.utils.parseEther('1000'))) {
    await sendSlackAlert(`🐋 Whale deposit: ${ethers.utils.formatEther(amount)} ETH`);
  }
});

vault.on('Withdrawn', async (user, amount, shares) => {
  metrics.withdrawals.inc();
  
  // Mass withdrawal alert
  const recentWithdrawals = await getRecentWithdrawals(1 * 60 * 60); // 1 hour
  if (recentWithdrawals > parseEther('5000')) {
    await sendPagerDutyAlert('High withdrawal volume detected');
  }
});

// Monitor governance
const governor = new ethers.Contract(GOVERNOR_ADDRESS, GOV_ABI, provider);

governor.on('ProposalCreated', async (proposalId, proposer, ...args) => {
  await sendDiscordNotification({
    title: 'New Governance Proposal',
    description: args[8], // description
    proposer,
    proposalId: proposalId.toString(),
    url: `https://basero.app/governance/${proposalId}`
  });
});
```

### Prometheus Metrics

```javascript
import { register, Counter, Gauge, Histogram } from 'prom-client';

// Counters
const depositsCounter = new Counter({
  name: 'basero_deposits_total',
  help: 'Total number of deposits',
  labelNames: ['tier']
});

const withdrawalsCounter = new Counter({
  name: 'basero_withdrawals_total',
  help: 'Total number of withdrawals'
});

// Gauges
const tvlGauge = new Gauge({
  name: 'basero_tvl_eth',
  help: 'Total Value Locked in ETH'
});

const activeUsersGauge = new Gauge({
  name: 'basero_active_users',
  help: 'Number of users with deposits'
});

const votingPowerGauge = new Gauge({
  name: 'basero_voting_power_total',
  help: 'Total voting power locked'
});

// Histograms
const depositSizeHistogram = new Histogram({
  name: 'basero_deposit_size_eth',
  help: 'Distribution of deposit sizes',
  buckets: [0.1, 1, 10, 50, 100, 500, 1000, 5000]
});

// Update metrics
vault.on('Deposited', (user, amount) => {
  depositsCounter.inc();
  depositSizeHistogram.observe(parseFloat(ethers.utils.formatEther(amount)));
});

// Expose metrics endpoint
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});
```

---

## Query Patterns

### Historical Analysis

**Deposit Trends:**
```javascript
async function getDepositTrends(days = 30) {
  const fromBlock = await getBlockFromDaysAgo(days);
  
  const deposits = await vault.queryFilter(
    vault.filters.Deposited(),
    fromBlock,
    'latest'
  );
  
  // Group by day
  const dailyDeposits = deposits.reduce((acc, event) => {
    const date = new Date(event.args.timestamp.toNumber() * 1000);
    const day = date.toISOString().split('T')[0];
    
    acc[day] = (acc[day] || 0) + parseFloat(
      ethers.utils.formatEther(event.args.amount)
    );
    
    return acc;
  }, {});
  
  return dailyDeposits;
}
```

**Rebase History:**
```javascript
async function getRebaseHistory(count = 100) {
  const rebases = await token.queryFilter(
    token.filters.Rebase(),
    -1000000,
    'latest'
  );
  
  return rebases.slice(-count).map(event => ({
    epoch: event.args.epoch.toNumber(),
    percentChange: event.args.delta
      .mul(10000)
      .div(event.args.prevTotalSupply)
      .toNumber() / 100,
    timestamp: event.args.timestamp?.toNumber(),
    blockNumber: event.blockNumber
  }));
}
```

**Voting Participation:**
```javascript
async function getVotingParticipation(proposalId) {
  const votes = await governor.queryFilter(
    governor.filters.VoteCast(null, proposalId),
    0,
    'latest'
  );
  
  const totalVotingPower = await votingEscrow.totalSupply();
  
  const participation = votes.reduce((acc, vote) => {
    acc.totalVotes = acc.totalVotes.add(vote.args.votes);
    acc.uniqueVoters.add(vote.args.voter);
    
    if (vote.args.support) {
      acc.forVotes = acc.forVotes.add(vote.args.votes);
    } else {
      acc.againstVotes = acc.againstVotes.add(vote.args.votes);
    }
    
    return acc;
  }, {
    totalVotes: ethers.BigNumber.from(0),
    forVotes: ethers.BigNumber.from(0),
    againstVotes: ethers.BigNumber.from(0),
    uniqueVoters: new Set()
  });
  
  return {
    ...participation,
    participationRate: participation.totalVotes
      .mul(10000)
      .div(totalVotingPower)
      .toNumber() / 100,
    voterCount: participation.uniqueVoters.size
  };
}
```

---

## Best Practices

### 1. Event Filtering

**Use indexed parameters:**
```javascript
// Efficient - uses indexed parameter
const userDeposits = await vault.queryFilter(
  vault.filters.Deposited(userAddress)
);

// Inefficient - filters all deposits
const allDeposits = await vault.queryFilter(
  vault.filters.Deposited()
);
const userDeposits = allDeposits.filter(e => e.args.user === userAddress);
```

### 2. Block Range Limits

**Chunk large queries:**
```javascript
async function queryEventsInChunks(contract, filter, fromBlock, toBlock, chunkSize = 10000) {
  const events = [];
  
  for (let start = fromBlock; start <= toBlock; start += chunkSize) {
    const end = Math.min(start + chunkSize - 1, toBlock);
    const chunk = await contract.queryFilter(filter, start, end);
    events.push(...chunk);
  }
  
  return events;
}
```

### 3. Re-org Handling

**Wait for confirmations:**
```javascript
vault.on('Deposited', async (user, amount, shares, rate, event) => {
  // Wait for 12 confirmations on mainnet
  const receipt = await event.getTransactionReceipt();
  
  provider.once(receipt.blockNumber + 12, async () => {
    // Now safe to process
    await finalizeDeposit(user, amount, event.transactionHash);
  });
});
```

### 4. Error Handling

**Robust listeners:**
```javascript
function setupVaultListener() {
  vault.on('Deposited', async (user, amount, shares, rate, event) => {
    try {
      await processDeposit({ user, amount, shares, rate, event });
    } catch (error) {
      console.error('Failed to process deposit:', error);
      
      // Queue for retry
      await retryQueue.add({
        type: 'deposit',
        data: { user, amount, shares, rate },
        transactionHash: event.transactionHash
      });
    }
  });
  
  vault.on('error', (error) => {
    console.error('Vault listener error:', error);
    
    // Reconnect after delay
    setTimeout(() => {
      console.log('Reconnecting vault listener...');
      setupVaultListener();
    }, 5000);
  });
}
```

### 5. Performance Optimization

**Cache frequently accessed data:**
```javascript
const cache = new Map();

async function getTVL() {
  const cacheKey = 'tvl';
  const cached = cache.get(cacheKey);
  
  if (cached && Date.now() - cached.timestamp < 60000) {
    return cached.value;
  }
  
  const tvl = await vault.totalDeposited();
  
  cache.set(cacheKey, {
    value: tvl,
    timestamp: Date.now()
  });
  
  return tvl;
}
```

### 6. Data Normalization

**Consistent formats:**
```javascript
function normalizeEvent(event) {
  return {
    name: event.event,
    args: Object.entries(event.args)
      .filter(([key]) => isNaN(key))
      .reduce((acc, [key, value]) => {
        acc[key] = ethers.BigNumber.isBigNumber(value)
          ? value.toString()
          : value;
        return acc;
      }, {}),
    blockNumber: event.blockNumber,
    transactionHash: event.transactionHash,
    logIndex: event.logIndex,
    timestamp: null // Fetch separately
  };
}
```

---

## Common Issues

### Issue 1: Missing Events

**Symptom:** Events not appearing in queries

**Solutions:**
- Check contract address is correct
- Verify event signature matches ABI
- Ensure block range includes event
- Check provider connection

### Issue 2: Rate Limiting

**Symptom:** `429 Too Many Requests`

**Solutions:**
- Use paid RPC provider (Alchemy, QuickNode, Infura)
- Implement request queuing
- Cache responses
- Use The Graph for complex queries

### Issue 3: Stale Data

**Symptom:** UI shows old data

**Solutions:**
- Implement cache invalidation
- Use WebSocket for real-time updates
- Add timestamp to cached data
- Show "last updated" timestamp to users

---

## Tools & Libraries

### Recommended Stack

**Indexing:**
- [The Graph](https://thegraph.com/) - Decentralized indexing
- [Ethers.js](https://docs.ethers.org/) - Event listeners
- [Alchemy Notify](https://www.alchemy.com/notify) - Webhooks

**Storage:**
- [PostgreSQL](https://www.postgresql.org/) - Relational data
- [TimescaleDB](https://www.timescale.com/) - Time-series
- [Redis](https://redis.io/) - Caching

**Monitoring:**
- [Prometheus](https://prometheus.io/) - Metrics
- [Grafana](https://grafana.com/) - Dashboards
- [PagerDuty](https://www.pagerduty.com/) - Alerts

**Analytics:**
- [Dune Analytics](https://dune.com/) - SQL queries
- [Flipside Crypto](https://flipsidecrypto.xyz/) - Data science
- [Nansen](https://www.nansen.ai/) - Wallet analytics

---

## Next Steps

1. **Deploy Subgraph:** See `subgraph/` directory
2. **Set Up Monitoring:** See [DASHBOARD_TEMPLATES.md](DASHBOARD_TEMPLATES.md)
3. **Configure Alerts:** See [ALERT_THRESHOLDS.md](ALERT_THRESHOLDS.md)
4. **Build Analytics:** Query historical data
5. **Create UI:** Display real-time data to users

---

## References

- [Ethers.js Events](https://docs.ethers.org/v5/api/contract/contract/#Contract--events)
- [The Graph Docs](https://thegraph.com/docs/en/)
- [Alchemy Notify](https://docs.alchemy.com/reference/notify-api-quickstart)
- [Event Indexing Best Practices](https://ethereum.org/en/developers/tutorials/logging-events-smart-contracts/)

**Version:** 1.0  
**Last Updated:** January 2026  
**Maintainer:** Basero Development Team
