# Cross-Chain Rebase Token

A sophisticated cross-chain rebase token implementation using **Foundry**, **OpenZeppelin**, and **Chainlink CCIP** (Cross-Chain Interoperability Protocol). This project enables dynamic token supply adjustments (rebasing) across multiple blockchain networks with seamless cross-chain transfers.

## 🌟 Features

- **Rebase Mechanism**: Automatically adjusts token supply while maintaining proportional ownership
- **Cross-Chain Transfers**: Seamlessly transfer tokens across different blockchain networks using Chainlink CCIP
- **Shares-Based System**: Uses an internal shares system to efficiently handle rebasing
- **Secure Implementation**: Built on OpenZeppelin's battle-tested contracts
- **Flexible Rebasing**: Support for both absolute and percentage-based supply adjustments
- **Comprehensive Testing**: Full test coverage using Foundry's testing framework

## 📋 Table of Contents

- [Features](#-features)
- [Prerequisites](#-prerequisites)
- [Installation](#-installation)
- [Project Structure](#-project-structure)
- [Smart Contracts](#-smart-contracts)
- [Setup](#-setup)
- [Usage](#-usage)
- [Testing](#-testing)
- [Deployment](#-deployment)
- [Cross-Chain Configuration](#-cross-chain-configuration)
- [Gas Optimization](#-gas-optimization)
- [Security Considerations](#-security-considerations)
- [Contributing](#-contributing)
- [License](#-license)

## 🔧 Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) - Smart contract development framework
- [Git](https://git-scm.com/)
- Node.js v16+ (optional, for additional tooling)

## 📦 Installation

1. **Clone the repository**:
```bash
git clone https://github.com/your-username/crossChainRebaseToken.git
cd crossChainRebaseToken
```

2. **Install dependencies**:
```bash
forge install
```

This will install:
- OpenZeppelin Contracts
- Chainlink Contracts
- Forge Standard Library

3. **Set up environment variables**:
```bash
cp .env.example .env
```

Edit `.env` and add your private keys and RPC URLs.

## 📁 Project Structure

```
crossChainRebaseToken/
├── src/
│   ├── RebaseToken.sol                 # Core rebase token contract
│   ├── CCIPRebaseTokenSender.sol       # Cross-chain sender contract
│   └── CCIPRebaseTokenReceiver.sol     # Cross-chain receiver contract
├── script/
│   ├── DeployRebaseToken.s.sol         # Deploy rebase token only
│   ├── DeployCrossChainRebaseToken.s.sol # Deploy full system
│   └── ConfigureCCIP.s.sol             # Configure cross-chain connections
├── test/
│   ├── RebaseToken.t.sol               # Rebase token tests
│   └── CCIPRebaseToken.t.sol           # CCIP integration tests
├── foundry.toml                         # Foundry configuration
├── remappings.txt                       # Import remappings
└── README.md
```

## 🔐 Smart Contracts

### RebaseToken.sol
The core ERC-20 token with rebase functionality:
- **Shares-based system**: Balances calculated from shares × (totalSupply / totalShares)
- **Rebase functions**: Adjust supply by absolute value or percentage
- **Mint/Burn**: Create or destroy tokens with automatic share management
- **Standard ERC-20**: Full compatibility with ERC-20 interfaces

### CCIPRebaseTokenSender.sol
Manages outbound cross-chain transfers:
- **Token burning**: Burns tokens on source chain before transfer
- **CCIP messaging**: Sends cross-chain messages via Chainlink CCIP
- **Access control**: Allowlisted destination chains and receivers
- **Fee management**: Handles LINK token fees for cross-chain messages

### CCIPRebaseTokenReceiver.sol
Handles inbound cross-chain transfers:
- **Token minting**: Mints tokens on destination chain upon receipt
- **Message validation**: Validates source chains and senders
- **Event emission**: Tracks all received cross-chain transfers

## ⚙️ Setup

1. **Configure Foundry** (already done in `foundry.toml`)

2. **Set up environment variables** in `.env`:
```env
PRIVATE_KEY=your_private_key_here
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/your-api-key
ARBITRUM_SEPOLIA_RPC_URL=https://arb-sepolia.g.alchemy.com/v2/your-api-key
```

3. **Fund your wallet**:
   - Get testnet ETH from faucets
   - Get testnet LINK from [Chainlink Faucet](https://faucets.chain.link/)

## 🚀 Usage

### Build
Compile all contracts:
```bash
forge build
```

### Test
Run the complete test suite:
```bash
forge test
```

Run with verbose output:
```bash
forge test -vvv
```

Run specific test:
```bash
forge test --match-test testRebase -vvv
```

### Format
Format Solidity code:
```bash
forge fmt
```

### Gas Snapshots
Generate gas usage reports:
```bash
forge snapshot
```

## 🧪 Testing

The project includes comprehensive tests:

### RebaseToken Tests
- Initial state verification
- Token transfers and approvals
- Rebase mechanics (absolute and percentage)
- Mint and burn operations
- Shares conversion
- Access control
- Fuzz testing

### CCIP Tests
- Sender/receiver configuration
- Allowlisting chains and contracts
- LINK withdrawal
- Access control
- Router interactions

Run coverage report:
```bash
forge coverage
```

## 🌐 Deployment

### Deploy to Testnet

1. **Deploy on Sepolia (Source Chain)**:
```bash
forge script script/DeployCrossChainRebaseToken.s.sol \
    --rpc-url $SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --verify
```

2. **Deploy on Arbitrum Sepolia (Destination Chain)**:
```bash
forge script script/DeployCrossChainRebaseToken.s.sol \
    --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --verify
```

3. **Save deployed addresses** in your `.env`:
```env
SENDER_ADDRESS=0x...
RECEIVER_ADDRESS=0x...
```

## 🔗 Cross-Chain Configuration

After deploying to both chains, configure the cross-chain connections:

```bash
forge script script/ConfigureCCIP.s.sol \
    --rpc-url $SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast
```

This script:
1. Allowlists the destination chain on the sender
2. Allowlists the receiver contract
3. Allowlists the source chain on the receiver
4. Allowlists the sender contract

### Fund CCIP Contracts

Transfer LINK tokens to the sender contract for cross-chain fees:
```bash
# Transfer LINK to sender contract
cast send $SEPOLIA_LINK \
    "transfer(address,uint256)" \
    $SENDER_ADDRESS \
    1000000000000000000 \
    --rpc-url $SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY
```

## ⛽ Gas Optimization

The rebase mechanism uses a shares-based system for gas efficiency:
- Rebasing only updates a single storage variable (`_totalSupply`)
- No iteration over holder addresses required
- Transfers operate on shares, not balances
- Minimal gas cost for rebase operations

## 🔒 Security Considerations

1. **Access Control**: Only owner can rebase, mint, or burn tokens
2. **Allowlisting**: Both chains and contracts must be allowlisted for cross-chain transfers
3. **Validation**: All cross-chain messages are validated before execution
4. **Reentrancy**: Uses OpenZeppelin's battle-tested implementations
5. **Integer Overflow**: Solidity 0.8.24 has built-in overflow protection

### Best Practices

- Always test on testnets before mainnet deployment
- Audit your contracts before production use
- Use multi-sig wallets for ownership
- Monitor cross-chain transactions
- Keep LINK funded for CCIP operations

## 🤝 Contributing

Contributions are welcome! Please follow these steps:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

### Development Guidelines

- Write tests for all new features
- Follow the existing code style
- Update documentation as needed
- Ensure all tests pass before submitting PR

## 📚 Additional Resources

- [Foundry Book](https://book.getfoundry.sh/)
- [OpenZeppelin Docs](https://docs.openzeppelin.com/)
- [Chainlink CCIP Docs](https://docs.chain.link/ccip)
- [Cyfrin Updraft](https://updraft.cyfrin.io/)

## 📄 License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [Foundry](https://github.com/foundry-rs/foundry) for the amazing development framework
- [OpenZeppelin](https://github.com/OpenZeppelin/openzeppelin-contracts) for secure contract implementations
- [Chainlink](https://github.com/smartcontractkit/chainlink) for CCIP infrastructure
- [Cyfrin](https://www.cyfrin.io/) for educational resources

## 📞 Support

For questions and support:
- Open an issue on GitHub
- Check existing documentation
- Review test files for usage examples

---

**Built with ❤️ using Foundry, OpenZeppelin, and Chainlink CCIP**
