# 🏛️ Governance Quick Reference

Fast reference for governance operations and commands.

---

## Core Contracts

| Contract | Purpose | Key Functions |
|----------|---------|----------------|
| **BASEGovernanceToken** | Voting power | `delegateSelf()`, `mint()`, `burn()` |
| **BASEGovernor** | Voting & proposals | `propose()`, `castVote()`, `queue()` |
| **BASETimelock** | Execution delay | `schedule()`, `execute()`, `emergencyWithdrawETH()` |
| **BASEGovernanceHelpers** | Proposal encoding | `encodeVaultFeeProposal()`, `encodeTreasuryDistributionProposal()` |
| **RebaseTokenVault** | Parameters | `setFeeConfig()`, `setAccrualConfig()`, `setDepositCaps()` |

---

## Voting Parameters

```
Voting Delay:          1 block (~12 seconds)
Voting Period:         50,400 blocks (~1 week)
Proposal Threshold:    100,000 BASE tokens
Quorum:                4% of voting power
Min Vote to Pass:      > 50% FOR (not >=)
Execution Delay:       2 days
Vote Types:            0 = Against, 1 = For, 2 = Abstain
```

---

## CLI Cheatsheet

### Check Balance

```bash
cast call $BASE_TOKEN "balanceOf($YOUR_ADDR)" --rpc-url $RPC
```

### Delegate Voting Power

```bash
cast send $BASE_TOKEN "delegateSelf()" \
  --private-key $KEY --rpc-url $RPC
```

### Check Voting Power

```bash
cast call $BASE_TOKEN "getVotes($YOUR_ADDR)" --rpc-url $RPC
```

### Get Proposal State

```bash
cast call $GOVERNOR "state($PROPOSAL_ID)" --rpc-url $RPC
# Returns: 0=Pending, 1=Active, 2=Canceled, 3=Defeated, 
#          4=Succeeded, 5=Queued, 6=Expired, 7=Executed
```

### Cast Vote

```bash
cast send $GOVERNOR "castVote($PROPOSAL_ID, $SUPPORT)" \
  --private-key $KEY --rpc-url $RPC
# $SUPPORT: 0=Against, 1=For, 2=Abstain
```

### Get Vote Results

```bash
cast call $GOVERNOR "proposalVotes($PROPOSAL_ID)" --rpc-url $RPC
# Returns: (againstVotes, forVotes, abstainVotes)
```

### Check Treasury Balance

```bash
cast call $TIMELOCK "getTreasuryBalance()" --rpc-url $RPC
```

---

## Proposal Flow

```
1. DRAFT
   └─ Create proposal locally
   └─ Encode via helpers or custom
   
2. PENDING (1 block)
   └─ Propose (requires 100k BASE)
   └─ Voting hasn't started
   
3. ACTIVE (50,400 blocks)
   └─ Community votes
   └─ For/Against/Abstain accepted
   
4. COUNTING (after voting ends)
   └─ Tally votes
   └─ Check quorum (4%)
   └─ Check majority (>50% for)
   
5. SUCCESS OR FAILURE
   ├─ SUCCEEDED
   │  └─ Queue to timelock
   │  └─ Voting succeeded
   │
   └─ DEFEATED
      └─ Proposal rejected
      └─ Community disagreed
      
6. QUEUED (2 day delay)
   └─ In timelock
   └─ Cannot execute yet
   
7. READY FOR EXECUTION
   └─ Delay period passed
   └─ Can now execute
   
8. EXECUTED / EXPIRED
   ├─ EXECUTED: Proposal actions completed
   └─ EXPIRED: 2-week window passed
```

---

## Proposal Examples

### Fee Update

```solidity
helpers.encodeVaultFeeProposal(
    0x..., // fee recipient
    500    // 5% fee (500 bps)
)
```

### Deposit Caps

```solidity
helpers.encodeVaultCapProposal(
    1 ether,      // min deposit
    1000 ether,   // max per user
    50000 ether   // max total
)
```

### Accrual Config

```solidity
helpers.encodeVaultAccrualProposal(
    1 days,  // accrual period
    1000     // max 10% daily accrual
)
```

### Treasury Distribution

```solidity
helpers.encodeTreasuryDistributionProposal(
    [recipient1, recipient2],  // addresses
    [10 ether, 5 ether],       // amounts
    timelock                   // treasury
)
```

---

## Access Control Matrix

