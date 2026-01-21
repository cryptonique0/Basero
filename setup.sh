#!/bin/bash

# Cross-Chain Rebase Token - Setup Script
# This script helps set up the development environment

echo "==================================="
echo "Cross-Chain Rebase Token Setup"
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
    forge install OpenZeppelin/openzeppelin-contracts@v5.0.1 --no-commit
else
    echo "✅ OpenZeppelin Contracts already installed"
fi

# Install Chainlink Contracts
if [ ! -d "lib/chainlink-brownie-contracts" ]; then
    echo "📦 Installing Chainlink Brownie Contracts..."
    forge install smartcontractkit/chainlink-brownie-contracts@1.1.1 --no-commit
else
    echo "✅ Chainlink Brownie Contracts already installed"
fi

# Install Chainlink CCIP
if [ ! -d "lib/ccip" ]; then
    echo "📦 Installing Chainlink CCIP..."
    forge install smartcontractkit/ccip@ccip-develop --no-commit
else
    echo "✅ Chainlink CCIP already installed"
fi

# Install Forge Standard Library
if [ ! -d "lib/forge-std" ]; then
    echo "📦 Installing Forge Standard Library..."
    forge install foundry-rs/forge-std@v1.7.3 --no-commit
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
    echo "1. Copy .env.example to .env and fill in your values"
    echo "2. Run 'forge test' to execute tests"
    echo "3. Run 'forge build' to compile contracts"
    echo ""
else
    echo ""
    echo "❌ Build failed. Please check for errors above."
    exit 1
fi
