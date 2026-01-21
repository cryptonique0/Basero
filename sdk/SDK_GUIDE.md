# Basero SDK Guide

## Table of Contents

- [Installation](#installation)
- [Getting Started](#getting-started)
- [Basic Usage](#basic-usage)
- [Advanced Features](#advanced-features)
- [API Reference](#api-reference)
- [Examples](#examples)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)

## Installation

```bash
npm install @basero/sdk ethers@^6.0.0
```

Or with yarn:

```bash
yarn add @basero/sdk ethers@^6.0.0
```

### Requirements

- Node.js 16+
- ethers.js v6.0+
- TypeScript 4.5+ (optional but recommended)

## Getting Started

### Initialize the SDK

```typescript
import { BaseroSDK } from '@basero/sdk';
import { ethers } from 'ethers';

// Create a provider
const provider = new ethers.JsonRpcProvider('https://sepolia.drpc.org');

// Create network configuration
const config = {
  chainId: 11155111, // Sepolia
  rpcUrl: 'https://sepolia.drpc.org',
  explorerUrl: 'https://sepolia.etherscan.io',
  addresses: {
    token: '0x...',
    vault: '0x...',
    bridge: '0x...',
    governor: '0x...',
    timelock: '0x...',
    votingEscrow: '0x...',
  },
};

// Initialize SDK
const sdk = new BaseroSDK(provider, config);
```

### Set Up a Signer (for transactions)

```typescript
// Using MetaMask or other Web3 provider
const signer = await provider.getSigner();
sdk.setSigner(signer);

// Now you can execute transactions
```

## Basic Usage

### Token Operations

```typescript
const token = sdk.getToken();

// Get token metadata
const metadata = await token.getMetadata();
console.log(metadata);
// { name: 'Basero Token', symbol: 'BASE', decimals: 18, totalSupply: BigInt(...) }

// Get balance
const balance = await token.getBalance('0x1234...');
console.log(balance);
// { raw: BigInt('1000000000000000000'), formatted: '1.00', decimals: 18 }

// Get allowance
const allowance = await token.getAllowance(
  userAddress,
  vaultAddress
);

// Transfer tokens
const result = await token.transfer(recipientAddress, '100'); // 100 tokens
console.log(result);
// { success: true, hash: '0x...', data: null, error: null }

// Approve spending
await token.approve(vaultAddress, ethers.MaxUint256);

// Rebase tokens
await token.rebase(5); // 5% rebase
```

### Vault Operations

```typescript
const vault = sdk.getVault();

// Get vault metrics
const metrics = await vault.getMetrics();
console.log(metrics);
// {
//   totalAssets: BigInt(...),
//   totalSupply: BigInt(...),
//   sharePrice: BigInt(...)
// }

// Check your vault shares balance
const vaultBalance = await vault.getBalance(userAddress);

// Preview deposit
const preview = await vault.previewDeposit('1000');
console.log(preview);
// { shares: BigInt(...), raw: '1000000000000000000' }

// Deposit into vault
const depositResult = await vault.deposit('1000', userAddress);
console.log(depositResult);
// { success: true, hash: '0x...', data: null }

// Withdraw from vault
const withdrawResult = await vault.withdraw(
  shareAmount,
  userAddress,
  userAddress
);
```

### Bridge Operations

```typescript
const bridge = sdk.getBridge();

// Check bridge status
const status = await bridge.getStatus();
console.log(status);
// { isPaused: false }

// Send tokens across chains
const transferResult = await bridge.sendTokens(
  8453, // Base chain ID
  recipientAddress,
  '500', // 500 tokens
);
```

### Governance

```typescript
const governance = sdk.getGovernance();

// Check voting power
const votingPower = await governance.getVotingPower(userAddress);
console.log(votingPower);
// { raw: BigInt(...), formatted: '100.00' }

// Lock tokens for voting
await governance.lock('1000', 52 * 7 * 24 * 60 * 60); // 52 weeks

// Create a proposal
const proposeResult = await governance.propose(
  ['0x...'], // targets
  [BigInt(0)], // values
  ['0x...'], // calldatas
  'Proposal: Increase rebase rate'
);

// Cast a vote
await governance.castVote(proposalId, 1); // 1 = For, 0 = Against, 2 = Abstain
```

## Advanced Features

### Transaction Builders

Use fluent transaction builders for complex operations:

```typescript
import { VaultTxBuilder, TokenTxBuilder, BatchTxBuilder } from '@basero/sdk';

// Single operation
const depositTx = new VaultTxBuilder()
  .deposit(vaultAddress, '1000', userAddress)
  .setDescription('User deposit')
  .build();

// Multiple operations in batch
const batch = new BatchTxBuilder()
  .addToken(
    new TokenTxBuilder()
      .approve(vaultAddress, ethers.MaxUint256)
      .setDescription('Approve vault')
  )
  .addVault(
    new VaultTxBuilder()
      .deposit(vaultAddress, '1000', userAddress)
      .setDescription('Deposit into vault')
  )
  .build();

console.log(batch);
// {
//   targets: [...],
//   values: [...],
//   calldatas: [...],
//   count: 2
// }
```

### Governance Proposals

```typescript
import { GovernanceTxBuilder } from '@basero/sdk';

const proposal = new GovernanceTxBuilder()
  .updateParameter(tokenAddress, 'rebasePercent', 5)
  .updateParameter(vaultAddress, 'managementFee', 1)
  .setVotingParameters(
    governorAddress,
    1, // votingDelay in blocks
    50400, // votingPeriod in blocks (1 week)
    100000 // proposalThreshold
  )
  .setDescription('Update protocol parameters')
  .getProposal();

// Submit proposal to governance
const tx = await governor.propose(
  proposal.targets,
  proposal.values,
  proposal.calldatas,
  proposal.description
);
```

### Event Monitoring

```typescript
import { EventIndexer } from '@basero/sdk';

const indexer = new EventIndexer();

// Get recent logs
const logs = await provider.getLogs({
  address: tokenAddress,
  fromBlock: blockNumber - 1000,
  toBlock: blockNumber,
});

// Get user activity
const activity = indexer.getUserActivity(logs, userAddress);
console.log(activity);
// {
//   transfers: 5,
//   approvals: 2,
//   deposits: 3,
//   withdrawals: 1,
//   votes: 2,
//   messages: 0
// }
```

## API Reference

### BaseroSDK

**Constructor**
```typescript
new BaseroSDK(
  provider: ethers.Provider,
  config: NetworkConfig,
  signer?: ethers.Signer
)
```

**Methods**
- `setSigner(signer: ethers.Signer): void` - Set transaction signer
- `getToken(): TokenHelper` - Get token helper
- `getVault(): VaultHelper` - Get vault helper
- `getBridge(): BridgeHelper` - Get bridge helper
- `getGovernance(): GovernanceHelper` - Get governance helper
- `getBalance(address: string): Promise<Balance>` - Get all balances
- `getConfig(): NetworkConfig` - Get current configuration
- `hasSigner(): boolean` - Check if signer is set
- `getProvider(): ethers.Provider` - Get provider
- `getSigner(): ethers.Signer | undefined` - Get signer

### TokenHelper

**Methods**
- `getMetadata(): Promise<TokenMetadata>` - Get token info
- `getBalance(address: string): Promise<Amount>` - Get balance
- `getTotalSupply(): Promise<Amount>` - Get total supply
- `getAllowance(owner: string, spender: string): Promise<Amount>` - Get allowance
- `transfer(to: string, amount: string, options?: TransactionOptions): Promise<OperationResult>` - Transfer tokens
- `approve(spender: string, amount: string, options?: TransactionOptions): Promise<OperationResult>` - Approve spending
- `rebase(percent: number, options?: TransactionOptions): Promise<OperationResult>` - Execute rebase

### VaultHelper

**Methods**
- `getMetrics(): Promise<VaultMetrics>` - Get vault metrics
- `getBalance(address: string): Promise<Amount>` - Get vault share balance
- `previewDeposit(amount: string): Promise<{shares: bigint, raw: string}>` - Preview deposit
- `deposit(amount: string, receiver?: string, options?: TransactionOptions): Promise<OperationResult>` - Deposit
- `withdraw(shares: string, receiver?: string, owner?: string, options?: TransactionOptions): Promise<OperationResult>` - Withdraw

### Utilities

**AmountFormatter**
- `toBN(amount: string|number|bigint, decimals?: number): bigint`
- `toDecimal(amount: bigint, decimals?: number, displayDecimals?: number): string`
- `toPercent(amount: bigint, total: bigint, decimals?: number): string`
- `toUSD(amount: bigint, price: number, decimals?: number): string`
- `toAbbreviated(amount: bigint, decimals?: number): string`
- `convert(amount: bigint, fromDecimals: number, toDecimals: number): bigint`

**AddressUtils**
- `isValidAddress(address: string): boolean`
- `toChecksum(address: string): string`
- `formatAddress(address: string, charsStart?: number, charsEnd?: number): string`
- `compare(address1: string, address2: string): boolean`
- `isZeroAddress(address: string): boolean`

**ChainUtils**
- `getChainName(chainId: number): string`
- `getTxExplorerUrl(chainId: number, txHash: string): string | null`
- `getAddressExplorerUrl(chainId: number, address: string): string | null`
- `isTestnet(chainId: number): boolean`
- `isMainnet(chainId: number): boolean`

**Validators**
- `isValidAmount(amount: any): boolean`
- `isValidTransferAmount(amount: bigint): boolean`
- `isValidPercent(percent: number): boolean`
- `isValidDuration(duration: bigint | number): boolean`
- `isValidChainId(chainId: number): boolean`
- `validateNetworkConfig(config: any): boolean`

**FeeEstimator**
- `estimateDepositGas(): bigint`
- `estimateWithdrawGas(): bigint`
- `estimateTransferGas(): bigint`
- `estimateApprovalGas(): bigint`
- `estimateRebaseGas(): bigint`
- `estimateVoteCastGas(): bigint`
- `estimateProposalGas(): bigint`
- `estimateCrossChainGas(): bigint`
- `calculateFee(gas: bigint, gasPrice: bigint): bigint`
- `calculateTotalCost(amount: bigint, gas: bigint, gasPrice: bigint): bigint`

**TimeUtils**
- `now(): bigint` - Current timestamp
- `formatDuration(seconds: bigint | number): string`
- `getDurationFromNow(timestamp: bigint | number): bigint`
- `hasTimePassed(timestamp: bigint | number): boolean`
- `hoursToSeconds(hours: number): bigint`
- `daysToSeconds(days: number): bigint`
- `weeksToSeconds(weeks: number): bigint`
- `yearsToSeconds(years: number): bigint`

## Examples

### Complete Deposit Workflow

```typescript
import { BaseroSDK, AmountFormatter, Validators } from '@basero/sdk';
import { ethers } from 'ethers';

async function depositToVault() {
  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const signer = await provider.getSigner();
  
  const sdk = new BaseroSDK(provider, config, signer);
  
  const depositAmount = '1000'; // 1000 tokens
  
  // Validate amount
  if (!Validators.isValidAmount(depositAmount)) {
    throw new Error('Invalid amount');
  }
  
  const token = sdk.getToken();
  const vault = sdk.getVault();
  
  // Check balance
  const balance = await token.getBalance(signer.address);
  console.log(`Balance: ${balance.formatted} tokens`);
  
  // Approve vault
  const approval = await token.approve(
    config.addresses.vault,
    ethers.MaxUint256
  );
  console.log(`Approved at tx: ${approval.hash}`);
  
  // Deposit
  const result = await vault.deposit(depositAmount);
  console.log(`Deposit successful: ${result.hash}`);
  
  // Check new balance
  const newBalance = await vault.getBalance(signer.address);
  console.log(`New vault shares: ${newBalance.formatted}`);
}
```

### Monitoring Token Transfers

```typescript
import { TokenEventParser } from '@basero/sdk';

async function trackTransfers(address: string) {
  const parser = new TokenEventParser();
  
  const logs = await provider.getLogs({
    address: tokenAddress,
    topics: [ethers.id('Transfer(address,address,uint256)')],
    fromBlock: 'latest' - 1000,
  });
  
  const transfers = parser.filterTransfers(logs, {
    from: address,
    to: undefined,
  });
  
  console.log(`User transferred ${transfers.length} times`);
  let totalTransferred = 0n;
  
  for (const transfer of transfers) {
    totalTransferred += transfer.amount;
  }
  
  console.log(`Total transferred: ${AmountFormatter.toDecimal(totalTransferred)}`);
}
```

### Governance Proposal

```typescript
import { GovernanceTxBuilder } from '@basero/sdk';

async function createProposal() {
  const builder = new GovernanceTxBuilder()
    .updateParameter(
      config.addresses.token,
      'rebasePercent',
      ethers.parseUnits('5', 0)
    )
    .setVotingParameters(
      config.addresses.governor,
      1,
      50400,
      ethers.parseUnits('100000', 18)
    )
    .setDescription('Increase rebase to 5%');
  
  const proposal = builder.getProposal();
  
  const tx = await governor.propose(
    proposal.targets,
    proposal.values,
    proposal.calldatas,
    proposal.description
  );
  
  console.log(`Proposal created: ${tx.hash}`);
}
```

## Best Practices

### 1. Always Validate Amounts

```typescript
import { Validators } from '@basero/sdk';

if (!Validators.isValidAmount(amount)) {
  throw new Error('Invalid amount');
}
```

### 2. Use Safe Operations

```typescript
import { AmountFormatter } from '@basero/sdk';

// Avoid overflow
const total = AmountFormatter.safeAdd(balance, deposit);

// Avoid underflow
const remaining = AmountFormatter.safeSub(balance, withdrawal);
```

### 3. Handle Errors Gracefully

```typescript
import { ErrorFormatter } from '@basero/sdk';

try {
  await token.transfer(address, amount);
} catch (error) {
  const reason = ErrorFormatter.extractRevertReason(error);
  console.error(`Transfer failed: ${reason}`);
}
```

### 4. Check Chain ID

```typescript
import { Validators, ChainUtils } from '@basero/sdk';

const provider = new ethers.JsonRpcProvider(rpcUrl);
const network = await provider.getNetwork();

if (!Validators.isValidChainId(Number(network.chainId))) {
  throw new Error(`Unsupported chain: ${ChainUtils.getChainName(Number(network.chainId))}`);
}
```

### 5. Use Transaction Builders for Complex Operations

```typescript
import { BatchTxBuilder, VaultTxBuilder, TokenTxBuilder } from '@basero/sdk';

const batch = new BatchTxBuilder()
  .addToken(new TokenTxBuilder().approve(vaultAddress, amount))
  .addVault(new VaultTxBuilder().deposit(vaultAddress, amount, receiver))
  .build();
```

## Troubleshooting

### Connection Issues

**Error**: "Failed to connect to RPC"
- Check RPC URL is correct
- Verify network connectivity
- Try alternative RPC endpoint

### Insufficient Balance

```typescript
import { ErrorFormatter } from '@basero/sdk';

try {
  await token.transfer(recipient, amount);
} catch (error) {
  if (ErrorFormatter.isInsufficientBalance(error)) {
    const balance = await token.getBalance(userAddress);
    console.log(`Available: ${balance.formatted}`);
  }
}
```

### Invalid Address

```typescript
import { AddressUtils, ErrorFormatter } from '@basero/sdk';

if (!AddressUtils.isValidAddress(address)) {
  throw new Error('Invalid address format');
}
```

### Transaction Timeouts

```typescript
import { ErrorFormatter } from '@basero/sdk';

try {
  await transaction.wait();
} catch (error) {
  if (ErrorFormatter.isTimeoutError(error)) {
    console.log('Transaction timed out - check tx hash on explorer');
  }
}
```

### Approval Issues

Always approve before operations:

```typescript
// Approve maximum to avoid multiple approvals
await token.approve(vaultAddress, ethers.MaxUint256);
```

## Support

For issues or questions:
- GitHub Issues: https://github.com/basero/sdk
- Documentation: https://docs.basero.io
- Discord: https://discord.gg/basero
