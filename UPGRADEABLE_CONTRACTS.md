# Basero Upgradeable Contracts - Technical Guide

## Overview

Phase 7 delivers production-grade upgradeability infrastructure using the UUPS (Universal Upgradeable Proxy Standard) pattern. This enables safe contract upgrades while preserving user state and maintaining security.

## Architecture

### UUPS Pattern Choice

**Why UUPS over Transparent Proxy:**
- **Gas Efficiency**: Upgrade logic in implementation (not proxy) saves ~2,500 gas per call
- **Smaller Proxy**: Simpler proxy bytecode reduces deployment costs by ~60%
- **Security**: Explicit upgrade authorization in implementation contract
- **Flexibility**: Each implementation controls its own upgrade logic

**Trade-offs:**
- Risk: Implementation must include upgrade function
- Mitigation: OpenZeppelin UUPSUpgradeable base with strict authorization

## Core Contracts

### 1. UpgradeableRebaseToken (330 LOC)

**Purpose**: UUPS upgradeable version of RebaseToken with storage safety

**Key Features:**
```solidity
// Inheritance chain
Initializable, UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable

// Storage Layout V1 (58 slots total)
string _name;
string _symbol;
uint8 _decimals;
uint256 _totalShares;
uint256 _totalSupply;
mapping(address => uint256) _shares;
mapping(address => uint256) _interestRates;
mapping(address => mapping(address => uint256)) _allowances;
uint256[50] __gap; // Reserved for future versions
```

**Critical Functions:**
- `initialize(name, symbol, owner)`: Replaces constructor for proxy pattern
- `_authorizeUpgrade(newImpl)`: Only owner can upgrade, emits event
- `getStorageLayoutHash()`: Returns keccak256 of layout for validation
- `getStorageSlots()`: Returns total slots (58) for collision detection

**Upgrade Safety:**
- 50-slot storage gap reserves space for future variables
- Storage layout validation before upgrades
- Version tracking for monitoring

### 2. UpgradeableRebaseTokenVault (260 LOC)

**Purpose**: UUPS upgradeable vault for ETH deposits

**Storage Layout V1 (52 slots total):**
```solidity
UpgradeableRebaseToken rebaseToken;
uint256 totalDeposited;
uint256 lastAccrualTime;
uint256 accrualPeriod;
uint256 dailyAccrualCap;
uint256 baseInterestRate;
uint256 rateDecrement;
uint256 decrementThreshold;
uint256 minimumRate;
mapping(address => uint256) userDeposits;
mapping(address => uint256) userInterestRates;
mapping(address => uint256) lastDepositTime;
uint256[40] __gap; // Reserved
```

**Key Features:**
- Pausable for emergency scenarios
- Interest rate system preserved
- Deposit/withdraw functionality unchanged
- 40-slot gap for future features

### 3. StorageLayoutValidator (180 LOC)

**Purpose**: Detect storage collisions and validate upgrades

**Core Functions:**

```solidity
// Register a contract version's storage layout
function registerLayout(
    address contractAddr,
    uint256 version,
    bytes32 layoutHash,
    uint256 totalSlots,
    string[] calldata variableNames
) external

// Validate upgrade safety
function validateUpgrade(
    address contractAddr,
    uint256 fromVersion,
    uint256 toVersion
) external returns (bool safe, string memory message)

// Check remaining gap space
function checkRemainingGap(
    address contractAddr,
    uint256 version,
    uint256 gapSize
) external view returns (uint256 remaining)
```

**Validation Rules:**
1. ✅ **Storage Growth**: New version can use MORE slots (consuming gap)
2. ❌ **Storage Shrink**: New version using FEWER slots = data loss risk
3. ⚠️ **Gap Warning**: Less than 10 remaining gap slots triggers warning
4. ✅ **Hash Match**: Identical layouts are always safe

**Usage Example:**
```solidity
// Register v1
validator.registerLayout(tokenProxy, 1, v1Hash, v1Slots, v1Vars);

// Register v2
validator.registerLayout(tokenProxy, 2, v2Hash, v2Slots, v2Vars);

// Validate before upgrade
(bool safe, string memory msg) = validator.validateUpgrade(tokenProxy, 1, 2);
require(safe, msg);
```

