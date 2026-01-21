# Makefile for Cross-Chain Rebase Token

-include .env

.PHONY: all test clean deploy help install format snapshot anvil lint coverage check-fmt dev-setup

DEFAULT_ANVIL_KEY := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

help:
	@echo "📦 Cross-Chain Rebase Token - Makefile Targets"
	@echo ""
	@echo "Installation & Setup:"
	@echo "  make install           - Install dependencies"
	@echo "  make build             - Build the project"
	@echo ""
	@echo "Testing & Quality:"
	@echo "  make test              - Run all tests"
	@echo "  make test-unit         - Run unit tests only"
	@echo "  make coverage          - Generate coverage report"
	@echo "  make lint              - Run solhint linter"
	@echo "  make check-fmt         - Check code formatting (no changes)"
	@echo "  make format            - Format code automatically"
	@echo ""
	@echo "Deployment:"
	@echo "  make deploy            - Deploy to local Anvil"
	@echo "  make deploy-sepolia    - Deploy to Sepolia testnet"
	@echo "  make deploy-arbitrum   - Deploy to Arbitrum Sepolia"
	@echo ""
	@echo "Local Development:"
	@echo "  make anvil             - Start Anvil local node"
	@echo ""
	@echo "Utilities:"
	@echo "  make clean             - Clean build artifacts"
	@echo "  make snapshot          - Generate gas snapshots"
	@echo "  make help              - Show this message"

all: clean install build test

install:
	forge install OpenZeppelin/openzeppelin-contracts --no-commit
	forge install smartcontractkit/chainlink-brownie-contracts --no-commit
	forge install smartcontractkit/ccip --no-commit
	forge install foundry-rs/forge-std --no-commit

build:
	forge build

test:
	forge test -vvv

test-unit:
	forge test --no-match integration -vvv

coverage:
	@echo "📊 Generating coverage report..."
	forge coverage --report lcov

lint:
	@echo "🔍 Running solhint linter..."
	@if command -v solhint &> /dev/null; then \
		solhint 'src/**/*.sol'; \
	else \
		echo "⚠️  solhint not found. Install with: npm install -g solhint"; \
		exit 1; \
	fi

check-fmt:
	@echo "📋 Checking code formatting..."
	@forge fmt --check

format:
	@echo "✨ Formatting code..."
	forge fmt

snapshot:
	@echo "📊 Generating gas snapshots..."
	forge snapshot

anvil:
	anvil -m 'test test test test test test test test test test test junk' --steps-tracing --block-time 1

deploy:
	@echo "🚀 Deploying to local Anvil..."
	@forge script script/DeployVault.s.sol:DeployVault --rpc-url http://localhost:8545 --private-key $(DEFAULT_ANVIL_KEY) --broadcast

deploy-sepolia:
	@echo "🚀 Deploying to Sepolia testnet..."
	@forge script script/DeployVault.s.sol:DeployVault \
		--rpc-url $(SEPOLIA_RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		--verify \
		--etherscan-api-key $(ETHERSCAN_API_KEY) \
		-vvv

deploy-arbitrum:
	@echo "🚀 Deploying to Arbitrum Sepolia testnet..."
	@forge script script/DeployReceiver.s.sol:DeployReceiver \
		--rpc-url $(ARBITRUM_SEPOLIA_RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		--verify \
		--verifier arbiscan \
		--etherscan-api-key $(ARBISCAN_API_KEY) \
		-vvv

clean:
	forge clean

dev-setup: install build format lint
	@echo "✅ Development environment ready!"
