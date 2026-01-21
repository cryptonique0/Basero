# Basero Subgraph

Official subgraph for indexing Basero protocol events on Base.

## Overview

This subgraph indexes all Basero protocol contracts:
- **RebaseToken** - Token transfers, rebases, minting
- **RebaseTokenVault** - Deposits, withdrawals, interest
- **VotingEscrow** - Locks, delegation, voting power
- **GovernorAlpha** - Proposals, votes, execution
- **EnhancedCCIPBridge** - Cross-chain transfers, batches
- **AdvancedStrategyVault** - Tiers, locks, utilization

## Quick Start

### Prerequisites

```bash
npm install -g @graphprotocol/graph-cli
```

### Setup

1. **Install dependencies:**
```bash
npm install
```

2. **Update contract addresses:**

Edit `subgraph.yaml` and replace placeholder addresses:
```yaml
source:
  address: "0x..." # Your deployed contract address
  startBlock: 12345 # Deployment block number
```

3. **Generate types:**
```bash
npm run codegen
```

4. **Build subgraph:**
```bash
npm run build
```

### Deploy

#### Hosted Service (The Graph)

```bash
# Authenticate
graph auth --product hosted-service <ACCESS_TOKEN>

# Deploy
graph deploy --product hosted-service <GITHUB_USERNAME>/basero-subgraph
```

#### Decentralized Network

```bash
# Create subgraph
graph create basero-subgraph --node https://api.thegraph.com/deploy/

# Deploy
graph deploy basero-subgraph \
  --ipfs https://api.thegraph.com/ipfs/ \
  --node https://api.thegraph.com/deploy/
```

#### Local Development

```bash
# Start Graph Node
docker-compose up -d

# Create local subgraph
npm run create-local

# Deploy locally
npm run deploy-local
```

## Schema

See [schema.graphql](./schema.graphql) for full entity definitions.

### Key Entities

**User** - User account with all activity
**Deposit/Withdrawal** - Vault interactions
**Rebase** - Token rebase events
**Proposal** - Governance proposals
**Vote** - Governance votes
**BridgeTransfer** - Cross-chain transfers
**Lock** - Voting escrow locks

## Example Queries

### User Dashboard

```graphql
{
  user(id: "0x...") {
    totalDeposited
    totalWithdrawn
    currentVaultBalance
    votingPower
    tier
    
    deposits(first: 10, orderBy: timestamp, orderDirection: desc) {
      amount
      interestRate
      timestamp
    }
    
    votes(first: 5, orderBy: timestamp, orderDirection: desc) {
      proposal {
        description
      }
      support
      votes
    }
  }
}
```

### Protocol Stats

```graphql
{
  vaultStats(id: "global") {
    totalDeposited
    totalWithdrawn
    totalUsers
    activeUsers
    isPaused
  }
  
  globalStats(id: "global") {
    totalValueLocked
    totalUsers
    totalProposals
    totalBridgeVolume
  }
}
```

### Recent Activity

```graphql
{
  deposits(first: 20, orderBy: timestamp, orderDirection: desc) {
    user { id }
    amount
    interestRate
    timestamp
  }
  
  rebases(first: 10, orderBy: epoch, orderDirection: desc) {
    epoch
    percentChange
    timestamp
  }
  
  proposals(where: { state: Active }) {
    id
    description
    forVotes
    againstVotes
    endBlock
  }
}
```

### Bridge Analytics

```graphql
{
  chainStats(id: "1") { # Ethereum
    totalBridgedOut
    totalBridgedIn
    transferCount
    uniqueUsers
  }
  
  bridgeTransfers(
    first: 50
    orderBy: sentAt
    orderDirection: desc
    where: { status: Sent }
  ) {
    sender { id }
    amount
    destinationChain
    sentAt
  }
}
```

### Daily Snapshots

```graphql
{
  dailySnapshots(
    first: 30
    orderBy: date
    orderDirection: desc
  ) {
    date
    tvl
    uniqueDepositors
    bridgeVolume
    rebaseCount
  }
}
```

## Development

### File Structure

```
subgraph/
├── schema.graphql           # Entity definitions
├── subgraph.yaml           # Subgraph manifest
├── src/
│   ├── rebase-token.ts     # RebaseToken event handlers
│   ├── vault.ts            # Vault event handlers
│   ├── voting-escrow.ts    # VotingEscrow handlers
│   ├── governor.ts         # Governor handlers
│   ├── bridge.ts           # Bridge handlers
│   ├── advanced-vault.ts   # Advanced vault handlers
│   └── utils.ts            # Helper functions
├── abis/                   # Contract ABIs
└── package.json
```

### Adding New Handlers

1. **Add event to schema.graphql**
2. **Update subgraph.yaml eventHandlers**
3. **Create handler in src/**
4. **Rebuild**: `npm run codegen && npm run build`

### Testing

```bash
# Run tests
npm test

# Test specific file
npm test -- vault.test.ts
```

### Debugging

```bash
# Check logs
graph logs <SUBGRAPH_ID>

# Rebuild with debug info
npm run build -- --debug
```

## Monitoring

### Health Check

```graphql
{
  _meta {
    block {
      number
      hash
      timestamp
    }
    deployment
    hasIndexingErrors
  }
}
```

### Indexing Status

```bash
# Get indexing status
curl -X POST \
  -H "Content-Type: application/json" \
  -d '{"query": "{ indexingStatusForCurrentVersion(subgraphName: \"basero-subgraph\") { synced health fatalError { message } chains { latestBlock { number } chainHeadBlock { number } } } }"}' \
  https://api.thegraph.com/index-node/graphql
```

## Performance Tips

1. **Use indexed fields** for filtering:
```graphql
deposits(where: { user: "0x..." }) # Fast (indexed)
deposits(where: { amount_gt: "1000" }) # Slower (not indexed)
```

2. **Limit results:**
```graphql
deposits(first: 100) # Good
deposits(first: 10000) # Too many
```

3. **Order for pagination:**
```graphql
deposits(
  first: 100
  orderBy: timestamp
  orderDirection: desc
  where: { timestamp_lt: $lastTimestamp }
)
```

4. **Use @derivedFrom** instead of manual arrays

5. **Batch related queries** in single request

## Common Issues

### Subgraph Failed to Sync

**Check:**
- Contract addresses correct in subgraph.yaml
- Start block before first transaction
- ABI matches deployed contract
- Network name correct

### Missing Events

**Check:**
- Event signature matches ABI
- Handler function name correct
- Entity saved in handler
- No errors in mapping code

### Slow Queries

**Optimize:**
- Add indexes to frequently queried fields
- Reduce result size (first: 100)
- Use pagination
- Cache results client-side

## Resources

- [The Graph Docs](https://thegraph.com/docs/en/)
- [AssemblyScript API](https://thegraph.com/docs/en/developing/assemblyscript-api/)
- [Subgraph Studio](https://thegraph.com/studio/)

## Support

- **Documentation**: [Basero Docs](https://docs.basero.app)
- **Discord**: [Join our server](https://discord.gg/basero)
- **GitHub**: [Open an issue](https://github.com/basero/subgraph/issues)

## License

MIT