## Deployment & Upgrade Scripts

### DeployUpgradeable.s.sol (170 LOC)

**Deployment Flow:**
```bash
1. Deploy StorageLayoutValidator
2. Deploy token implementation (logic contract)
3. Deploy ERC1967Proxy with initialize calldata
4. Wrap proxy as UpgradeableRebaseToken interface
5. Deploy vault implementation
6. Deploy vault proxy with initialize calldata
7. Register storage layouts in validator
8. Transfer token ownership to vault
```

**Command:**
```bash
forge script script/DeployUpgradeable.s.sol:DeployUpgradeableSystem \
    --rpc-url $RPC_URL \
    --broadcast \
    --verify
```

**Environment Variables:**
```bash
PRIVATE_KEY=0x...
RPC_URL=https://sepolia.base.org
```

### UpgradeContracts.s.sol (155 LOC)

**Upgrade Flow:**
```bash
1. Load existing proxy addresses
2. Deploy new implementations
3. Register new storage layouts
4. Validate upgrade safety
5. Execute upgradeToAndCall() on proxies
6. Verify version increments
```

**Command:**
```bash
export TOKEN_PROXY=0x...
export VAULT_PROXY=0x...
export VALIDATOR=0x...

forge script script/UpgradeContracts.s.sol:UpgradeContract \
    --rpc-url $RPC_URL \
    --broadcast
```

**Safety Checks:**
- ✅ Storage layout validation before upgrade
- ✅ Authorization check (only owner)
- ✅ Version tracking
- ✅ Event emission for monitoring

## Testing (530 LOC, 50+ tests)

### Test Categories

**1. Initialization Tests (3)**
- `test_InitialState`: Verify proxy initialization
- `test_VaultInitialState`: Check vault setup
- `test_CannotReinitialize`: Prevent re-initialization attacks

**2. Basic Functionality (2)**
- `test_DepositAndWithdraw`: Core vault operations
- `test_TokenTransfer`: Token transfers work

**3. Authorization (3)**
- `test_OnlyOwnerCanUpgrade`: Non-owners blocked
- `test_OwnerCanUpgrade`: Owner upgrade succeeds
- `test_VaultUpgradeAuthorization`: Vault upgrade auth

**4. Storage Preservation (3)**
- `test_UpgradePreservesTokenBalances`: Balances intact after upgrade
- `test_UpgradePreservesVaultDeposits`: Deposits preserved
- `test_UpgradePreservesInterestRates`: Interest rates maintained

**5. Storage Validation (3)**
- `test_StorageLayoutRegistration`: Layout tracking works
- `test_ValidateUpgradeSafety`: Validation catches issues
- `test_DetectStorageCollision`: Collision detection

**6. Complex Scenarios (3)**
- `test_UpgradeWithActiveUsers`: Multiple users preserved
- `test_FunctionalityAfterUpgrade`: Features work post-upgrade
- `test_MultipleSequentialUpgrades`: Sequential upgrades safe

**7. Edge Cases (5+)**
- `test_PausePreservedAfterUpgrade`: State preservation
- `testFuzz_UpgradeWithRandomBalances`: Fuzz testing
- `test_UpgradeGasCost`: Gas optimization checks

### Running Tests

```bash
# All upgrade tests
forge test --match-contract UpgradeableSystemTest -vvv

# Specific category
forge test --match-test "test_UpgradePreserves" -vvv

# Gas report
forge test --gas-report --match-contract UpgradeableSystemTest

# Coverage
forge coverage --match-contract UpgradeableSystemTest
```

## Storage Layout Rules

### Critical Guidelines

1. **Never Reorder Variables**: Storage slots assigned by order
   ```solidity
   // ❌ WRONG - Reordering breaks storage
   uint256 a;  // slot 0
   uint256 b;  // slot 1
   // After upgrade: b, a  <- COLLISION!
   
   // ✅ RIGHT - Always append
   uint256 a;  // slot 0
   uint256 b;  // slot 1
   uint256 c;  // slot 2 (new in v2)
   ```

