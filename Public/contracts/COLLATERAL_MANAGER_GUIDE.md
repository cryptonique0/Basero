# Collateral Manager - Advanced Features Guide

## Overview
The collateral manager now includes a comprehensive feature set for production DeFi use:

## Feature Set

### 1. **Liquidation Mechanism**
- Anyone can liquidate unhealthy positions when health factor < 1.0
- Liquidators receive seized collateral
- Function: `liquidate-collateral`

### 2. **Fee System**
- Configurable deposit, withdrawal, and borrow fees (max 10%)
- Fee collection and claiming by designated recipient
- Functions: `set-deposit-fee`, `set-withdrawal-fee`, `set-borrow-fee`, `claim-collected-fees`

### 3. **Pause & Emergency Controls**
- Global pause for all operations
- Asset-level pause for specific collateral types
- Functions: `toggle-global-pause`, `toggle-asset-pause`

### 4. **Oracle Integration**
- External price feed support via trait
- Manual or automatic price refresh
- Functions: `set-price-oracle`, `refresh-price-from-oracle`
- Mock oracle available: `mock-price-oracle.clar`

### 5. **Rewards/Interest System**
- Per-asset reward rates (basis points)
- Time-based accrual on deposited collateral
- Functions: `set-reward-rate`, `claim-rewards`
- Query: `get-pending-rewards`

### 6. **Multi-Admin Support**
- Add/remove admin roles
- Functions: `add-admin`, `remove-admin`
- Query: `is-admin`

### 7. **Blacklist Management**
- User and asset blacklisting
- Functions: `blacklist-user`, `blacklist-asset`, `remove-user-blacklist`, `remove-asset-blacklist`
- Queries: `is-user-blacklisted`, `is-asset-blacklisted`

### 8. **Dynamic Collateral Parameters**
- Update LTV and liquidation thresholds
- Function: `update-collateral-params`

### 9. **Batch Operations**
- Batch deposits and withdrawals for gas efficiency
- Functions: `deposit-collateral-batch`, `withdraw-collateral-batch`

### 10. **Advanced Event Logging**
- On-chain event log storage
- Comprehensive tracking of all state changes
- Query: `get-event`

## Usage Examples

### Setting Up Oracle
```clarity
;; Deploy mock oracle
(contract-call? .mock-price-oracle set-price 'SP000000000000000000002Q6VF78.token-a u1500000) ;; $1.50

;; Configure collateral manager to use oracle
(contract-call? .collateral-manager set-price-oracle .mock-price-oracle)

;; Refresh price from oracle
(contract-call? .collateral-manager refresh-price-from-oracle 'SP000000000000000000002Q6VF78.token-a)
```

### Configuring Rewards
```clarity
;; Set 5% annual reward rate (500 basis points / 31536000 seconds)
(contract-call? .collateral-manager set-reward-rate 'SP000000000000000000002Q6VF78.token-a u15)

;; Check pending rewards
(contract-call? .collateral-manager get-pending-rewards tx-sender 'SP000000000000000000002Q6VF78.token-a)

;; Claim rewards
(contract-call? .collateral-manager claim-rewards 'SP000000000000000000002Q6VF78.token-a)
```

### Batch Operations
```clarity
;; Deposit multiple assets at once
(contract-call? .collateral-manager deposit-collateral-batch 
  (list 
    {asset: 'SP...token-a, amount: u1000000}
    {asset: 'SP...token-b, amount: u2000000}
  )
)
```

### Fee Management
```clarity
;; Set 0.3% deposit fee (30 basis points)
(contract-call? .collateral-manager set-deposit-fee u30)

;; Set fee recipient
(contract-call? .collateral-manager set-fee-recipient 'SP...treasury)

;; Claim collected fees
(contract-call? .collateral-manager claim-collected-fees)
```

### Emergency Controls
```clarity
;; Pause all operations
(contract-call? .collateral-manager toggle-global-pause)

;; Pause specific asset
(contract-call? .collateral-manager toggle-asset-pause 'SP...token-a)

;; Blacklist user
(contract-call? .collateral-manager blacklist-user 'SP...bad-actor)
```

## Security Considerations

1. **Owner Controls**: Most admin functions require CONTRACT-OWNER authorization
2. **Fee Limits**: Fees capped at 10% (MAX-FEE-BASIS-POINTS)
3. **Health Factor Checks**: Withdrawals blocked if health would drop below 1.0
4. **Pause Safety**: Global and asset-level emergency stops
5. **Blacklist Protection**: Prevent malicious actors from using the protocol

## Testing with Mock Oracle

The `mock-price-oracle.clar` contract provides:
- Manual price setting for any asset
- Batch price updates
- Simulated price feeds with random variation
- Full compatibility with collateral-manager's oracle trait

## Read-Only Queries

- `get-collateral-type`: Asset configuration
- `get-user-collateral`: User position details
- `get-health-factor`: Position safety metric
- `calculate-max-borrow`: Borrowing capacity
- `get-fee-config`: Current fee settings
- `get-pending-rewards`: Unclaimed rewards
- `is-paused-global`: Global pause status
- `is-asset-paused`: Asset-specific pause status
- `is-user-blacklisted`: User blacklist check
- `is-admin`: Admin role check

## Contract Architecture

```
collateral-manager.clar (main contract)
├── Multi-asset management
├── Price feeds (manual or oracle)
├── Deposit/withdraw with fees & health checks
├── Liquidation system
├── Rewards accrual
├── Admin & blacklist controls
├── Event logging
└── Batch operations

mock-price-oracle.clar (testing oracle)
├── Price storage
├── Batch updates
└── Simulated feeds
```

## Next Steps

1. **Deploy contracts** to testnet/mainnet
2. **Configure oracle** or use manual price updates
3. **Set initial parameters** (fees, LTV, liquidation thresholds)
4. **Add collateral types** with `add-collateral-type`
5. **Enable rewards** with `set-reward-rate` (optional)
6. **Monitor events** via `get-event` for auditing
