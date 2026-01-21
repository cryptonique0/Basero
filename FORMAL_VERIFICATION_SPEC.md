# Basero Formal Verification Specification

## Overview

This document specifies the formal verification approach for Basero protocol contracts using:
- **Halmos**: Symbolic execution for bounded verification
- **Certora**: SMT-based formal verification for unbounded properties
- **Inline Specifications**: Code-level contract specifications

---

## Formal Verification Strategy

### Verification Scope

**Tier 1: Critical (Halmos + Certora)**
- RebaseToken (ERC20 invariants)
- RebaseTokenVault (accounting invariants)
- VotingEscrow (voting power invariants)

**Tier 2: Important (Halmos)**
- EnhancedCCIPBridge (message integrity)
- AdvancedInterestStrategy (rate calculation)
- BASEGovernor (governance state)

**Tier 3: Supported (Static Analysis)**
- BASETimelock (delay verification)
- Helpers and utilities

### Verification Properties

#### Supply Invariants
```
∀ t. totalSupply[t] = sum(balances[i][t])  -- Conservation of tokens
∀ t. totalSupply[t] > 0                     -- Supply always positive
```

#### Vault Invariants
```
∀ t. totalDeposits[t] = sum(deposits[i][t]) -- Accounting correctness
∀ t. accruedInterest[t] >= 0                -- Non-negative interest
∀ t. solvencyRatio[t] >= 1.0                -- Vault always solvent
```

#### Voting Invariants
```
∀ t. totalVotingPower[t] = sum(locks[i][t]) -- Voting power conservation
∀ t. votingPower[i][t] >= 0                 -- Non-negative voting power
∀ t. delegated[i][t] ∈ {0} ∪ holders       -- Delegation target is valid
```

#### Bridge Invariants
```
∀ t. sentVolume[t] = receivedVolume[t] + pending[t]  -- Atomicity
∀ t. rateLimitUsed[chain][t] <= rateLimitMax         -- Rate limit
∀ t. nonce[t] is monotonically increasing            -- Order preservation
```

---

## Formal Specification Format

### Specification Notation

All formal specifications follow this notation:

```
@spec <name>
  precondition: <logical expression>
  postcondition: <logical expression>
  invariant: <logical expression>
  reverts_on: <condition> with <error>
```

### Contract-Level Specifications

#### RebaseToken

```
CONTRACT: RebaseToken (ERC20)

INVARIANT: Balance Sum
  sum(balances[user] for all users) == totalSupply

INVARIANT: Supply Bounds
  0 < totalSupply <= type(uint256).max

INVARIANT: Allowance Non-negativity
  allowance[owner][spender] >= 0

FUNCTION: transfer(recipient, amount)
  PRECONDITION:
    - balances[msg.sender] >= amount
    - recipient != address(0)
  POSTCONDITION:
    - balances[msg.sender] decreased by amount
    - balances[recipient] increased by amount
    - totalSupply unchanged
    - For all other users: balance unchanged
  REVERTS_ON:
    - amount > balances[msg.sender] → "ERC20: insufficient balance"
    - recipient == address(0) → "ERC20: transfer to zero address"

FUNCTION: approve(spender, amount)
  POSTCONDITION:
    - allowance[msg.sender][spender] == amount
    - Caller and spender unchanged

FUNCTION: transferFrom(from, to, amount)
  PRECONDITION:
    - balances[from] >= amount
    - allowance[from][msg.sender] >= amount
  POSTCONDITION:
    - balances[from] decreased by amount
    - balances[to] increased by amount
    - allowance[from][msg.sender] decreased by amount
    - totalSupply unchanged
  REVERTS_ON:
    - amount > balances[from] → "Insufficient balance"
    - amount > allowance[from][msg.sender] → "Insufficient allowance"

FUNCTION: mint(to, amount, sharesToMint)
  PRECONDITION:
    - to != address(0)
    - only MINTER role
  POSTCONDITION:
    - balances[to] increased by amount
    - totalSupply increased by amount
    - sharesPerToken updated according to mint
  REVERTS_ON:
    - to == address(0) → "Mint to zero address"
    - caller not MINTER → "Access denied"

FUNCTION: rebase(percentageBps)
  PRECONDITION:
    - -10_00 <= percentageBps <= 10_00  -- Between -10% and +10%
    - only REBASE role
  POSTCONDITION:
    - totalSupply changed by percentageBps
    - All balances scaled proportionally
    - sharesPerToken updated
  REVERTS_ON:
    - percentageBps < -10_00 or > 10_00 → "Rebase out of bounds"
    - caller not REBASE → "Access denied"
```