2. **Never Delete Variables**: Leave gaps instead
   ```solidity
   // ❌ WRONG - Deleting shifts everything
   uint256 a;
   // uint256 b; <- deleted
   uint256 c;  // Now in b's slot!
   
   // ✅ RIGHT - Leave deprecated variables
   uint256 a;
   uint256 b_DEPRECATED;
   uint256 c;
   ```

3. **Never Change Types**: Type changes break slot layout
   ```solidity
   // ❌ WRONG - Type change breaks storage
   uint256 value;  // slot 0
   // After upgrade:
   address value;  // Still slot 0 but wrong size!
   
   // ✅ RIGHT - Add new variable
   uint256 value;
   address newValue;  // slot 1
   ```

4. **Always Use Gap**: Reserve slots for future versions
   ```solidity
   // Storage V1
   uint256 value;
   uint256[50] __gap;
   
   // Storage V2 - consuming gap
   uint256 value;
   uint256 newValue;  // Uses gap slot
   uint256[49] __gap; // Reduce gap by 1
   ```

5. **Mappings & Arrays**: Never change key/value types
   ```solidity
   // ❌ WRONG - Changing mapping types
   mapping(address => uint256) balances;
   // After upgrade:
   mapping(address => uint128) balances; // BREAKS!
   
   // ✅ RIGHT - Add new mapping
   mapping(address => uint256) balances;
   mapping(address => uint128) newBalances;
   ```

### Gap Size Recommendations

| Contract Complexity | Gap Size | Rationale |
|---------------------|----------|-----------|
| Simple token | 50 slots | Standard OpenZeppelin |
| Complex DeFi | 100 slots | More features expected |
| Governance | 75 slots | Medium complexity |
| Bridge | 100 slots | High complexity |

## Upgrade Safety Checklist

### Pre-Upgrade

- [ ] Deploy new implementation to testnet
- [ ] Run full test suite (50+ tests passing)
- [ ] Register new storage layout in validator
- [ ] Validate upgrade with `validateUpgrade()`
- [ ] Check remaining gap slots (>10 recommended)
- [ ] Compare storage layout hashes
- [ ] Audit new implementation code
- [ ] Test on fork with production state
- [ ] Verify upgrade authorization works

### Upgrade Execution

- [ ] Pause contract if supported
- [ ] Backup current state (snapshot RPC)
- [ ] Execute `upgradeToAndCall()` from owner
- [ ] Verify new implementation address
- [ ] Check version increment
- [ ] Test basic functionality
- [ ] Unpause contract
- [ ] Monitor events for issues

### Post-Upgrade

- [ ] Verify storage preservation (spot checks)
- [ ] Test all major features
- [ ] Monitor for unexpected behavior
- [ ] Check gas costs unchanged
- [ ] Verify event emission
- [ ] Update documentation
- [ ] Notify users of upgrade
- [ ] Plan rollback if needed

## Rollback Procedures

### Quick Rollback

If upgrade fails, immediately rollback to previous implementation:

```solidity
// Emergency rollback
address previousImplementation = 0x...; // Saved before upgrade
token.upgradeToAndCall(previousImplementation, "");
```

### Rollback Checklist

1. **Identify Issue**: Log analysis, user reports
2. **Assess Impact**: Scope of data corruption
3. **Execute Rollback**: Use previous implementation address
4. **Verify Restoration**: Test critical functions
5. **Communicate**: Notify users, explain issue
6. **Root Cause**: Analyze what went wrong
7. **Fix & Redeploy**: Address issues, re-test

### Rollback Safety

- ✅ **Data Preserved**: Storage untouched during rollback
- ✅ **Fast**: Single transaction rollback
- ⚠️ **State Changes**: Any state changes during failed upgrade persist
- ❌ **Not Always Possible**: If storage corrupted, rollback won't help

## Gas Optimization

### Deployment Costs

