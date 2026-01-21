# 🏛️ Basero Governance & DAO Guide

Complete guide to the Basero governance system, voting, proposals, and treasury management.

---

## 📋 Table of Contents

1. [Governance Overview](#governance-overview)
2. [Architecture](#architecture)
3. [TOKEN: BASEGovernanceToken](#token-basegovernancetoken)
4. [VOTING: BASEGovernor](#voting-basegovernor)
5. [EXECUTION: BASETimelock](#execution-basetimelock)
6. [Proposal Types](#proposal-types)
7. [Voting Guide](#voting-guide)
8. [Creating Proposals](#creating-proposals)
9. [Treasury Management](#treasury-management)
10. [Emergency Procedures](#emergency-procedures)
11. [Governance Parameters](#governance-parameters)
12. [FAQ](#faq)

---

## Governance Overview

Basero uses a **decentralized governance system** allowing BASE token holders to vote on critical protocol changes including:

- **Fees**: Protocol fees, per-chain bridging fees
- **Capacity**: Deposit caps, daily limits, per-user maximums
- **Interest Rates**: Accrual periods, daily accrual caps
- **Treasury**: Distributions of accumulated fees
- **Upgrades**: Contract improvements and security patches

### Key Design Principles

✅ **Decentralized**: One token = one vote (with delegation)
✅ **Time-locked**: All decisions have 2-day execution delay for safety
✅ **Community-aligned**: Quorum requirements ensure broad support (4% voting power)
✅ **Transparent**: All proposals and votes are on-chain and verifiable

---

## Architecture

### Three-Layer System

```
┌─────────────────────────────────────────┐
│  BASEGovernanceToken (Voting Power)     │
│  - ERC20Votes extension                 │
│  - Delegation support                   │
│  - 100M max supply                      │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│  BASEGovernor (Voting & Proposals)      │
│  - Create proposals                     │
│  - Vote on proposals                    │
│  - Queue approved proposals             │
│  - 1 week voting period                 │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│  BASETimelock (Execution Delay)         │
│  - 2-day minimum delay                  │
│  - Public execution after delay         │
│  - Treasury management                  │
│  - Emergency controls (multisig)        │
└─────────────────────────────────────────┘
```

---

## TOKEN: BASEGovernanceToken

### Overview

The BASE governance token grants voting power proportional to holdings.

**Contract**: `src/BASEGovernanceToken.sol`
**Symbol**: BASE
**Decimals**: 18
**Max Supply**: 100,000,000 BASE

### Key Features

#### Voting Power Delegation

```solidity
// Delegate to yourself (activate voting)
governanceToken.delegateSelf();

// Delegate to someone else
governanceToken.delegateVotes(delegatee);

// Check voting power at current block
governanceToken.getVotes(account);

// Check voting power at specific block (historical)
governanceToken.getPastVotes(account, blockNumber);
```

#### Minting & Burning

```solidity
// Mint new tokens (owner only)
governanceToken.mint(recipient, amount);

// Burn your own tokens
governanceToken.burn(amount);

// Check remaining mintable supply
governanceToken.getRemainingMintable();
```

### Voting Power Mechanics

- **Vote Per Token**: 1 BASE token = 1 vote
- **Delegation**: Voting power delegated when `delegateSelf()` or `delegateVotes()` called
- **Snapshots**: Historical voting power tracked via checkpoints
- **No Self-Vote**: Delegates must actively delegate voting power

### Getting Started with BASE

```bash
# Check token details
cast call 0x... "name()" --rpc-url $RPC_URL

# Check your balance
cast call 0x... "balanceOf(address)" $YOUR_ADDRESS --rpc-url $RPC_URL

# Delegate your voting power
cast send 0x... "delegateSelf()" --private-key $KEY --rpc-url $RPC_URL
```

---

## VOTING: BASEGovernor

### Overview

BASEGovernor is an OpenZeppelin Governor implementation that manages voting on protocol changes.

**Contract**: `src/BASEGovernor.sol`

### Voting Parameters

| Parameter | Value | Duration |
|-----------|-------|----------|
| **Voting Delay** | 1 block | ~12 seconds |
| **Voting Period** | 50,400 blocks | ~1 week (Ethereum) |
| **Proposal Threshold** | 100,000 BASE | Required to propose |
| **Quorum** | 4% of voting power | 4,000,000 BASE (if all minted) |
| **Vote Type** | For / Against / Abstain | 3-way vote |

### Proposal Lifecycle

```
1. PENDING (1 block delay)
   └─ Voting hasn't started yet
   
2. ACTIVE (50,400 blocks)
   └─ Community votes on proposal
   └─ For / Against / Abstain votes counted
   
3. CANCELED / DEFEATED
   └─ Voting period ended
   └─ Quorum not reached OR more against than for
   
4. SUCCEEDED
   └─ Voting period ended
   └─ Quorum reached AND more for than against
   
5. QUEUED
   └─ Proposal submitted to timelock
   └─ 2-day delay begins
   
6. EXPIRED / EXECUTED / CANCELED
   └─ After 2-day delay:
      ├─ EXECUTED: Proposal action completed
      ├─ EXPIRED: 2-week window closed without execution
      └─ CANCELED: Proposal was canceled
```

### Voting Actions

```solidity
// Cast a for vote
governor.castVote(proposalId, 1);

// Cast an against vote
governor.castVote(proposalId, 0);

// Cast an abstain vote
governor.castVote(proposalId, 2);

// Vote with reason
governor.castVoteWithReason(proposalId, 1, "Lower fees help adoption");

// Vote with signature (delegation off-chain)
governor.castVoteBySig(proposalId, 1, v, r, s);

// Check voting results
(uint256 against, uint256 forVotes, uint256 abstain) = governor.proposalVotes(proposalId);

// Check proposal state
IGovernor.ProposalState state = governor.state(proposalId);
```

### Voting States Explained

| State | Meaning |
|-------|---------|
| **Pending** | Voting hasn't started (1 block delay) |
| **Active** | Voting is open (50,400 blocks) |
| **Canceled** | Proposal was canceled by proposer |
| **Defeated** | Voting ended but didn't pass (quorum/vote threshold) |
| **Succeeded** | Voting passed (quorum + majority for) |
| **Queued** | Proposal queued in timelock (2-day delay) |
| **Expired** | Timelock window passed without execution |
| **Executed** | Proposal successfully executed |

---

## EXECUTION: BASETimelock

### Overview

The Timelock ensures governance decisions are time-locked for safety and allows emergency controls.

**Contract**: `src/BASETimelock.sol`
**Min Delay**: 2 days (172,800 seconds)

### Key Features

#### Governance Timelock

```solidity
// Queue an operation in timelock
// Called automatically by Governor
timelock.schedule(targets, values, calldatas, salt, predecessorId, delay);

// Execute after delay expires
timelock.execute(targets, values, calldatas, salt, successorId);

// Check if operation is ready
timelock.isOperationReady(operationId);

// Get operation status
timelock.isOperation(operationId);
```

#### Treasury Management

```solidity
// View treasury balance
timelock.getTreasuryBalance();

// Emergency ETH withdraw (multisig only, no delay)
timelock.emergencyWithdrawETH(recipient, amount);

// Treasury receives ETH directly
receive() external payable;
```

#### Role Management

```solidity
// Roles for governance
bytes32 PROPOSER_ROLE = timelock.PROPOSER_ROLE();   // Governor proposes
bytes32 EXECUTOR_ROLE = timelock.EXECUTOR_ROLE();   // Public execution
bytes32 ADMIN_ROLE = timelock.DEFAULT_ADMIN_ROLE(); // Multisig admin

// Grant proposer role to new governor
timelock.grantRole(PROPOSER_ROLE, newGovernor);

// Grant executor role (public = address(0))
timelock.grantRole(EXECUTOR_ROLE, address(0));
```

### Emergency Procedures

**Multisig Emergency Controls**:

```solidity
// Update governor (if compromised)
timelock.updateGovernor(newGovernor);

// Update multisig itself
timelock.updateTreasuryMultisig(newMultisig);

// Emergency ETH withdrawal
timelock.emergencyWithdrawETH(safeAddress, balance);
```

---

## Proposal Types

All proposals are created via `BASEGovernanceHelpers` which encodes the necessary calldata.

### 1. Fee Update Proposal

**Effect**: Update protocol fees or per-chain bridge fees

```solidity
helpers.encodeVaultFeeProposal(
    feeRecipient,  // New fee recipient address
    feeBps         // New fee in basis points (0-10000)
);
```

**Execution**: Calls `vault.setFeeConfig(recipient, feeBps)`

**Example**:
- Update protocol fee from 0% to 5% (500 bps)
- Send fees to treasury multisig
- Passes with 60% support

---

### 2. Deposit Cap Proposal

**Effect**: Update deposit limits and minimums

```solidity
helpers.encodeVaultCapProposal(
    minDeposit,           // Minimum deposit per user
    maxDepositPerAddress, // Max per user
    maxTotalDeposits      // Max total TVL
);
```

**Execution**: Calls `vault.setDepositCaps(...)`

**Example**:
- Set min deposit to 1 ETH
- Set max per user to 1,000 ETH
- Set max total to 50,000 ETH
- Prevents whale concentration

---

### 3. Accrual Configuration Proposal

**Effect**: Update interest accrual mechanics

```solidity
helpers.encodeVaultAccrualProposal(
    accrualPeriod,      // Period in seconds (1h to 7d)
    maxDailyAccrualBps  // Max daily accrual (basis points)
);
```

**Execution**: Calls `vault.setAccrualConfig(...)`

**Example**:
- Accrual every 12 hours instead of 24
- Max daily accrual 5% instead of 10%
- Faster but more conservative interest

---

### 4. CCIP Fee Proposal

**Effect**: Update per-chain bridging fees

```solidity
helpers.encodeCCIPFeeProposal(
    chainSelector, // CCIP chain selector
    feeBps         // Fee in basis points
);
```

**Execution**: Calls `sender.setChainFeeBps(chainSelector, feeBps)`

**Example**:
- Arbitrum bridge fee: 10 bps (0.1%)
- Avalanche bridge fee: 20 bps (0.2%)
- Reflects operational costs per chain

---

### 5. CCIP Cap Proposal

**Effect**: Update per-chain bridging limits

```solidity
helpers.encodeCCIPCapProposal(
    chainSelector, // CCIP chain selector
    sendCap,       // Max per transaction
    dailyLimit     // Max per day
);
```

**Execution**: Calls `sender.setChainCaps(chainSelector, sendCap, dailyLimit)`

**Example**:
- Arbitrum: 1,000 BASE per send, 100,000 BASE per day
- Avalanche: 500 BASE per send, 50,000 BASE per day

---

### 6. Treasury Distribution Proposal

**Effect**: Distribute ETH from treasury to recipients

```solidity
helpers.encodeTreasuryDistributionProposal(
    recipients[], // Array of recipient addresses
    amounts[],    // Array of ETH amounts
    timelockAddr  // Treasury address
);
```

**Execution**: Direct ETH transfers from timelock

**Example**:
- Grant 10 ETH to audit firm
- Grant 5 ETH to bug bounty program
- Total: 15 ETH from treasury

---

## Voting Guide

### Step 1: Get Governance Token

```bash
# Receive BASE tokens (genesis distribution or purchase)
# Check balance
cast call $BASE_TOKEN "balanceOf($YOUR_ADDRESS)" --rpc-url $RPC_URL
```

### Step 2: Delegate Voting Power

**Required**: You must delegate to participate in voting!

```bash
# Delegate to yourself
cast send $BASE_TOKEN "delegateSelf()" \
  --private-key $KEY \
  --rpc-url $RPC_URL

# Or delegate to another address
cast send $BASE_TOKEN "delegateVotes($DELEGATEE)" \
  --private-key $KEY \
  --rpc-url $RPC_URL

# Verify delegation
cast call $BASE_TOKEN "getVotes($YOUR_ADDRESS)" --rpc-url $RPC_URL
```

### Step 3: Review Active Proposals

```bash
# Get proposal details
cast call $GOVERNOR "proposalSnapshot($PROPOSAL_ID)" --rpc-url $RPC_URL
cast call $GOVERNOR "proposalDeadline($PROPOSAL_ID)" --rpc-url $RPC_URL

# Check proposal state
cast call $GOVERNOR "state($PROPOSAL_ID)" --rpc-url $RPC_URL
```

### Step 4: Cast Your Vote

```bash
# Vote FOR (1), AGAINST (0), or ABSTAIN (2)
cast send $GOVERNOR "castVote($PROPOSAL_ID, 1)" \
  --private-key $KEY \
  --rpc-url $RPC_URL

# Vote with reason (optional)
cast send $GOVERNOR "castVoteWithReason($PROPOSAL_ID, 1, 'This is good for the protocol')" \
  --private-key $KEY \
  --rpc-url $RPC_URL
```

### Step 5: Monitor Results

```bash
# Check voting results
cast call $GOVERNOR "proposalVotes($PROPOSAL_ID)" --rpc-url $RPC_URL

# Returns: againstVotes, forVotes, abstainVotes
```

---

## Creating Proposals

### For Protocol Contributors

#### Prerequisites

- Hold at least **100,000 BASE** tokens
- Tokens **delegated** (via `delegateSelf()`)
- Proposal ready (encoded via helpers or custom)

#### Proposal Creation

```solidity
// Example: Create fee update proposal
address[] memory targets = new address[](1);
targets[0] = address(vault);

uint256[] memory values = new uint256[](1);
values[0] = 0;

bytes[] memory calldatas = new bytes[](1);
calldatas[0] = abi.encodeWithSignature(
    "setFeeConfig(address,uint256)",
    feeRecipient,
    500 // 5% fee
);

string memory description = "Proposal #1: Update protocol fee to 5%";

uint256 proposalId = governor.propose(targets, values, calldatas, description);
```

#### Using Governance Helpers

```solidity
// Simpler approach using helpers
(
    address[] memory targets,
    uint256[] memory values,
    bytes[] memory calldatas,
    string memory description
) = helpers.encodeVaultFeeProposal(feeRecipient, 500);

uint256 proposalId = governor.propose(targets, values, calldatas, description);
```

### CLI Proposal Creation

```bash
# 1. Encode proposal (using solc or Python script)
ENCODED_PROPOSAL=$(cast abi-encode "setFeeConfig(address,uint256)" \
  "0x..." 500)

# 2. Create proposal
cast send $GOVERNOR "propose(...)" \
  --private-key $KEY \
  --rpc-url $RPC_URL
```

---

## Treasury Management

### Treasury Structure

```
BASETimelock
├─ Holds accumulated protocol fees (ETH)
├─ Role-based access:
│  ├─ PROPOSER_ROLE: Governor (proposes distributions)
│  ├─ EXECUTOR_ROLE: Public (executes after delay)
│  └─ ADMIN_ROLE: Multisig (emergency controls)
└─ 2-day execution delay on all actions
```

### Treasury Operations

#### View Treasury Balance

```bash
cast call $TIMELOCK "getTreasuryBalance()" --rpc-url $RPC_URL
```

#### Distribute Treasury Funds (Via Governance)

```solidity
// Create proposal to distribute 10 ETH to audit firm
address[] memory recipients = new address[](1);
recipients[0] = auditFirm;

uint256[] memory amounts = new uint256[](1);
amounts[0] = 10 ether;

(
    address[] memory targets,
    uint256[] memory values,
    bytes[] memory calldatas,
    string memory description
) = helpers.encodeTreasuryDistributionProposal(recipients, amounts, address(timelock));

// Create and vote on proposal normally
governor.propose(targets, values, calldatas, description);
```

#### Emergency Treasury Withdrawal (Multisig Only)

```bash
# Direct withdrawal bypassing governance (for emergencies)
cast send $TIMELOCK "emergencyWithdrawETH($RECIPIENT, $AMOUNT)" \
  --private-key $MULTISIG_KEY \
  --rpc-url $RPC_URL
```

---

## Emergency Procedures

### Governance Emergencies

**Scenario 1: Proposal Contains Malicious Code**

```
1. Monitor during voting period
2. Vote AGAINST proposal
3. Proposal should fail to reach quorum/threshold
4. If passes: Timelock prevents execution
5. Multisig can cancel via DEFAULT_ADMIN_ROLE
```

**Scenario 2: Governor Contract Compromised**

```
1. Multisig calls timelock.updateGovernor(newGovernor)
2. No delay for admin functions
3. New governor takes over proposal queue
4. Old governor cannot propose
```

**Scenario 3: Timelock Funds at Risk**

```
1. Multisig calls emergencyWithdrawETH(safeAddress, amount)
2. Funds moved immediately (no 2-day delay)
3. Governance paused until multisig intervention
```

### Access Control

```
Emergency Powers:
├─ Only 2-of-N multisig (configured at deployment)
├─ No governance delay on emergency functions
├─ Limited to:
│  ├─ updateGovernor()
│  ├─ updateTreasuryMultisig()
│  └─ emergencyWithdrawETH()
└─ All other functions: 2-day timelock + community vote
```

---

## Governance Parameters

### Static Parameters (Cannot Change)

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| Voting Delay | 1 block | Minimal delay, community has seen proposal |
| Voting Period | 50,400 blocks (~1 week) | Time for community discussion |
| Proposal Threshold | 100,000 BASE | Prevents spam (0.1% of max supply) |
| Quorum | 4% | Reasonable engagement level |
| Timelock Delay | 2 days | Allows exit if governance compromised |

### Controllable Parameters (Via Governance)

| Parameter | Range | Governance Effect |
|-----------|-------|-------------------|
| Protocol Fee | 0 - 100% | Vault fee config |
| Per-Chain Bridge Fees | 0 - 100% | CCIP cost per chain |
| Deposit Min | 0 - any | Vault min deposit |
| Deposit Cap/User | 1 - any | Vault per-user limit |
| Total TVL Cap | 1 - any | Vault max deposits |
| Accrual Period | 1h - 7d | Interest frequency |
| Max Daily Accrual | 0 - 10% | Interest cap |

### Future Governance Enhancements

Potential improvements (governance vote required):

- Delegation voting periods
- Weighted voting (skin-in-game multiplier)
- Veto council for emergency stops
- DAO treasury for development
- Incentives for voting participation

---

## FAQ

### Voting

**Q: Why do I need to delegate?**
A: Delegation creates a checkpoint of voting power. Without it, contract can't verify your vote. Call `delegateSelf()` to activate your voting power.

**Q: Can I change my vote?**
A: No, votes are final once cast. Vote only after thorough review.

**Q: What if I miss a vote?**
A: Votes can be cast up to the voting deadline. After deadline, proposal moves to counting phase.

**Q: Can voting power be transferred during voting?**
A: No, voting power is snapshotted at proposal start block. Transfers after don't affect that proposal.

---

### Proposals

**Q: How much BASE do I need to propose?**
A: 100,000 BASE minimum, delegated to yourself.

**Q: Can I cancel my proposal?**
A: Yes, as the proposer during voting period. After voting ends, only governance can cancel.

**Q: What if my proposal gets defeated?**
A: You can propose again after waiting period. Community likely disagreed with terms.

---

### Treasury

**Q: Where do protocol fees go?**
A: To BASETimelock treasury. Distributions require governance vote.

**Q: Can multisig withdraw treasury freely?**
A: Only for emergencies (no governance delay). Normal distributions require 2-day timelock + community vote.

**Q: Can treasury be upgraded to smart contract?**
A: Yes, via governance vote to transfer treasury contract to new address.

---

### Technical

**Q: How is quorum calculated?**
A: 4% of total voting power at proposal snapshot block.

**Q: What if exactly 50% vote FOR and 50% AGAINST?**
A: Proposal fails (need >50% for, not >=50%).

**Q: Can I vote with someone else's tokens via signature?**
A: Only if you have a valid signature from token holder (`castVoteBySig`).

**Q: What's the maximum proposal size?**
A: Limited by block gas (can be ~20-30 transactions per proposal safely).

---

## Resources

- **Contracts**: `src/BASEGovernanceToken.sol`, `src/BASEGovernor.sol`, `src/BASETimelock.sol`
- **Helpers**: `src/BASEGovernanceHelpers.sol`
- **Tests**: `test/GovernanceIntegration.t.sol`
- **OpenZeppelin Docs**: https://docs.openzeppelin.com/contracts/5.0/governance
- **CCIP Docs**: https://docs.chain.link/ccip

---

**Last Updated**: January 21, 2026
**Version**: 1.0
**Status**: ✅ Ready for Testnet Governance
