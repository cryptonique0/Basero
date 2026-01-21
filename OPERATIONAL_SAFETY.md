# Operational Safety & Multi-Sig Management Guide

**Last Updated:** January 22, 2026
**Version:** 1.0
**Classification:** Internal

---

## Table of Contents

1. [Multi-Sig Key Management](#multi-sig-key-management)
2. [Emergency Procedures](#emergency-procedures)
3. [Drill Schedules](#drill-schedules)
4. [Security Baseline](#security-baseline)
5. [Incident Communication](#incident-communication)

---

## Multi-Sig Key Management

### Multi-Sig Architecture

**Contract:** `BaseEmergencyMultiSig.sol`

```
┌─────────────────────────────────────────┐
│ Threshold: 3 of 5 Signers               │
│                                         │
│ Signers:                                │
│ 1. Engineering Lead (AWS KMS)           │
│ 2. Operations Lead (Azure Key Vault)    │
│ 3. Chief Security Officer (Hardware)    │
│ 4. Team Lead #1 (Fireblocks)            │
│ 5. Team Lead #2 (Hardware Wallet)       │
└─────────────────────────────────────────┘

Threshold: 3 of 5
Status: Active
Update Frequency: Quarterly
```

### Signer Responsibilities

#### 1. Engineering Lead
- **Role:** Primary incident responder
- **Key Storage:** AWS KMS (encrypted)
- **Access:** Office VPN + 2FA
- **Responsibilities:**
  - Monitor production 24/7
  - Initiate emergency pause
  - Technical decision making
- **Backup:** On-call engineer

#### 2. Operations Lead
- **Role:** Secondary responder
- **Key Storage:** Azure Key Vault
- **Access:** Cloud infrastructure
- **Responsibilities:**
  - Monitor operational metrics
  - Authorize recovery procedures
  - Status communications
- **Backup:** Operations team member

#### 3. Chief Security Officer
- **Role:** Security verification
- **Key Storage:** Ledger Nano S (Hardware)
- **Access:** Physical safe + biometric
- **Responsibilities:**
  - Verify no backdoors
  - Security approvals
  - Audit trail review
- **Backup:** Security team lead

#### 4. Team Lead #1
- **Role:** Escalation point
- **Key Storage:** Fireblocks
- **Access:** Company infrastructure
- **Responsibilities:**
  - Escalation approvals
  - Policy enforcement
  - Training oversight
- **Backup:** Designated team member

#### 5. Team Lead #2
- **Role:** Distributed backup
- **Key Storage:** Hardware Wallet (SafePal)
- **Access:** Physical possession
- **Responsibilities:**
  - Geographic redundancy
  - Emergency backup
  - Key recovery procedures
- **Backup:** Alternate team member

### Key Distribution

**Threshold:** 3 of 5 required

```
Ideal Approval Patterns:
├─ Primary Response: Engineering + Operations + Security
├─ Escalation: Engineering + Team Lead #1 + Team Lead #2
├─ Emergency: Operations + Security + Any Team Lead
└─ Recovery: Any 3 signers (all present in office)
```

### Key Rotation Schedule

**Frequency:** Quarterly (every 3 months)

| Date | Signer | Key | Action |
|------|--------|-----|--------|
| Q1 | Engineering Lead | AWS KMS | Rotate |
| Q2 | Operations Lead | Azure KV | Rotate |
| Q3 | CSO | Hardware | Verify |
| Q4 | All | Review | Audit |

### Key Security Practices

**DO:**
- ✅ Use hardware wallets for air-gapped storage
- ✅ Encrypt all key material at rest
- ✅ Require 2FA for all key access
- ✅ Log all key access attempts
- ✅ Rotate keys quarterly
- ✅ Test key recovery procedures quarterly
- ✅ Keep backups in separate locations
- ✅ Use multi-sig for all critical operations

**DON'T:**
- ❌ Store keys in plaintext
- ❌ Share keys across signers
- ❌ Keep keys on development machines
- ❌ Use same key for multiple purposes
- ❌ Store all backups in one location
- ❌ Approve transactions without review
- ❌ Bypass multi-sig threshold
- ❌ Use same password for all systems

### Access Control Matrix

| Operation | Min Signers | Approval Time | Emergency Bypass |
|-----------|------------|---|---|
| Pause Vault | 2 of 5 | < 15 min | ✅ Yes (expedited) |
| Pause Bridge | 2 of 5 | < 15 min | ✅ Yes (expedited) |
| Full Protocol Pause | 3 of 5 | < 5 min | ✅ Yes (immediate) |
| Emergency Withdrawal | 3 of 5 | < 30 min | ✅ Yes |
| Unpause System | 3 of 5 | < 1 hour | ❌ No |
| Parameter Update | 3 of 5 | < 2 hours | ❌ No |
| Add New Signer | 4 of 5 | < 4 hours | ❌ No |
| Remove Signer | 4 of 5 | < 4 hours | ❌ No |

---

## Emergency Procedures

### Emergency Pause Procedure

**Trigger:** Any P0 incident or manual activation

**Requirements:**
- 2 of 5 signers minimum
- Network connectivity to chain
- Multi-sig contract deployed

**Steps:**

1. **Verification Phase (1-2 min)**
   ```bash
   # Verify incident is real
   cast call $VAULT_ADDRESS "paused()" --rpc-url $RPC_URL
   
   # Check recent transactions
   cast tx $LATEST_TX_HASH --rpc-url $RPC_URL
   ```

2. **Authorization Phase (2-5 min)**
   - Signer #1: Approve emergency pause
   - Signer #2: Review and approve
   - Threshold met: Proceed to execution

3. **Execution Phase (< 1 min)**
   ```bash
   # Execute emergency pause
   cast send $MULTISIG_ADDRESS \
     "emergencyPause()" \
     --rpc-url $RPC_URL \
     --private-key $SIGNER_1_KEY
   ```

4. **Verification Phase (1-2 min)**
   ```bash
   # Confirm pause executed
   cast call $VAULT_ADDRESS "paused()" --rpc-url $RPC_URL
   # Should return: true
   ```

**Total Time to Pause:** < 5 minutes

### Emergency Recovery Procedure

**Trigger:** After incident contained

**Requirements:**
- Root cause identified
- Fix deployed or validated
- 3 of 5 signers approval
- State consistency verified

**Steps:**

1. **Assessment Phase (30-60 min)**
   - Collect evidence
   - Analyze impact
   - Create recovery plan

2. **Planning Phase (1-2 hours)**
   - Prepare recovery transactions
   - Validate with test network
   - Get multi-sig consensus

3. **Execution Phase (30-60 min)**
   ```bash
   # Execute recovery procedures
   bash scripts/incident-response.sh recover [recovery-id]
   ```

4. **Verification Phase (15-30 min)**
   - Validate all systems
   - Check balances
   - Monitor for issues

5. **Resume Phase (15 min)**
   ```bash
   # Unpause protocol
   cast send $MULTISIG_ADDRESS \
     "unpauseProtocol()" \
     --rpc-url $RPC_URL \
     --private-key $SIGNER_1_KEY
   ```

**Total Recovery Time:** 3-6 hours

### Emergency Withdrawal Procedure

**Trigger:** User fund access needed during pause

**Flow:**

1. **Request Phase**
   ```solidity
   PauseRecovery(recovery).requestEmergencyWithdrawal(
     user_address,
     token_address,
     amount
   );
   ```

2. **Approval Phase**
   - Multi-sig reviews request
   - Verifies user identity
   - Approves if legitimate

3. **Execution Phase**
   ```solidity
   PauseRecovery(recovery).executeEmergencyWithdrawal(request_id);
   ```

**Limits:**
- Max 10% of vault TVL per request
- Max 10 requests per day
- Requires multi-sig approval
- Transaction limit: $10M

---

## Drill Schedules

### Quarterly Incident Response Drills

**Schedule:** Last Tuesday of each quarter

| Quarter | Date | Scenario | Lead |
|---------|------|----------|------|
| Q1 | Jan 24 | Vault Drain | Engineering |
| Q2 | Apr 24 | Bridge Stuck | Infrastructure |
| Q3 | Jul 24 | Governance Attack | Security |
| Q4 | Oct 24 | Full Protocol | Operations |

### Monthly Key Rotation Drills

**Schedule:** First Monday of each month

```
Month 1: Key Backup Procedure
Month 2: Key Recovery Procedure
Month 3: Multi-sig Transaction Test
Month 4: Emergency Access Test
```

### Scenario Details

#### Vault Drain Drill (Q1)

**Objective:** Verify vault pause procedure

**Setup:**
1. Create test vault with dummy funds
2. Simulate withdrawal anomaly (>50% TVL)
3. Trigger automated alert

**Execution:**
```bash
bash scripts/incident-response.sh drill vault-drain
```

**Validation:**
- [ ] Alert triggered within 5 minutes
- [ ] Multi-sig contacted within 10 minutes
- [ ] Pause executed within 15 minutes
- [ ] State snapshot taken
- [ ] Communication sent

**Success Criteria:** All steps completed, no errors

---

#### Bridge Stuck Drill (Q2)

**Objective:** Verify bridge recovery procedure

**Setup:**
1. Deploy test bridge with artificial delay
2. Simulate stuck message (> 24 hours)
3. Trigger monitoring alert

**Execution:**
```bash
bash scripts/incident-response.sh drill bridge-stuck
```

**Validation:**
- [ ] Stuck message detected
- [ ] Bridge paused
- [ ] Recovery plan created
- [ ] Message replayed or recovered

**Success Criteria:** Message recovered or alternate routing confirmed

---

#### Governance Attack Drill (Q3)

**Objective:** Verify governance pause procedure

**Setup:**
1. Create test proposal
2. Simulate flash loan voting
3. Detect voting anomaly

**Execution:**
```bash
bash scripts/incident-response.sh drill governance-attack
```

**Validation:**
- [ ] Anomaly detected
- [ ] Governance paused
- [ ] Proposal cancelled
- [ ] Voting power reset

**Success Criteria:** Attack mitigated, governance secured

---

#### Full Protocol Drill (Q4)

**Objective:** Verify full protocol emergency response

**Setup:**
1. Simulate multiple system failures
2. Trigger cascade incident
3. Activate full emergency protocols

**Execution:**
```bash
bash scripts/incident-response.sh drill full-protocol
```

**Validation:**
- [ ] All systems paused
- [ ] State snapshot taken
- [ ] Recovery plan activated
- [ ] All communications sent

**Success Criteria:** Full protocol recovery completed

---

### Post-Drill Debrief

**Template:**

```markdown
# Drill Debrief: [Scenario]

Date: [Date]
Duration: [Start - End]
Participants: [Names]

## What Went Well
- [Point 1]
- [Point 2]
- [Point 3]

## What Could Improve
- [Point 1]
- [Point 2]

## Action Items
- [ ] [Action] - Owner: [Name] - Due: [Date]
- [ ] [Action] - Owner: [Name] - Due: [Date]

## Lessons Learned
[Insights from drill]

## Sign-off
- Exercise Lead: _________________ Date: _______
- Operations: _________________ Date: _______
```

---

## Security Baseline

### Security Requirements

**Multi-Sig Configuration:**
- ✅ 3 of 5 threshold
- ✅ Geographically distributed signers
- ✅ Different key storage methods
- ✅ Quarterly key rotation
- ✅ Annual penetration testing

**Access Controls:**
- ✅ 2FA for all key access
- ✅ VPN required
- ✅ Audit logging enabled
- ✅ IP allowlisting
- ✅ Rate limiting

**Operational Security:**
- ✅ Incident response runbook
- ✅ 24/7 monitoring
- ✅ Automated alerting
- ✅ Quarterly drills
- ✅ Annual security audit

### Compliance Checklist

- [ ] **SOC 2 Type II:** Current audit status
- [ ] **ISO 27001:** Certification current
- [ ] **Key Management:** Meets standards
- [ ] **Incident Response:** Annual testing
- [ ] **Disaster Recovery:** RTO/RPO verified

### Security Incident Classification

| Event | Classification | Response |
|-------|---|---|
| Signer key compromise | P0 | Immediate replacement |
| Unauthorized transaction attempt | P0 | Investigate and audit |
| Multi-sig contract bug | P0 | Immediate patch |
| Monitoring system failure | P1 | Restore within 1 hour |
| Key backup access issue | P2 | Resolve within 4 hours |
| Policy violation | P2 | Investigate and remediate |
| Minor configuration error | P3 | Fix in next release |

---

## Incident Communication

### Internal Escalation Matrix

```
P0 CRITICAL
├─ Level 1: On-call Engineer + Operations
├─ Level 2: Engineering Lead + CSO
├─ Level 3: CTO + CEO
└─ Escalation Time: Immediate

P1 HIGH
├─ Level 1: Engineering Lead
├─ Level 2: Operations Lead
├─ Level 3: CTO
└─ Escalation Time: < 15 min

P2 MEDIUM
├─ Level 1: Engineering Team
├─ Level 2: Operations Team
└─ Escalation Time: < 1 hour

P3 LOW
├─ Level 1: Engineering Team
└─ Escalation Time: < 4 hours
```

### Communication Channels

**Incident Comms:**
- 🔴 **P0:** Phone call + Slack + Email
- 🟠 **P1:** Slack + Email + Status page
- 🟡 **P2:** Slack + Status page
- 🟢 **P3:** Slack + Internal notes

**Public Communications:**
- ✅ Status page updates (all severity)
- ✅ Twitter announcements (P0-P1)
- ✅ Blog post (post-incident analysis)
- ✅ Discord community notifications

### Stakeholder Notification List

| Stakeholder | P0 | P1 | P2 | P3 |
|---|---|---|---|---|
| Engineering Team | 🔔 | 🔔 | 📧 | - |
| Operations Team | 🔔 | 🔔 | 🔔 | 📧 |
| Executive Team | 🔔 | 🔔 | 📧 | - |
| Community/Users | 📱 | 📧 | - | - |
| Partners/Investors | 🔔 | 📧 | - | - |

**Legend:** 🔔 Phone | 📧 Email | 📱 Social Media | - Not notified

### Status Page Updates

**Cadence:**
- P0: Every 15 minutes
- P1: Every 30 minutes
- P2: Every 2 hours
- P3: Daily or when resolved

**Template:**

```
Investigating: [Issue Description]
Status: INVESTIGATING/IN PROGRESS/RESOLVED
Severity: P[0-3]
Last Update: [Timestamp UTC]

We are aware of [issue] and are actively working on resolution.
Users may experience [impact]. No funds at risk at this time.

Next update in [time].
```

---

## Monthly Checklist

- [ ] **Week 1:**
  - [ ] Review incident logs
  - [ ] Verify all alerts working
  - [ ] Check key access logs
  
- [ ] **Week 2:**
  - [ ] Run key rotation drill
  - [ ] Update contact list
  - [ ] Review runbooks
  
- [ ] **Week 3:**
  - [ ] Backup verification
  - [ ] Access control audit
  - [ ] Monitoring verification
  
- [ ] **Week 4:**
  - [ ] Security review
  - [ ] Compliance check
  - [ ] Team training/updates

---

## Annual Review

**Schedule:** December each year

**Review Items:**
- [ ] Multi-sig threshold adequacy
- [ ] Signer composition
- [ ] Incident response metrics
- [ ] Security posture
- [ ] Compliance status
- [ ] External audit findings
- [ ] Process improvements
- [ ] Team training needs

---

## Additional Resources

- [Emergency Response Procedures](./EMERGENCY_RESPONSE.md)
- [Incident Response Scripts](./scripts/incident-response.sh)
- [Monitoring & Alerting](./ALERT_THRESHOLDS.md)
- [Architecture Documentation](./ARCHITECTURE.md)

---

**Document Date:** January 22, 2026
**Version:** 1.0
**Approval:** [Signatures]

For questions, contact the Operations Team.
