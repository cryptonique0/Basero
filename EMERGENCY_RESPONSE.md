# Emergency Response Procedures & Playbooks

**Last Updated:** January 22, 2026
**Version:** 1.0
**Status:** Production Ready

---

## Table of Contents

1. [Incident Classification](#incident-classification)
2. [Response Procedures](#response-procedures)
3. [Scenario-Specific Playbooks](#scenario-specific-playbooks)
4. [Recovery Procedures](#recovery-procedures)
5. [Post-Incident Analysis](#post-incident-analysis)
6. [Communication Templates](#communication-templates)

---

## Incident Classification

### Incident Severity Levels

| Level | Name | Impact | Response Time | Authority |
|-------|------|--------|---|---|
| **P0** | **CRITICAL** | Protocol halt, funds at risk | Immediate (< 5 min) | Multi-sig, Owner |
| **P1** | **HIGH** | Major system degradation | Urgent (< 15 min) | Multi-sig |
| **P2** | **MEDIUM** | Component malfunction | Standard (< 1 hour) | Multi-sig, DevOps |
| **P3** | **LOW** | Minor issues, no impact | Routine (< 4 hours) | DevOps, Team |

### Incident Categories

#### 1. **Vault Issues** (VLT)
- **Critical Signs:**
  - Unusual withdrawal patterns (>50% TVL drain in 1 hour)
  - Calculation errors in share/asset conversion
  - Balance accounting mismatches
  - Interest accrual malfunction
  
- **Severity Mapping:**
  - Funds locked: P1
  - Loss of funds: P0
  - Calculation error: P2
  - Performance degradation: P3

#### 2. **Bridge Issues** (BRG)
- **Critical Signs:**
  - Messages stuck > 24 hours
  - Rate limiting malfunction
  - Cross-chain message ordering violations
  - Liquidity exhaustion on destination chain
  
- **Severity Mapping:**
  - Stuck message: P1
  - Lost message: P0
  - Delayed message: P2
  - High utilization: P3

#### 3. **Governance Issues** (GVN)
- **Critical Signs:**
  - Flash loan voting detected
  - Voting manipulation
  - Proposal execution failure
  - Timelock bypass attempts
  
- **Severity Mapping:**
  - Malicious proposal passed: P0
  - Voting anomaly: P1
  - Proposal stuck: P2
  - Minor bug: P3

#### 4. **Smart Contract Issues** (SCT)
- **Critical Signs:**
  - Arithmetic overflow/underflow
  - Reentrancy attack
  - State corruption
  - Access control bypass
  
- **Severity Mapping:**
  - Unauthorized action: P0
  - Balance corruption: P0
  - Temporary malfunction: P1
  - Minor bug: P2

#### 5. **External Issues** (EXT)
- **Critical Signs:**
  - Oracle failure
  - Network congestion
  - Gas price spike
  - Exchange integration failure
  
- **Severity Mapping:**
  - Oracle data invalid: P1
  - Network partitioned: P1
  - Gas spike > threshold: P2
  - Performance degradation: P3

---

## Response Procedures

### Phase 1: Detection & Assessment (5-15 minutes)

**Trigger:** Automated alert or manual report

**Steps:**
1. ✅ Verify incident reality
   ```bash
   # Check vault state
   cast call $VAULT_ADDRESS "paused()" --rpc-url $RPC_URL
   
   # Check recent transactions
   etherscan_api call
   ```

2. ✅ Classify severity and category
   - Review incident characteristics
   - Cross-reference with classification matrix
   - Assign incident ID (format: YYYY-MM-DD-HHMM-XXX)

3. ✅ Activate incident response team
   - Page on-call engineer
   - Notify ops team
   - Post in #incident-response Slack channel

4. ✅ Take initial state snapshot
   ```bash
   bash scripts/incident-response.sh snapshot "Initial assessment"
   ```

### Phase 2: Containment (15-30 minutes)

**Goal:** Prevent further damage

**For P0 (CRITICAL):**
```bash
# Execute emergency pause immediately
cast send $MULTISIG_ADDRESS "emergencyPause(uint8)" 5 \
  --rpc-url $RPC_URL \
  --private-key $SIGNER_1_KEY

# Confirm pause executed
cast call $VAULT_ADDRESS "paused()" --rpc-url $RPC_URL
```

**For P1 (HIGH):**
- Create multi-sig proposal for targeted pause
- Vote on proposal (require 3/5 signers)
- Execute if threshold met

**For P2 (MEDIUM) & P3 (LOW):**
- Monitor situation for escalation
- Prepare response if needed

### Phase 3: Investigation (30 mins - 2 hours)

**Goal:** Understand root cause

**Steps:**
1. ✅ Analyze transaction history
   ```bash
   etherscan query 50 recent tx
   ```

2. ✅ Review contract state
   ```bash
   # Vault state
   cast call $VAULT_ADDRESS "totalAssets()" --rpc-url $RPC_URL
   cast call $VAULT_ADDRESS "totalSupply()" --rpc-url $RPC_URL
   
   # Bridge state
   cast call $BRIDGE_ADDRESS "getQueuedMessagesCount()" --rpc-url $RPC_URL
   ```

3. ✅ Check external systems
   - Oracle prices
   - Network status
   - Bridge status on destination chain

4. ✅ Document findings
   ```
   Root Cause: [Summary of issue]
   
   Evidence:
   - [Transaction hash]
   - [Contract state]
   - [Timeline of events]
   
   Impact Assessment:
   - [Number of affected users]
   - [Amount at risk]
   - [Estimated recovery time]
   ```

### Phase 4: Recovery (1-6 hours)

**Goal:** Restore protocol to safe state

**Steps:**
1. ✅ Create recovery plan
   - Identify corrective actions
   - Estimate execution time
   - Plan multi-sig approvals

2. ✅ Execute recovery transactions
   ```bash
   # Example: Rebalance vault
   cast send $VAULT_ADDRESS "rebalance()" \
     --rpc-url $RPC_URL \
     --private-key $OPERATOR_KEY
   ```

3. ✅ Verify recovery success
   ```bash
   bash scripts/incident-response.sh verify-state
   ```

4. ✅ Take post-recovery snapshot
   ```bash
   bash scripts/incident-response.sh snapshot "Post-recovery state"
   ```

### Phase 5: Resume Operations (6+ hours)

**Goal:** Restore normal operations

**Conditions for Resume:**
- [ ] Root cause identified and documented
- [ ] Recovery verified and tested
- [ ] Multi-sig approval obtained
- [ ] State validation passing
- [ ] Team readiness confirmed

**Execution:**
```bash
# Unpause with gradual resume
cast send $MULTISIG_ADDRESS "unpauseProtocol(uint8)" 0 \
  --rpc-url $RPC_URL \
  --private-key $SIGNER_1_KEY
```

---

## Scenario-Specific Playbooks

### 🏦 Scenario 1: Vault Drain (TVL Rapid Loss)

**Detection:**
- TVL drops > 50% in 1 hour
- Unusual withdrawal patterns
- Alert: `VAULT_DRAIN` triggered

**Immediate Response (5 min):**
1. Verify genuine withdrawal vs. calculation error
2. Check if legitimate withdrawal or exploit
3. Pause vault if exploit confirmed

**Investigation (1 hour):**
```bash
# Check withdrawal receipts
cast call $VAULT_ADDRESS "getUserWithdrawals(address)" $USER_ADDRESS \
  --rpc-url $RPC_URL

# Check share calculations
echo "Expected shares: $(($TVL_NOW / $PRICE_PER_SHARE))"
echo "Actual shares: $(cast call $VAULT_ADDRESS "totalSupply()")"
```

**Recovery Actions:**
- If calculation error: Deploy fix, migrate state
- If exploit: Drain compromised address, freeze account
- If legitimate: Resume normally

**Communication:**
```
Subject: Vault Withdrawal Event - Status Update

We detected elevated withdrawal activity in our vault.
After investigation, [root cause].

Actions taken:
- [Recovery action]
- [Timeline for resolution]

Affected users: [Count]
Estimated recovery time: [Time]
```

---

### 🌉 Scenario 2: Bridge Message Stuck

**Detection:**
- Messages stuck > 24 hours
- Alert: `BRIDGE_STUCK` triggered
- Cross-chain communication halted

**Immediate Response (5 min):**
1. Check destination chain bridge status
2. Verify message hash and payload
3. Determine if stuck or lost

**Investigation (1 hour):**
```bash
# Check message queue
cast call $BRIDGE_ADDRESS "getQueuedMessages()" --rpc-url $RPC_URL

# Check CCIP status
curl -s https://ccip-status.chain.link/api/health

# Verify destination chain
cast call $BRIDGE_DESTINATION "getMessageStatus(bytes32)" $MSG_HASH \
  --rpc-url $DEST_RPC_URL
```

**Recovery Actions:**

**Option A: Replay Message**
```bash
# Re-broadcast message to destination
cast send $BRIDGE_ADDRESS "replayMessage(bytes32)" $MSG_HASH \
  --rpc-url $RPC_URL \
  --private-key $OPERATOR_KEY \
  --gas 500000
```

**Option B: Manual Bridge Recovery**
- If CCIP failure: Execute manual settlement
- If destination issue: Contact destination chain team

**Option C: Emergency Withdrawal**
- Lock assets on source chain
- Manual user withdrawal process
- Reimburse any losses

---

### 🗳️ Scenario 3: Governance Attack (Flash Loan Vote)

**Detection:**
- Voting power spike before proposal
- Vote result inconsistent with historical voting
- Alert: `GOVERNANCE_ATTACK` triggered

**Immediate Response (5 min):**
1. Pause governance temporarily
2. Cancel ongoing voting
3. Freeze suspicious accounts

**Investigation (1 hour):**
```bash
# Check voting power history
cast call $VE_ADDRESS "getPriorVotes(address,uint256)" $ATTACKER 2000000 \
  --rpc-url $RPC_URL

# Check for flash loans
# Query DEX for large borrow/repay in same block
```

**Recovery Actions:**

**If Flash Loan Confirmed:**
1. Cancel malicious proposal
2. Implement flash loan protection
3. Deploy governance upgrade

**If Whale Vote (Legitimate):**
1. Continue proposal normally
2. Update voting monitoring

---

### 💥 Scenario 4: Critical Bug (State Corruption)

**Detection:**
- State validation fails
- totalSupply != sum(balances)
- Alert: `STATE_CORRUPTION` triggered

**Immediate Response (< 2 min):**
1. PAUSE ALL OPERATIONS immediately
2. Take comprehensive state snapshot
3. Page all engineers

**Investigation (2-4 hours):**
```bash
# Detailed state audit
forge test --match "state_validation"

# Check migration history
git log --oneline src/contracts/ | head -20

# Identify corrupted state
cast call $CONTRACT "validate()" --rpc-url $RPC_URL
```

**Recovery Actions:**

**Option A: Rollback & Restart**
- Identify last good state
- Execute state reset transaction
- Redeploy with fix

**Option B: Migrate State**
- Deploy new contract with corrected state
- Migrate user balances
- Update oracle references

**Option C: Manual Reconstruction**
- For small user base
- Reimburse based on historical records

---

### 🌐 Scenario 5: External Service Failure (Oracle)

**Detection:**
- Price feed stale (> 1 hour)
- Price deviation > 10%
- Alert: `ORACLE_FAILURE` triggered

**Immediate Response (5 min):**
1. Check oracle health
2. Switch to backup oracle if available
3. Alert users of price risk

**Investigation (30 min):**
```bash
# Check oracle contract
cast call $ORACLE_ADDRESS "latestPrice()" --rpc-url $RPC_URL

# Check underlying data source
# E.g., Chainlink feed status
curl https://api.chain.link/v1/feeds

# Check for flash loan price manipulation
```

**Recovery Actions:**

**If Oracle Down:**
1. Switch to backup price source
2. Pause price-sensitive operations
3. Wait for oracle recovery

**If Price Manipulation:**
1. Implement circuit breaker
2. Freeze suspicious transfers
3. Resume with validated prices

---

## Recovery Procedures

### Multi-Stage Recovery Process

```
┌─────────────────────────────────────────────┐
│ Stage 1: INITIAL (Pause & Assess)          │
│ - Pause affected systems                    │
│ - Take snapshots                            │
│ - Assess damage                             │
│ Duration: 5-15 min                          │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│ Stage 2: ASSESSMENT (Analyze & Plan)        │
│ - Investigate root cause                    │
│ - Create recovery plan                      │
│ - Estimate resource requirements            │
│ Duration: 30 min - 2 hours                  │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│ Stage 3: PLANNING (Prepare Fixes)           │
│ - Prepare contract fixes                    │
│ - Get multi-sig approvals                   │
│ - Test recovery procedures                  │
│ Duration: 1-4 hours                         │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│ Stage 4: EXECUTION (Deploy Fixes)           │
│ - Deploy contract upgrades                  │
│ - Execute recovery transactions             │
│ - Migrate state if needed                   │
│ Duration: 1-2 hours                         │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│ Stage 5: VERIFICATION (Validate)            │
│ - Verify fix successful                     │
│ - Validate state consistency                │
│ - Run regression tests                      │
│ Duration: 30 min - 1 hour                   │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│ Stage 6: COMPLETION (Resume & Analyze)      │
│ - Unpause system (gradual resume)           │
│ - Monitor recovery                          │
│ - Post-incident review                      │
│ Duration: 30 min - ongoing                  │
└─────────────────────────────────────────────┘
```

### Recovery Automation

```bash
# Automated recovery execution
bash scripts/incident-response.sh recover [recovery-id]

# Manual recovery stages
bash scripts/incident-response.sh recover [id] --stage assessment
bash scripts/incident-response.sh recover [id] --stage planning
bash scripts/incident-response.sh recover [id] --stage execution
bash scripts/incident-response.sh recover [id] --stage verification
```

---

## Post-Incident Analysis

### Post-Incident Review Template

```markdown
# Post-Incident Review: [INCIDENT-ID]

## Incident Summary
**Date:** [Date]
**Duration:** [Start] - [End] ([Total Time])
**Severity:** P[0-3] ([Name])
**Category:** [Category]

## Timeline

| Time | Event | Action | Owner |
|------|-------|--------|-------|
| HH:MM | Detection | Automated alert triggered | System |
| HH:MM | Verification | Confirmed as real incident | Engineer |
| HH:MM | Response | Initiated emergency pause | Multi-sig |
| ... | ... | ... | ... |

## Root Cause Analysis

**Primary Cause:**
[What happened]

**Contributing Factors:**
1. [Factor 1]
2. [Factor 2]
3. [Factor 3]

**Why It Wasn't Caught:**
- [Detection gap 1]
- [Detection gap 2]

## Impact Assessment

**Affected Users:** [Count]
**Amount at Risk:** [Amount + $value]
**Funds Lost:** [If any]
**Reputation Impact:** [Assessment]

## Resolution

**Actions Taken:**
1. [Action 1]
2. [Action 2]
3. [Action 3]

**Effectiveness:** [Successful/Partial/Failed]

## Prevention

**Short-term (1-2 weeks):**
- [ ] Implement detection improvement
- [ ] Add monitoring alert
- [ ] Improve runbook

**Medium-term (1-2 months):**
- [ ] Deploy code fix
- [ ] Upgrade contract
- [ ] Enhance testing

**Long-term (3-6 months):**
- [ ] Formal verification
- [ ] Architecture redesign
- [ ] External audit

## Lessons Learned

**What Went Well:**
- Team responded quickly
- Good incident tracking
- [Other positive]

**What Could Be Better:**
- Better automation
- Faster detection
- [Other improvement]

## Action Items

| Item | Priority | Owner | Due Date |
|------|----------|-------|----------|
| [Action] | P1 | [Owner] | [Date] |
| ... | ... | ... | ... |

**Follow-up Meeting:** [Date/Time]
```

---

## Communication Templates

### Internal Notification Template

**Subject:** [INCIDENT-ID] - [Severity] - [Brief Description]

```
INCIDENT ALERT
==============

Severity: P[0-3] - [CRITICAL/HIGH/MEDIUM/LOW]
Time: [HH:MM UTC]
Category: [Category]
Status: [Active/In Progress/Resolved]

Description:
[One sentence summary]

Affected Systems:
- [System 1]
- [System 2]

Impact:
- [Impact 1]
- [Impact 2]

Actions Taken:
- [Action 1]
- [Action 2]

Next Update: [Time]

Incident ID: [INCIDENT-ID]
Responders: [Names]
```

### User Communication Template (No Immediate Impact)

**Subject:** Scheduled Maintenance - Brief Service Pause

```
Hello,

We performed scheduled maintenance on our protocol at [TIME UTC].
During this time, [OPERATIONS] were temporarily unavailable.

Impact:
- Duration: [X minutes]
- Affected operations: [List]
- User funds: Not at risk

We have resumed operations and all systems are operating normally.

Thank you for your patience.

- Basero Team
```

### User Communication Template (Issue Encountered)

**Subject:** Incident Update - We're Working On It

```
Dear Users,

We detected and addressed an issue in our protocol at [TIME UTC].

What Happened:
[Brief explanation in simple terms]

What We're Doing:
- Temporarily paused affected operations
- Investigating the root cause
- Working on resolution

Your Funds:
- Protected and secure
- No losses incurred
- Being closely monitored

Timeline:
- [Time]: Issue detected
- [Time]: Paused operations
- [Time]: Investigation began
- [Expected Time]: Resolution

Next Update: [Time]

We'll keep you informed every [X minutes].
Thank you for your patience.

- Basero Team
```

### Media/Community Update (After Resolution)

**Subject:** Incident Report - What Happened and What We're Doing

```
INCIDENT REPORT: [INCIDENT-ID]

Overview:
- Incident: [Description]
- Duration: [X hours]
- Severity: [P0-P3]
- Status: ✅ RESOLVED

Timeline:
- [Time]: Detected by monitoring
- [Time]: Paused operations
- [Time]: Root cause identified
- [Time]: Fix deployed
- [Time]: Normal operations resumed

Impact:
- User funds: Protected
- Tokens affected: None
- Transactions lost: None
- Data compromised: None

Root Cause:
[Detailed explanation]

Response:
[Actions taken]

Prevention:
[Improvements being made]

We apologize for the disruption. We're implementing [improvements] to prevent this in the future.

- Basero Team
```

---

## Incident Response Checklist

### P0 (CRITICAL) Response Checklist

- [ ] **0-1 min:** Report confirmed, severity assessed
- [ ] **1-2 min:** Emergency pause triggered
- [ ] **2-5 min:** Incident channel created
- [ ] **5-15 min:** Multi-sig contacted for approval
- [ ] **15-30 min:** Initial investigation started
- [ ] **30-60 min:** Root cause identified
- [ ] **1-2 hours:** Recovery plan prepared
- [ ] **2-4 hours:** Fix deployed
- [ ] **4-6 hours:** Verification complete
- [ ] **6+ hours:** Unpause approved and executed
- [ ] **Daily:** Post-incident review

### P1 (HIGH) Response Checklist

- [ ] **<15 min:** Confirmed and classified
- [ ] **15-30 min:** Proposal created for targeted pause
- [ ] **30-60 min:** Multi-sig voting in progress
- [ ] **1-2 hours:** Investigation started
- [ ] **2-4 hours:** Root cause identified
- [ ] **4-8 hours:** Fix deployed or workaround implemented
- [ ] **Daily:** Status updates to stakeholders

### Incident Drill Checklist

Run quarterly drills to validate procedures:

- [ ] **Detection:** Run `incident-response.sh detect`
- [ ] **Response:** Execute response procedures
- [ ] **Communication:** Send test alert
- [ ] **Recovery:** Execute recovery stage
- [ ] **Verification:** Validate all systems
- [ ] **Debrief:** Document lessons learned

---

## Emergency Contacts

### Primary Escalation

| Role | Name | Phone | Slack |
|------|------|-------|-------|
| Incident Commander | [Name] | [Number] | @[Handle] |
| On-Call Engineer | [Name] | [Number] | @[Handle] |
| Operations Lead | [Name] | [Number] | @[Handle] |

### Secondary Escalation

| Role | Name | Phone | Slack |
|------|------|-------|-------|
| Engineering Lead | [Name] | [Number] | @[Handle] |
| Security Lead | [Name] | [Number] | @[Handle] |
| CEO/CTO | [Name] | [Number] | @[Handle] |

### External Contacts

- **Chainlink (Oracle):** [Contact]
- **Aave (Lending):** [Contact]
- **Curve (DEX):** [Contact]
- **Base Network Team:** [Contact]

---

## Additional Resources

- [Operational Safety Guide](./OPERATIONAL_SAFETY.md)
- [Multi-sig Key Management](./OPERATIONAL_SAFETY.md#multi-sig-key-management)
- [Emergency Contact Directory](./OPERATIONAL_SAFETY.md#emergency-contacts)
- [Incident Response Automation](./scripts/incident-response.sh)
- [Monitoring & Alerting](./ALERT_THRESHOLDS.md)

---

**Document Date:** January 22, 2026
**Last Updated:** January 22, 2026
**Version:** 1.0
**Status:** Approved for Production Use

For questions or updates, contact the Operations Team.
