# Alert Thresholds & Incident Response

## Overview

This document defines critical alert thresholds, warning levels, and incident response procedures for the Basero protocol.

**Alert Categories:** 7  
**Total Alert Rules:** 35+  
**Severity Levels:** 4 (Info, Warning, Critical, Emergency)  
**Response Times:** 15m - 4h  

## Table of Contents

1. [Severity Levels](#severity-levels)
2. [Alert Categories](#alert-categories)
3. [Critical Alerts](#critical-alerts)
4. [Warning Alerts](#warning-alerts)
5. [Incident Response](#incident-response)
6. [Escalation Procedures](#escalation-procedures)
7. [Monitoring Setup](#monitoring-setup)
8. [Alert Configuration](#alert-configuration)

---

## Severity Levels

### P0 - Emergency (Red)

**Response Time:** Immediate (within 15 minutes)  
**Notification:** Page on-call engineer, alert all team  
**Impact:** Protocol at risk, potential loss of funds  

**Examples:**
- Vault solvency < 1.0 (cannot pay all depositors)
- Smart contract paused for > 1 hour
- Exploit detected (abnormal withdrawals)
- Bridge failure affecting > 100 ETH

**Actions:**
1. Page on-call engineer immediately
2. Alert security team
3. Assess situation (exploit vs bug vs expected behavior)
4. Activate incident response plan
5. Consider emergency pause if needed

### P1 - Critical (Orange)

**Response Time:** 30 minutes  
**Notification:** Slack alert, email on-call  
**Impact:** Major functionality degraded, user impact  

**Examples:**
- TVL drop > 20% in 1 hour
- Error rate > 100/hour
- Bridge success rate < 95%
- Gas costs > 0.1 ETH per transaction
- Governance attack (malicious proposal)

**Actions:**
1. Acknowledge alert
2. Investigate root cause
3. Implement mitigation
4. Monitor for resolution
5. Post-mortem within 24h

### P2 - Warning (Yellow)

**Response Time:** 2 hours  
**Notification:** Slack notification  
**Impact:** Potential issues, degraded performance  

**Examples:**
- Utilization > 90%
- Interest rate > 15%
- Active users drop > 30% in 7 days
- Rate limit utilization > 80%
- Unusual governance voting patterns

**Actions:**
1. Review metrics
2. Determine if action needed
3. Monitor for escalation
4. Log for analysis

### P3 - Info (Blue)

**Response Time:** Next business day  
**Notification:** Dashboard, daily summary  
**Impact:** Informational, trends  

**Examples:**
- New milestone reached (1000 users, 10k ETH TVL)
- Daily statistics
- Performance improvements
- Non-critical config changes

**Actions:**
1. Log for records
2. Include in weekly report
3. No immediate action required

---

## Alert Categories

### 1. Vault Security Alerts

#### 🚨 P0: Vault Insolvency

**Condition:**
```
vault.balance < vault.totalDeposited
```

**Threshold:** Solvency ratio < 1.0  
**Check Frequency:** Every block  
**Notification:** PagerDuty + Slack #critical  

**Response:**
1. **IMMEDIATE:** Pause vault deposits/withdrawals
2. **ASSESS:** Check for exploit vs accounting error
3. **INVESTIGATE:** Review recent transactions
4. **COMMUNICATE:** Notify users if confirmed exploit
5. **RESOLVE:** Deploy fix or initiate recovery

**Root Causes:**
- Reentrancy attack
- Rounding error accumulation
- Oracle manipulation
- Flash loan attack

#### 🟠 P1: Large Withdrawal

**Condition:**
```
single_withdrawal > 1000 ETH
OR
total_withdrawals_1h > 5000 ETH
```

**Threshold:** 1000 ETH single / 5000 ETH hourly  
**Check Frequency:** Per transaction  
**Notification:** Slack #alerts  

**Response:**
1. Verify withdrawal is legitimate
2. Check if whale or exploit
3. Monitor vault solvency
4. Prepare liquidity if needed

#### 🟡 P2: High Utilization

**Condition:**
```
(totalDeposited / maxTotalDeposits) > 0.90
```

**Threshold:** > 90% of cap  
**Check Frequency:** Every 5 minutes  
**Notification:** Slack #monitoring  

**Response:**
1. Consider raising cap
2. Communicate to users
3. Monitor interest rate response

---

### 2. Token Security Alerts

#### 🚨 P0: Unexpected Supply Change

**Condition:**
```
ABS(supply_change - expected_rebase) > 1% of totalSupply
```

**Threshold:** >1% unexpected change  
**Check Frequency:** Every block  
**Notification:** PagerDuty + Slack #critical  

**Response:**
1. **IMMEDIATE:** Investigate transaction
2. **CHECK:** For unauthorized minting/burning
3. **PAUSE:** If exploit confirmed
4. **AUDIT:** Review all recent token operations

#### 🟠 P1: Rebase Failure

**Condition:**
```
timeSinceLastRebase > 25 hours
(expected: 24 hours)
```

**Threshold:** No rebase in 25 hours  
**Check Frequency:** Hourly  
**Notification:** Slack #alerts  

**Response:**
1. Check rebase transaction status
2. Verify oracle data availability
3. Manually trigger if needed
4. Investigate automation failure

#### 🟡 P2: Abnormal Interest Rate

**Condition:**
```
effectiveInterestRate > 15%
OR
effectiveInterestRate < 0.5%
```

**Threshold:** Outside 0.5%-15% range  
**Check Frequency:** Every 5 minutes  
**Notification:** Slack #monitoring  

**Response:**
1. Verify utilization rate
2. Check tier distribution
3. Confirm calculations correct
4. Adjust parameters if needed

---

### 3. Governance Alerts

#### 🚨 P0: Malicious Proposal Queued

**Condition:**
```
proposal.targets includes critical contracts
AND proposal.eta < 24 hours
AND proposal has not been reviewed
```

**Threshold:** Unreviewed critical proposal  
**Check Frequency:** Per proposal  
**Notification:** PagerDuty + Slack #governance  

**Response:**
1. **IMMEDIATE:** Review proposal details
2. **ASSESS:** Determine if malicious
3. **CANCEL:** If confirmed malicious
4. **COMMUNICATE:** Notify community
5. **INVESTIGATE:** How proposal reached quorum

**Critical Targets:**
- Vault contract
- Token contract
- Timelock admin
- Treasury

#### 🟠 P1: Low Voting Participation

**Condition:**
```
(totalVotes / totalVotingPower) < 0.05
AND proposal.state == Active
AND blocksUntilEnd < 1000
```

**Threshold:** <5% participation with <1000 blocks left  
**Check Frequency:** Every 100 blocks  
**Notification:** Slack #governance  

**Response:**
1. Send reminder to voters
2. Communicate via Discord/Twitter
3. Extend voting period if warranted
4. Analyze low participation cause

#### 🟡 P2: High Voting Concentration

**Condition:**
```
topVoter.votes / totalVotes > 0.40
```

**Threshold:** Single voter >40% of votes  
**Check Frequency:** Per vote  
**Notification:** Slack #monitoring  

**Response:**
1. Verify voter legitimacy
2. Check for vote buying
3. Monitor for sybil attack
4. Document for governance review

---

### 4. Bridge Alerts

#### 🚨 P0: Bridge Failure

**Condition:**
```
failedTransfers > 10
AND totalValue > 100 ETH
AND timePeriod < 1 hour
```

**Threshold:** 10+ failures, >100 ETH, <1h  
**Check Frequency:** Per transaction  
**Notification:** PagerDuty + Slack #bridge  

**Response:**
1. **IMMEDIATE:** Pause bridge if needed
2. **INVESTIGATE:** CCIP router status
3. **CHECK:** Destination chain availability
4. **RETRY:** Failed transfers if safe
5. **REFUND:** If permanent failure

#### 🟠 P1: Rate Limit Exhausted

**Condition:**
```
rateLimitAvailable < 0.10 * maxBurstSize
```

**Threshold:** <10% rate limit remaining  
**Check Frequency:** Every 1 minute  
**Notification:** Slack #bridge  

**Response:**
1. Notify users of delay
2. Estimate refill time
3. Consider increasing rate limit
4. Queue pending transfers

#### 🟡 P2: High Bridge Costs

**Condition:**
```
ccipFee > 0.01 ETH per transfer
```

**Threshold:** >0.01 ETH per bridge tx  
**Check Frequency:** Per transaction  
**Notification:** Slack #monitoring  

**Response:**
1. Review CCIP pricing
2. Consider batching transfers
3. Communicate costs to users
4. Explore alternative routes

---

### 5. System Performance Alerts

#### 🚨 P0: System Unresponsive

**Condition:**
```
healthCheck.status != "OK"
OR
lastBlockProcessed < currentBlock - 100
```

**Threshold:** Health check failing or 100 blocks behind  
**Check Frequency:** Every 30 seconds  
**Notification:** PagerDuty + Slack #ops  

**Response:**
1. **IMMEDIATE:** Check RPC provider
2. **RESTART:** Indexer/monitoring services
3. **FAILOVER:** To backup infrastructure
4. **NOTIFY:** Users if UI affected

#### 🟠 P1: High Gas Costs

**Condition:**
```
avgGasPrice > 100 gwei (Base)
OR
avgTxCost > 0.01 ETH
```

**Threshold:** Gas price spike  
**Check Frequency:** Every 5 minutes  
**Notification:** Slack #ops  

**Response:**
1. Notify users of high costs
2. Delay non-urgent transactions
3. Monitor for normalization
4. Use gas price oracle for UX

#### 🟡 P2: Slow Confirmations

**Condition:**
```
avgConfirmationTime > 5 minutes
```

**Threshold:** >5 min to confirm  
**Check Frequency:** Every 10 minutes  
**Notification:** Slack #monitoring  

**Response:**
1. Check network congestion
2. Verify block production
3. Adjust gas recommendations
4. Communicate delays to users

---

### 6. User Activity Alerts

#### 🟠 P1: Mass Exodus

**Condition:**
```
activeUsers_7d / activeUsers_30d < 0.30
```

**Threshold:** >70% user loss in 7 days  
**Check Frequency:** Daily  
**Notification:** Slack #product  

**Response:**
1. Investigate cause (exploit, competitor, UX issue)
2. Review recent changes
3. Survey users
4. Plan retention campaign

#### 🟡 P2: Whale Deposit

**Condition:**
```
singleDeposit > 1000 ETH
```

**Threshold:** >1000 ETH deposit  
**Check Frequency:** Per transaction  
**Notification:** Slack #monitoring  

**Response:**
1. Welcome new whale
2. Ensure adequate liquidity
3. Monitor for MEV risks
4. Update risk parameters if needed

---

### 7. Economic Alerts

#### 🟠 P1: TVL Flash Crash

**Condition:**
```
(tvl_now - tvl_1h_ago) / tvl_1h_ago < -0.20
```

**Threshold:** >20% TVL drop in 1 hour  
**Check Frequency:** Every 5 minutes  
**Notification:** Slack #alerts  

**Response:**
1. Verify legitimacy of withdrawals
2. Check for exploit
3. Monitor market conditions
4. Prepare communications
5. Review liquidity

#### 🟡 P2: Negative Yield

**Condition:**
```
avgInterestRate < inflationRate
```

**Threshold:** Real yield negative  
**Check Frequency:** Daily  
**Notification:** Slack #economics  

**Response:**
1. Review interest rate model
2. Check utilization curve
3. Consider parameter adjustments
4. Communicate to users

---

## Incident Response

### Response Timeline

**P0 - Emergency:**
- **0-5 min:** Detection and acknowledgment
- **5-15 min:** Initial assessment and triage
- **15-30 min:** Mitigation actions (pause, fix, etc.)
- **30-60 min:** Root cause analysis
- **1-4 hours:** Resolution and monitoring
- **24 hours:** Post-mortem report

**P1 - Critical:**
- **0-10 min:** Detection and acknowledgment
- **10-30 min:** Investigation
- **30-120 min:** Mitigation
- **2-24 hours:** Resolution
- **48 hours:** Post-mortem

### Emergency Procedures

#### Circuit Breaker Activation

**When to Activate:**
- Confirmed exploit in progress
- Vault insolvency detected
- Smart contract bug affecting funds
- Governance attack

**How to Activate:**
```solidity
// Multi-sig required
vault.pause(); // Pause deposits/withdrawals
bridge.pause(); // Pause cross-chain transfers
```

**Communication:**
1. Post status page update: "Under maintenance"
2. Tweet from official account
3. Discord announcement
4. Dune dashboard banner

#### Rollback Procedure

**Criteria:**
- Exploit confirmed
- Users affected
- State corruption detected

**Steps:**
1. Pause all contracts
2. Snapshot affected state
3. Calculate remediation amounts
4. Deploy fix or new contracts
5. Airdrop compensation if needed
6. Resume operations

### Communication Templates

#### P0 Incident Alert

```
🚨 CRITICAL ALERT 🚨

Incident: [Vault Insolvency Detected]
Severity: P0 - Emergency
Status: Investigating
Impact: Deposits/withdrawals paused

We've detected [issue description]. The team is actively investigating. 
All user funds are safe. Updates every 30 minutes.

Status page: https://status.basero.app
```

#### All Clear Message

```
✅ INCIDENT RESOLVED

The issue has been resolved. All systems are operating normally.

Summary:
- Issue: [Description]
- Root cause: [Cause]
- Resolution: [Fix]
- Impact: [User impact]
- Prevention: [Future measures]

Full post-mortem: [Link]
```

---

## Escalation Procedures

### On-Call Rotation

**Primary:** Protocol engineer (24/7)  
**Secondary:** Smart contract auditor  
**Tertiary:** Founder/CTO  

**Escalation:**
- P0: Page all immediately
- P1: Page primary, notify secondary
- P2: Notify primary via Slack
- P3: No escalation

### Contact List

```yaml
on_call:
  primary:
    slack: "@engineer-oncall"
    phone: "+1-XXX-XXX-XXXX"
    pagerduty: "engineer-oncall"
  
  security:
    slack: "@security-team"
    email: "security@basero.app"
    
  communications:
    slack: "@comms-lead"
    twitter: "@BaseroProtocol"
    
  multisig_signers:
    - address: "0x..."
      contact: "@signer1"
    - address: "0x..."
      contact: "@signer2"
```

---

## Monitoring Setup

### Prometheus Alert Rules

**File:** `prometheus/alerts.yml`

```yaml
groups:
  - name: basero_critical
    interval: 30s
    rules:
      - alert: VaultInsolvency
        expr: basero_vault_solvency_ratio < 1.0
        for: 1m
        labels:
          severity: P0
          component: vault
        annotations:
          summary: "Vault cannot pay all depositors"
          description: "Solvency ratio: {{ $value }}"
          runbook: "https://docs.basero.app/runbooks/vault-insolvency"
      
      - alert: TVLFlashCrash
        expr: (rate(basero_tvl_eth[1h]) / basero_tvl_eth) < -0.20
        for: 5m
        labels:
          severity: P1
          component: vault
        annotations:
          summary: "TVL dropped >20% in 1 hour"
          
      - alert: HighUtilization
        expr: basero_utilization_rate > 9000
        for: 10m
        labels:
          severity: P2
          component: vault
        annotations:
          summary: "Utilization >90%"
```

### PagerDuty Integration

```javascript
const pagerduty = require('@pagerduty/pdjs');

async function triggerIncident(severity, title, details) {
  const incident = await pagerduty.incidents.create({
    incident: {
      type: 'incident',
      title: title,
      service: {
        id: 'BASERO_SERVICE_ID',
        type: 'service_reference'
      },
      urgency: severity === 'P0' ? 'high' : 'low',
      body: {
        type: 'incident_body',
        details: details
      }
    }
  });
  
  return incident.id;
}
```

---

## Alert Configuration

### Slack Webhook

```bash
# .env
SLACK_WEBHOOK_CRITICAL=https://hooks.slack.com/services/XXX/YYY/ZZZ
SLACK_WEBHOOK_ALERTS=https://hooks.slack.com/services/AAA/BBB/CCC
```

```javascript
async function sendSlackAlert(severity, message, details) {
  const webhook = severity === 'P0' 
    ? process.env.SLACK_WEBHOOK_CRITICAL
    : process.env.SLACK_WEBHOOK_ALERTS;
  
  await fetch(webhook, {
    method: 'POST',
    body: JSON.stringify({
      text: `${getSeverityEmoji(severity)} ${message}`,
      blocks: [
        {
          type: 'section',
          text: {
            type: 'mrkdwn',
            text: `*${message}*\n${details}`
          }
        },
        {
          type: 'actions',
          elements: [
            {
              type: 'button',
              text: { type: 'plain_text', text: 'View Dashboard' },
              url: 'https://grafana.basero.app'
            },
            {
              type: 'button',
              text: { type: 'plain_text', text: 'Runbook' },
              url: `https://docs.basero.app/runbooks/${severity}`
            }
          ]
        }
      ]
    })
  });
}
```

### Email Alerts

```javascript
import nodemailer from 'nodemailer';

