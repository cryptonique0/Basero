# Dashboard Templates & Monitoring

## Overview

This guide provides pre-built dashboard templates for monitoring Basero protocol metrics using popular analytics platforms.

**Platforms Covered:**
- Grafana (on-chain + infrastructure metrics)
- Dune Analytics (on-chain analytics)
- Custom web dashboards (React/Next.js)

**Metrics Categories:** 8  
**Total Visualizations:** 50+  

## Table of Contents

1. [Grafana Dashboards](#grafana-dashboards)
2. [Dune Analytics](#dune-analytics)
3. [Custom Web Dashboards](#custom-web-dashboards)
4. [Key Metrics](#key-metrics)
5. [Alert Integration](#alert-integration)
6. [Best Practices](#best-practices)

---

## Grafana Dashboards

### Setup

**Prerequisites:**
- Grafana instance (Cloud or self-hosted)
- Prometheus metrics endpoint (see EVENT_INDEXING.md)
- PostgreSQL database (for subgraph data)

**Installation:**
```bash
# Install Grafana
docker run -d -p 3000:3000 grafana/grafana

# Add Prometheus data source
# Settings > Data Sources > Add Prometheus
# URL: http://prometheus:9090

# Add PostgreSQL data source (for subgraph)
# Settings > Data Sources > Add PostgreSQL
# Host: postgres:5432
# Database: basero_subgraph
```

### Dashboard 1: Protocol Overview

**File:** `grafana-dashboards/protocol-overview.json`

**Panels:**

#### TVL (Total Value Locked)
```promql
# Current TVL in ETH
basero_tvl_eth

# TVL over time (24h)
basero_tvl_eth[24h]

# TVL growth rate
rate(basero_tvl_eth[1h])
```

**Visualization:** Time series graph  
**Refresh:** 30s  
**Alerts:** TVL drops >20% in 1 hour

#### Active Users
```promql
# Current active users (with deposits)
basero_active_users

# New users (24h)
increase(basero_users_total[24h])

# User retention (7d active / 30d active)
basero_active_users{period="7d"} / basero_active_users{period="30d"}
```

**Visualization:** Stat panel + trend  
**Refresh:** 1m

#### Deposit/Withdrawal Volume
```promql
# Deposits (24h)
increase(basero_deposits_total[24h])

# Withdrawals (24h)
increase(basero_withdrawals_total[24h])

# Net flow
increase(basero_deposits_total[24h]) - increase(basero_withdrawals_total[24h])
```

**Visualization:** Bar graph  
**Refresh:** 5m

#### Token Supply
```promql
# Total supply
basero_token_total_supply

# Supply change rate
rate(basero_token_total_supply[1h])

# Rebase count (24h)
increase(basero_rebases_total[24h])
```

**Visualization:** Time series  
**Refresh:** 1m

### Dashboard 2: Vault Health

#### Interest Rate Distribution
```promql
# Average interest rate
avg(basero_interest_rate)

# Interest rate by tier
basero_interest_rate{tier="bronze"}
basero_interest_rate{tier="silver"}
basero_interest_rate{tier="gold"}
basero_interest_rate{tier="platinum"}
basero_interest_rate{tier="diamond"}
```

**Visualization:** Histogram  
**Refresh:** 5m

#### Utilization Rate
```promql
# Current utilization
basero_utilization_rate

# Utilization vs optimal (80%)
basero_utilization_rate / 8000
```

**Visualization:** Gauge (0-100%)  
**Thresholds:**
- Green: <60%
- Yellow: 60-90%
- Red: >90%

#### Vault Solvency
```promql
# Vault balance
basero_vault_balance_eth

# Total deposits
basero_vault_deposits_total_eth

# Solvency ratio (should be >= 1)
basero_vault_balance_eth / basero_vault_deposits_total_eth
```

**Visualization:** Stat panel  
**Alert:** Ratio < 1.0 (CRITICAL)

### Dashboard 3: Governance

#### Proposal Activity
```sql
-- SQL query for PostgreSQL data source
SELECT
  DATE(created_at) as date,
  COUNT(*) as proposals,
  SUM(CASE WHEN state = 'Active' THEN 1 ELSE 0 END) as active,
  SUM(CASE WHEN state = 'Executed' THEN 1 ELSE 0 END) as executed
FROM proposals
WHERE created_at > NOW() - INTERVAL '30 days'
GROUP BY DATE(created_at)
ORDER BY date DESC
```

**Visualization:** Table + time series  
**Refresh:** 10m

#### Voting Power Distribution
```sql
SELECT
  tier,
  SUM(voting_power) as total_power,
  COUNT(DISTINCT user_id) as users
FROM users
WHERE voting_power > 0
GROUP BY tier
ORDER BY total_power DESC
```

**Visualization:** Pie chart  
**Refresh:** 1h

#### Voter Participation
```sql
SELECT
  p.id,
  p.description,
  COUNT(DISTINCT v.voter) as voters,
  (SELECT COUNT(*) FROM users WHERE voting_power > 0) as total_eligible,
  ROUND(COUNT(DISTINCT v.voter)::numeric / (SELECT COUNT(*) FROM users WHERE voting_power > 0) * 100, 2) as participation_rate
FROM proposals p
LEFT JOIN votes v ON v.proposal_id = p.id
WHERE p.state IN ('Active', 'Succeeded', 'Executed')
GROUP BY p.id, p.description
ORDER BY p.id DESC
LIMIT 10
```

**Visualization:** Table  
**Refresh:** 5m

### Dashboard 4: Bridge Metrics

#### Cross-Chain Volume
```sql
SELECT
  destination_chain,
  SUM(amount) as total_volume,
  COUNT(*) as transfer_count,
  AVG(amount) as avg_transfer_size
FROM bridge_transfers
WHERE sent_at > NOW() - INTERVAL '24 hours'
GROUP BY destination_chain
ORDER BY total_volume DESC
```

**Visualization:** Bar chart  
**Refresh:** 5m

#### Bridge Status
```promql
# Pending transfers
basero_bridge_pending_total

# Failed transfers (24h)
increase(basero_bridge_failed_total[24h])

# Success rate
rate(basero_bridge_success_total[1h]) / rate(basero_bridge_total[1h])
```

**Visualization:** Stat panels  
**Alert:** Success rate < 95%

#### Rate Limit Status
```promql
# Tokens available by chain
basero_rate_limit_available{chain="ethereum"}
basero_rate_limit_available{chain="polygon"}
basero_rate_limit_available{chain="arbitrum"}

# Utilization (used / max)
(basero_rate_limit_max - basero_rate_limit_available) / basero_rate_limit_max
```

**Visualization:** Gauge per chain  
**Alert:** Utilization > 90%

### Dashboard 5: System Health

#### Contract Gas Usage
```promql
# Average gas per deposit
rate(basero_gas_used_total{operation="deposit"}[5m]) / rate(basero_deposits_total[5m])

# Average gas per bridge transfer
rate(basero_gas_used_total{operation="bridge"}[5m]) / rate(basero_bridge_total[5m])
```

**Visualization:** Time series  
**Refresh:** 1m

#### Error Rates
```promql
# Failed transactions (1h)
increase(basero_errors_total[1h])

# Error rate by type
rate(basero_errors_total{type="insufficient_balance"}[5m])
rate(basero_errors_total{type="rate_limit"}[5m])
rate(basero_errors_total{type="paused"}[5m])
```

**Visualization:** Table  
**Alert:** Total errors > 100/hour

#### Paused Status
```promql
# Is vault paused (1 = yes, 0 = no)
basero_vault_paused

# Time since last unpause
time() - basero_vault_last_unpause_timestamp
```

**Visualization:** Stat panel + alert  
**Alert:** Paused for > 1 hour

---

## Dune Analytics

### Setup

1. Create Dune account: https://dune.com
2. Add Base network
3. Import Basero contract addresses
4. Create queries and dashboards

### Query 1: TVL Over Time

```sql
WITH daily_tvl AS (
  SELECT
    DATE_TRUNC('day', evt_block_time) as day,
    SUM(CASE 
      WHEN evt_tx_hash IN (SELECT evt_tx_hash FROM basero."RebaseTokenVault_evt_Deposited")
      THEN amount
      ELSE 0
    END) as deposits,
    SUM(CASE 
      WHEN evt_tx_hash IN (SELECT evt_tx_hash FROM basero."RebaseTokenVault_evt_Withdrawn")
      THEN amount
      ELSE 0
    END) as withdrawals
  FROM basero."RebaseTokenVault_evt_Deposited"
  UNION ALL
  SELECT
    DATE_TRUNC('day', evt_block_time) as day,
    0 as deposits,
    amount as withdrawals
  FROM basero."RebaseTokenVault_evt_Withdrawn"
)
SELECT
  day,
  SUM(SUM(deposits - withdrawals)) OVER (ORDER BY day) / 1e18 as tvl_eth
FROM daily_tvl
GROUP BY day
ORDER BY day DESC
```

**Visualization:** Area chart  
**Refresh:** Daily

### Query 2: Top Depositors

```sql
SELECT
  "user" as address,
  COUNT(*) as deposit_count,
  SUM(amount) / 1e18 as total_deposited_eth,
  MAX(evt_block_time) as last_deposit
FROM basero."RebaseTokenVault_evt_Deposited"
GROUP BY "user"
ORDER BY total_deposited_eth DESC
LIMIT 100
```

**Visualization:** Table  
**Refresh:** Hourly

### Query 3: Rebase Impact

```sql
WITH rebases AS (
  SELECT
    epoch,
    evt_block_time,
    delta / 1e18 as delta_eth,
    (delta::numeric / prevTotalSupply::numeric) * 100 as percent_change
  FROM basero."RebaseToken_evt_Rebase"
)
SELECT
  DATE_TRUNC('day', evt_block_time) as day,
  COUNT(*) as rebase_count,
  AVG(percent_change) as avg_percent_change,
  SUM(delta_eth) as total_delta_eth
FROM rebases
WHERE evt_block_time > NOW() - INTERVAL '30 days'
GROUP BY day
ORDER BY day DESC
```

**Visualization:** Bar + line chart  
**Refresh:** Daily

### Query 4: Governance Participation

```sql
SELECT
  p.id as proposal_id,
  p.description,
  COUNT(DISTINCT v.voter) as unique_voters,
  SUM(CASE WHEN v.support THEN v.votes ELSE 0 END) / 1e18 as votes_for,
  SUM(CASE WHEN NOT v.support THEN v.votes ELSE 0 END) / 1e18 as votes_against,
  (COUNT(DISTINCT v.voter)::numeric / (
    SELECT COUNT(*) FROM basero."VotingEscrow_evt_LockCreated"
  )) * 100 as participation_rate
FROM basero."GovernorAlpha_evt_ProposalCreated" p
LEFT JOIN basero."GovernorAlpha_evt_VoteCast" v ON v.proposalId = p.id
GROUP BY p.id, p.description
ORDER BY p.id DESC
```

**Visualization:** Table  
**Refresh:** Hourly

### Query 5: Bridge Volume by Chain

```sql
SELECT
  CASE destinationChain
    WHEN 1 THEN 'Ethereum'
    WHEN 2 THEN 'Polygon'
    WHEN 3 THEN 'Arbitrum'
    ELSE 'Unknown'
  END as chain,
  COUNT(*) as transfer_count,
  SUM(amount) / 1e18 as total_volume_eth,
  COUNT(DISTINCT sender) as unique_users
FROM basero."EnhancedCCIPBridge_evt_TokensBridged"
WHERE evt_block_time > NOW() - INTERVAL '7 days'
GROUP BY destinationChain
ORDER BY total_volume_eth DESC
```

**Visualization:** Pie chart + table  
**Refresh:** Daily

### Complete Dune Dashboard

**Dashboard Name:** Basero Protocol Analytics

**Sections:**
1. **Overview** - TVL, users, transactions
2. **Vault** - Deposits, withdrawals, interest rates
3. **Token** - Supply, rebases, transfers
4. **Governance** - Proposals, votes, participation
5. **Bridge** - Volume, chains, batches
6. **Users** - Top depositors, tier distribution

**URL:** `https://dune.com/basero/protocol-analytics`

---

## Custom Web Dashboards

### React Dashboard Component

```typescript
import { useQuery } from '@apollo/client';
import { LineChart, Line, XAxis, YAxis, Tooltip, Legend } from 'recharts';

const ProtocolDashboard = () => {
  const { data, loading } = useQuery(PROTOCOL_STATS_QUERY);

  if (loading) return <LoadingSpinner />;

  return (
    <div className="dashboard">
      <div className="metrics-grid">
        <MetricCard
          title="Total Value Locked"
          value={`${formatEther(data.vaultStats.totalDeposited)} ETH`}
          change="+12.5%"
          trend="up"
        />
        
        <MetricCard
          title="Active Users"
          value={data.vaultStats.activeUsers}
          change="+8.3%"
          trend="up"
        />
        
        <MetricCard
          title="Avg Interest Rate"
          value={`${data.vaultStats.baseInterestRate / 100}%`}
          change="-0.2%"
          trend="down"
        />
        
        <MetricCard
          title="Total Proposals"
          value={data.globalStats.totalProposals}
          change="+2"
          trend="neutral"
        />
      </div>

      <div className="charts">
        <Card title="TVL History">
          <TVLChart data={data.dailySnapshots} />
        </Card>
        
        <Card title="Deposit Activity">
          <DepositChart data={data.deposits} />
        </Card>
        
        <Card title="Governance Activity">
          <ProposalChart data={data.proposals} />
        </Card>
      </div>

      <div className="tables">
        <Card title="Recent Deposits">
          <DepositsTable data={data.deposits.slice(0, 10)} />
        </Card>
        
        <Card title="Active Proposals">
          <ProposalsTable data={data.activeProposals} />
        </Card>
      </div>
    </div>
  );
};
```

### GraphQL Queries

```graphql
query ProtocolStats {
  vaultStats(id: "global") {
    totalDeposited
    totalWithdrawn
    activeUsers
    totalUsers
    baseInterestRate
  }
  
  globalStats(id: "global") {
    totalValueLocked
    totalProposals
    totalVotingPower
  }
  
  dailySnapshots(first: 30, orderBy: date, orderDirection: desc) {
    date
    tvl
    uniqueDepositors
    netDeposits
  }
  
  deposits(first: 10, orderBy: timestamp, orderDirection: desc) {
    user { id }
    amount
    interestRate
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

### Real-Time Updates

```typescript
import { useSubscription } from '@apollo/client';

const NEW_DEPOSIT_SUBSCRIPTION = gql`
  subscription OnNewDeposit {
    deposits(orderBy: timestamp, orderDirection: desc, first: 1) {
      user { id }
      amount
      timestamp
    }
  }
`;

const RealtimeFeed = () => {
  const { data } = useSubscription(NEW_DEPOSIT_SUBSCRIPTION);

  useEffect(() => {
    if (data?.deposits?.[0]) {
      toast.success(`New deposit: ${formatEther(data.deposits[0].amount)} ETH`);
    }
  }, [data]);

  return <ActivityFeed />;
};
```

---

## Key Metrics

### Protocol Health Metrics

| Metric | Definition | Healthy Range | Critical Threshold |
|--------|-----------|---------------|-------------------|
| **TVL** | Total value locked | Growing | -20% in 24h |
| **Vault Solvency** | Balance / Deposits | ≥ 1.0 | < 1.0 |
| **Active Users** | Users with deposits | Growing | -50% in 7d |
| **Utilization** | Deposits / Max | 40-80% | > 95% |
| **Interest Rate** | Current avg rate | 2-10% | > 15% |

### Governance Metrics

| Metric | Definition | Healthy Range | Critical Threshold |
|--------|-----------|---------------|-------------------|
| **Participation** | Voters / Eligible | > 20% | < 5% |
| **Quorum** | Votes / Required | > 100% | < 80% |
| **Proposal Success** | Passed / Total | 30-70% | < 10% or > 90% |
| **Voting Power** | Total locked | Growing | -30% in 30d |

### Bridge Metrics

| Metric | Definition | Healthy Range | Critical Threshold |
|--------|-----------|---------------|-------------------|
| **Success Rate** | Completed / Sent | > 99% | < 95% |
| **Avg Time** | Time to complete | < 5 min | > 30 min |
| **Rate Limit** | Available / Max | > 30% | < 10% |
| **Daily Volume** | Total bridged | Stable | -80% in 24h |

### System Metrics

| Metric | Definition | Healthy Range | Critical Threshold |
|--------|-----------|---------------|-------------------|
| **Error Rate** | Errors / Hour | < 10 | > 100 |
| **Gas Price** | Avg tx cost | < 0.01 ETH | > 0.1 ETH |
| **Confirmations** | Avg conf time | < 1 min | > 10 min |
| **Uptime** | Service available | 99.9% | < 99% |

---

## Alert Integration

### Grafana Alerts

**Configure in dashboard JSON:**
```json
{
  "alert": {
    "name": "TVL Drop Alert",
    "conditions": [{
      "evaluator": {
        "params": [-20],
        "type": "lt"
      },
      "query": {
        "params": ["A", "1h", "now"]
      },
      "reducer": {
        "type": "diff_abs"
      },
      "type": "query"
    }],
    "frequency": "1m",
    "handler": 1,
    "notifications": [
      {
        "uid": "slack-notifications"
      },
      {
        "uid": "pagerduty-critical"
      }
    ]
  }
}
```

### Slack Integration

```javascript
// Send dashboard link with alert
const sendSlackDashboard = async (metric, value, threshold) => {
  await slack.sendMessage({
    channel: '#basero-alerts',
    text: `🚨 Alert: ${metric}`,
    blocks: [
      {
        type: 'section',
        text: {
          type: 'mrkdwn',
          text: `*${metric}* has reached *${value}* (threshold: ${threshold})`
        }
      },
      {
        type: 'actions',
        elements: [
          {
            type: 'button',
            text: { type: 'plain_text', text: 'View Dashboard' },
            url: 'https://grafana.basero.app/d/protocol-overview'
          }
        ]
      }
    ]
  });
};
```

---

## Best Practices

### 1. Dashboard Organization

**Hierarchy:**
- **Overview** - Key metrics (TVL, users, activity)
- **Details** - Specific component metrics
- **Debugging** - Error rates, logs, traces

### 2. Refresh Rates

- **Real-time data:** 30s - 1m
- **Historical data:** 5m - 1h
- **Analytics:** Daily

### 3. Color Coding

- **Green:** Healthy metrics
- **Yellow:** Warning thresholds
- **Red:** Critical alerts
- **Blue:** Neutral information

### 4. Time Ranges

Provide multiple views:
- Last 1 hour (real-time monitoring)
- Last 24 hours (daily ops)
- Last 7 days (trends)
- Last 30 days (analytics)

### 5. Mobile Optimization

Ensure dashboards work on mobile for on-call monitoring.

---

## Dashboard Templates

All dashboard templates available in:
- `grafana-dashboards/` - JSON files for Grafana
- `dune-queries/` - SQL files for Dune
- `web-components/` - React components

**Import:**
```bash
# Grafana
curl -X POST http://localhost:3000/api/dashboards/db \
  -H "Content-Type: application/json" \
  -d @grafana-dashboards/protocol-overview.json

# Dune
# Import via Dune UI: My Creations > Import Query
```

---

## Resources

- [Grafana Docs](https://grafana.com/docs/)
- [Dune Docs](https://dune.com/docs/)
- [Recharts](https://recharts.org/)
- [The Graph Queries](https://thegraph.com/docs/en/querying/graphql-api/)

**Version:** 1.0  
**Last Updated:** January 2026  
**Maintainer:** Basero Development Team
