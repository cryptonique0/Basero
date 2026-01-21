# 📈 Advanced Interest Strategies Guide

Comprehensive guide to Basero's advanced interest rate mechanisms including variable rates, tiering, locking, and performance fees.

---

## 📋 Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Utilization-Based Rates](#utilization-based-rates)
4. [Tier-Based Rewards](#tier-based-rewards)
5. [Lock Mechanisms](#lock-mechanisms)
6. [Performance Fees](#performance-fees)
7. [Composite Rates](#composite-rates)
8. [Integration Guide](#integration-guide)
9. [Examples](#examples)
10. [Monitoring](#monitoring)

---

## Overview

Basero implements a **four-layer interest rate system** that rewards users based on:

1. **Vault Utilization** - Higher rates when vault is highly utilized
2. **Deposit Tier** - Larger deposits receive bonus rates
3. **Lock Duration** - Locked deposits get additional bonus
4. **Performance** - Excess returns above target are subject to performance fees

### Design Philosophy

✅ **Incentivizes Liquidity**: Higher rates when vault needs capital
✅ **Rewards Loyalty**: Larger and locked deposits get better rates
✅ **Alignment**: Performance fees align vault with users
✅ **Composable**: All factors stack together

---

## Architecture

### Contract: AdvancedInterestStrategy

**Location**: `src/AdvancedInterestStrategy.sol`
**Purpose**: Central configuration and calculation of all interest mechanics

```
AdvancedInterestStrategy
├─ Utilization-based rates (variable curve)
├─ Tier rewards (deposit-size based)
├─ Lock bonuses (duration-based)
├─ Performance fees (excess return capture)
└─ Composite rate calculation
```

### Integration Flow

```
RebaseTokenVault (accrues interest)
    │
    ├─ Calls: calculateUserRate(deposit, utilization)
    │
    ├─ AdvancedInterestStrategy
    │   ├─ 1. Get base rate from utilization
    │   ├─ 2. Add tier bonus
    │   ├─ 3. Add lock bonus
    │   └─ 4. Calculate performance fee
    │
    └─ Returns total rate (bps)
```

---

## Utilization-Based Rates

### Concept

Interest rates **increase as the vault fills up**, using a **piecewise linear curve**:

```
Rate
  │
  │            ╱╲
  │           ╱  ╲___
  │          ╱       (Max: 12%)
  │         ╱
  │        ╱ (Kink: 8%)
  │       ╱
  │      ╱
  │_____╱ (Zero: 2%)
  └─────────────── Utilization
     0%   80%   100%
```

### Rate Curve Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| **Kink** | 80% | Utilization where slope changes |
| **Rate at 0%** | 2% | Rate at zero utilization |
| **Rate at Kink** | 8% | Rate at 80% utilization |
| **Rate at 100%** | 12% | Rate at full utilization |

### Calculation

**Below Kink (0% → 80%)**:
```
rate = rateAtZero + (utilization / kink) * (rateAtKink - rateAtZero)
```

**Above Kink (80% → 100%)**:
```
rate = rateAtKink + ((utilization - kink) / (100% - kink)) * (rateAtMax - rateAtKink)
```

### Examples

```
Utilization 0%:    Rate = 2.00%
Utilization 40%:   Rate = 5.00% (interpolated)
Utilization 80%:   Rate = 8.00% (at kink)
Utilization 90%:   Rate = 10.00% (interpolated)
Utilization 100%:  Rate = 12.00% (max)
```

### Configuration

```solidity
// Set custom utilization curve
strategy.setUtilizationRates(
    7500,  // kink at 75%
    150,   // 1.5% at zero
    900,   // 9% at kink
    1400   // 14% at max
);
```

---

## Tier-Based Rewards

### Concept

**Larger deposits receive bonus rates**, incentivizing significant capital:

```
Tier System:
├─ Tier 0: <10 ETH → 0% bonus
├─ Tier 1: 10-100 ETH → 1% bonus
├─ Tier 2: 100-1000 ETH → 2% bonus
└─ Tier 3: 1000+ ETH → 3% bonus
```

### Example Rate with Tiers

```
Base rate (50% utilization):       5.00%
+ Tier bonus (50 ETH deposit):     1.00%
─────────────────────────────────
Total rate:                        6.00%
```

### Configuration

```solidity
// Add tier for 10 ETH deposits with 1% bonus
strategy.addTier(10 ether, 100); // 100 bps = 1%

// Add tier for 100 ETH deposits with 2% bonus
strategy.addTier(100 ether, 200); // 200 bps = 2%

// Add tier for 1000 ETH deposits with 3% bonus
strategy.addTier(1000 ether, 300); // 300 bps = 3%

// Remove tier (replaces with last, pops)
strategy.removeTier(0);
```

### Tier Lookup

```solidity
// Get tier bonus for a deposit amount
uint256 bonus = strategy.getTierBonus(500 ether);
// Returns: 200 (2% for 100-1000 ETH tier)

// Get all tiers
AdvancedInterestStrategy.TierConfig[] memory tiers = strategy.getTiers();
```

---

## Lock Mechanisms

### Concept

Users can **lock deposits for a period** to earn additional bonus rates:

```
Lock Duration     Bonus Rate
1 week - 1 year   1-5% additional

Example:
- Lock 100 ETH for 1 year → +5% bonus rate
- Lock 50 ETH for 6 months → +3% bonus rate
```

### How It Works

**1. Create Lock**
```solidity
strategy.lockDeposit(
    user,           // User address
    100 ether,      // Amount to lock
    52 weeks,       // Lock duration
    500             // 5% bonus rate (bps)
);
```

**2. Lock Active Period**
- User cannot withdraw locked amount
- User earns bonus rate on locked deposit
- Lock is tracked per user

**3. Lock Expires**
- After duration expires, owner calls `unlockDeposit()`
- Bonus rate no longer applies
- User can withdraw

**4. Optional: Extend Lock**
```solidity
strategy.extendLock(
    user,           // User with existing lock
    26 weeks        // Additional time
);
```

### Example Rate with Lock

```
Base rate (50% utilization):        5.00%
+ Tier bonus (100 ETH):             2.00%
+ Lock bonus (52 weeks):            5.00%
─────────────────────────────────
Total rate:                        12.00%
```

### Lock Status

```solidity
// Check lock status
(uint256 locked, uint256 endTime, bool isLocked) = strategy.getLockStatus(user);

// Get lock bonus (0 if not locked or expired)
uint256 bonus = strategy.getLockBonus(user);
```

---

## Performance Fees

### Concept

The vault takes a **fee on excess returns above a target**, aligning incentives:

```
If Target = 5% annual return:

Scenario A: Earn 5%
  Excess return:  0%
  Performance fee: 0% (no excess)
  User keeps: 5%

Scenario B: Earn 8%
  Excess return:  3% (8% - 5%)
  Performance fee: 0.6% (3% × 20%)
  User keeps: 7.4%

Scenario C: Earn 3%
  Excess return:  0% (below target)
  Performance fee: 0% (never negative)
  User keeps: 3%
```

### Configuration

```solidity
// Set performance fee config
strategy.setPerformanceFeeConfig(
    500,     // 5% target annual return (bps)
    2000,    // 20% fee on excess returns (bps)
    treasury // Fee recipient address
);
```

### Calculation

```solidity
// Calculate performance fee for user
(uint256 excess, uint256 fee) = strategy.calculatePerformanceFee(
    userBalance,       // Current balance
    originalDeposit,   // Initial deposit
    elapsedSeconds     // Time elapsed
);

// Example (1 year elapsed, 8% earned):
// excess = 3% of deposit
// fee = 0.6% of deposit (20% of excess)
```

### Fee Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| **Target Return** | 5% | Annual return threshold |
| **Performance Fee** | 20% | Fee on excess returns |
| **Recipient** | Treasury | Address receiving fees |

---

## Composite Rates

### Complete Rate Formula

```
Total User Rate = Base Rate + Tier Bonus + Lock Bonus

Where:
  Base Rate = calculateUtilizationRate(utilization%)
  Tier Bonus = getTierBonus(depositAmount)
  Lock Bonus = getLockBonus(user) if locked else 0
```

### Example: Maximum Rate

```
Scenario: High utilization, large locked deposit

Base (100% utilization):           12.00%
+ Tier (1000 ETH):                  3.00%
+ Lock (52 weeks):                  5.00%
────────────────────────────────
Total rate:                        20.00%
```

### Example: Minimum Rate

```
Scenario: Low utilization, small unlocked deposit

Base (0% utilization):              2.00%
+ Tier (<10 ETH):                   0.00%
+ Lock (not locked):                0.00%
────────────────────────────────
Total rate:                         2.00%
```

### Calculation

```solidity
// Calculate rate without lock check
uint256 rate = strategy.calculateUserRate(
    depositAmount,
    utilizationBps
);

// Calculate rate with lock check
uint256 rateWithLock = strategy.calculateUserRateWithLock(
    user,
    depositAmount,
    utilizationBps
);
```

---

## Integration Guide

### For Vault Developers

Integrate AdvancedInterestStrategy into RebaseTokenVault:

```solidity
// 1. Store strategy reference
AdvancedInterestStrategy public strategy;

// 2. In constructor
strategy = new AdvancedInterestStrategy(address(this));

// 3. When accruing interest
function _accrueInterest() internal {
    // Calculate vault utilization
    uint256 utilization = (totalDeposits * 10000) / maxDeposits;
    
    // Get rate for each user
    uint256 userRate = strategy.calculateUserRateWithLock(
        user,
        userDeposit,
        utilization
    );
    
    // Apply interest with calculated rate
    uint256 interest = (userDeposit * userRate) / 10000;
    rebaseToken.accrueInterest(interest);
}

// 4. Handle locks (optional)
function lockUserDeposit(uint256 amount, uint256 duration, uint256 bonus) 
    external 
    onlyGovernance 
{
    strategy.lockDeposit(msg.sender, amount, duration, bonus);
}
```

### For Frontend Integration

```javascript
// Get user's composite rate
const utilization = totalDeposits / maxDeposits;
const rate = await strategy.calculateUserRateWithLock(
    userAddress,
    userDeposit,
    Math.floor(utilization * 10000)
);

// Display to user
const apy = rate / 100; // Convert bps to percentage
console.log(`Your APY: ${apy}%`);

// Show breakdown
const baseRate = await strategy.calculateUtilizationRate(...);
const tierBonus = await strategy.getTierBonus(userDeposit);
const lockBonus = await strategy.getLockBonus(userAddress);

console.log(`
  Base:  ${baseRate / 100}%
  Tier:  ${tierBonus / 100}%
  Lock:  ${lockBonus / 100}%
  Total: ${apy}%
`);
```

---

## Examples

### Example 1: Small Deposit, No Lock

```
User deposits: 5 ETH
Vault utilization: 40%
Tier: None (< 10 ETH)
Lock: No

Base rate (40% util):  4.00%
Tier bonus:             0.00%
Lock bonus:             0.00%
────────────────────────
Total APY:              4.00%

Annual earnings on 5 ETH: 0.2 ETH
```

### Example 2: Medium Deposit, 6-Month Lock

```
User deposits: 50 ETH (locked 26 weeks)
Vault utilization: 60%
Tier: 1% (10-100 ETH)
Lock: 3% (26 weeks bonus)

Base rate (60% util):  5.50%
Tier bonus:            1.00%
Lock bonus:            3.00%
────────────────────────
Total APY:             9.50%

Annual earnings on 50 ETH: 4.75 ETH
```

### Example 3: Large Deposit, 1-Year Lock

```
User deposits: 500 ETH (locked 52 weeks)
Vault utilization: 80%
Tier: 2% (100-1000 ETH)
Lock: 5% (52 weeks bonus)

Base rate (80% util):  8.00%
Tier bonus:            2.00%
Lock bonus:            5.00%
────────────────────────
Total APY:             15.00%

Annual earnings on 500 ETH: 75 ETH
```

### Example 4: Performance Fee Impact

```
Scenario: 8% earned when 5% is target

Gross return: 8%
Target return: 5%
Excess: 3% (8% - 5%)
Performance fee: 20% × 3% = 0.6%

Net to user: 8% - 0.6% = 7.4%

On 100 ETH deposit:
  Gross: 8 ETH
  Fee: 0.6 ETH
  Net: 7.4 ETH
```

---

## Monitoring

### Dashboard Metrics

**Utilization Tracking**
```solidity
uint256 utilization = (totalDeposits * 10000) / maxDeposits;
// 0-10000 basis points (0-100%)

emit VaultUtilization(utilization);
```

**Rate Distribution**
```
Track per-user rates:
- Count users in each rate bucket
- Monitor average APY
- Track tier distribution
- Monitor lock participation
```

**Performance Fee Impact**
```
Monitor quarterly:
- Total excess returns earned
- Total performance fees collected
- Performance fee participation
- Distribution of benefits
```

### Governance Metrics

**Parameter Health**
```
Monthly review:
- Is utilization near kink? (Adjust if need more capital)
- Are tier bonuses competitive? (Compare with DeFi)
- Are locks popular? (Gauge user commitment)
- Are performance fees fair? (Benchmark returns)
```

---

## Safety Considerations

### Rate Constraints

✅ **Bounds Checking**: All rates between 0-100% (10000 bps)
✅ **Monotonicity**: Utilization rates always increasing
✅ **No Overflow**: 256-bit arithmetic with bounds
✅ **Time-based**: Performance fees scale with elapsed time

### Lock Safety

✅ **Duration Limits**: 1 week to 4 years maximum
✅ **Per-User Tracking**: One lock per user
✅ **Expiry Enforcement**: Cannot unlock before expiry
✅ **Atomic Updates**: Lock changes are atomic

### Performance Fee Safety

✅ **No Negative Fees**: Only charged on excess
✅ **Time-Scaled**: Accounts for partial years
✅ **Recipient Validation**: Fee address checked
✅ **Fee Cap**: Cannot exceed 100%

---

## Configuration Recommendations

### Mainnet

```solidity
// Conservative settings
Utilization rates:
  - Kink: 75%
  - At zero: 2%
  - At kink: 7%
  - At max: 10%

Tiers:
  - 10 ETH: +0.5%
  - 100 ETH: +1.0%
  - 1000 ETH: +1.5%

Lock bonus: 3-5% (1-year)
Performance fee: 20% on excess
Target return: 5% annual
```

### Testnet

```solidity
// Aggressive settings for testing
Utilization rates:
  - Kink: 80%
  - At zero: 1%
  - At kink: 5%
  - At max: 15%

Tiers:
  - 1 ETH: +1%
  - 10 ETH: +2%
  - 100 ETH: +3%

Lock bonus: 2-10% (variable)
Performance fee: 10-30% (configurable)
Target return: 3-8% annual
```

---

## Migration Path

### From Simple Rates to Advanced

```
Phase 1: Deploy AdvancedInterestStrategy
└─ No changes to vault yet
└─ Configuration only

Phase 2: Enable Utilization Rates
└─ Remove hardcoded rates
└─ Use calculateUtilizationRate()

Phase 3: Enable Tiers
└─ Add tier tracking
└─ Call getTierBonus()

Phase 4: Enable Locks
└─ Vault calls strategy.lockDeposit()
└─ Implement lock visualization

Phase 5: Enable Performance Fees
└─ Calculate and deduct fees
└─ Send to treasury
```

---

## FAQ

**Q: Can a user have multiple locks?**
A: No, one lock per user. Extend instead of creating new locks.

**Q: What if utilization drops during lock?**
A: Lock bonus persists. User still earns bonus until expiry.

**Q: Can performance fees be negative?**
A: No. Fee only charged if earnings exceed target.

**Q: How often should rates be recalculated?**
A: Per accrual period (daily recommended).

**Q: Can tiers be modified mid-year?**
A: Yes. Changes apply to new accruals only.

---

**Version**: 1.0
**Last Updated**: January 21, 2026
**Status**: ✅ Ready for Integration
