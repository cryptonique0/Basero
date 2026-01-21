<div align="center">

# 🔗 Cross-Chain Rebase Token

[![Foundry][foundry-badge]][foundry]
[![License: MIT][license-badge]][license]
[![Solidity][solidity-badge]][solidity]

**A sophisticated cross-chain rebase token powered by Chainlink CCIP**

[Features](#-features) • [Quick Start](#-quick-start) • [Documentation](#-documentation) • [Testing](#-testing) • [Deployment](#-deployment)

</div>

---

## 📖 Overview

This project implements a **cross-chain rebase token** that automatically adjusts its supply across multiple blockchain networks. Built with **Foundry**, **OpenZeppelin**, and **Chainlink CCIP**, it enables seamless token transfers and dynamic tokenomics across chains.

### What is a Rebase Token?

Rebase tokens automatically adjust their supply based on predefined mechanisms while maintaining users' proportional ownership. This implementation uses a **shares-based system** where:
- User balances = (user shares × total supply) / total shares
- Rebasing only updates the total supply variable
- Proportional ownership remains constant

### Why Cross-Chain?

Cross-chain capability allows the token to:
- Operate across multiple blockchain networks
- Leverage different chain ecosystems
- Enable multi-chain DeFi strategies
- Provide unified tokenomics globally

## ✨ Features

| Feature | Description |
|---------|-------------|
| 🔄 **Dynamic Rebasing** | Adjust token supply by absolute value or percentage |
| 🌉 **Cross-Chain** | Transfer tokens seamlessly between networks via CCIP |
| 💎 **Shares System** | Gas-efficient balance tracking that survives rebases |
| 🛡️ **Secure** | Built on OpenZeppelin's audited contracts |
| ⚡ **Gas Optimized** | Minimal gas cost for rebase operations |
| 🧪 **Well Tested** | 20+ comprehensive test cases |
| 📚 **Documented** | Extensive guides and examples |

## 🚀 Quick Start

### Prerequisites

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### Installation

```bash
# Clone the repository
git clone https://github.com/your-username/crossChainRebaseToken.git
cd crossChainRebaseToken

# Run automated setup
chmod +x setup.sh
./setup.sh
```

### Configure Environment

```bash
# Copy environment template
cp .env.example .env

# Edit .env with your values
nano .env
```

### Build & Test

```bash
# Build contracts
forge build

# Run tests
forge test

# Run tests with gas report
forge test --gas-report

# Check coverage
forge coverage
```

## 📚 Documentation

| Document | Description |
|----------|-------------|
| [📘 README](README.md) | Complete project documentation |
| [⚡ Quick Start](QUICKSTART.md) | Fast setup guide |
| [🚀 Deployment Guide](DEPLOYMENT.md) | Step-by-step deployment |
| [💡 Examples](EXAMPLES.md) | Usage patterns and code examples |
| [🤝 Contributing](CONTRIBUTING.md) | Contribution guidelines |
| [🔒 Security](SECURITY.md) | Security policy and best practices |
| [📊 Overview](PROJECT_OVERVIEW.md) | Project architecture and metrics |

## 🏗️ Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                    Cross-Chain System                         │
├──────────────────────────────────────────────────────────────┤
│                                                               │
│  Source Chain (Ethereum)       CCIP        Dest Chain (Arb)  │
│  ┌─────────────────┐                      ┌─────────────────┐│
│  │  RebaseToken    │                      │  RebaseToken    ││
│  │  (Burn tokens)  │───────Msg─────────>│  (Mint tokens)  ││
│  │                 │                      │                 ││
│  │  CCIPSender     │                      │  CCIPReceiver   ││
│  └─────────────────┘                      └─────────────────┘│
│         │                                          │          │
│         └──────────────────────────────────────────┘          │
│                    User maintains ownership                   │
└──────────────────────────────────────────────────────────────┘
```

## 🧪 Testing

The project includes comprehensive tests:

```bash
# Run all tests
forge test

# Run with verbosity
forge test -vvv

# Run specific test
forge test --match-test testRebase

# Gas report
forge test --gas-report

# Coverage report
forge coverage --report summary
```

### Test Coverage

- ✅ Token transfers and approvals
- ✅ Rebase mechanics (absolute & percentage)
- ✅ Mint and burn operations
- ✅ Cross-chain transfers
- ✅ Access control
- ✅ Fuzz testing
- ✅ Edge cases

## 🌐 Deployment

### Testnet Deployment

```bash
# Deploy to Sepolia
forge script script/DeployCrossChainRebaseToken.s.sol \
    --rpc-url $SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --verify

# Deploy to Arbitrum Sepolia
forge script script/DeployCrossChainRebaseToken.s.sol \
    --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --verify
```

See [DEPLOYMENT.md](DEPLOYMENT.md) for complete instructions.

## 📦 Project Structure

```
crossChainRebaseToken/
├── src/
│   ├── RebaseToken.sol                 # Core rebase token
│   ├── CCIPRebaseTokenSender.sol       # Cross-chain sender
│   └── CCIPRebaseTokenReceiver.sol     # Cross-chain receiver
├── test/
│   ├── RebaseToken.t.sol               # Token tests
│   └── CCIPRebaseToken.t.sol           # CCIP tests
├── script/
│   ├── DeployRebaseToken.s.sol         # Deploy token
│   ├── DeployCrossChainRebaseToken.s.sol # Deploy full system
│   └── ConfigureCCIP.s.sol             # Configure cross-chain
├── foundry.toml                         # Foundry config
└── README.md                            # This file
```

## 🔧 Technology Stack

- **Solidity 0.8.24** - Smart contract language
- **Foundry** - Development framework
- **OpenZeppelin** - Secure contract library
- **Chainlink CCIP** - Cross-chain messaging
- **GitHub Actions** - CI/CD

## 🌟 Key Contracts

### RebaseToken.sol
Core ERC-20 token with:
- Shares-based balance system
- Rebase by absolute value or percentage
- Mint/burn with automatic share management
- Gas-optimized operations

### CCIPRebaseTokenSender.sol
Handles outbound cross-chain transfers:
- Burns tokens on source chain
- Sends CCIP message to destination
- Manages LINK fees
- Allowlisting for security

### CCIPRebaseTokenReceiver.sol
Handles inbound cross-chain transfers:
- Receives CCIP messages
- Mints tokens on destination chain
- Validates source and sender
- Event emission for tracking

## 🎓 Learn More

This project demonstrates:
- ✅ Advanced ERC-20 implementation
- ✅ Rebase mechanics with shares
- ✅ Cross-chain interoperability
- ✅ Foundry testing patterns
- ✅ Smart contract deployment
- ✅ Access control best practices

## 🔒 Security

⚠️ **Important**: This code has not been professionally audited.

For production use:
1. Get a professional security audit
2. Test extensively on testnets
3. Use multi-sig for ownership
4. Implement monitoring
5. Have incident response plan

See [SECURITY.md](SECURITY.md) for details.

## 🤝 Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Write/update tests
5. Submit a pull request

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## 📄 License

This project is licensed under the MIT License - see [LICENSE](LICENSE) for details.

## 🙏 Acknowledgments

- [Foundry](https://github.com/foundry-rs/foundry) - Development framework
- [OpenZeppelin](https://github.com/OpenZeppelin/openzeppelin-contracts) - Secure contracts
- [Chainlink](https://github.com/smartcontractkit/chainlink) - CCIP infrastructure
- [Cyfrin Updraft](https://updraft.cyfrin.io/) - Educational resources

## 📞 Support

- 📖 [Documentation](README.md)
- 🐛 [Report Issues](https://github.com/your-username/crossChainRebaseToken/issues)
- 💬 [Discussions](https://github.com/your-username/crossChainRebaseToken/discussions)

## ⭐ Show Your Support

If this project helped you, please give it a ⭐!

---

<div align="center">

**Built with ❤️ using Foundry, OpenZeppelin, and Chainlink CCIP**

[foundry]: https://getfoundry.sh/
[foundry-badge]: https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg
[license]: https://opensource.org/licenses/MIT
[license-badge]: https://img.shields.io/badge/License-MIT-blue.svg
[solidity]: https://soliditylang.org/
[solidity-badge]: https://img.shields.io/badge/Solidity-0.8.24-e6e6e6?logo=solidity

</div>
