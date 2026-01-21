# 📚 Basero Documentation Index

Quick reference guide to all documentation and resources.

---

## 🚀 Quick Start

**New to the project?** Start here:
1. [README.md](README.md) - Project overview and features
2. [QUICKSTART.md](QUICKSTART.md) - Get up and running locally
3. [.env.example](.env.example) - Configuration template

---

## 📖 Core Documentation

### Project Overview
- [README.md](README.md) - Project description, features, architecture
- [PROJECT_OVERVIEW.md](PROJECT_OVERVIEW.md) - Detailed technical overview
- [SUMMARY.md](SUMMARY.md) - Executive summary

### Features & Examples
- [EXAMPLES.md](EXAMPLES.md) - Usage examples and code samples
- [FEATURES.md](FEATURES.md) - Feature list and specifications

### Contributing
- [CONTRIBUTING.md](CONTRIBUTING.md) - Contribution guidelines

---

## 🔒 Security & Hardening

### Security Documentation
- [SECURITY.md](SECURITY.md) - **⭐ Key Reading**
  - Vulnerability reporting procedures
  - Security assumptions and threat model
  - Incident response procedures
  - Monitoring checklist
  - 15 identified and mitigated threats

### What's New
- [HARDENING_COMPLETE.md](HARDENING_COMPLETE.md) - Hardening phase summary
- [COMMITS_SUMMARY.md](COMMITS_SUMMARY.md) - All 30+ commits documented
- [CHANGELOG.md](CHANGELOG.md) - Complete file changelog

---

## 🚢 Deployment & Operations

### Deployment Guides
- [DEPLOYMENT.md](DEPLOYMENT.md) - General deployment guide
- [DEPLOYMENT_RUNBOOKS.md](DEPLOYMENT_RUNBOOKS.md) - **⭐ Essential for Deployment**
  - Per-chain deployment steps (Sepolia, Arbitrum, Avalanche, Base)
  - Cross-chain configuration procedures
  - CCIP chain selector reference
  - End-to-end testing guide
  - Troubleshooting solutions

### Configuration
- [.env.example](.env.example) - Environment configuration template
  - Required vs optional variables
  - Testnet/mainnet configurations
  - Detailed inline documentation

---

## 🧪 Testing & Quality

### Test Files Location
- `test/VaultPause.t.sol` - Pause/unpause controls (6 tests)
- `test/VaultCaps.t.sol` - Deposit caps and allowlist (8 tests)
- `test/VaultAccrual.t.sol` - Accrual mechanics and circuit breaker (9 tests)
- `test/VaultViewHelpers.t.sol` - Preview and info functions (8 tests)
- `test/VaultSlippage.t.sol` - Slippage protection (5 tests)
- `test/VaultEmergency.t.sol` - Emergency functions (12 tests)
- `test/VaultAutomation.t.sol` - Automation hooks (6 tests)
- `test/CCIPPause.t.sol` - CCIP pause controls (3 tests)
- `test/CCIPFeesAndCaps.t.sol` - CCIP fees and limits (11 tests)
- `test/CCIPReceiverCaps.t.sol` - Receiver caps (3 tests)

**Total**: 71 tests

### Running Tests
```bash
make test           # Run all tests
make test-unit      # Unit tests only
make coverage       # Generate coverage report
```

### Quality Tools
```bash
make lint           # Run solhint
make check-fmt      # Check formatting
make format         # Auto-format code
make dev-setup      # Full environment setup
```

---

## 🔧 Development Setup

### Installation
```bash
make install        # Install all dependencies
make build          # Build contracts
```

### Local Development
```bash
make anvil          # Start local blockchain
make deploy         # Deploy to local chain
make dev-setup      # Full setup with linting
```

### Configuration
- [.solhint.json](.solhint.json) - Linting rules
- [Makefile](Makefile) - Build and deployment targets
- [foundry.toml](foundry.toml) - Forge configuration

---

## 📋 Git Workflow

### Pre-commit Hooks
Automatic checks before committing:
- Private key detection
- .env file protection
- Code formatting
- Linting

**Setup**: `scripts/setup-hooks.sh`

### CI/CD
GitHub Actions workflows in `.github/workflows/`:
- `lint.yml` - Linting and formatting checks

---

## 📦 Smart Contracts

### Core Contracts
- `src/RebaseToken.sol` - ERC20 with shares-based rebase
- `src/RebaseTokenVault.sol` - ETH vault with interest accrual
- `src/CCIPRebaseTokenSender.sol` - Cross-chain sending
- `src/CCIPRebaseTokenReceiver.sol` - Cross-chain receiving

