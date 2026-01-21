# Per-Chain Deployment Runbooks

## Ethereum Sepolia (L1 Vault)

### Prerequisites
- Sepolia ETH for gas (~0.5 ETH recommended)
- LINK tokens for CCIP fees (~10 LINK)
- Etherscan API key for verification

### Deployment Steps

```bash
# 1. Set environment
export CHAIN_NAME="sepolia"
export RPC_URL="https://eth-sepolia.g.alchemy.com/v2/YOUR-API-KEY"
export VERIFIER="etherscan"
export VERIFIER_KEY="YOUR-ETHERSCAN-KEY"

# 2. Deploy vault system
forge script script/DeployVault.s.sol \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --verify \
    --verifier $VERIFIER \
    --verifier-url https://api-sepolia.etherscan.io/api \
    -vvvv

# 3. Configure vault parameters
forge script script/ConfigureVault.s.sol \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    -vvvv
```

### Verification Post-Deploy
```bash
# Check deployed contracts
cast call <VAULT_ADDRESS> "getCurrentInterestRate()(uint256)" --rpc-url $RPC_URL

# Verify owner
cast call <VAULT_ADDRESS> "owner()(address)" --rpc-url $RPC_URL

# Check balance
cast balance <VAULT_ADDRESS> --rpc-url $RPC_URL
```

---

## Arbitrum Sepolia (L2 Bridged)

### Prerequisites
- Arbitrum Sepolia ETH for gas (~0.1 ETH)
- LINK tokens for CCIP fees (~10 LINK)
- Arbiscan API key for verification

### Deployment Steps

```bash
# 1. Set environment
export CHAIN_NAME="arbitrum-sepolia"
export RPC_URL="https://arb-sepolia.g.alchemy.com/v2/YOUR-API-KEY"
export VERIFIER="arbiscan"

# 2. Deploy receiver system
forge script script/DeployReceiver.s.sol \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --verify \
    --verifier arbiscan \
    --verifier-url https://api-sepolia.arbiscan.io/api \
    -vvvv

# 3. Setup CCIP allowlisting
forge script script/ConfigureCCIPReceiver.s.sol \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    -vvvv
```

### Verification
```bash
# Check receiver allowlisted chains
cast call <RECEIVER_ADDRESS> \
    "allowlistedSourceChains(uint64)(bool)" 16015286601757825753 \
    --rpc-url $RPC_URL

# Check allowlisted sender
cast call <RECEIVER_ADDRESS> \
    "allowlistedSenders(uint64)(address)" 16015286601757825753 \
    --rpc-url $RPC_URL
```

---

## Avalanche Fuji (L2 Optional)

### Prerequisites
- Fuji AVAX for gas (~1 AVAX)
- LINK tokens (~5 LINK)
- Snowtrace API key

### Deployment Steps

```bash
# Similar to Arbitrum but with Fuji RPC and chain selector
export RPC_URL="https://api.avax-test.network/ext/bc/C/rpc"
export CHAIN_SELECTOR="14767482510784806043"  # Fuji on CCIP

forge script script/DeployReceiver.s.sol \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --verify \
    --verifier snowtrace \
    -vvvv
```

---

## Base Sepolia (L2 Optional)

### Prerequisites
- Base Sepolia ETH for gas
- LINK tokens
- Basescan API key

### Deployment
```bash
export RPC_URL="https://sepolia.base.org"
export VERIFIER="basescan"

# Deploy and verify similar to above chains
```

---

## Cross-Chain Configuration

### Step 1: Configure Sender (on Sepolia)

```bash
# Add destination chain
cast send <SENDER_ADDRESS> \
    "allowlistDestinationChain(uint64,bool)" \
    3478487238524512106 true \
    --rpc-url $SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY

# Add receiver address on destination
cast send <SENDER_ADDRESS> \
    "allowlistReceiver(uint64,address)" \
    3478487238524512106 <ARBITRUM_RECEIVER_ADDRESS> \
    --rpc-url $SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY

# Configure per-chain fees (1% protocol fee)
cast send <SENDER_ADDRESS> \
    "setChainFeeBps(uint64,uint256)" \
    3478487238524512106 100 \
    --rpc-url $SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY

# Configure per-chain caps (100 ETH per send, 500 ETH daily)
cast send <SENDER_ADDRESS> \
    "setChainCaps(uint64,uint256,uint256)" \
    3478487238524512106 "100000000000000000000" "500000000000000000000" \
    --rpc-url $SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY
```

### Step 2: Configure Receiver (on Arbitrum Sepolia)