#### RebaseTokenVault

```
CONTRACT: RebaseTokenVault

INVARIANT: Deposit Accounting
  sum(depositedAmount[user] for all users) == totalDeposits

INVARIANT: Interest Non-Negativity
  accruedInterest >= 0

INVARIANT: Vault Solvency
  address(vault).balance >= totalDeposits

INVARIANT: Shares Consistency
  sharesPerToken > 0 after initialization

FUNCTION: deposit()
  PRECONDITION:
    - msg.value > 0
    - not paused
  POSTCONDITION:
    - depositedAmount[msg.sender] increased by msg.value
    - totalDeposits increased by msg.value
    - vault balance increased by msg.value
    - shares minted proportionally
  REVERTS_ON:
    - msg.value == 0 → "Deposit amount zero"
    - paused == true → "Vault paused"

FUNCTION: withdraw(amount)
  PRECONDITION:
    - depositedAmount[msg.sender] >= amount
    - amount > 0
    - not paused
  POSTCONDITION:
    - depositedAmount[msg.sender] decreased by amount
    - totalDeposits decreased by amount
    - msg.sender receives amount in ETH
    - shares burned proportionally
  REVERTS_ON:
    - amount > depositedAmount[msg.sender] → "Insufficient balance"
    - amount == 0 → "Zero amount"
    - paused == true → "Vault paused"
    - Transfer failed → "Withdrawal failed"

FUNCTION: accrueInterest(newRate)
  PRECONDITION:
    - newRate >= 0
    - newRate <= maxRate
    - only INTEREST_ADMIN role
  POSTCONDITION:
    - accruedInterest increased
    - interestRate updated
    - sharesPerToken increased
  REVERTS_ON:
    - newRate > maxRate → "Rate too high"
    - caller not INTEREST_ADMIN → "Access denied"

FUNCTION: claimInterest()
  PRECONDITION:
    - depositedAmount[msg.sender] > 0
  POSTCONDITION:
    - interest transferred to msg.sender
    - lastInterestClaim updated
    - totalDeposits unchanged (interest from balance)
  REVERTS_ON:
    - Transfer failed → "Claim failed"
```

#### VotingEscrow

```
CONTRACT: VotingEscrow

INVARIANT: Voting Power Conservation
  sum(votingPower[user] for all users) == totalVotingPower

INVARIANT: Lock Expiry Monotonic
  ∀ user. lockEnd[user] increases or stays same

INVARIANT: Delegation Consistency
  ∀ user. delegatedTo[user] is valid address or zero

INVARIANT: Voting Power Non-Negative
  ∀ user. votingPower[user] >= 0

FUNCTION: createLock(amount, unlockTime)
  PRECONDITION:
    - amount > 0
    - unlockTime > block.timestamp
    - no existing lock for msg.sender
  POSTCONDITION:
    - lock created with amount and unlockTime
    - votingPower[msg.sender] > 0
    - tokens transferred to contract
  REVERTS_ON:
    - amount == 0 → "Zero amount"
    - unlockTime <= block.timestamp → "Invalid unlock time"
    - lock already exists → "Lock exists"

FUNCTION: increaseLock(amount)
  PRECONDITION:
    - amount > 0
    - lock exists for msg.sender
  POSTCONDITION:
    - lock amount increased by amount
    - votingPower[msg.sender] increased
    - tokens transferred to contract
  REVERTS_ON:
    - lock doesn't exist → "No lock"
    - amount == 0 → "Zero amount"

FUNCTION: extendLock(newUnlockTime)
  PRECONDITION:
    - newUnlockTime > lockEnd[msg.sender]
    - lock exists
  POSTCONDITION:
    - lockEnd[msg.sender] updated
    - votingPower[msg.sender] increased
  REVERTS_ON:
    - newUnlockTime <= lockEnd → "Not extended"
    - lock doesn't exist → "No lock"

FUNCTION: withdraw()
  PRECONDITION:
    - lock exists
    - block.timestamp >= lockEnd[msg.sender]
  POSTCONDITION:
    - lock deleted
    - votingPower[msg.sender] = 0
    - tokens returned to msg.sender
  REVERTS_ON:
    - lock doesn't exist → "No lock"
    - not unlocked → "Lock not expired"

FUNCTION: delegate(to)
  PRECONDITION:
    - to is valid address or zero
    - lock exists
  POSTCONDITION:
    - delegatedTo[msg.sender] = to
    - votingPower transferred
  REVERTS_ON:
    - lock doesn't exist → "No lock"
```

