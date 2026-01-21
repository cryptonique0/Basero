# Security Policy

## Reporting Security Vulnerabilities

If you discover a security vulnerability in Basero, please **do not** open a public GitHub issue. Instead:

1. **Email Report**: Send a detailed report to [security contact - to be configured]
2. **Include**: 
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested mitigation (if any)
3. **Confidentiality**: Reports will be handled confidentially until a fix is released

## Security Assumptions

### Core Security Model

1. **Token Supply Management**
   - `RebaseToken` uses a shares-based model to track user ownership fairly
   - Interest accrual is permissionless but capped by circuit breaker
   - Only vault and CCIP contracts can mint/burn tokens

2. **Vault Integrity**
   - Vault holds ETH backing on L1; all redeems draw from vault ETH
   - Rate tiers decrease with TVL to incentivize early deposits
   - Pause mechanisms allow guardian intervention
   - Reentrancy guards protect critical functions

3. **Cross-Chain Bridging**
   - User interest rates are preserved across chains (sent in CCIP message)
   - Per-chain fee configuration allows protocol revenue
   - Daily limits and per-send caps prevent bridge overflow
   - Receiver enforces stricter validation than sender

4. **Access Control**
   - Owner-only functions use OpenZeppelin's `Ownable`
   - Pause/unpause functions restricted to owner (potential guardian role)
   - Allowlist can be toggled and configured per address
   - Fee recipient separate from owner for flexibility

### Trust Boundaries

- **Chainlink CCIP**: Trusted to relay messages accurately and enforce chain selectors
- **Vault Owner**: Trusted to configure reasonable caps and fees
- **Fee Recipient**: Receives protocol fees (can be governance or treasury)
- **Users**: Assumed rational; can always redeem at fair share price

### Out of Scope / Known Risks

1. **Contract Upgrade Path**: Placeholder storage gap reserved but no proxy deployed yet
2. **Chainlink Router Failures**: If router becomes unavailable, bridging stops (not vault operations)
3. **Extreme Market Conditions**: Circuit breaker has fixed bounds; extreme rate scenarios uncovered
4. **Flash Loans**: Not explicitly mitigated (future consideration)
5. **Governance**: No decentralized governance for fee/cap changes (centralized owner)

## Threat Model

### High-Priority Threats

| Threat | Mitigation | Status |
|--------|-----------|--------|
| Reentrancy in emergency/sweep | `ReentrancyGuard` on critical functions | ✅ |
| Unauthorized pause | Owner-only access, event emissions | ✅ |
| Slippage on redeem | `redeemWithMinOut()` with user-specified floor | ✅ |
| Protocol fee leakage | Fee recipient minting preserves total supply | ✅ |
| Daily limit bypass | Day-bucket reset logic on each call | ✅ |
| Invalid rate bridging | Rate encoded in CCIP message + receiver validation | ✅ |

### Medium-Priority Threats

| Threat | Mitigation | Status |
|--------|-----------|--------|
| Integer overflow (accrual math) | Solidity 0.8.24 overflow checks | ✅ |
| Paused state lock-in | Manual unpause by owner | ✅ |
| Cap misconfiguration | Bounds checks (min deposit > 0, fees ≤ 10000) | ✅ |
| Bridged amount mismatch | Amount and interest rate both verified in receiver | ✅ |

### Low-Priority Threats

| Threat | Mitigation | Status |
|--------|-----------|--------|
| Timestamp manipulation | Only used for daily resets (not precision-critical) | ✅ |
| Permit vulnerabilities | No permit functions implemented | ✅ |
| Storage collision | Fixed layout, storage gap reserved | ✅ |

## Incident Response

### If a vulnerability is discovered:

1. **Immediate Actions**
   - Pause affected functionality (`pauseDeposits()`, `pauseRedeems()`, `pauseBridging()`)
   - Review logs and transaction history
   - Notify affected users if funds are at risk

2. **Investigation**
   - Root cause analysis
   - Scope of affected transactions
   - Potential financial impact

3. **Remediation**
   - Deploy hotfix if possible
   - Enable emergency withdraw if necessary
   - Communicate timeline and recovery plan

4. **Post-Mortem**
   - Document lessons learned
   - Update security model and assumptions
   - Implement additional safeguards

## Monitoring Checklist

- [ ] Monitor vault TVL for anomalies
- [ ] Track interest accrual patterns for circuit breaker hits
- [ ] Check daily bridge limits for abuse attempts
- [ ] Review fee recipient balance growth (anti-skimming)
- [ ] Audit allowlist changes in logs
- [ ] Track pause event frequency
- [ ] Monitor failed transactions and error patterns

## Code Review Practices

- All changes to core logic require security review
- Arithmetic operations checked for overflow/underflow
- Reentrancy guards verified on state-modifying functions
- Event emission for critical actions
- Comprehensive test coverage (target: 90%+ lines)

## External Dependencies

- **@openzeppelin/contracts**: `Ownable`, `Pausable`, `ReentrancyGuard`, ERC20 base
- **@chainlink/contracts-ccip**: CCIP router and message routing
- **forge**: Build, test, and deployment tooling

**Note**: Regular audits recommended for production deployments.

### Access Control
- Owner has significant privileges (rebase, mint, burn)
- Consider using Timelock or multi-sig for production
- Regularly audit owner permissions

## Audit Status

This project has not yet been professionally audited. Use at your own risk.

For production deployments, we strongly recommend:
- Professional security audit
- Bug bounty program
- Gradual rollout strategy
- Emergency pause mechanism

## Dependencies

This project relies on:
- OpenZeppelin Contracts (audited)
- Chainlink CCIP (audited)
- Foundry (development tool)

Always ensure you're using the latest stable versions.

## License

This security policy is licensed under MIT License.