```bash
# Add source chain
cast send <RECEIVER_ADDRESS> \
    "allowlistSourceChain(uint64,bool)" \
    16015286601757825753 true \
    --rpc-url $ARBITRUM_RPC_URL \
    --private-key $PRIVATE_KEY

# Add sender address on source
cast send <RECEIVER_ADDRESS> \
    "allowlistSender(uint64,address)" \
    16015286601757825753 <SEPOLIA_SENDER_ADDRESS> \
    --rpc-url $ARBITRUM_RPC_URL \
    --private-key $PRIVATE_KEY

# Configure per-chain caps (90 ETH per message, 450 ETH daily)
cast send <RECEIVER_ADDRESS> \
    "setChainCaps(uint64,uint256,uint256)" \
    16015286601757825753 "90000000000000000000" "450000000000000000000" \
    --rpc-url $ARBITRUM_RPC_URL \
    --private-key $PRIVATE_KEY
```

### CCIP Chain Selectors Reference

| Network | Testnet | Chain Selector | LINK Faucet |
|---------|---------|----------------|------------|
| Sepolia | Yes | 16015286601757825753 | https://faucets.chain.link/ |
| Arbitrum Sepolia | Yes | 3478487238524512106 | https://faucets.chain.link/ |
| Avalanche Fuji | Yes | 14767482510784806043 | https://faucets.chain.link/ |
| Base Sepolia | Yes | 10344971235874465080 | https://faucets.chain.link/ |
| Ethereum | Mainnet | 5009297550715157269 | N/A |
| Arbitrum One | Mainnet | 4949039107694359331 | N/A |
| Avalanche C-Chain | Mainnet | 6433500567565415735 | N/A |
| Base | Mainnet | 15971525489660198786 | N/A |

---

## Testing End-to-End

### 1. Fund Vault and Configure

```bash
# Send ETH to vault (e.g., 10 ETH)
cast send <VAULT_ADDRESS> --value "10ether" \
    --rpc-url $SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY

# Or use vault deposit function if available
```

### 2. Test Deposit

```bash
# Deposit 1 ETH to vault
cast send <VAULT_ADDRESS> \
    "deposit()" \
    --value "1ether" \
    --rpc-url $SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY
```

### 3. Test Bridge

```bash
# Fund sender with LINK for fees
cast send <LINK_ADDRESS> \
    "transfer(address,uint256)" <SENDER_ADDRESS> "5000000000000000000" \
    --rpc-url $SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY

# Approve sender to spend tokens
cast send <REBASE_TOKEN_ADDRESS> \
    "approve(address,uint256)" <SENDER_ADDRESS> "1000000000000000000000" \
    --rpc-url $SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY

# Send tokens cross-chain
cast send <SENDER_ADDRESS> \
    "sendTokensCrossChain(uint64,address,uint256)" \
    3478487238524512106 <YOUR_ADDRESS> "1000000000000000000" \
    --rpc-url $SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY
```

### 4. Wait for CCIP Confirmation

- Check CCIP explorer for message status
- Monitor receiver contract for `MessageReceived` event
- Verify balance increased on destination chain

```bash
# Check balance on Arbitrum
cast call <ARBITRUM_TOKEN_ADDRESS> \
    "balanceOf(address)(uint256)" <YOUR_ADDRESS> \
    --rpc-url $ARBITRUM_RPC_URL
```

---

## Troubleshooting Deployment Issues

### Issue: `ChainNotSupported` error

**Cause**: Chain selector not properly configured in CCIP allowlist

**Solution**:
```bash
# Verify chain selector is correct for network
cast call <SENDER_ADDRESS> \
    "allowlistedDestinationChains(uint64)(bool)" <SELECTOR> \
    --rpc-url $SEPOLIA_RPC_URL
```

### Issue: `ReceiverNotAllowlisted` error

**Cause**: Receiver address not added to sender's allowlist

**Solution**:
```bash
# Re-run allowlist configuration
cast send <SENDER_ADDRESS> \
    "allowlistReceiver(uint64,address)" \
    <CHAIN_SELECTOR> <RECEIVER_ADDRESS> \
    --rpc-url $SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY
```

### Issue: CCIP message pending too long

**Cause**: Router congestion or network issue

**Solution**:
- Wait 20-30 minutes for confirmation
- Check CCIP explorer for error details
- Increase gas limit if needed in next attempt

### Issue: `NotEnoughLINK` error

**Cause**: Insufficient LINK balance for fees

**Solution**:
```bash
# Fund sender with more LINK
cast send <LINK_ADDRESS> \
    "transfer(address,uint256)" <SENDER_ADDRESS> "10000000000000000000" \
    --rpc-url $SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY
```

---

## Post-Deployment Checklist

- [ ] Verify contracts on block explorers
- [ ] Test deposit functionality
- [ ] Test redeem functionality
- [ ] Test pause/unpause controls
- [ ] Test cross-chain bridge
- [ ] Monitor gas usage and optimization
- [ ] Create vault cap configuration
- [ ] Setup allowlist for depositors (if enabled)
- [ ] Configure protocol fee recipient
- [ ] Fund CCIP contracts with sufficient LINK
- [ ] Setup monitoring and alerts