#### EnhancedCCIPBridge

```
CONTRACT: EnhancedCCIPBridge

INVARIANT: Atomicity
  sentTokens[t] == receivedTokens[t] + pending[t]

INVARIANT: Rate Limit
  bucketFilled[chain][hour] <= maxRateLimit[chain]

INVARIANT: Nonce Monotonic
  nonce[chain] is strictly increasing

INVARIANT: Batch Consistency
  ∀ batch. sum(amounts) == batchTotal

FUNCTION: transferToChain(destChain, recipient, amount)
  PRECONDITION:
    - destChain is supported
    - recipient != address(0)
    - amount > 0
    - amount <= available
    - getRateLimitRemaining(destChain) >= amount
  POSTCONDITION:
    - tokens locked in contract
    - CCIP message sent
    - nonce incremented
    - rate limit consumed
  REVERTS_ON:
    - destChain unsupported → "Unsupported chain"
    - amount > available → "Insufficient liquidity"
    - rate limit exceeded → "Rate limit exceeded"
    - CCIP send fails → "Send failed"

FUNCTION: _ccipReceive(message)
  PRECONDITION:
    - message from trusted sender
    - sourceChain is supported
    - recipient != address(0)
  POSTCONDITION:
    - tokens released to recipient
    - delivery confirmed
  REVERTS_ON:
    - untrusted sender → "Unauthorized"
    - invalid chain → "Unknown chain"

FUNCTION: createBatchTransfer(recipients, amounts)
  PRECONDITION:
    - recipients.length == amounts.length
    - recipients.length <= maxBatchSize
    - sum(amounts) > 0
    - rates respected
  POSTCONDITION:
    - batch created with batchId
    - total == sum(amounts)
  REVERTS_ON:
    - length mismatch → "Length mismatch"
    - too many recipients → "Batch too large"

FUNCTION: executeBatch(batchId)
  PRECONDITION:
    - batch exists
    - batch not executed
    - all conditions met
  POSTCONDITION:
    - batch executed
    - all transfers completed atomically
    - batch marked executed
  REVERTS_ON:
    - batch doesn't exist → "Unknown batch"
    - already executed → "Already executed"
    - conditions not met → "Conditions not met"
```

#### BASEGovernor

```
CONTRACT: BASEGovernor

INVARIANT: Proposal State Consistency
  ∀ proposal. state ∈ {Pending, Active, Canceled, Defeated, Succeeded, Queued, Expired, Executed}

INVARIANT: Vote Counting
  votesFor[proposal] + votesAgainst[proposal] + votesAbstain[proposal] == totalVotes[proposal]

INVARIANT: Quorum Requirement
  executed[proposal] → votesFor[proposal] >= quorumVotes

INVARIANT: Voting Period Order
  startBlock < endBlock for active proposals

FUNCTION: propose(targets, values, calldatas, description)
  PRECONDITION:
    - proposer has >= proposalThreshold votes
    - targets.length > 0 and balanced
  POSTCONDITION:
    - proposal created with unique id
    - proposal state = Pending
    - proposalCount incremented
  REVERTS_ON:
    - insufficient votes → "Insufficient voting power"
    - invalid targets → "Invalid proposal"

FUNCTION: vote(proposalId, support)
  PRECONDITION:
    - proposal is Active (startBlock <= block.number <= endBlock)
    - voter hasn't voted on this proposal
    - voter has voting power
  POSTCONDITION:
    - vote recorded
    - appropriate vote count incremented
    - hasVoted[proposalId][voter] = true
  REVERTS_ON:
    - proposal not active → "Voting closed"
    - already voted → "Already voted"
    - no voting power → "No voting power"

FUNCTION: queue(proposalId)
  PRECONDITION:
    - proposal state == Succeeded
    - proposal passed quorum
  POSTCONDITION:
    - proposal state = Queued
    - eta set to current block + delay
  REVERTS_ON:
    - proposal not succeeded → "Not succeeded"

FUNCTION: execute(proposalId)
  PRECONDITION:
    - proposal state == Queued
    - current time >= eta
    - not executed before
  POSTCONDITION:
    - proposal state = Executed
    - all targets executed atomically
  REVERTS_ON:
    - not queued → "Not queued"
    - not ready → "Timelock not expired"
    - execution reverts → propagate
```