| Contract | Deployment Gas | USD (50 gwei, $3000 ETH) |
|----------|---------------|--------------------------|
| Token Implementation | ~2.1M gas | ~$315 |
| Vault Implementation | ~2.8M gas | ~$420 |
| Storage Validator | ~1.2M gas | ~$180 |
| Token Proxy | ~450k gas | ~$67 |
| Vault Proxy | ~480k gas | ~$72 |
| **Total** | **~7M gas** | **~$1,050** |

### Upgrade Costs

| Operation | Gas Cost | USD (50 gwei, $3000 ETH) |
|-----------|----------|--------------------------|
| Deploy new impl | ~2.1M gas | ~$315 |
| upgradeToAndCall() | ~65k gas | ~$10 |
| Register layout | ~120k gas | ~$18 |
| Validate upgrade | ~45k gas | ~$7 |
| **Total Upgrade** | **~2.33M gas** | **~$350** |

### Operation Costs (Post-Upgrade)

UUPS proxies add ~2,000 gas per call vs non-upgradeable:

| Operation | Non-Upgradeable | UUPS | Overhead |
|-----------|----------------|------|----------|
| Deposit | ~85k gas | ~87k gas | +2k (+2.4%) |
| Withdraw | ~78k gas | ~80k gas | +2k (+2.6%) |
| Transfer | ~52k gas | ~54k gas | +2k (+3.8%) |
| Approve | ~45k gas | ~47k gas | +2k (+4.4%) |

**Analysis**: 2-4% overhead is acceptable for upgrade flexibility

## Advanced Topics

### Storage Gap Strategy

**Scenario**: Adding features over multiple upgrades

```solidity
// V1 - Initial (50 gap)
uint256 value;
uint256[50] __gap;

// V2 - Add 3 variables (47 gap)
uint256 value;
uint256 newValue1;
uint256 newValue2;
uint256 newValue3;
uint256[47] __gap;

// V3 - Add 2 more (45 gap)
uint256 value;
uint256 newValue1;
uint256 newValue2;
uint256 newValue3;
uint256 anotherValue1;
uint256 anotherValue2;
uint256[45] __gap;
```

**When Gap Runs Out:**
- Option 1: Deploy new contract, migrate users
- Option 2: Use mappings (single slot, infinite storage)
- Option 3: Namespaced storage (diamond pattern)

### Namespaced Storage (Advanced)

For infinite upgrades without gaps:

```solidity
library TokenStorage {
    bytes32 constant STORAGE_POSITION = keccak256("basero.token.storage");
    
    struct Layout {
        uint256 totalSupply;
        mapping(address => uint256) balances;
        // Add infinite fields without collisions
    }
    
    function getStorage() internal pure returns (Layout storage s) {
        bytes32 position = STORAGE_POSITION;
        assembly { s.slot := position }
    }
}
```

### Multi-Contract Upgrades

Upgrading multiple dependent contracts:

```bash
1. Deploy all new implementations
2. Validate all storage layouts
3. Pause all contracts
4. Upgrade in dependency order:
   a. Token (no dependencies)
   b. Vault (depends on Token)
   c. Governance (depends on Token)
5. Test integration
6. Unpause all contracts
```

## Security Considerations

### Attack Vectors

**1. Malicious Implementation**
- **Risk**: Owner deploys malicious upgrade stealing funds
- **Mitigation**: Timelock upgrades, multi-sig ownership, audits

**2. Storage Collision**
- **Risk**: New implementation corrupts storage
- **Mitigation**: StorageLayoutValidator, extensive testing

**3. Initialization Attack**
- **Risk**: Front-running proxy deployment to initialize
- **Mitigation**: Deploy + initialize in same transaction

**4. Self-Destruct**
- **Risk**: Implementation self-destructs, proxy unusable
- **Mitigation**: Don't use selfdestruct in implementations

**5. Delegatecall Exploits**
- **Risk**: Proxy delegatecalls to malicious contract
- **Mitigation**: Strict upgrade authorization, audit calls

### Best Practices