### Scripts
- `script/DeployVault.s.sol` - Vault deployment
- `script/DeployCrossChainRebaseToken.s.sol` - Full CCIP setup
- `script/ConfigureCCIP.s.sol` - Cross-chain configuration

---

## 📊 Project Statistics

- **Smart Contracts**: 4 core contracts
- **Test Suites**: 10 files with 71 tests
- **Documentation**: 5 major documents (1500+ lines)
- **Test Code**: 2000+ lines
- **New Features**: 30+
- **Events**: 22 new
- **Error Types**: 17 new

---

## 🎯 Key Features

### Vault Controls (RebaseTokenVault)
- ✅ Pause/unpause deposits and redeems
- ✅ Per-user deposit caps
- ✅ Global TVL caps
- ✅ Allowlist/whitelist for depositors
- ✅ Minimum deposit requirements
- ✅ Slippage protection on redeems
- ✅ Emergency ETH withdraw
- ✅ ERC20 sweep for stuck tokens
- ✅ Configurable accrual period (1h-7d)
- ✅ Circuit breaker on daily accrual
- ✅ Protocol fee on accrual
- ✅ View helpers (preview, estimate, info)
- ✅ Chainlink Automation compatible

### CCIP Bridging
- ✅ Pause/unpause bridging per sender/receiver
- ✅ Per-chain protocol fees (1-100%)
- ✅ Per-send caps on bridging
- ✅ Daily rolling limits
- ✅ Interest rate preservation across chains
- ✅ Reentrancy protection on receiver
- ✅ Fee recipient configuration

### Security & Hardening
- ✅ Reentrancy guards
- ✅ Overflow/underflow protection (Solidity 0.8.24)
- ✅ Threat model documented (15 threats)
- ✅ Incident response procedures
- ✅ Event emissions for all state changes
- ✅ Private key protection in git
- ✅ Storage gap for future upgrades

---

## 🔍 Finding Specific Information

### "How do I..."

**...deploy the contract?**
→ [DEPLOYMENT_RUNBOOKS.md](DEPLOYMENT_RUNBOOKS.md)

**...configure the vault?**
→ [.env.example](.env.example)

**...understand the security model?**
→ [SECURITY.md](SECURITY.md)

**...run tests?**
→ `make test` and [Makefile](Makefile)

**...set up development?**
→ `make dev-setup` and [QUICKSTART.md](QUICKSTART.md)

**...bridge tokens across chains?**
→ [DEPLOYMENT_RUNBOOKS.md](DEPLOYMENT_RUNBOOKS.md) - Cross-Chain Configuration

**...handle an emergency?**
→ [SECURITY.md](SECURITY.md) - Incident Response

**...understand what changed?**
→ [COMMITS_SUMMARY.md](COMMITS_SUMMARY.md)

**...see all files?**
→ [CHANGELOG.md](CHANGELOG.md)

---

## 📞 Support

### Documentation
- Check the relevant guide above
- Review [EXAMPLES.md](EXAMPLES.md) for code examples
- See test files in `test/` for usage patterns

### Issues & Questions
1. Check existing documentation
2. Search in test files for examples
3. Review [TROUBLESHOOTING](DEPLOYMENT_RUNBOOKS.md#troubleshooting-deployment-issues)
4. Check [SECURITY.md](SECURITY.md) for threat model

---

## 📅 Version History

- **Phase 1** (Jan 2026): Core Implementation
- **Phase 2** (Jan 2026): Hardening & Controls
- **Phase 3** (Jan 2026): Testing & Documentation ✅ **Current**
- **Phase 4** (Planned): Security Audit
- **Phase 5** (Planned): Mainnet Deployment

---

## 🏁 Status

✅ **Phase 3 Complete**: Hardening, Testing, and Documentation
- All 30+ features implemented
- 71 tests written and ready
- Comprehensive documentation complete
- Security hardened
- Development tooling setup
- Ready for testnet deployment

---

## 📝 Quick Links

| Resource | Purpose |
|----------|---------|
| [README.md](README.md) | Project overview |
| [SECURITY.md](SECURITY.md) | Security & threat model |
| [DEPLOYMENT_RUNBOOKS.md](DEPLOYMENT_RUNBOOKS.md) | Deployment guide |
| [.env.example](.env.example) | Configuration |
| [test/](test/) | Test suite |
| [Makefile](Makefile) | Development commands |
| [COMMITS_SUMMARY.md](COMMITS_SUMMARY.md) | What changed |

---

**Last Updated**: January 21, 2026
**Status**: ✅ Ready for Testnet Deployment