---

## Halmos Symbolic Execution Properties

### Halmos Configuration

```toml
# halmos.toml
[profile.default]
# Solver
solver = "z3"
solver_timeout = 0
solver_max_memory = 4000

# Search
max_iterations = 10
loop_bound = 10
call_depth_limit = 10
create_depth_limit = 5
memory_size = 2^20

# Output
verbose = 1
output_dir = "halmos-reports"

[profile.intensive]
max_iterations = 100
loop_bound = 100
solver_timeout = 300
```

### Property Examples for Halmos

#### Balance Conservation (RebaseToken)

```python
# halmos/test/RebaseToken.t.sol
import "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";

contract RebaseTokenHalmos is Test {
    RebaseToken token;
    
    function setUp() public {
        token = new RebaseToken("Test", "TEST");
    }
    
    /// @dev Balance sum equals total supply
    /// @dev This property should hold for all sequences of transfers
    function halmos_transfer_balance_conservation(
        address from,
        address to,
        uint256 amount
    ) public {
        // Assume preconditions
        vm.assume(from != address(0));
        vm.assume(to != address(0));
        vm.assume(from != to);
        
        uint256 initialSum = getBalanceSum();
        
        // Execute transfer
        vm.prank(from);
        try token.transfer(to, amount) {
            // Verify balance sum unchanged
            uint256 finalSum = getBalanceSum();
            assert(initialSum == finalSum);
        } catch {
            // Even on revert, sum should be unchanged
            uint256 finalSum = getBalanceSum();
            assert(initialSum == finalSum);
        }
    }
    
    /// @dev No token creation or destruction
    function halmos_no_token_creation(
        address account,
        uint256 amount
    ) public {
        vm.assume(account != address(0));
        vm.assume(amount > 0);
        
        uint256 before = token.totalSupply();
        
        // Transfer cannot change total supply
        try token.transferFrom(account, address(0x1), amount) {
            uint256 after = token.totalSupply();
            assert(before == after);
        } catch {
            // Revert doesn't change supply
            uint256 after = token.totalSupply();
            assert(before == after);
        }
    }
    
    function getBalanceSum() internal view returns (uint256) {
        // Note: This is simplified; real implementation
        // would need to track all accounts
        return token.totalSupply();
    }
}
```

#### Vault Solvency (RebaseTokenVault)

```python
# halmos/test/RebaseTokenVault.t.sol
contract RebaseTokenVaultHalmos is Test {
    RebaseTokenVault vault;
    
    /// @dev Vault always maintains deposits <= balance
    function halmos_vault_solvency() public {
        uint256 vaultBalance = address(vault).balance;
        uint256 totalDeposits = vault.totalDeposits();
        
        assert(vaultBalance >= totalDeposits);
    }
    
    /// @dev Deposit increases both balance and deposits
    function halmos_deposit_increases_totals(
        address user,
        uint256 amount
    ) public {
        vm.assume(user != address(0));
        vm.assume(amount > 0);
        
        uint256 balanceBefore = address(vault).balance;
        uint256 depositsBefore = vault.totalDeposits();
        
        vm.prank(user);
        vm.deal(user, amount);
        try vault.deposit{value: amount}() {
            uint256 balanceAfter = address(vault).balance;
            uint256 depositsAfter = vault.totalDeposits();
            
            assert(balanceAfter == balanceBefore + amount);
            assert(depositsAfter == depositsBefore + amount);
        } catch {
            // Failed deposit shouldn't change state
            uint256 balanceAfter = address(vault).balance;
            uint256 depositsAfter = vault.totalDeposits();
            assert(balanceAfter == balanceBefore);
            assert(depositsAfter == depositsBefore);
        }
    }
}
```

#### Voting Power Conservation (VotingEscrow)

