# Basero Security & Production Guide

## Table of Contents
1. [Security Architecture](#security-architecture)
2. [Access Control](#access-control)
3. [Reentrancy Protection](#reentrancy-protection)
4. [Integer Safety](#integer-safety)
5. [Emergency Procedures](#emergency-procedures)
6. [Upgrade Safety](#upgrade-safety)
7. [Production Checklist](#production-checklist)
8. [Incident Response](#incident-response)

---

## Security Architecture

### Defense in Depth

Basero implements multiple security layers:

```
┌─────────────────────────────────────────────┐
│  Layer 1: Access Control (RBAC)            │
│  - Owner, Governance, Pauser, Upgrader     │
└─────────────────────────────────────────────┘
           ↓
┌─────────────────────────────────────────────┐
│  Layer 2: Input Validation                 │
│  - Bounds checking, zero address checks    │
└─────────────────────────────────────────────┘
           ↓
┌─────────────────────────────────────────────┐
│  Layer 3: Business Logic Guards            │
│  - Reentrancy protection, rate limiting    │
└─────────────────────────────────────────────┘
           ↓
┌─────────────────────────────────────────────┐
│  Layer 4: Circuit Breakers                 │
│  - Pausable, emergency withdrawal          │
└─────────────────────────────────────────────┘
           ↓
┌─────────────────────────────────────────────┐
│  Layer 5: Upgrade Safety                   │
│  - Timelocks, storage layout validation    │
└─────────────────────────────────────────────┘
```

### Security Principles

1. **Least Privilege:** Roles have minimum necessary permissions
2. **Fail-Safe Defaults:** Secure by default, explicit opt-in
3. **Complete Mediation:** All actions checked on every invocation
4. **Open Design:** Security through correctness, not obscurity
5. **Separation of Privilege:** Multi-sig for critical operations
6. **Defense in Depth:** Multiple independent security layers

---

## Access Control

### Role-Based Access Control (RBAC)

Basero uses OpenZeppelin's AccessControl for granular permissions:

```solidity
// Core roles
bytes32 public constant ADMIN_ROLE = DEFAULT_ADMIN_ROLE;
bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
bytes32 public constant REBASE_ROLE = keccak256("REBASE_ROLE");

// Governance roles
bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
bytes32 public constant TIMELOCK_ADMIN_ROLE = keccak256("TIMELOCK_ADMIN_ROLE");

// Bridge roles
bytes32 public constant BRIDGE_ADMIN_ROLE = keccak256("BRIDGE_ADMIN_ROLE");
bytes32 public constant RATE_LIMIT_ADMIN_ROLE = keccak256("RATE_LIMIT_ADMIN_ROLE");
```

### Role Permission Matrix

| Role | RebaseToken | Vault | VotingEscrow | Governor | Bridge |
|------|-------------|-------|--------------|----------|--------|
| **ADMIN** | Grant/revoke roles | Grant/revoke roles | Grant/revoke roles | Configure | Configure |
| **PAUSER** | Pause/unpause | Pause/unpause | - | - | Pause/unpause |
| **UPGRADER** | Upgrade | Upgrade | Upgrade | - | Upgrade |
| **MINTER** | Mint tokens | - | - | - | Mint |
| **REBASE** | Trigger rebase | - | - | - | - |
| **PROPOSER** | - | - | - | Create proposals | - |
| **EXECUTOR** | - | - | - | Execute proposals | - |
| **BRIDGE_ADMIN** | - | - | - | - | Set routes, limits |
| **RATE_LIMIT_ADMIN** | - | - | - | - | Configure limits |

### Role Assignment Best Practices

#### Development Environment
```solidity
// Single EOA for testing (NOT for production!)
address deployer = msg.sender;
_grantRole(ADMIN_ROLE, deployer);
_grantRole(PAUSER_ROLE, deployer);
_grantRole(UPGRADER_ROLE, deployer);
```

#### Testnet Environment
```solidity
// Team multi-sig (3-of-5)
address teamMultiSig = 0x...;
_grantRole(ADMIN_ROLE, teamMultiSig);

// Individual team members for testing
_grantRole(PAUSER_ROLE, developer1);
_grantRole(PAUSER_ROLE, developer2);
```

#### Production Environment (Recommended)
```solidity
// DAO governance contract
address daoGovernor = address(governor);
_grantRole(ADMIN_ROLE, daoGovernor);

// Security team multi-sig (4-of-7)
address securityMultiSig = 0x...;
_grantRole(PAUSER_ROLE, securityMultiSig);

// Upgrade multi-sig (6-of-9, 48hr timelock)
address upgradeMultiSig = 0x...;
_grantRole(UPGRADER_ROLE, address(upgradeTimelock));

// Automated keeper (rate-limited)
address rebaseKeeper = 0x...;
_grantRole(REBASE_ROLE, rebaseKeeper);

// Revoke deployer admin
_revokeRole(ADMIN_ROLE, msg.sender);
```

### Access Control Security Checklist

- [ ] All privileged functions use `onlyRole()` modifier
- [ ] Admin role is transferred to governance/multi-sig
- [ ] No single EOA has multiple critical roles
- [ ] Role grant/revoke emits events and is monitored
- [ ] Emergency pause authority is separate from upgrade authority
- [ ] Deployer admin role is revoked after setup
- [ ] All role changes go through timelock (production)
- [ ] Role recovery procedure documented

### Critical Access Control Patterns

#### ✅ CORRECT: Role-based function protection
```solidity
function pause() external onlyRole(PAUSER_ROLE) {
    _pause();
}

function rebase(int256 percentage) external onlyRole(REBASE_ROLE) {
    require(percentage >= -10_00 && percentage <= 10_00, "Invalid rebase");
    _rebase(percentage);
}
```

#### ❌ INCORRECT: Owner-only (single point of failure)
```solidity
function pause() external onlyOwner {  // Bad: Single point of failure
    _pause();
}
```

#### ✅ CORRECT: Time-delayed critical operations
```solidity
function upgradeTo(address newImplementation) 
    external 
    onlyRole(UPGRADER_ROLE) 
{
    require(upgradeTimelock.isReady(newImplementation), "Timelock not ready");
    _upgradeTo(newImplementation);
}
```

---

## Reentrancy Protection

### Attack Surface Analysis

Basero's reentrancy risk points:

| Contract | Function | Risk | Mitigation |
|----------|----------|------|------------|
| RebaseToken | `transfer()` | 🟡 Medium | ReentrancyGuard |
| RebaseToken | `transferFrom()` | 🟡 Medium | ReentrancyGuard |
| RebaseTokenVault | `deposit()` | 🟢 Low | CEI pattern |
| RebaseTokenVault | `withdraw()` | 🔴 High | ReentrancyGuard |
| VotingEscrow | `withdraw()` | 🟡 Medium | ReentrancyGuard |
| CCIPBridge | `transferToChain()` | 🟡 Medium | ReentrancyGuard |
| Governor | `execute()` | 🔴 High | ReentrancyGuard |

### ReentrancyGuard Implementation

All Basero contracts inherit OpenZeppelin's `ReentrancyGuard`:

```solidity
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract RebaseTokenVault is ReentrancyGuard {
    function withdraw(uint256 amount) external nonReentrant {
        // Safe from reentrancy
        _withdraw(msg.sender, amount);
    }
}
```

### Checks-Effects-Interactions (CEI) Pattern

**✅ CORRECT: CEI pattern**
```solidity
function withdraw(uint256 amount) external nonReentrant {
    // CHECKS
    require(amount > 0, "Zero amount");
    require(depositedAmount[msg.sender] >= amount, "Insufficient balance");
    
    // EFFECTS
    depositedAmount[msg.sender] -= amount;
    totalDeposits -= amount;
    emit Withdrawal(msg.sender, amount);
    
    // INTERACTIONS
    (bool success, ) = msg.sender.call{value: amount}("");
    require(success, "Transfer failed");
}
```

**❌ INCORRECT: Interactions before effects**
```solidity
function withdraw(uint256 amount) external {
    require(depositedAmount[msg.sender] >= amount);
    
    // DANGEROUS: Interaction before state update
    (bool success, ) = msg.sender.call{value: amount}("");
    require(success, "Transfer failed");
    
    // Attacker can re-enter here and drain vault!
    depositedAmount[msg.sender] -= amount;
}
```

### Read-Only Reentrancy Protection

**Problem:** View functions can be called during reentrancy

**Example Attack:**
```solidity
// Attacker contract
contract Attacker {
    Vault public vault;
    
    receive() external payable {
        // Re-enter view function during withdrawal
        uint256 balance = vault.depositedAmount(address(this));
        // Use stale balance for flash loan or oracle manipulation
    }
}
```

**Solution 1: ReentrancyGuard on view functions**
```solidity
function depositedAmount(address user) 
    external 
    view 
    nonReentrantView  // Custom modifier
    returns (uint256) 
{
    return _depositedAmount[user];
}

modifier nonReentrantView() {
    require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
    _;
}
```

**Solution 2: Pull over Push**
```solidity
// Instead of pushing ETH to user (dangerous):
function withdraw(uint256 amount) external {
    // ... checks and effects ...
    payable(msg.sender).transfer(amount);  // Could reenter
}

// Pull pattern (safer):
function withdraw(uint256 amount) external {
    pendingWithdrawals[msg.sender] += amount;
    depositedAmount[msg.sender] -= amount;
}

function claim() external nonReentrant {
    uint256 amount = pendingWithdrawals[msg.sender];
    pendingWithdrawals[msg.sender] = 0;
    payable(msg.sender).transfer(amount);
}
```

### Reentrancy Testing

```solidity
// test/security/ReentrancyTest.t.sol
contract ReentrancyTest is Test {
    function testReentrancy_VaultWithdrawal() public {
        AttackerContract attacker = new AttackerContract(vault);
        
        // Attacker deposits
        attacker.deposit{value: 1 ether}();
        
        // Attacker tries to drain vault via reentrancy
        vm.expectRevert("ReentrancyGuard: reentrant call");
        attacker.attack();
        
        // Verify vault balance unchanged
        assertEq(address(vault).balance, 1 ether);
    }
}

contract AttackerContract {
    Vault public vault;
    uint256 public attackCount;
    
    receive() external payable {
        if (attackCount < 10) {
            attackCount++;
            vault.withdraw(0.1 ether);  // Attempt reentrant call
        }
    }
    
    function attack() external {
        vault.withdraw(0.1 ether);
    }
}
```

### Reentrancy Security Checklist

- [ ] All state-changing functions use `nonReentrant`
- [ ] CEI pattern followed everywhere
- [ ] No external calls before state updates
- [ ] Pull pattern used for ETH transfers
- [ ] View functions safe from read-only reentrancy
- [ ] Reentrancy tests for all withdrawal/transfer functions
- [ ] Cross-contract reentrancy considered (e.g., token callbacks)
- [ ] Flash loan reentrancy vectors analyzed

---

## Integer Safety

### Solidity 0.8+ Automatic Checks

Basero uses Solidity 0.8.24, which includes automatic overflow/underflow checks:

```solidity
uint256 max = type(uint256).max;
max + 1;  // Reverts with Panic(0x11) - arithmetic overflow
```

### When to Use `unchecked`

**✅ SAFE: Loop counters**
```solidity
for (uint256 i = 0; i < array.length;) {
    // ... process array[i] ...
    unchecked { ++i; }  // Safe: i bounded by array.length
}
```

**✅ SAFE: After explicit bounds check**
```solidity
function safeSubtract(uint256 a, uint256 b) public pure returns (uint256) {
    require(a >= b, "Underflow");
    unchecked {
        return a - b;  // Safe: already checked a >= b
    }
}
```

**❌ UNSAFE: User input without validation**
```solidity
function unsafeAdd(uint256 a, uint256 b) public pure returns (uint256) {
    unchecked {
        return a + b;  // DANGEROUS: Could overflow!
    }
}
```

### Storage Packing Integer Safety

**Problem:** Packed integers can overflow more easily

**Example:**
```solidity
struct PackedData {
    uint128 balance;     // Max: 3.4e38 wei = 340B ETH
    uint64 timestamp;    // Max: Year 292B
    uint32 count;        // Max: 4.3B
    uint32 rate;         // Max: 4.3B (basis points: 430M%)
}
```

**Safety Margins:**

| Type | Max Value | Basero Use Case | Safety Margin |
|------|-----------|-----------------|---------------|
| uint8 | 255 | Enum, small counter | None (exact fit) |
| uint16 | 65,535 | Basis points (up to 655.35%) | 65x (max rate 10%) |
| uint32 | 4.3B | Large counter | Good for counts |
| uint64 | 1.8e19 | Unix timestamp | 292B years |
| uint128 | 3.4e38 | Token amounts | 2.8 million ETH total supply |
| uint256 | 1.1e77 | Unlimited | No overflow risk |

**Recommended Checks:**
```solidity
function setInterestRate(uint256 newRate) external {
    require(newRate <= 10_00, "Rate too high");  // 10% max
    require(newRate <= type(uint16).max, "Overflow");  // Fit in uint16
    interestRate = uint16(newRate);
}
```

### Percentage Calculation Safety

**Problem:** Percentage calculations can overflow or lose precision

**❌ UNSAFE: Overflow risk**
```solidity
// If principal = type(uint256).max and rate = 100%
uint256 interest = principal * rate / 100;  // Overflows!
```

**✅ SAFE: Checked multiplication**
```solidity
function calculateInterest(uint256 principal, uint256 rateBps) 
    public 
    pure 
    returns (uint256) 
{
    // rateBps = basis points (10000 = 100%)
    require(rateBps <= 10_000, "Rate too high");
    
    // Use checked arithmetic (default in 0.8+)
    return (principal * rateBps) / 10_000;
}
```

**✅ SAFER: Fixed-point arithmetic**
```solidity
// Use 1e18 precision (like Solmate's FixedPointMathLib)
uint256 constant PRECISION = 1e18;

function calculateInterest(uint256 principal, uint256 rateWad) 
    public 
    pure 
    returns (uint256) 
{
    // rateWad = 0.05e18 for 5% rate
    require(rateWad <= PRECISION, "Rate too high");  // Max 100%
    
    return (principal * rateWad) / PRECISION;
}
```

### Rebase Percentage Safety

**Critical:** Rebase percentage must be bounded

```solidity
function rebase(int256 percentageBps) external onlyRole(REBASE_ROLE) {
    // Allow -10% to +10% rebase
    require(percentageBps >= -10_00, "Rebase too negative");
    require(percentageBps <= 10_00, "Rebase too positive");
    
    // Calculate new supply
    int256 currentSupply = int256(totalSupply());
    int256 delta = (currentSupply * percentageBps) / 10_000;
    
    // Ensure result is positive and fits in uint256
    int256 newSupply = currentSupply + delta;
    require(newSupply > 0, "Supply cannot be zero");
    require(newSupply <= int256(type(uint256).max), "Supply overflow");
    
    _totalSupply = uint256(newSupply);
}
```

### Integer Safety Checklist

- [ ] All arithmetic uses Solidity 0.8+ (automatic checks)
- [ ] `unchecked` only used for provably safe operations
- [ ] Packed integers have sufficient safety margins
- [ ] Percentage calculations use basis points (10000 = 100%)
- [ ] Rebase percentage bounded to ±10%
- [ ] Division before multiplication to prevent overflow
- [ ] Type conversions validated (uint256 → uint128, int256 → uint256)
- [ ] Fuzz testing for all arithmetic operations

---

## Emergency Procedures

### Circuit Breaker Pattern

Basero implements pausable contracts for emergency stops:

```solidity
import "@openzeppelin/contracts/security/Pausable.sol";

contract RebaseTokenVault is Pausable, ReentrancyGuard {
    function deposit() external payable whenNotPaused {
        // Normal operation
    }
    
    function withdraw(uint256 amount) external whenNotPaused nonReentrant {
        // Normal operation
    }
    
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }
    
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }
}
```

### Emergency Pause Triggers

Pause should be activated when:

| Severity | Condition | Response Time | Example |
|----------|-----------|---------------|---------|
| **P0** | Active exploit detected | Immediate | Reentrancy attack, price manipulation |
| **P0** | Vault insolvency (ratio < 1.0) | <5 minutes | Unexpected withdrawals exceed deposits |
| **P1** | Critical bug discovered | <15 minutes | Integer overflow, access control bypass |
| **P1** | Bridge failure (>100 ETH lost) | <15 minutes | CCIP failure, cross-chain desync |
| **P2** | Abnormal activity (>1000 ETH in 1 hour) | <1 hour | Whale dump, coordinated attack |

### Emergency Pause Procedure

```bash
# 1. Detect issue (automated monitoring)
curl -X POST https://alerts.basero.io/emergency \
  -d '{"severity":"P0","reason":"Vault insolvency detected"}'

# 2. Verify issue (security team)
cast call $VAULT "depositedAmount(address)" $USER
cast call $VAULT "totalDeposits()"

# 3. Pause affected contracts (multi-sig)
# Option A: Individual contract
cast send $VAULT "pause()" --private-key $PAUSER_KEY

# Option B: Global pause (if available)
cast send $PAUSE_CONTROLLER "pauseAll()" --from $MULTI_SIG

# 4. Notify community
echo "⚠️ Basero has been paused due to [REASON]. Funds are safe. 
Investigation underway. Updates: https://status.basero.io" \
  | post-to-discord

# 5. Investigate root cause
forge test --match-contract ExploitTest -vvvv
```

### Emergency Withdrawal

**Last Resort:** If contract is compromised and unrecoverable

```solidity
// Emergency withdrawal (use with extreme caution!)
contract RebaseTokenVault {
    address public emergencyRecoveryAddress;
    bool public emergencyMode;
    
    function activateEmergency() 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        require(!emergencyMode, "Already in emergency");
        emergencyMode = true;
        _pause();
        emit EmergencyActivated(block.timestamp);
    }
    
    function emergencyWithdrawAll(address to) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        require(emergencyMode, "Not in emergency");
        require(block.timestamp > emergencyActivationTime + 48 hours, "Timelock");
        
        uint256 balance = address(this).balance;
        (bool success, ) = to.call{value: balance}("");
        require(success, "Transfer failed");
        
        emit EmergencyWithdrawal(to, balance);
    }
}
```

**⚠️ WARNING:** Emergency withdrawal should:
- Require multi-sig (6-of-9 minimum)
- Have 48-hour timelock
- Be announced publicly before execution
- Include user refund plan

### Emergency Response Team

**On-Call Rotation:**
```
Week 1: Alice (Primary), Bob (Secondary), Carol (Tertiary)
Week 2: Bob (Primary), Carol (Secondary), Alice (Tertiary)
Week 3: Carol (Primary), Alice (Secondary), Bob (Tertiary)
```

**Contact Methods:**
- PagerDuty: Immediate alerts
- Signal: Encrypted group chat
- Emergency hotline: +1-XXX-XXX-XXXX

**Response Protocol:**
1. **0-5 min:** Primary acknowledges alert
2. **5-10 min:** Primary assesses severity
3. **10-15 min:** If P0/P1, pause contracts
4. **15-30 min:** Convene emergency team
5. **30-60 min:** Public communication
6. **1-6 hours:** Root cause analysis
7. **6-24 hours:** Fix development
8. **24-48 hours:** Testing and audit
9. **48+ hours:** Unpause with fix

---

## Upgrade Safety

### UUPS (Universal Upgradeable Proxy Standard)

Basero uses OpenZeppelin's UUPSUpgradeable:

```solidity
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract RebaseToken is UUPSUpgradeable {
    function _authorizeUpgrade(address newImplementation) 
        internal 
        override 
        onlyRole(UPGRADER_ROLE) 
    {
        // Additional checks can be added here
        require(newImplementation != address(0), "Invalid implementation");
    }
}
```

### Storage Layout Validation

**Critical:** Storage layout must remain compatible across upgrades

```solidity
// V1 Storage Layout
contract RebaseTokenV1 {
    uint256 private _totalSupply;    // Slot 0
    mapping(address => uint256) private _balances;  // Slot 1
    mapping(address => mapping(address => uint256)) private _allowances;  // Slot 2
}

// V2 Storage Layout (✅ SAFE: Append-only)
contract RebaseTokenV2 {
    uint256 private _totalSupply;    // Slot 0 (unchanged)
    mapping(address => uint256) private _balances;  // Slot 1 (unchanged)
    mapping(address => mapping(address => uint256)) private _allowances;  // Slot 2 (unchanged)
    uint256 private _sharesPerToken;  // Slot 3 (NEW - appended)
}

// V2 Storage Layout (❌ UNSAFE: Reordered)
contract RebaseTokenV2Bad {
    uint256 private _sharesPerToken;  // Slot 0 (WRONG! Was _totalSupply)
    uint256 private _totalSupply;     // Slot 1 (WRONG! Was _balances mapping)
    // Storage corruption! _totalSupply will read balances data!
}
```

### Automated Storage Layout Validation

Use Basero's `StorageLayoutValidator`:

```solidity
// test/StorageLayoutValidator.t.sol
function testUpgrade_V1toV2_StorageCompatibility() public {
    // Deploy V1
    RebaseTokenV1 v1 = new RebaseTokenV1();
    
    // Capture V1 storage layout
    string memory v1Layout = vm.serializeStorageLayout(address(v1));
    
    // Deploy V2
    RebaseTokenV2 v2 = new RebaseTokenV2();
    
    // Capture V2 storage layout
    string memory v2Layout = vm.serializeStorageLayout(address(v2));
    
    // Validate compatibility
    StorageLayoutValidator.validateUpgrade(v1Layout, v2Layout);
}
```

### Upgrade Timelock

**Critical operations require timelock:**

```solidity
contract UpgradeTimelock {
    uint256 public constant UPGRADE_DELAY = 48 hours;
    
    mapping(address => uint256) public upgradeScheduled;
    
    function scheduleUpgrade(address newImplementation) external onlyRole(UPGRADER_ROLE) {
        upgradeScheduled[newImplementation] = block.timestamp + UPGRADE_DELAY;
        emit UpgradeScheduled(newImplementation, upgradeScheduled[newImplementation]);
    }
    
    function executeUpgrade(address newImplementation) external onlyRole(UPGRADER_ROLE) {
        require(block.timestamp >= upgradeScheduled[newImplementation], "Timelock not expired");
        require(upgradeScheduled[newImplementation] != 0, "Upgrade not scheduled");
        
        delete upgradeScheduled[newImplementation];
        _upgradeTo(newImplementation);
        
        emit UpgradeExecuted(newImplementation);
    }
    
    function cancelUpgrade(address newImplementation) external onlyRole(ADMIN_ROLE) {
        delete upgradeScheduled[newImplementation];
        emit UpgradeCancelled(newImplementation);
    }
}
```

### Upgrade Testing Procedure

```bash
# 1. Deploy new implementation to testnet
forge script script/DeployV2.s.sol --rpc-url $SEPOLIA_RPC --broadcast

# 2. Validate storage layout
forge test --match-test testUpgrade_StorageCompatibility

# 3. Test state migration
forge test --match-test testUpgrade_StateMigration

# 4. Test all functionality with upgraded implementation
forge test --match-contract RebaseTokenV2Test

# 5. Run invariant tests
forge test --match-contract RebaseTokenInvariant --fuzz-runs 100000

# 6. Gas profiling
forge snapshot --diff

# 7. Schedule upgrade on mainnet (48hr timelock)
cast send $PROXY "scheduleUpgrade(address)" $NEW_IMPL --from $MULTI_SIG

# 8. Announce publicly
echo "Upgrade scheduled for block X (est. 48 hours)" | post-to-discord

# 9. Wait for timelock...

# 10. Execute upgrade
cast send $PROXY "executeUpgrade(address)" $NEW_IMPL --from $MULTI_SIG

# 11. Verify upgrade
cast call $PROXY "implementation()" 
forge verify-contract $NEW_IMPL RebaseTokenV2 --chain base
```

### Upgrade Safety Checklist

- [ ] Storage layout validated (no reordering or deletion)
- [ ] Initializer guarded with `initializer` modifier
- [ ] All tests passing with new implementation
- [ ] Invariant tests passing with 100k+ runs
- [ ] Gas costs reviewed (no unexpected increases)
- [ ] External audit completed for major upgrades
- [ ] 48-hour timelock before execution
- [ ] Community notification before upgrade
- [ ] Rollback plan prepared
- [ ] Post-upgrade monitoring for 24 hours

---

## Production Checklist

### Pre-Deployment

**Code Quality:**
- [ ] All contracts compiled without warnings
- [ ] Solidity version locked (0.8.24)
- [ ] Optimizer enabled (200 runs)
- [ ] No `console.log` or debug code
- [ ] All TODOs resolved
- [ ] Code style consistent (Prettier + Solhint)

**Testing:**
- [ ] Unit tests: 100% coverage
- [ ] Integration tests: All scenarios covered
- [ ] Fuzz tests: 100,000+ runs per function
- [ ] Invariant tests: 100,000+ runs per contract
- [ ] Gas profiling: Baseline captured
- [ ] Upgrade tests: Storage compatibility validated

**Security:**
- [ ] Reentrancy guards on all state-changing functions
- [ ] Access control on all privileged functions
- [ ] Input validation on all external functions
- [ ] Integer overflow protection (Solidity 0.8+)
- [ ] External audit completed (if mainnet)
- [ ] All audit findings resolved
- [ ] Bug bounty program launched

**Documentation:**
- [ ] NatSpec: 100% coverage
- [ ] Architecture diagram
- [ ] User guide
- [ ] Developer guide
- [ ] Deployment guide
- [ ] Incident response runbook

### Deployment

**Testnet (Base Sepolia):**
```bash
# 1. Deploy contracts
forge script script/Deploy.s.sol \
  --rpc-url $SEPOLIA_RPC \
  --broadcast \
  --verify

# 2. Configure access control
cast send $TOKEN "grantRole(bytes32,address)" $PAUSER_ROLE $MULTI_SIG
cast send $TOKEN "revokeRole(bytes32,address)" $ADMIN_ROLE $DEPLOYER

# 3. Verify deployment
forge verify-contract $TOKEN RebaseToken --chain base-sepolia

# 4. Test functionality
forge test --fork-url $SEPOLIA_RPC

# 5. Monitor for 1 week
```

**Mainnet (Base):**
```bash
# 1. Review deployment script
cat script/Deploy.s.sol

# 2. Dry-run deployment
forge script script/Deploy.s.sol \
  --rpc-url $BASE_RPC

# 3. Execute deployment (multi-sig)
forge script script/Deploy.s.sol \
  --rpc-url $BASE_RPC \
  --broadcast \
  --ledger

# 4. Verify on Basescan
forge verify-contract $TOKEN RebaseToken \
  --chain base \
  --constructor-args $(cast abi-encode "constructor(string,string)" "Basero" "BASE")

# 5. Configure roles (multi-sig)
# - Transfer admin to governance
# - Set pauser to security multi-sig
# - Set upgrader to timelock

# 6. Fund contracts
cast send $TOKEN --value 100ether

# 7. Initialize subgraph
graph deploy basero/vault --ipfs $IPFS_NODE --node $GRAPH_NODE

# 8. Start monitoring
pm2 start monitoring/prometheus.js
pm2 start monitoring/grafana.js
```

### Post-Deployment

**First 24 Hours:**
- [ ] Monitor all transactions
- [ ] Verify all events emitting correctly
- [ ] Check gas costs vs estimates
- [ ] Monitor for anomalous activity
- [ ] Verify subgraph indexing
- [ ] Test all user flows
- [ ] Verify access control
- [ ] On-call team ready

**First Week:**
- [ ] Daily security reviews
- [ ] Daily metrics review (TVL, users, gas)
- [ ] Community feedback monitoring
- [ ] Bug bounty active
- [ ] Incident response drills

**First Month:**
- [ ] Weekly security reviews
- [ ] Performance optimization based on real usage
- [ ] User feedback implementation
- [ ] Governance transition planning

### Monitoring Dashboard

```javascript
// monitoring/dashboard.js
const metrics = {
  // Protocol health
  tvl: await vault.totalDeposits(),
  activeUsers: await vault.userCount(),
  solvencyRatio: await vault.solvencyRatio(),
  
  // Security alerts
  pauseStatus: await token.paused(),
  adminChanges: await getLogs(token, 'RoleGranted'),
  largeTransfers: await getLogs(token, 'Transfer', { amount: { $gt: '100e18' } }),
  
  // Performance
  avgGasDeposit: await getAvgGas('deposit'),
  avgGasWithdrawal: await getAvgGas('withdraw'),
  
  // User activity
  depositsLast24h: await getEventCount('Deposit', 24 * 60 * 60),
  withdrawalsLast24h: await getEventCount('Withdrawal', 24 * 60 * 60),
};

// Alert if any metric is abnormal
if (metrics.solvencyRatio < 1.0) {
  alert('P0: Vault insolvency!');
}
if (metrics.pauseStatus) {
  alert('P1: Contracts paused!');
}
```

---

## Incident Response

### Incident Classification

| Priority | Response Time | Description | Examples |
|----------|---------------|-------------|----------|
| **P0 - Emergency** | 15 minutes | Active exploit, funds at risk | Reentrancy attack, vault drain |
| **P1 - Critical** | 30 minutes | Severe bug, no active exploit | Access control bypass, overflow bug |
| **P2 - High** | 2 hours | Important issue, limited impact | Gas inefficiency, UI bug |
| **P3 - Medium** | 24 hours | Non-critical issue | Documentation error, optimization opportunity |
| **P4 - Low** | Next release | Minor improvement | Code cleanup, refactoring |

### Incident Response Playbook

#### P0: Active Exploit

**Immediate Actions (0-15 minutes):**
1. **PAUSE ALL AFFECTED CONTRACTS**
   ```bash
   cast send $TOKEN "pause()" --from $PAUSER_MULTI_SIG
   cast send $VAULT "pause()" --from $PAUSER_MULTI_SIG
   cast send $BRIDGE "pause()" --from $PAUSER_MULTI_SIG
   ```

2. **Notify team via PagerDuty**
   ```bash
   curl -X POST https://events.pagerduty.com/v2/enqueue \
     -d '{"routing_key":"$KEY","event_action":"trigger",
          "payload":{"severity":"critical","summary":"Basero P0 incident"}}'
   ```

3. **Public communication**
   ```
   Twitter: "⚠️ Basero protocol paused due to security incident. 
            User funds are safe. Investigation underway. 
            Updates: https://status.basero.io"
   ```

**Investigation (15-60 minutes):**
4. **Identify attack vector**
   ```bash
   # Review recent transactions
   cast logs $TOKEN --from-block $(($CURRENT_BLOCK - 100))
   
   # Check attacker address
   cast balance $ATTACKER
   cast nonce $ATTACKER
   ```

5. **Quantify damage**
   ```bash
   # Check vault balance
   cast balance $VAULT
   
   # Compare to expected balance
   cast call $VAULT "totalDeposits()"
   ```

**Resolution (1-24 hours):**
6. **Develop fix**
   ```solidity
   // patch/FixReentrancy.sol
   function withdraw(uint256 amount) external nonReentrant {
       // Add reentrancy guard
   }
   ```

7. **Test fix extensively**
   ```bash
   forge test --match-test testExploit_Fixed
   forge test --match-contract Invariant --fuzz-runs 100000
   ```

8. **Emergency upgrade (if necessary)**
   ```bash
   # Deploy fix
   forge script script/EmergencyPatch.s.sol --rpc-url $BASE_RPC --broadcast
   
   # Upgrade immediately (bypass timelock for emergencies)
   cast send $PROXY "emergencyUpgrade(address)" $NEW_IMPL --from $ADMIN_MULTI_SIG
   ```

**Post-Incident (24+ hours):**
9. **Post-mortem report**
   - Timeline of events
   - Root cause analysis
   - Impact assessment (users affected, funds at risk)
   - Response evaluation
   - Lessons learned
   - Preventive measures

10. **User remediation (if applicable)**
    - Identify affected users
    - Calculate losses
    - Prepare compensation plan
    - Execute refunds

#### P1: Critical Bug (No Active Exploit)

**Response (0-30 minutes):**
1. **Assess risk:** Is pause necessary?
2. **If high risk:** Pause contracts
3. **Notify team:** Convene security review
4. **Develop fix:** Create patch

**Resolution (1-48 hours):**
5. **Test fix thoroughly**
6. **External review (if significant)**
7. **Schedule upgrade (with timelock)**
8. **Public announcement**
9. **Monitor post-fix**

### Communication Templates

#### P0 Initial Alert
```
🚨 URGENT: Basero Protocol Paused

We have paused the Basero protocol due to a detected security incident.

✅ User funds are safe
✅ Investigation underway
✅ Team is working on resolution

Updates will be posted every 30 minutes at:
- https://status.basero.io
- Twitter: @BaseroProtocol
- Discord: #announcements

DO NOT interact with contracts until we announce all-clear.
```

#### P0 All-Clear
```
✅ Basero Protocol Resumed

The security incident has been resolved. Key details:

• Issue: [Brief description]
• Impact: [# users affected, $ value]
• Fix: [Description of patch]
• Status: Contracts unpaused and operational

Full post-mortem: https://basero.io/incident-report-2024-XX

Thank you for your patience and support.
```

#### P1 Bug Disclosure
```
⚠️ Security Update: Basero Protocol

We have identified a critical bug in [COMPONENT].

• Severity: P1 (Critical, no active exploit)
• Impact: [Description]
• Status: Fix developed, upgrade scheduled for [DATE]
• User Action: None required

We will provide updates as the fix is deployed.

Details: https://basero.io/security-update-2024-XX
```

### Post-Incident Review

**Template:**
```markdown
# Incident Report: [TITLE]

## Summary
One-paragraph executive summary

## Timeline
- HH:MM: Event 1
- HH:MM: Event 2
...

## Impact
- Users affected: X
- Funds at risk: $Y
- Actual loss: $Z
- Downtime: N hours

## Root Cause
Technical explanation of what went wrong

## Response Evaluation
What went well / What could be improved

## Action Items
1. [ ] Immediate fix (Owner: Alice, Due: YYYY-MM-DD)
2. [ ] Enhanced monitoring (Owner: Bob, Due: YYYY-MM-DD)
3. [ ] Update docs (Owner: Carol, Due: YYYY-MM-DD)

## Lessons Learned
- Lesson 1
- Lesson 2

## Preventive Measures
- Measure 1
- Measure 2
```

---

## Conclusion

This security and production guide provides comprehensive procedures for:

✅ **Access Control:** RBAC with multi-sig and governance
✅ **Reentrancy Protection:** Guards, CEI pattern, testing
✅ **Integer Safety:** Overflow protection, safe unchecked, packing
✅ **Emergency Procedures:** Pause, recovery, team protocols
✅ **Upgrade Safety:** Storage layout, timelock, testing
✅ **Production Deployment:** Checklist, monitoring, post-deployment
✅ **Incident Response:** Classification, playbooks, communication

**Key Takeaways:**
1. **Defense in Depth:** Multiple security layers
2. **Fail-Safe Defaults:** Secure by default
3. **Test Everything:** 100k+ fuzz runs, invariant testing
4. **Monitor Continuously:** Real-time alerts, dashboards
5. **Respond Quickly:** 15-min P0 response time
6. **Learn and Improve:** Post-mortems, preventive measures

**Next Steps:**
1. Review this guide with the team
2. Conduct incident response drills
3. Set up monitoring infrastructure
4. Complete pre-deployment checklist
5. Execute testnet deployment
6. Monitor and optimize
7. Prepare for mainnet launch

**Security is not a one-time task - it's an ongoing commitment to users.**
