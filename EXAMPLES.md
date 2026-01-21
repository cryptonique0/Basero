# Example Usage

This file demonstrates common usage patterns for the Cross-Chain Rebase Token system.

## Table of Contents

1. [Basic Token Operations](#basic-token-operations)
2. [Rebase Operations](#rebase-operations)
3. [Cross-Chain Transfers](#cross-chain-transfers)
4. [Administrative Functions](#administrative-functions)

## Basic Token Operations

### Transfer Tokens

```solidity
// Transfer 100 tokens to another address
uint256 amount = 100 * 10**18;
rebaseToken.transfer(recipientAddress, amount);
```

### Approve and TransferFrom

```solidity
// Approve spender to transfer tokens on your behalf
uint256 allowanceAmount = 1000 * 10**18;
rebaseToken.approve(spenderAddress, allowanceAmount);

// Spender can now transfer tokens
rebaseToken.transferFrom(ownerAddress, recipientAddress, amount);
```

### Check Balances

```solidity
// Check token balance
uint256 balance = rebaseToken.balanceOf(userAddress);

// Check shares (underlying ownership)
uint256 shares = rebaseToken.sharesOf(userAddress);

// Check total supply
uint256 supply = rebaseToken.totalSupply();
```

## Rebase Operations

### Absolute Rebase

```solidity
// Rebase to a specific total supply
uint256 newTotalSupply = 2_000_000 * 10**18;
rebaseToken.rebase(newTotalSupply);
```

**Effect**: If you previously had 10% of tokens, you still have 10% after rebase, but the absolute amount changes based on new total supply.

Example:
- Before: 100,000 tokens out of 1,000,000 total = 10%
- After rebase to 2,000,000: You now have 200,000 tokens (still 10%)

### Percentage-Based Rebase

```solidity
// Increase supply by 5% (500 basis points)
rebaseToken.rebaseByPercentage(500, true);

// Decrease supply by 3% (300 basis points)
rebaseToken.rebaseByPercentage(300, false);
```

**Basis Points**: 10,000 = 100%, so 500 = 5%

### Understanding Shares

The token uses a shares-based system:

```solidity
// Get shares equivalent to token amount
uint256 shares = rebaseToken.getSharesByTokenAmount(tokenAmount);

// Get token amount equivalent to shares
uint256 tokens = rebaseToken.getTokenAmountByShares(sharesAmount);
```

**Key Concept**: Shares never change on rebase, only the conversion rate between shares and tokens changes.

## Cross-Chain Transfers

### Setup (One-time Configuration)

```solidity
// On source chain (e.g., Ethereum Sepolia)
CCIPRebaseTokenSender sender = CCIPRebaseTokenSender(senderAddress);

// Allowlist destination chain
sender.allowlistDestinationChain(arbitrumSepoliaChainSelector, true);

// Allowlist receiver contract on destination
sender.allowlistReceiver(arbitrumSepoliaChainSelector, receiverAddress);

// On destination chain (e.g., Arbitrum Sepolia)
CCIPRebaseTokenReceiver receiver = CCIPRebaseTokenReceiver(receiverAddress);

// Allowlist source chain
receiver.allowlistSourceChain(ethereumSepoliaChainSelector, true);

// Allowlist sender contract on source
receiver.allowlistSender(ethereumSepoliaChainSelector, senderAddress);
```

### Funding the Sender

```solidity
// The sender contract needs LINK tokens for CCIP fees
IERC20 linkToken = IERC20(linkTokenAddress);
linkToken.transfer(senderAddress, 1 * 10**18); // Send 1 LINK
```

### Execute Cross-Chain Transfer

```solidity
// Burn tokens on source chain and mint on destination
uint256 amount = 1000 * 10**18;
bytes32 messageId = sender.sendTokensCrossChain(
    destinationChainSelector,
    recipientAddress,
    amount
);
```

**What happens**:
1. Tokens are burned from sender on source chain
2. CCIP message is sent to destination chain
3. Tokens are minted to recipient on destination chain

### Monitor Cross-Chain Transfer

```solidity
// Listen for events
event MessageSent(
    bytes32 indexed messageId,
    uint64 indexed destinationChainSelector,
    address receiver,
    uint256 amount,
    uint256 fees
);

event MessageReceived(
    bytes32 indexed messageId,
    uint64 indexed sourceChainSelector,
    address sender,
    address recipient,
    uint256 amount
);
```

## Administrative Functions

### Mint New Tokens

```solidity
// Mint 10,000 new tokens to an address
uint256 mintAmount = 10_000 * 10**18;
rebaseToken.mint(recipientAddress, mintAmount);
```

**Effect**: Increases both total supply and total shares proportionally.

### Burn Tokens

```solidity
// Burn 5,000 tokens from an address
uint256 burnAmount = 5_000 * 10**18;
rebaseToken.burn(holderAddress, burnAmount);
```

**Effect**: Decreases both total supply and total shares proportionally.

### Transfer Ownership

```solidity
// Transfer contract ownership to new owner
rebaseToken.transferOwnership(newOwnerAddress);

// Or for CCIP contracts
sender.transferOwnership(newOwnerAddress);
receiver.transferOwnership(newOwnerAddress);
```

### Withdraw LINK Fees

```solidity
// Withdraw accumulated LINK from sender contract
sender.withdrawLINK(beneficiaryAddress);
```

## Complete Example Flow

### Scenario: Cross-Chain Transfer with Rebase

```solidity
// 1. Initial Setup
RebaseToken token = new RebaseToken("Rebase Token", "RBT", 1_000_000 * 10**18);
CCIPRebaseTokenSender sender = new CCIPRebaseTokenSender(routerAddress, linkAddress, address(token));
token.transferOwnership(address(sender));

// 2. User has 10,000 tokens (1% of supply)
token.transfer(userAddress, 10_000 * 10**18);

// 3. Rebase increases supply by 10%
token.rebaseByPercentage(1000, true);
// User now has 11,000 tokens (still 1% of new supply)

// 4. User transfers 5,000 tokens cross-chain
sender.sendTokensCrossChain(
    destinationChainSelector,
    recipientAddress,
    5_000 * 10**18
);

// 5. On source chain: User has 6,000 tokens
// 6. On destination chain: Recipient receives 5,000 tokens

// 7. Another rebase decreases supply by 5%
token.rebaseByPercentage(500, false);
// All balances decrease by 5% proportionally
```

## Testing Examples

### Using Foundry Tests

```solidity
// test/Example.t.sol
function testCrossChainTransfer() public {
    // Setup
    uint256 transferAmount = 1000 * 10**18;
    token.transfer(alice, transferAmount);
    
    // Execute transfer
    vm.prank(alice);
    bytes32 messageId = sender.sendTokensCrossChain(
        DEST_CHAIN_SELECTOR,
        bob,
        transferAmount
    );
    
    // Verify
    assertEq(token.balanceOf(alice), 0);
    assertTrue(messageId != bytes32(0));
}

function testRebasePreservesOwnership() public {
    // Give alice 50% of tokens
    token.transfer(alice, 500_000 * 10**18);
    
    // Rebase to double supply
    token.rebase(2_000_000 * 10**18);
    
    // Alice still has 50%
    assertEq(token.balanceOf(alice), 1_000_000 * 10**18);
}
```

## Common Patterns

### Check Before Transfer

```solidity
uint256 balance = rebaseToken.balanceOf(msg.sender);
require(balance >= amount, "Insufficient balance");
rebaseToken.transfer(recipient, amount);
```

### Calculate Share Percentage

```solidity
uint256 shares = rebaseToken.sharesOf(userAddress);
uint256 totalShares = rebaseToken.getTotalShares();
uint256 percentage = (shares * 10000) / totalShares; // In basis points
```

### Safe Cross-Chain Transfer

```solidity
// Check allowlisting first
require(sender.allowlistedDestinationChains(chainSelector), "Chain not allowed");
require(sender.allowlistedReceivers(chainSelector) != address(0), "No receiver");

// Check LINK balance
uint256 linkBalance = linkToken.balanceOf(address(sender));
require(linkBalance > 0, "Insufficient LINK for fees");

// Execute transfer
sender.sendTokensCrossChain(chainSelector, recipient, amount);
```

## Advanced: Integrating with DeFi

### Example: Lending Protocol Integration

```solidity
// When using rebase tokens in DeFi, track shares instead of balances
contract LendingPool {
    mapping(address => uint256) public depositedShares;
    
    function deposit(uint256 tokenAmount) external {
        uint256 shares = rebaseToken.getSharesByTokenAmount(tokenAmount);
        rebaseToken.transferFrom(msg.sender, address(this), tokenAmount);
        depositedShares[msg.sender] += shares;
    }
    
    function withdraw() external {
        uint256 shares = depositedShares[msg.sender];
        uint256 tokenAmount = rebaseToken.getTokenAmountByShares(shares);
        depositedShares[msg.sender] = 0;
        rebaseToken.transfer(msg.sender, tokenAmount);
    }
}
```

## Security Considerations

1. **Always validate chain selectors** before cross-chain transfers
2. **Monitor LINK balance** to ensure CCIP operations can complete
3. **Use multi-sig** for owner operations in production
4. **Test thoroughly** on testnets before mainnet
5. **Consider rebase impact** when integrating with other protocols
6. **Implement proper access controls** for administrative functions

## Gas Optimization Tips

1. **Batch operations** when possible
2. **Rebase infrequently** to minimize gas costs for users
3. **Use shares** for internal accounting in DeFi integrations
4. **Cache storage reads** in local variables
5. **Use custom errors** instead of require strings

---

For more examples, see the test files in the `test/` directory.