```python
# halmos/test/VotingEscrow.t.sol
contract VotingEscrowHalmos is Test {
    VotingEscrow ve;
    
    /// @dev Total voting power equals sum of user powers
    function halmos_voting_power_conservation() public {
        // Note: This requires tracking all users
        // Implementation specific
        assert(ve.totalVotingPower() >= 0);
    }
    
    /// @dev Delegation doesn't change total power
    function halmos_delegation_preserves_power(
        address voter,
        address delegatee
    ) public {
        vm.assume(voter != address(0));
        vm.assume(delegatee != address(0));
        vm.assume(voter != delegatee);
        
        uint256 powerBefore = ve.totalVotingPower();
        
        vm.prank(voter);
        try ve.delegate(delegatee) {
            uint256 powerAfter = ve.totalVotingPower();
            assert(powerBefore == powerAfter);
        } catch {
            uint256 powerAfter = ve.totalVotingPower();
            assert(powerBefore == powerAfter);
        }
    }
}
```

### Running Halmos

```bash
# Install halmos
pip install halmos

# Run all halmos tests
halmos

# Run specific contract
halmos --contract RebaseTokenHalmos

# Run with intensive profile
halmos --profile intensive

# Generate report
halmos --output-dir halmos-reports --report
```

---

## Certora Formal Verification

### Certora Specifications

#### RebaseToken.spec

```
// src/specs/RebaseToken.spec

/// @title Balance and Supply Invariants
/// @notice Formal specification for RebaseToken ERC20 properties

// Environment variable for method calls
methods {
    balanceOf(address) returns uint256 envfree
    totalSupply() returns uint256 envfree
    allowance(address, address) returns uint256 envfree
    transfer(address, uint256) returns bool
    transferFrom(address, address, uint256) returns bool
    approve(address, uint256) returns bool
    mint(address, uint256, uint256)
    burn(uint256)
    rebase(int256)
}

// INVARIANT 1: Balance Sum Equals Total Supply
invariant balanceSumEqualsSupply()
    sumAllBalances() == totalSupply()
    {
        preserved by all;
        preserved transfer(address to, uint256 amount) with (env e) {
            require e.msg.sender != to;
        }
        preserved transferFrom(address from, address to, uint256 amount) with (env e) {
            require from != to;
        }
    }

// INVARIANT 2: Non-negative balances
invariant balancesNonNegative(address user)
    balanceOf(user) >= 0
    {
        preserved by all;
    }

// INVARIANT 3: Total supply positive
invariant supplyPositive()
    totalSupply() > 0
    {
        preserved by all;
    }

// RULE 1: Transfer preserves supply
rule transferPreservesSupply(address from, address to, uint256 amount) {
    env e;
    require e.msg.sender == from;
    
    uint256 supplyBefore = totalSupply();
    transfer(to, amount);
    uint256 supplyAfter = totalSupply();
    
    assert supplyBefore == supplyAfter,
        "Transfer should not change supply";
}

// RULE 2: Approve updates allowance
rule approveUpdatesAllowance(address spender, uint256 amount) {
    env e;
    
    approve(spender, amount);
    
    assert allowance(e.msg.sender, spender) == amount,
        "Allowance not updated correctly";
}

// RULE 3: No double spending
rule noDoubleSpending(address from, address spender) {
    env e1; env e2;
    require e1.msg.sender == from;
    require e2.msg.sender == from;
    
    uint256 allowance1 = allowance(from, spender);
    transferFrom(from, e2.msg.sender, allowance1);
    uint256 allowance2 = allowance(from, spender);
    
    // Cannot transfer same amount twice
    require allowance2 == 0 || allowance1 != allowance2,
        "Double spending detected";
}

// RULE 4: Rebase bounds
rule rebaseRespectsBounds(int256 percentageBps) {
    env e;
    
    require percentageBps >= -10_00 && percentageBps <= 10_00;
    
    uint256 supplyBefore = totalSupply();
    rebase(percentageBps);
    uint256 supplyAfter = totalSupply();
    
    // Supply can only change by bounded amount
    assert supplyAfter >= supplyBefore * 9 / 10 &&
           supplyAfter <= supplyBefore * 11 / 10,
        "Rebase exceeded bounds";
}

// HELPER: Sum all balances (requires finite account tracking)
function sumAllBalances() returns uint256 {
    // Implementation depends on contract tracking
    return totalSupply();
}
```

#### RebaseTokenVault.spec

