# Makefile for Cross-Chain Rebase Token

-include .env

.PHONY: all test clean deploy help install format snapshot anvil

DEFAULT_ANVIL_KEY := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

help:
	@echo "Usage:"
	@echo "  make install    - Install dependencies"
	@echo "  make build      - Build the project"
	@echo "  make test       - Run tests"
	@echo "  make format     - Format code"
	@echo "  make snapshot   - Generate gas snapshots"
	@echo "  make anvil      - Start local Anvil node"
	@echo "  make deploy     - Deploy to Anvil (local)"
	@echo "  make deploy-sepolia - Deploy to Sepolia"

all: clean install build

install:
	forge install OpenZeppelin/openzeppelin-contracts --no-commit
	forge install smartcontractkit/chainlink-brownie-contracts --no-commit
	forge install smartcontractkit/ccip --no-commit
	forge install foundry-rs/forge-std --no-commit

build:
	forge build

test:
	forge test -vvv

format:
	forge fmt

snapshot:
	forge snapshot

anvil:
	anvil -m 'test test test test test test test test test test test junk' --steps-tracing --block-time 1

deploy:
	@forge script script/DeployVault.s.sol:DeployVault --rpc-url http://localhost:8545 --private-key $(DEFAULT_ANVIL_KEY) --broadcast

deploy-sepolia:
	@forge script script/DeployVault.s.sol:DeployVault \
		--rpc-url $(SEPOLIA_RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		--verify \
		--etherscan-api-key $(ETHERSCAN_API_KEY) \
		-vvvv

clean:
	forge clean
