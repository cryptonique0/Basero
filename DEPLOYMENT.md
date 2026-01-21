# Deployment Guide

Complete guide for deploying the Cross-Chain Rebase Token system to testnets and mainnet.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Testnet Deployment](#testnet-deployment)
3. [Configuration](#configuration)
4. [Verification](#verification)
5. [Mainnet Deployment](#mainnet-deployment)
6. [Post-Deployment](#post-deployment)
7. [Troubleshooting](#troubleshooting)

## Prerequisites

### Required Tools

- Foundry installed and updated
- Git
- A wallet with private key
- RPC endpoints for target networks
- Block explorer API keys (for verification)

### Required Funds

For each network:
- Native tokens for gas (ETH, AVAX, etc.)
- LINK tokens for CCIP fees

**Testnet Faucets:**
- Sepolia ETH: https://sepoliafaucet.com/
- Arbitrum Sepolia ETH: https://faucet.quicknode.com/arbitrum/sepolia
- Avalanche Fuji AVAX: https://faucet.avax.network/
- LINK (all testnets): https://faucets.chain.link/

## Testnet Deployment

### Step 1: Environment Setup

1. **Copy environment template**:
```bash
cp .env.example .env
```

2. **Edit `.env` file**:
```bash
# Your deployment wallet private key
PRIVATE_KEY=0x1234...

# RPC Endpoints
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR-API-KEY
ARBITRUM_SEPOLIA_RPC_URL=https://arb-sepolia.g.alchemy.com/v2/YOUR-API-KEY

# Block Explorer API Keys (for verification)
ETHERSCAN_API_KEY=YOUR-KEY
ARBISCAN_API_KEY=YOUR-KEY

# Chainlink CCIP Configuration (Testnet addresses - already set)
# No need to change these for testnet
```

3. **Verify configuration**:
```bash
source .env
echo $PRIVATE_KEY | grep "0x" && echo "✅ Private key set" || echo "❌ Private key not set"
```

### Step 2: Deploy to Source Chain (Sepolia)

```bash
# Deploy complete system to Sepolia
forge script script/DeployCrossChainRebaseToken.s.sol \
    --rpc-url $SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --verify \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    -vvvv
```

**Expected Output:**
```
=== Deployment Summary ===
RebaseToken: 0xABC...
CCIPRebaseTokenSender: 0xDEF...
CCIPRebaseTokenReceiver: 0xGHI...
==========================
```

**Save these addresses!** You'll need them for the next steps.

### Step 3: Deploy to Destination Chain (Arbitrum Sepolia)

```bash
# Deploy complete system to Arbitrum Sepolia
forge script script/DeployCrossChainRebaseToken.s.sol \
    --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --verify \
    --etherscan-api-key $ARBISCAN_API_KEY \
    -vvvv
```

**Save these addresses too!**

### Step 4: Update Environment Variables

Add deployed addresses to your `.env`:

```bash
# Sepolia Deployments
SEPOLIA_TOKEN_ADDRESS=0x...
SEPOLIA_SENDER_ADDRESS=0x...
SEPOLIA_RECEIVER_ADDRESS=0x...

# Arbitrum Sepolia Deployments
ARBITRUM_TOKEN_ADDRESS=0x...
ARBITRUM_SENDER_ADDRESS=0x...
ARBITRUM_RECEIVER_ADDRESS=0x...
```

## Configuration

### Step 5: Configure Cross-Chain Connections

You need to configure the connections between chains in both directions.

**Configure Sepolia → Arbitrum:**

```bash
# Create a configuration script or use cast commands
cast send $SEPOLIA_SENDER_ADDRESS \
    "allowlistDestinationChain(uint64,bool)" \
    $ARBITRUM_SEPOLIA_CHAIN_SELECTOR \
    true \
    --rpc-url $SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY

cast send $SEPOLIA_SENDER_ADDRESS \
    "allowlistReceiver(uint64,address)" \
    $ARBITRUM_SEPOLIA_CHAIN_SELECTOR \
    $ARBITRUM_RECEIVER_ADDRESS \
    --rpc-url $SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY
```

**Configure Arbitrum → Sepolia:**

```bash
cast send $ARBITRUM_RECEIVER_ADDRESS \
    "allowlistSourceChain(uint64,bool)" \
    $SEPOLIA_CHAIN_SELECTOR \
    true \
    --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY

cast send $ARBITRUM_RECEIVER_ADDRESS \
    "allowlistSender(uint64,address)" \
    $SEPOLIA_CHAIN_SELECTOR \
    $SEPOLIA_SENDER_ADDRESS \
    --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY
```

### Step 6: Fund CCIP Contracts with LINK

The sender contracts need LINK tokens to pay for cross-chain messages.

**Fund Sepolia Sender:**

```bash
cast send $SEPOLIA_LINK \
    "transfer(address,uint256)" \
    $SEPOLIA_SENDER_ADDRESS \
    1000000000000000000 \
    --rpc-url $SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY
```

**Fund Arbitrum Sender (if doing reverse transfers):**

```bash
cast send $ARBITRUM_SEPOLIA_LINK \
    "transfer(address,uint256)" \
    $ARBITRUM_SENDER_ADDRESS \
    1000000000000000000 \
    --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY
```

## Verification

### Step 7: Verify Deployment

**Check Token Deployment:**

```bash
# Check total supply
cast call $SEPOLIA_TOKEN_ADDRESS \
    "totalSupply()" \
    --rpc-url $SEPOLIA_RPC_URL

# Check token name
cast call $SEPOLIA_TOKEN_ADDRESS \
    "name()" \
    --rpc-url $SEPOLIA_RPC_URL

# Check owner
cast call $SEPOLIA_TOKEN_ADDRESS \
    "owner()" \
    --rpc-url $SEPOLIA_RPC_URL
```

**Check CCIP Configuration:**

```bash
# Check if destination chain is allowlisted
cast call $SEPOLIA_SENDER_ADDRESS \
    "allowlistedDestinationChains(uint64)" \
    $ARBITRUM_SEPOLIA_CHAIN_SELECTOR \
    --rpc-url $SEPOLIA_RPC_URL

# Check LINK balance
cast call $SEPOLIA_LINK \
    "balanceOf(address)" \
    $SEPOLIA_SENDER_ADDRESS \
    --rpc-url $SEPOLIA_RPC_URL
```

### Step 8: Test Cross-Chain Transfer

**Execute a test transfer:**

```bash
# First, mint some tokens to your address
cast send $SEPOLIA_TOKEN_ADDRESS \
    "mint(address,uint256)" \
    $YOUR_ADDRESS \
    1000000000000000000 \
    --rpc-url $SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY

# Send cross-chain
cast send $SEPOLIA_SENDER_ADDRESS \
    "sendTokensCrossChain(uint64,address,uint256)" \
    $ARBITRUM_SEPOLIA_CHAIN_SELECTOR \
    $YOUR_ADDRESS \
    100000000000000000 \
    --rpc-url $SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY
```

**Monitor the transfer:**

Check CCIP Explorer: https://ccip.chain.link/

## Mainnet Deployment

⚠️ **WARNING**: Mainnet deployment involves real funds. Proceed with extreme caution.

### Pre-Mainnet Checklist

- [ ] All tests pass on testnets
- [ ] Cross-chain transfers tested successfully
- [ ] Contracts audited by professional firm
- [ ] Multi-sig wallet prepared for ownership
- [ ] Emergency procedures documented
- [ ] Team trained on operations
- [ ] Monitoring system in place
- [ ] Sufficient LINK tokens acquired
- [ ] Gas costs calculated and budgeted

### Mainnet Networks

Update `.env` for mainnet:

```bash
# Mainnet RPC URLs
ETHEREUM_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR-API-KEY
ARBITRUM_RPC_URL=https://arb-mainnet.g.alchemy.com/v2/YOUR-API-KEY
AVALANCHE_RPC_URL=https://api.avax.network/ext/bc/C/rpc

# Mainnet CCIP Routers
ETHEREUM_CCIP_ROUTER=0x80226fc0Ee2b096224EeAc085Bb9a8cba1146f7D
ARBITRUM_CCIP_ROUTER=0x141fa059441E0ca23ce184B6A78bafD2A517DdE8
AVALANCHE_CCIP_ROUTER=0x27F39D0af3303703750D4001fCc1844c6491563c

# Mainnet LINK Tokens
ETHEREUM_LINK=0x514910771AF9Ca656af840dff83E8264EcF986CA
ARBITRUM_LINK=0xf97f4df75117a78c1A5a0DBb814Af92458539FB4
AVALANCHE_LINK=0x5947BB275c521040051D82396192181b413227A3

# Mainnet Chain Selectors
ETHEREUM_CHAIN_SELECTOR=5009297550715157269
ARBITRUM_CHAIN_SELECTOR=4949039107694359620
AVALANCHE_CHAIN_SELECTOR=6433500567565415381
```

### Mainnet Deployment Steps

1. **Deploy to Ethereum Mainnet**:
```bash
forge script script/DeployCrossChainRebaseToken.s.sol \
    --rpc-url $ETHEREUM_RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --verify \
    --etherscan-api-key $ETHERSCAN_API_KEY
```

2. **Deploy to other chains** (Arbitrum, Avalanche, etc.)

3. **Transfer ownership to multi-sig**:
```bash
cast send $TOKEN_ADDRESS \
    "transferOwnership(address)" \
    $MULTISIG_ADDRESS \
    --rpc-url $ETHEREUM_RPC_URL \
    --private-key $PRIVATE_KEY
```

4. **Configure CCIP** using multi-sig

5. **Fund with LINK** (substantial amounts for mainnet)

## Post-Deployment

### Monitoring

Set up monitoring for:
- Token transfers
- Rebase events
- Cross-chain message status
- LINK balance in sender contracts
- Contract ownership
- Failed transactions

### Documentation

Document all:
- Deployed contract addresses
- Configuration parameters
- Multi-sig signers
- Emergency contacts
- Operational procedures

### Security

1. **Verify ownership**: Ensure multi-sig controls critical functions
2. **Test emergency procedures**: Practice pause/unpause if implemented
3. **Monitor continuously**: Set up alerts for unusual activity
4. **Regular audits**: Schedule periodic security reviews

## Troubleshooting

### Common Issues

**"Insufficient LINK balance"**
- Fund the sender contract with more LINK tokens
- Check LINK balance: `cast call $LINK_ADDRESS "balanceOf(address)" $SENDER_ADDRESS`

**"Destination chain not allowlisted"**
- Run allowlisting commands again
- Verify with: `cast call $SENDER_ADDRESS "allowlistedDestinationChains(uint64)" $CHAIN_SELECTOR`

**"Transaction reverts during cross-chain send"**
- Check token ownership (should be sender contract for burn permission)
- Verify LINK approval
- Ensure receiver is allowlisted

**"Verification fails"**
- Wait a few minutes and try again
- Use `--watch` flag to monitor verification
- Check constructor arguments match deployment

**"Out of gas"**
- Increase gas limit: `--gas-limit 3000000`
- Check gas price: `--gas-price 50gwei`

### Debug Commands

```bash
# Check contract code exists
cast code $CONTRACT_ADDRESS --rpc-url $RPC_URL

# Check transaction receipt
cast receipt $TX_HASH --rpc-url $RPC_URL

# Decode revert reason
cast run $TX_HASH --rpc-url $RPC_URL

# Check current gas price
cast gas-price --rpc-url $RPC_URL
```

### Getting Help

- Check CCIP Explorer: https://ccip.chain.link/
- Chainlink Discord: https://discord.gg/chainlink
- Foundry Support: https://t.me/foundry_support
- Project Issues: https://github.com/your-username/crossChainRebaseToken/issues

## Deployment Checklist

### Pre-Deployment
- [ ] All dependencies installed
- [ ] Environment variables configured
- [ ] Sufficient funds in wallet
- [ ] LINK tokens acquired
- [ ] RPC endpoints tested

### During Deployment
- [ ] Deploy to source chain
- [ ] Deploy to destination chain(s)
- [ ] Save all contract addresses
- [ ] Verify contracts on explorers
- [ ] Configure CCIP connections
- [ ] Fund sender contracts with LINK

### Post-Deployment
- [ ] Test basic token operations
- [ ] Test cross-chain transfers
- [ ] Transfer ownership to multi-sig
- [ ] Document all addresses and config
- [ ] Set up monitoring
- [ ] Train team on operations

---

**Remember**: Always test thoroughly on testnets before mainnet deployment!