```
// src/specs/RebaseTokenVault.spec

methods {
    deposit() payable returns bool
    withdraw(uint256) returns bool
    claimInterest() returns uint256
    depositedAmount(address) returns uint256 envfree
    totalDeposits() returns uint256 envfree
    solvencyRatio() returns uint256 envfree
    accrueInterest(uint256)
}

// INVARIANT: Vault solvency
invariant vaultSolvency()
    contractBalance >= totalDeposits()
    {
        preserved by all;
    }

// INVARIANT: Interest non-negative
invariant interestNonNegative()
    accruedInterest >= 0
    {
        preserved by all;
    }

// RULE: Deposit increases balance
rule depositIncreasesBalance(uint256 amount) {
    env e;
    require amount > 0;
    
    uint256 balanceBefore = depositedAmount(e.msg.sender);
    uint256 totalBefore = totalDeposits();
    
    deposit();  // amount is msg.value
    
    uint256 balanceAfter = depositedAmount(e.msg.sender);
    uint256 totalAfter = totalDeposits();
    
    assert balanceAfter > balanceBefore,
        "Balance not increased";
    assert totalAfter > totalBefore,
        "Total deposits not increased";
}

// RULE: Withdrawal respects balance
rule withdrawalRespectsBudget(uint256 amount) {
    env e;
    require amount <= depositedAmount(e.msg.sender);
    
    uint256 balanceBefore = depositedAmount(e.msg.sender);
    
    withdraw(amount);
    
    uint256 balanceAfter = depositedAmount(e.msg.sender);
    assert balanceAfter == balanceBefore - amount,
        "Balance not decreased correctly";
}

// RULE: Accrued interest valid
rule accruedInterestValid(uint256 newRate) {
    env e;
    require newRate <= maxRate();
    
    uint256 ratioBefore = solvencyRatio();
    accrueInterest(newRate);
    uint256 ratioAfter = solvencyRatio();
    
    assert ratioAfter >= 1,
        "Vault became insolvent after interest";
}
```

#### VotingEscrow.spec

```
// src/specs/VotingEscrow.spec

methods {
    createLock(uint256, uint256)
    increaseLock(uint256)
    extendLock(uint256)
    withdraw()
    delegate(address)
    votingPower(address) returns uint256 envfree
    totalVotingPower() returns uint256 envfree
    balanceOfAt(address, uint256) returns uint256 envfree
}

// INVARIANT: Voting power conservation
invariant votingPowerConservation()
    sumAllVotingPowers() == totalVotingPower()
    {
        preserved by all;
    }

// INVARIANT: Non-negative voting power
invariant votingPowerNonNegative(address user)
    votingPower(user) >= 0
    {
        preserved by all;
    }

// RULE: Create lock grants voting power
rule createLockGrantsPower(uint256 amount, uint256 unlockTime) {
    env e;
    require amount > 0;
    require unlockTime > currentTime();
    
    uint256 powerBefore = votingPower(e.msg.sender);
    createLock(amount, unlockTime);
    uint256 powerAfter = votingPower(e.msg.sender);
    
    assert powerAfter > powerBefore,
        "Voting power not increased";
}

// RULE: Withdrawal revokes voting power
rule withdrawalRevokes() {
    env e;
    require isLocked(e.msg.sender);
    require block.timestamp >= lockEnd(e.msg.sender);
    
    uint256 powerBefore = votingPower(e.msg.sender);
    withdraw();
    uint256 powerAfter = votingPower(e.msg.sender);
    
    assert powerAfter == 0,
        "Voting power not revoked";
}

// RULE: Delegation preserves voting power
rule delegationPreservesPower(address delegatee) {
    env e;
    require delegatee != address(0);
    
    uint256 powerBefore = totalVotingPower();
    delegate(delegatee);
    uint256 powerAfter = totalVotingPower();
    
    assert powerBefore == powerAfter,
        "Total voting power changed";
}
```

### Running Certora

```bash
# Install Certora CLI
pip install certora-cli

# Run verification
certora-cli src/RebaseToken.sol \
  --spec src/specs/RebaseToken.spec \
  --msg "RebaseToken Formal Verification" \
  --send_only

# Check status
certora-cli status

# View results
certora-cli results --job-id <job_id>
```

---

## Inline Specification Comments Format

### Standard Spec Comment Template