| Function | Owner | Governor | Multisig | Public |
|----------|-------|----------|----------|--------|
| propose() | ✅ | ✅ | ❌ | Need threshold |
| castVote() | ✅ | ✅ | ✅ | ✅ Need tokens |
| queue() | ✅ | ✅ | ❌ | ❌ |
| execute() | ✅ | ✅ | ❌ | ✅ After delay |
| setFeeConfig() | ✅ | Governor | ❌ | ❌ |
| emergencyWithdrawETH() | ✅ | ❌ | ✅ | ❌ |
| updateGovernor() | ❌ | ❌ | ✅ | ❌ |

---

## Solidity Code Snippets

### Create Proposal

```solidity
address[] memory targets = new address[](1);
uint256[] memory values = new uint256[](1);
bytes[] memory calldatas = new bytes[](1);

targets[0] = address(vault);
values[0] = 0;
calldatas[0] = abi.encodeWithSignature("setFeeConfig(address,uint256)", recipient, 500);

string memory description = "Update fee to 5%";

uint256 proposalId = governor.propose(targets, values, calldatas, description);
```

### Vote on Proposal

```solidity
// Vote FOR
governor.castVote(proposalId, 1);

// Vote AGAINST
governor.castVote(proposalId, 0);

// Vote ABSTAIN
governor.castVote(proposalId, 2);
```

### Check Quorum

```solidity
uint256 quorum = governor.getQuorumVotes(blockNumber);
(uint256 against, uint256 forVotes, uint256 abstain) = governor.proposalVotes(proposalId);

bool quorumReached = (forVotes + against + abstain) >= quorum;
bool passingVotes = forVotes > (against + abstain);
```

---

## Error Messages

| Error | Meaning | Fix |
|-------|---------|-----|
| "Governor: proposer votes below proposal threshold" | Need 100k BASE | Get more tokens or delegates |
| "Governor: voting is closed" | Voting period ended | Proposal already in counting |
| "Governor: proposal can only be canceled by proposer" | Not original proposer | Contact original proposer |
| "Timelock: underlying transaction reverted" | Execution failed | Review proposal logic |
| "OnlyGovernance" | Not governance address | Must be timelock or owner |

---

## Emergency Contacts

```
Multisig Emergency:
├─ Update Governor: timelock.updateGovernor(newGov)
├─ Withdraw ETH: timelock.emergencyWithdrawETH(to, amount)
└─ Update Multisig: timelock.updateTreasuryMultisig(newMulti)

Community Issues:
├─ Proposal Discussion: [Forum URL]
├─ Snapshot Voting: [Snapshot URL]
└─ Discord: [Discord URL]
```

---

## Key Dates

| Event | Date | Duration |
|-------|------|----------|
| Voting Opens | T+0 blocks | |
| Voting Closes | T+50,400 blocks | ~1 week |
| Timelock Queues | T+50,400 blocks | |
| Execution Ready | T+50,400 blocks + 2 days | |
| Execution Expires | T+50,400 blocks + 14 days | |

---

## Token Supply

```
Total Supply: 100,000,000 BASE
├─ Minted: [at deployment]
├─ Remaining Mintable: 100M - Minted
└─ Burn Cap: Unlimited (reduces supply)
```

---

## Gas Estimates

| Operation | Cost | Notes |
|-----------|------|-------|
| Propose | ~250k gas | Varies by targets |
| Cast Vote | ~100k gas | Per vote |
| Queue | ~80k gas | To timelock |
| Execute | ~200k gas | Varies by calldata |

---

## Testnet Addresses

```
Sepolia:
├─ BASE Token: 0x...
├─ Governor: 0x...
├─ Timelock: 0x...
└─ Helpers: 0x...

Arbitrum Sepolia:
├─ BASE Token: 0x...
├─ Receiver: 0x...
└─ CCIP: 0x...
```

---

## Resources

| Resource | Link |
|----------|------|
| Governance Docs | `GOVERNANCE.md` |
| Implementation | `GOVERNANCE_COMPLETE.md` |
| Contracts | `src/BASE*.sol` |
| Tests | `test/GovernanceIntegration.t.sol` |
| OpenZeppelin Gov | https://docs.openzeppelin.com/contracts/governance |

---

**Quick Tip**: Always delegate before voting! 🗳️

```bash
cast send $BASE_TOKEN "delegateSelf()" --private-key $KEY --rpc-url $RPC
```

---

Last Updated: January 21, 2026
