# Makefile for Cross-Chain Rebase Token

-include .env

.PHONY: all test clean deploy help install format snapshot anvil

help:
	@echo "Usage:"
	@echo "  make install    - Install dependencies"
	@echo "  make build      - Build the project"
	@echo "  make test       - Run tests"
	@echo "  make format     - Format code"
	@echo "  make snapshot   - Generate gas snapshots"
	@echo "  make anvil      - Start local Anvil node"
	@echo "  make deploy-sepolia - Deploy to Sepolia"
	@echo "  make deploy-arbitrum - Deploy to Arbitrum Sepolia"

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
	anvil

deploy-sepolia:
	forge script script/DeployCrossChainRebaseToken.s.sol \
		--rpc-url $(SEPOLIA_RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		--verify \
		--etherscan-api-key $(ETHERSCAN_API_KEY) \
		-vvvv

deploy-arbitrum:
	forge script script/DeployCrossChainRebaseToken.s.sol \
		--rpc-url $(ARBITRUM_SEPOLIA_RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		--verify \
		--etherscan-api-key $(ARBISCAN_API_KEY) \
		-vvvv

configure-ccip:
	forge script script/ConfigureCCIP.s.sol \
		--rpc-url $(SEPOLIA_RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		-vvvv

clean:
	forge clean