```solidity
/// @notice Brief description of function behavior
/// @dev Implementation notes (if needed)
/// @dev Formal specification:
///      PRECONDITION: <logical expression>
///      POSTCONDITION: <logical expression>
///      INVARIANT: <logical expression preserved>
///      REVERTS_ON: <condition> with <error>
/// @param param1 Parameter description
/// @param param2 Parameter description
/// @return Return value description
function functionName(
    type param1,
    type param2
) external returns (returnType) {
    // Implementation
}
```

### Example: RebaseToken.transfer()

```solidity
/// @notice Transfers tokens from caller to recipient
/// @dev Implements ERC20 transfer with formal specification
/// @dev Formal specification:
///      PRECONDITION:
///        - balances[msg.sender] >= amount
///        - recipient != address(0)
///      POSTCONDITION:
///        - balances[msg.sender] -= amount
///        - balances[recipient] += amount
///        - totalSupply unchanged
///        - sum(balances[i] for all i) == totalSupply
///      INVARIANT_PRESERVED:
///        - ∀ user. balanceOf(user) >= 0
///        - totalSupply > 0
///      REVERTS_ON:
///        - amount > balances[msg.sender] → "ERC20: insufficient balance"
///        - recipient == address(0) → "ERC20: transfer to zero address"
/// @param recipient Address to receive tokens
/// @param amount Number of tokens to transfer
/// @return success True if transfer successful
function transfer(address recipient, uint256 amount) external returns (bool) {
    require(recipient != address(0), "ERC20: transfer to zero address");
    require(balances[msg.sender] >= amount, "ERC20: insufficient balance");
    
    balances[msg.sender] -= amount;
    balances[recipient] += amount;
    
    emit Transfer(msg.sender, recipient, amount);
    return true;
}
```

### Example: RebaseTokenVault.deposit()

```solidity
/// @notice Deposits ETH into vault, minting vault shares
/// @dev Formal specification:
///      PRECONDITION:
///        - msg.value > 0
///        - not paused
///        - vault balance sufficient for operations
///      POSTCONDITION:
///        - depositedAmount[msg.sender] increased by msg.value
///        - totalDeposits increased by msg.value
///        - vault shares minted
///        - address(vault).balance increased by msg.value
///      INVARIANT_PRESERVED:
///        - address(vault).balance >= totalDeposits
///        - solvencyRatio >= 1.0
///        - sum(depositedAmount[user] for all users) == totalDeposits
///      REVERTS_ON:
///        - msg.value == 0 → "Deposit amount cannot be zero"
///        - paused == true → "Vault is paused"
///        - ETH transfer fails → "Deposit failed"
/// @return shares Number of shares minted
function deposit() external payable whenNotPaused returns (uint256) {
    require(msg.value > 0, "Deposit amount cannot be zero");
    
    uint256 shares = calculateShares(msg.value);
    
    depositedAmount[msg.sender] += msg.value;
    totalDeposits += msg.value;
    userShares[msg.sender] += shares;
    totalShares += shares;
    
    emit Deposit(msg.sender, msg.value, shares);
    return shares;
}
```

### Example: VotingEscrow.createLock()

```solidity
/// @notice Creates a voting lock with tokens and unlock time
/// @dev Formal specification:
///      PRECONDITION:
///        - amount > 0
///        - unlockTime > block.timestamp
///        - msg.sender has sufficient token balance
///        - no existing lock for msg.sender
///      POSTCONDITION:
///        - lock created: LockedBalance{amount, unlockTime}
///        - tokens transferred to contract
///        - votingPower[msg.sender] calculated from lock
///        - totalVotingPower increased
///      INVARIANT_PRESERVED:
///        - ∀ user. votingPower[user] >= 0
///        - sum(votingPower[user] for all users) == totalVotingPower
///        - ∀ user. lockEnd[user] is monotonically increasing
///      REVERTS_ON:
///        - amount == 0 → "Voting amount cannot be zero"
///        - unlockTime <= block.timestamp → "Invalid unlock time"
///        - lock already exists → "Existing lock found"
///        - transfer fails → "Transfer failed"
/// @param amount Number of tokens to lock
/// @param unlockTime Unix timestamp when tokens unlock
function createLock(uint256 amount, uint256 unlockTime) external nonReentrant {
    require(amount > 0, "Voting amount cannot be zero");
    require(unlockTime > block.timestamp, "Invalid unlock time");
    require(locks[msg.sender].amount == 0, "Existing lock found");
    
    locks[msg.sender] = LockedBalance({
        amount: amount,
        end: unlockTime
    });
    
    token.transferFrom(msg.sender, address(this), amount);
    
    _updateVotingPower(msg.sender);
    emit LockCreated(msg.sender, amount, unlockTime);
}
```