1. **Upgrade Governance**: Use timelock + multi-sig for upgrades
2. **Audit Everything**: Every implementation needs full audit
3. **Test Extensively**: 50+ tests covering all scenarios
4. **Monitor Upgrades**: Track events, alert on anomalies
5. **Plan Rollbacks**: Always have rollback plan ready
6. **Gradual Rollout**: Test on testnet, small mainnet subset, full rollout
7. **User Communication**: Notify users before/after upgrades

## Monitoring & Observability

### Events to Monitor

```solidity
// Upgrade events
event Upgraded(address indexed implementation, uint256 version);

// Storage validation
event LayoutRegistered(address indexed contractAddr, uint256 version, bytes32 layoutHash);
event ValidationPassed(address indexed contractAddr, uint256 fromVersion, uint256 toVersion);
event CollisionDetected(address indexed contractAddr, uint256 fromVersion, uint256 toVersion);
```

### Metrics to Track

- **Upgrade Count**: Total upgrades per contract
- **Version Numbers**: Current version of each contract
- **Gas Costs**: Upgrade transaction costs
- **Downtime**: Time contract paused for upgrade
- **Rollback Rate**: % upgrades requiring rollback
- **Storage Usage**: Remaining gap slots

### Dashboard Recommendations

```javascript
// Pseudocode for monitoring dashboard
const metrics = {
  currentVersion: await token.getVersion(),
  lastUpgrade: await getLastUpgradeTimestamp(),
  remainingGap: await calculateRemainingGap(),
  upgradeCount: await getUpgradeEventCount(),
  rollbackCount: await getRollbackEventCount()
};

// Alerts
if (metrics.remainingGap < 10) {
  alert("WARNING: Less than 10 gap slots remaining");
}
```

## Cost-Benefit Analysis

### Benefits

| Benefit | Value | Justification |
|---------|-------|---------------|
| **Bug Fixes** | High | Fix critical bugs without migration |
| **Feature Additions** | High | Add features to existing contracts |
| **Gas Optimization** | Medium | Optimize logic without redeployment |
| **Future-Proofing** | High | Adapt to protocol changes |
| **User Experience** | High | No migration = better UX |

### Costs

| Cost | Amount | Frequency |
|------|--------|-----------|
| **Deployment** | ~$1,050 | One-time |
| **Upgrade** | ~$350 | Per upgrade |
| **Gas Overhead** | +2-4% | Per transaction |
| **Complexity** | High | Ongoing |
| **Audit** | +20% cost | Per upgrade |

### Decision Matrix

**When to Use Upgradeable:**
- ✅ Long-term protocol (>1 year roadmap)
- ✅ Large user base (migration impractical)
- ✅ Active development (features expected)
- ✅ Regulatory risk (may need compliance updates)

**When to Skip Upgradeable:**
- ❌ Simple, stable protocol
- ❌ Short-term experiment
- ❌ Gas-sensitive application
- ❌ Immutability is feature (trust minimization)

## Appendix

### OpenZeppelin Dependencies

```json
{
  "@openzeppelin/contracts-upgradeable": "^5.0.0",
  "@openzeppelin/contracts": "^5.0.0"
}
```

### Solidity Version

```solidity
pragma solidity 0.8.24;
```

**Why 0.8.24:**
- Custom errors for gas efficiency
- Modern Solidity safety features
- OpenZeppelin 5.x compatibility

### Foundry Configuration

```toml
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
solc_version = "0.8.24"

[rpc_endpoints]
sepolia = "${SEPOLIA_RPC_URL}"
base_sepolia = "${BASE_SEPOLIA_RPC_URL}"

[etherscan]
base_sepolia = { key = "${BASESCAN_API_KEY}" }
```

### Further Reading

- [EIP-1967: Standard Proxy Storage Slots](https://eips.ethereum.org/EIPS/eip-1967)
- [EIP-1822: UUPS Proxies](https://eips.ethereum.org/EIPS/eip-1822)
- [OpenZeppelin Upgrades Guide](https://docs.openzeppelin.com/upgrades-plugins/1.x/)
- [Proxy Upgrade Pattern Security](https://blog.openzeppelin.com/proxy-patterns)

---

**Document Version**: 1.0  
**Last Updated**: Phase 7 Completion  
**Maintainer**: Basero Development Team
