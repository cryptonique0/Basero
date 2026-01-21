/**
 * @fileoverview Basero SDK Example Scripts
 * Common workflows and use cases
 */

// ============================================================================
// EXAMPLE 1: Simple Deposit Workflow
// ============================================================================

import { BaseroSDK, AmountFormatter, Validators } from '../src/index';
import { ethers } from 'ethers';

export async function exampleSimpleDeposit() {
  console.log('=== Simple Deposit Example ===\n');

  // Initialize
  const provider = new ethers.JsonRpcProvider(
    'https://sepolia.drpc.org'
  );
  const signer = await provider.getSigner();

  const config = {
    chainId: 11155111,
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

  const sdk = new BaseroSDK(provider, config, signer);
  const userAddress = await signer.getAddress();

  // Get token
  const token = sdk.getToken();

  // Check balance
  const balance = await token.getBalance(userAddress);
  console.log(`Current balance: ${balance.formatted} BASE`);

  // Check if we have enough
  const depositAmount = '100';
  if (parseFloat(balance.formatted) < parseFloat(depositAmount)) {
    console.log('Insufficient balance');
    return;
  }

  // Get vault
  const vault = sdk.getVault();

  // Approve vault
  console.log('Approving vault...');
  const approval = await token.approve(
    config.addresses.vault,
    ethers.MaxUint256
  );
  console.log(`✓ Approved at tx: ${approval.hash}`);

  // Deposit
  console.log(`Depositing ${depositAmount} BASE...`);
  const deposit = await vault.deposit(depositAmount, userAddress);
  console.log(`✓ Deposit successful: ${deposit.hash}`);

  // Check new vault balance
  const vaultBalance = await vault.getBalance(userAddress);
  console.log(`New vault shares: ${vaultBalance.formatted}`);
}

// ============================================================================
// EXAMPLE 2: Governance Proposal Workflow
// ============================================================================

export async function exampleGovernanceProposal() {
  console.log('=== Governance Proposal Example ===\n');

  const provider = new ethers.JsonRpcProvider(
    'https://sepolia.drpc.org'
  );
  const signer = await provider.getSigner();

  const config = {
    chainId: 11155111,
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

  const sdk = new BaseroSDK(provider, config, signer);
  const governance = sdk.getGovernance();

  // Check voting power
  const userAddress = await signer.getAddress();
  const votingPower = await governance.getVotingPower(userAddress);
  console.log(`Your voting power: ${votingPower.formatted} veBASE`);

  if (votingPower.raw === 0n) {
    console.log('You need to lock BASE tokens to vote');

    // Lock tokens
    console.log('Locking 1000 BASE for 1 year...');
    const lock = await governance.lock(
      '1000',
      52 * 7 * 24 * 60 * 60 // 1 year in seconds
    );
    console.log(`✓ Locked at tx: ${lock.hash}`);
  }

  // Create proposal
  console.log('Creating proposal to increase rebase rate...');

  // In a real scenario, you would encode the function call
  const targets = [config.addresses.token];
  const values = [BigInt(0)];
  const calldatas = [
    '0x...', // Encoded function call to setRebasePercent(5)
  ];
  const description = 'Proposal: Increase rebase rate to 5%';

  const proposal = await governance.propose(
    targets,
    values,
    calldatas,
    description
  );
  console.log(`✓ Proposal created at tx: ${proposal.hash}`);
}

// ============================================================================
// EXAMPLE 3: Event Monitoring
// ============================================================================

export async function exampleEventMonitoring() {
  console.log('=== Event Monitoring Example ===\n');

  const provider = new ethers.JsonRpcProvider(
    'https://sepolia.drpc.org'
  );

  const config = {
    chainId: 11155111,
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

  const sdk = new BaseroSDK(provider, config);

  // Get recent blocks
  const latestBlock = await provider.getBlockNumber();
  const fromBlock = latestBlock - 1000;

  // Get transfer logs
  console.log(`Scanning blocks ${fromBlock} to ${latestBlock}...\n`);

  const transferLogs = await provider.getLogs({
    address: config.addresses.token,
    topics: [ethers.id('Transfer(address,address,uint256)')],
    fromBlock,
    toBlock: latestBlock,
  });

  console.log(`Found ${transferLogs.length} transfers\n`);

  // Parse transfers
  const { TokenEventParser } = await import('../src/EventDecoders');
  const parser = new TokenEventParser();

  let totalVolume = 0n;
  const topSenders = new Map<string, bigint>();

  for (const log of transferLogs.slice(0, 10)) {
    const transfer = parser.parseTransfer(log);
    if (transfer) {
      totalVolume += transfer.amount;
      const current = topSenders.get(transfer.from) || 0n;
      topSenders.set(transfer.from, current + transfer.amount);

      console.log(`${transfer.from.slice(0, 6)}... → ${transfer.to.slice(0, 6)}... : ${AmountFormatter.toDecimal(transfer.amount)} BASE`);
    }
  }

  console.log(`\nTotal volume: ${AmountFormatter.toDecimal(totalVolume)} BASE`);
}

// ============================================================================
// EXAMPLE 4: Cross-Chain Transfer
// ============================================================================

export async function exampleCrossChainTransfer() {
  console.log('=== Cross-Chain Transfer Example ===\n');

  const provider = new ethers.JsonRpcProvider(
    'https://sepolia.drpc.org'
  );
  const signer = await provider.getSigner();

  const config = {
    chainId: 11155111,
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

  const sdk = new BaseroSDK(provider, config, signer);
  const bridge = sdk.getBridge();

  // Check bridge status
  const status = await bridge.getStatus();
  console.log(`Bridge paused: ${status.isPaused}`);

  if (status.isPaused) {
    console.log('Bridge is paused, cannot transfer');
    return;
  }

  // Send tokens to Base
  const recipientAddress = '0x...';
  const baseChainId = 8453;

  console.log(`Sending 50 BASE to Base network...`);
  const transfer = await bridge.sendTokens(
    baseChainId,
    recipientAddress,
    '50'
  );
  console.log(`✓ Transfer initiated at tx: ${transfer.hash}`);

  // In a real scenario, you would wait for CCIP confirmation
  console.log('Waiting for CCIP confirmation...');
}

// ============================================================================
// EXAMPLE 5: Batch Transaction
// ============================================================================

export async function exampleBatchTransaction() {
  console.log('=== Batch Transaction Example ===\n');

  import { BatchTxBuilder, TokenTxBuilder, VaultTxBuilder } from '../src/index';

  const config = {
    chainId: 11155111,
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

  // Build batch transaction
  const batch = new BatchTxBuilder()
    .addToken(
      new TokenTxBuilder()
        .approve(config.addresses.vault, ethers.MaxUint256)
        .setDescription('Approve vault spending')
    )
    .addVault(
      new VaultTxBuilder()
        .deposit(config.addresses.vault, '1000', '0x...')
        .setDescription('Deposit 1000 BASE')
    )
    .setDescription('Deposit workflow');

  const result = batch.build();
  console.log(`Batch transaction with ${result.count} operations`);
  console.log(`Targets: ${result.targets.length}`);
  console.log(`Calldatas: ${result.calldatas.length}`);
}

// ============================================================================
// EXAMPLE 6: Fee Estimation
// ============================================================================

export async function exampleFeeEstimation() {
  console.log('=== Fee Estimation Example ===\n');

  import { FeeEstimator } from '../src/Utils';

  const provider = new ethers.JsonRpcProvider(
    'https://sepolia.drpc.org'
  );

  // Get current gas price
  const feeData = await provider.getFeeData();
  const gasPrice = feeData.gasPrice || BigInt(0);

  console.log(`Current gas price: ${ethers.formatUnits(gasPrice, 'gwei')} gwei\n`);

  // Estimate various operations
  const operations = [
    { name: 'Transfer', gas: FeeEstimator.estimateTransferGas() },
    { name: 'Deposit', gas: FeeEstimator.estimateDepositGas() },
    { name: 'Withdraw', gas: FeeEstimator.estimateWithdrawGas() },
    { name: 'Vote', gas: FeeEstimator.estimateVoteCastGas() },
    { name: 'Proposal', gas: FeeEstimator.estimateProposalGas() },
    { name: 'Cross-chain', gas: FeeEstimator.estimateCrossChainGas() },
  ];

  for (const op of operations) {
    const fee = FeeEstimator.calculateFee(op.gas, gasPrice);
    const feeEth = parseFloat(ethers.formatUnits(fee));
    console.log(
      `${op.name.padEnd(15)} → ${op.gas} gas → $${(feeEth * 2000).toFixed(2)}`
    );
  }
}

// ============================================================================
// EXAMPLE 7: Token Analysis
// ============================================================================

export async function exampleTokenAnalysis() {
  console.log('=== Token Analysis Example ===\n');

  import { AmountFormatter, AddressUtils, ChainUtils } from '../src/Utils';

  const provider = new ethers.JsonRpcProvider(
    'https://sepolia.drpc.org'
  );

  const config = {
    chainId: 11155111,
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

  const sdk = new BaseroSDK(provider, config);
  const token = sdk.getToken();

  // Get metadata
  const metadata = await token.getMetadata();
  console.log(`Token: ${metadata.name} (${metadata.symbol})`);
  console.log(`Decimals: ${metadata.decimals}`);
  console.log(
    `Total Supply: ${AmountFormatter.toDecimal(metadata.totalSupply)}`
  );
  console.log(
    `Total Supply (abbreviated): ${AmountFormatter.toAbbreviated(metadata.totalSupply)}`
  );

  // Price analysis (assuming $10 per token)
  const tokenPrice = 10;
  const marketCap = AmountFormatter.toUSD(metadata.totalSupply, tokenPrice);
  console.log(`\nMarket cap (at $${tokenPrice}): ${marketCap}`);

  // Chain info
  console.log(`\nChain: ${ChainUtils.getChainName(config.chainId)}`);
  console.log(`Is testnet: ${ChainUtils.isTestnet(config.chainId)}`);
}

// ============================================================================
// EXAMPLE 8: Error Handling
// ============================================================================

export async function exampleErrorHandling() {
  console.log('=== Error Handling Example ===\n');

  import { ErrorFormatter, Validators } from '../src/Utils';

  const provider = new ethers.JsonRpcProvider(
    'https://sepolia.drpc.org'
  );
  const signer = await provider.getSigner();

  const config = {
    chainId: 11155111,
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

  const sdk = new BaseroSDK(provider, config, signer);
  const token = sdk.getToken();

  // Validate before attempting
  const amount = '0'; // Invalid - can't transfer 0
  if (!Validators.isValidTransferAmount(
    AmountFormatter.toBN(amount)
  )) {
    console.log('Error: Invalid transfer amount');
    return;
  }

  // Handle transaction errors
  try {
    await token.transfer('0x...', amount);
  } catch (error) {
    const reason = ErrorFormatter.extractRevertReason(error);
    console.log(`Transaction failed: ${reason}`);

    if (ErrorFormatter.isInsufficientBalance(error)) {
      console.log('Cause: Insufficient balance');
    } else if (ErrorFormatter.isInvalidAddress(error)) {
      console.log('Cause: Invalid recipient address');
    } else if (ErrorFormatter.isTimeoutError(error)) {
      console.log('Cause: Transaction timeout');
    }
  }
}