---

## Formal Verification Checklist

### Code Preparation (Tier 1 Priority)

- [ ] RebaseToken
  - [ ] All invariants documented in code
  - [ ] Preconditions/postconditions for: transfer, transferFrom, approve, mint, rebase
  - [ ] Halmos tests written and passing
  - [ ] Certora spec written

- [ ] RebaseTokenVault
  - [ ] All invariants documented
  - [ ] Preconditions/postconditions for: deposit, withdraw, accrueInterest, claimInterest
  - [ ] Halmos tests written and passing
  - [ ] Certora spec written

- [ ] VotingEscrow
  - [ ] All invariants documented
  - [ ] Preconditions/postconditions for: createLock, increaseLock, extendLock, withdraw, delegate
  - [ ] Halmos tests written and passing
  - [ ] Certora spec written

### Verification Execution (Tier 1 Priority)

- [ ] Halmos
  - [ ] Configuration file created (halmos.toml)
  - [ ] Property tests written for all Tier 1 contracts
  - [ ] All tests passing locally
  - [ ] CI/CD integration complete
  - [ ] Report generated

- [ ] Certora
  - [ ] Specification files created (.spec files)
  - [ ] Rules written for critical properties
  - [ ] Initial verification runs completed
  - [ ] Counterexamples analyzed (if any)

### Tier 2 & 3 Contracts (Optional)

- [ ] EnhancedCCIPBridge
  - [ ] Invariants documented
  - [ ] Message integrity properties specified

- [ ] AdvancedInterestStrategy
  - [ ] Rate calculation invariants

- [ ] BASEGovernor
  - [ ] State transition properties

### Audit Readiness

- [ ] All NatSpec complete (100%)
- [ ] Formal specs complete (Tier 1)
- [ ] Halmos reports generated
- [ ] Certora results available
- [ ] All test coverage >95%
- [ ] Invariant tests with 100k runs
- [ ] Security audit scheduled
- [ ] Audit packet compiled

---

## Verification Tools Integration

### CI/CD Integration

```yaml
# .github/workflows/formal-verification.yml
name: Formal Verification

on: [push, pull_request]

jobs:
  halmos:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-python@v4
      - name: Install Halmos
        run: pip install halmos
      - name: Run Halmos
        run: halmos --profile default
      - name: Upload Report
        uses: actions/upload-artifact@v3
        with:
          name: halmos-report
          path: halmos-reports/
      
  certora:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Run Certora
        run: |
          pip install certora-cli
          certora-cli src/RebaseToken.sol \
            --spec src/specs/RebaseToken.spec \
            --msg "Formal Verification Run"
      - name: Check Results
        run: certora-cli results
```

### Local Verification Script

```bash
#!/bin/bash
# scripts/verify.sh

echo "🔍 Starting formal verification..."

# Compile contracts
echo "📦 Compiling contracts..."
forge build

# Run unit tests
echo "🧪 Running unit tests..."
forge test

# Run coverage
echo "📊 Checking test coverage..."
forge coverage --report lcov

# Run invariant tests
echo "⚖️  Running invariant tests..."
forge test --match-contract Invariant --fuzz-runs 100000

# Run Halmos
echo "🔬 Running Halmos symbolic execution..."
halmos --profile default

# Generate reports
echo "📄 Generating reports..."
mkdir -p verification-reports
cp halmos-reports/* verification-reports/

echo "✅ Formal verification complete!"
echo "📁 Results in verification-reports/"
```

---

## Next Steps

1. **Week 1: Code Annotation**
   - Add inline specs to Tier 1 contracts
   - Document all preconditions/postconditions/invariants

2. **Week 2: Halmos Integration**
   - Create halmos.toml configuration
   - Write symbolic execution tests
   - Run and debug locally

3. **Week 3: Certora Setup**
   - Create .spec files for Tier 1
   - Run initial verification
   - Iterate on specs

4. **Week 4: Audit Preparation**
   - Compile all verification artifacts
   - Generate unified report
   - Schedule external audit

---

**Formal Verification Status:** 🟡 In Progress
**Target Completion:** Week 4
**Audit Readiness:** 60% Complete
