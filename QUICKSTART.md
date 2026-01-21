# Cross-Chain Rebase Token - Quick Start Guide

## Prerequisites

Before you begin, ensure you have Foundry installed:

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

Verify installation:
```bash
forge --version
```

## Quick Setup

1. **Run the setup script**:
```bash
chmod +x setup.sh
./setup.sh
```

This will automatically:
- Check for Foundry installation
- Install all dependencies (OpenZeppelin, Chainlink, etc.)
- Build the contracts

2. **Configure environment variables**:
```bash
cp .env.example .env
```

Edit `.env` and add your:
- Private key
- RPC URLs
- API keys

3. **Run tests**:
```bash
forge test
```

## Manual Setup (Alternative)

If you prefer to set up manually:

```bash
# Install dependencies
forge install OpenZeppelin/openzeppelin-contracts@v5.0.1 --no-commit
forge install smartcontractkit/chainlink-brownie-contracts@1.1.1 --no-commit
forge install smartcontractkit/ccip@ccip-develop --no-commit
forge install foundry-rs/forge-std@v1.7.3 --no-commit

# Build contracts
forge build

# Run tests
forge test
```

## Using the Makefile

The project includes a Makefile for convenience:

```bash
# Install all dependencies
make install

# Build contracts
make build

# Run tests
make test

# Format code
make format

# Generate gas snapshots
make snapshot

# Deploy to Sepolia
make deploy-sepolia

# Deploy to Arbitrum Sepolia
make deploy-arbitrum
```

## Common Commands

```bash
# Compile contracts
forge build

# Run tests with verbose output
forge test -vvv

# Run specific test
forge test --match-test testRebase

# Generate gas report
forge test --gas-report

# Format code
forge fmt

# Check code coverage
forge coverage
```

## Deployment

1. **Deploy to testnet**:
```bash
forge script script/DeployCrossChainRebaseToken.s.sol \
    --rpc-url $SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --verify
```

2. **Configure cross-chain connections**:
```bash
forge script script/ConfigureCCIP.s.sol \
    --rpc-url $SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast
```

## Troubleshooting

### Foundry not found
Install Foundry:
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### Build fails
Clean and rebuild:
```bash
forge clean
forge build
```

### Tests fail
Check your Solidity version matches `foundry.toml`:
```bash
forge --version
```

### Out of gas errors
Increase gas limit in `foundry.toml` or use `--gas-limit` flag

## Support

- [Foundry Documentation](https://book.getfoundry.sh/)
- [GitHub Issues](https://github.com/your-username/crossChainRebaseToken/issues)
- [Chainlink CCIP Docs](https://docs.chain.link/ccip)

---

For more detailed information, see [README.md](README.md)
