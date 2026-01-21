#!/bin/bash

# Cross-Chain Rebase Token - Setup Script
# This script helps set up the development environment

echo "==================================="
echo "Cross-Chain Rebase Token Setup"
echo "Cyfrin Foundry Course Project"
echo "==================================="
echo ""

# Check if Foundry is installed
if ! command -v forge &> /dev/null
then
    echo "❌ Foundry is not installed."
    echo ""
    echo "Please install Foundry by running:"
    echo "  curl -L https://foundry.paradigm.xyz | bash"
    echo "  foundryup"
    echo ""
    echo "Then run this script again."
    exit 1
else
    echo "✅ Foundry is installed"
    forge --version
fi

echo ""
echo "Installing dependencies..."

# Install OpenZeppelin Contracts
if [ ! -d "lib/openzeppelin-contracts" ]; then
    echo "📦 Installing OpenZeppelin Contracts..."
    forge install OpenZeppelin/openzeppelin-contracts --no-commit
else
    echo "✅ OpenZeppelin Contracts already installed"
fi

# Install Chainlink Contracts
if [ ! -d "lib/chainlink-brownie-contracts" ]; then
    echo "📦 Installing Chainlink Brownie Contracts..."
    forge install smartcontractkit/chainlink-brownie-contracts --no-commit
else
    echo "✅ Chainlink Brownie Contracts already installed"
fi

# Install Chainlink CCIP
if [ ! -d "lib/ccip" ]; then
    echo "📦 Installing Chainlink CCIP..."
    forge install smartcontractkit/ccip --no-commit
else
    echo "✅ Chainlink CCIP already installed"
fi

# Install Forge Standard Library
if [ ! -d "lib/forge-std" ]; then
    echo "📦 Installing Forge Standard Library..."
    forge install foundry-rs/forge-std --no-commit
else
    echo "✅ Forge Standard Library already installed"
fi

echo ""
echo "Building contracts..."
forge build

if [ $? -eq 0 ]; then
    echo ""
    echo "==================================="
    echo "✅ Setup completed successfully!"
    echo "==================================="
    echo ""
    echo "Next steps:"
    echo "1. Copy .env.example to .env and fill in your values:"
    echo "   cp .env.example .env"
    echo "2. Run 'forge test' to execute tests"
    echo "3. Run 'make deploy' to deploy locally"
    echo "4. Check out the README.md for more info"
    echo ""
    echo "To interact with the contracts:"
    echo "• Deposit ETH: cast send <vault-address> 'deposit()' --value 0.1ether"
    echo "• Check balance: cast call <token-address> 'balanceOf(address)' <your-address>"
    echo ""
else
    echo ""
    echo "❌ Build failed. Please check for errors above."
    exit 1
fi
