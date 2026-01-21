# Cross-Chain Rebase Token

A sophisticated cross-chain rebase token implementation using **Foundry**, **OpenZeppelin**, and **Chainlink CCIP**. This project enables users to deposit ETH in exchange for rebase tokens that accrue rewards over time, with seamless cross-chain transfers.

*This is a section of the Cyfrin Foundry Solidity course.*

## 🌟 About

This project is a cross-chain rebase token where users can deposit ETH in exchange for rebase tokens which accrue rewards over time. The token uses Chainlink CCIP to enable users to bridge their tokens cross-chain while maintaining their interest rates.

### Key Features

- **ETH Vault**: Deposit ETH to receive rebase tokens
- **Interest Accrual**: Tokens automatically earn interest over time
- **Discrete Interest Rates**: Early depositors get higher rates that decrease over time
- **Cross-Chain Bridging**: Transfer tokens across chains via Chainlink CCIP
- **Interest Rate Persistence**: Your interest rate bridges with you and stays static
- **L1-Only Deposits/Withdrawals**: Maintain security by limiting deposits and withdrawals to L1

## 📋 Project Design and Assumptions

- Interest rates decrease discretely as more ETH is deposited
- Users lock in their interest rate when they first deposit
- When bridging to L2, the interest rate bridges with the tokens and stays static
- Users can only deposit and withdraw on the L1 (source chain)
- No interest is earned during the bridging period
- Protocol rewards early users and users who bridge to L2
- Assumed rewards are held in the contract

## � Installation

### Requirements

- **Git**: Version control
  - Test: `git --version`
  - Expected: `git version x.x.x`
- **Foundry**: Smart contract development framework
  - Test: `forge --version`
  - Expected: `forge 0.2.0 (816e00b 2023-03-16T00:05:26.396218Z)` or newer

### Quickstart

```bash
git clone https://github.com/Cyfrin/foundry-cross-chain-rebase-token-cu
cd foundry-cross-chain-rebase-token-cu
forge build
```

## ⚙️ Setup

1. **Install dependencies**:
```bash
forge install
```

This installs:
- OpenZeppelin Contracts
- Chainlink Contracts
- Chainlink CCIP
- Forge Standard Library

2. **Set up environment variables**:
```bash
cp .env.example .env
```

Edit `.env` and add:
- `PRIVATE_KEY`: Your wallet private key (⚠️ **Use a development key only!**)
- `SEPOLIA_RPC_URL`: Sepolia testnet RPC URL (get from [Alchemy](https://alchemy.com))
- `ETHERSCAN_API_KEY`: For contract verification (optional)

## � Usage

### Start a Local Node

```bash
make anvil
```

### Build

Compile the contracts:

```bash
forge build
```

### Test

Run the test suite:

```bash
forge test
```

Run with verbosity:

```bash
forge test -vvv
```

### Test Coverage

```bash
forge coverage
```

For detailed coverage:

```bash
forge coverage --report debug
```

### Format

Format Solidity code:

```bash
forge fmt
```

### Gas Snapshots

Generate gas usage snapshots:

```bash
forge snapshot
```

## 📁 Project Structure

```
crossChainRebaseToken/
├── src/
│   ├── RebaseToken.sol                 # Core rebase token with interest mechanics
│   ├── RebaseTokenVault.sol            # ETH vault for deposits/withdrawals
│   ├── CCIPRebaseTokenSender.sol       # Cross-chain sender (bridges interest rate)
│   └── CCIPRebaseTokenReceiver.sol     # Cross-chain receiver
├── test/
│   ├── RebaseToken.t.sol               # Token tests
│   ├── RebaseTokenVault.t.sol          # Vault and interest tests
│   └── CCIPRebaseToken.t.sol           # CCIP integration tests
├── script/
│   ├── DeployVault.s.sol               # Deploy token and vault
│   ├── DeployCrossChainRebaseToken.s.sol # Deploy full cross-chain system
│   └── ConfigureCCIP.s.sol             # Configure cross-chain connections
├── foundry.toml                         # Foundry configuration
├── Makefile                             # Build automation
└── README.md                            # This file
```

## 🌐 Deployment

### Deployment to Local Network

Deploy to Anvil (local node):

```bash
make anvil  # In one terminal
make deploy # In another terminal
```

### Deployment to Testnet

1. **Get testnet ETH**:
   - Visit [faucets.chain.link](https://faucets.chain.link) for Sepolia ETH

2. **Deploy to Sepolia**:
```bash
make deploy ARGS="--network sepolia"
```

Or with environment variables:

```bash
forge script script/DeployVault.s.sol:DeployVault \
    --rpc-url $SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --verify \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    -vvvv
```

### Deployment to Mainnet

⚠️ **WARNING**: Mainnet deployment involves real funds. Ensure thorough testing on testnets first.

See [DEPLOYMENT.md](DEPLOYMENT.md) for complete mainnet deployment instructions.

## 🔧 Scripts

Instead of writing custom scripts, you can use `cast` commands to interact with the contract directly.

### Get RebaseTokens

Deposit ETH to receive rebase tokens:

```bash
cast send <vault-contract-address> "deposit()" \
    --value 0.1ether \
    --rpc-url $SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY
```

### Redeem RebaseTokens for ETH

```bash
cast send <vault-contract-address> "redeem(uint256)" 10000000000000000 \
    --rpc-url $SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY
```

### Check Your Balance

```bash
cast call <token-contract-address> "balanceOf(address)" <your-address> \
    --rpc-url $SEPOLIA_RPC_URL
```

### Check Current Interest Rate

```bash
cast call <vault-contract-address> "getCurrentInterestRate()" \
    --rpc-url $SEPOLIA_RPC_URL
```

### Check Your Interest Rate

```bash
cast call <vault-contract-address> "getUserInterestRate(address)" <your-address> \
    --rpc-url $SEPOLIA_RPC_URL
```

## ⛽ Estimate Gas

Generate gas usage snapshots:

```bash
forge snapshot
```

You'll see an output file called `.gas-snapshot` with gas usage for all functions.

## 🎨 Formatting

Format Solidity code:

```bash
forge fmt
```

## 🙏 Thank You!

Thanks for checking out this project! For more Solidity education, check out:
- [Cyfrin Updraft](https://updraft.cyfrin.io/)
- [Patrick Collins YouTube](https://www.youtube.com/c/PatrickCollins)

## 📚 Additional Resources

- [Foundry Book](https://book.getfoundry.sh/)
- [OpenZeppelin Docs](https://docs.openzeppelin.com/)
- [Chainlink CCIP Docs](https://docs.chain.link/ccip)
- [Cyfrin Updraft](https://updraft.cyfrin.io/)

## 📄 License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