async function sendEmailAlert(severity, subject, body) {
  const transporter = nodemailer.createTransport({
    service: 'gmail',
    auth: {
      user: 'alerts@basero.app',
      pass: process.env.EMAIL_PASSWORD
    }
  });
  
  await transporter.sendMail({
    from: 'Basero Alerts <alerts@basero.app>',
    to: getRecipients(severity),
    subject: `[${severity}] ${subject}`,
    html: generateEmailTemplate(severity, subject, body)
  });
}
```

---

## Runbooks

Each alert type should have a runbook:

**Location:** `docs/runbooks/`

**Template:**
```markdown
# Runbook: [Alert Name]

## Severity
P[0-3]

## Trigger Conditions
[When does this alert fire?]

## Impact
[What is affected?]

## Investigation Steps
1. Check [metric/dashboard]
2. Review [logs/transactions]
3. Verify [state/condition]

## Resolution Steps
1. [Action 1]
2. [Action 2]
3. [Action 3]

## Prevention
[How to prevent in future]

## Related Alerts
- [Other related alerts]
```

---

## Testing Alerts

### Simulate Alerts

```bash
# Test Slack webhook
curl -X POST $SLACK_WEBHOOK_CRITICAL \
  -H 'Content-Type: application/json' \
  -d '{"text": "Test alert - please ignore"}'

# Test PagerDuty
npm run test:alerts -- --trigger vault-insolvency

# Test email
npm run test:alerts -- --email --severity P0
```

### Alert Drills

**Monthly:** Run P2 alert drill  
**Quarterly:** Run P1 alert drill  
**Annually:** Run P0 emergency drill  

**Drill Checklist:**
- [ ] Alert fires correctly
- [ ] Team acknowledges within SLA
- [ ] Runbook is followed
- [ ] Communication sent
- [ ] Resolution logged
- [ ] Post-drill review

---

## Resources

- [Prometheus Alerting](https://prometheus.io/docs/alerting/latest/overview/)
- [PagerDuty Docs](https://developer.pagerduty.com/)
- [Incident Response Guide](https://response.pagerduty.com/)
- [SRE Book - Alerting](https://sre.google/sre-book/monitoring-distributed-systems/)

**Version:** 1.0  
**Last Updated:** January 2026  
**Maintainer:** Basero Development Team  
**On-Call:** See [PagerDuty Schedule](https://basero.pagerduty.com/)
