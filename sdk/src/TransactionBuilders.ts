/**
 * @fileoverview Basero Protocol Transaction Builders
 * Fluent API for constructing complex transactions
 */

import { ethers } from 'ethers';

/**
 * Transaction builder result
 */
export interface BuilderResult {
  targets: string[];
  values: bigint[];
  calldatas: string[];
  description: string;
}

/**
 * Base transaction builder
 */
export abstract class TransactionBuilder {
  protected targets: string[] = [];
  protected values: bigint[] = [];
  protected calldatas: string[] = [];
  protected description: string = '';

  /**
   * Build final transaction data
   */
  build(): BuilderResult {
    this.validate();
    return {
      targets: this.targets,
      values: this.values,
      calldatas: this.calldata,
      description: this.description,
    };
  }

  /**
   * Validate builder state
   */
  protected validate(): void {
    if (this.targets.length === 0) {
      throw new Error('No targets specified');
    }
    if (this.targets.length !== this.values.length || this.targets.length !== this.calldatas.length) {
      throw new Error('Mismatched arrays length');
    }
  }

  /**
   * Get calldata array
   */
  get calldata(): string[] {
    return this.calldatas;
  }

  /**
   * Get encoded description hash
   */
  getDescriptionHash(): string {
    return ethers.id(this.description);
  }

  /**
   * Reset builder
   */
  reset(): void {
    this.targets = [];
    this.values = [];
    this.calldatas = [];
    this.description = '';
  }
}

/**
 * Vault Transaction Builder
 */
export class VaultTxBuilder extends TransactionBuilder {
  /**
   * Add deposit transaction
   */
  deposit(vaultAddress: string, amount: string, receiver: string): this {
    const iface = new ethers.Interface([
      'function deposit(uint256 assets, address receiver) returns (uint256)',
    ]);

    const amountBn = ethers.parseUnits(amount, 18);
    const calldata = iface.encodeFunctionData('deposit', [amountBn, receiver]);

    this.targets.push(vaultAddress);
    this.values.push(0n);
    this.calldatas.push(calldata);

    this.description = `Deposit ${amount} to vault`;
    return this;
  }

  /**
   * Add withdrawal transaction
   */
  withdraw(
    vaultAddress: string,
    shares: string,
    receiver: string,
    owner: string
  ): this {
    const iface = new ethers.Interface([
      'function withdraw(uint256 shares, address receiver, address owner) returns (uint256)',
    ]);

    const sharesBn = ethers.parseUnits(shares, 18);
    const calldata = iface.encodeFunctionData('withdraw', [sharesBn, receiver, owner]);

    this.targets.push(vaultAddress);
    this.values.push(0n);
    this.calldatas.push(calldata);

    this.description = `Withdraw ${shares} from vault`;
    return this;
  }

  /**
   * Set description
   */
  setDescription(desc: string): this {
    this.description = desc;
    return this;
  }

  /**
   * Preview transaction (dry run)
   */
  preview(): {
    target: string;
    value: bigint;
    calldata: string;
    description: string;
  } {
    if (this.targets.length === 0) {
      throw new Error('No transactions added');
    }

    return {
      target: this.targets[0],
      value: this.values[0],
      calldata: this.calldatas[0],
      description: this.description,
    };
  }
}

/**
 * Token Transaction Builder
 */
export class TokenTxBuilder extends TransactionBuilder {
  /**
   * Add transfer transaction
   */
  transfer(tokenAddress: string, to: string, amount: string): this {
    const iface = new ethers.Interface([
      'function transfer(address to, uint256 amount) returns (bool)',
    ]);

    const amountBn = ethers.parseUnits(amount, 18);
    const calldata = iface.encodeFunctionData('transfer', [to, amountBn]);

    this.targets.push(tokenAddress);
    this.values.push(0n);
    this.calldatas.push(calldata);

    this.description = `Transfer ${amount} tokens to ${to}`;
    return this;
  }

  /**
   * Add approve transaction
   */
  approve(tokenAddress: string, spender: string, amount: string): this {
    const iface = new ethers.Interface([
      'function approve(address spender, uint256 amount) returns (bool)',
    ]);

    const amountBn = ethers.parseUnits(amount, 18);
    const calldata = iface.encodeFunctionData('approve', [spender, amountBn]);

    this.targets.push(tokenAddress);
    this.values.push(0n);
    this.calldatas.push(calldata);

    this.description = `Approve ${spender} to spend ${amount} tokens`;
    return this;
  }

  /**
   * Add rebase transaction
   */
  rebase(tokenAddress: string, percent: string): this {
    const iface = new ethers.Interface([
      'function rebase(int256 percent) returns (bool)',
    ]);

    // Convert percent to basis points (e.g., 10% = 1000000000000000000)
    const percentBn = ethers.parseUnits(percent, 18);
    const calldata = iface.encodeFunctionData('rebase', [percentBn]);

    this.targets.push(tokenAddress);
    this.values.push(0n);
    this.calldatas.push(calldata);

    this.description = `Apply ${percent}% rebase`;
    return this;
  }

  /**
   * Set description
   */
  setDescription(desc: string): this {
    this.description = desc;
    return this;
  }
}

/**
 * Governance Transaction Builder
 */
export class GovernanceTxBuilder extends TransactionBuilder {
  /**
   * Add proposal call
   */
  addProposalCall(
    target: string,
    value: string,
    calldata: string,
    description?: string
  ): this {
    this.targets.push(target);
    this.values.push(ethers.parseUnits(value, 18));
    this.calldatas.push(calldata);

    if (description) {
      this.description = description;
    }

    return this;
  }

  /**
   * Add parameter update call
   */
  updateParameter(
    targetAddress: string,
    paramName: string,
    paramValue: string
  ): this {
    const iface = new ethers.Interface([
      `function set${paramName}(${typeof paramValue === 'string' ? 'uint256' : 'address'}) public`,
    ]);

    let encodedValue;
    if (paramName === 'RebaseRate' || paramName === 'DepositCap') {
      encodedValue = ethers.parseUnits(paramValue, 18);
    } else {
      encodedValue = paramValue; // Assume address
    }

    const calldata = iface.encodeFunctionData(
      `set${paramName}`,
      [encodedValue]
    );

    this.targets.push(targetAddress);
    this.values.push(0n);
    this.calldatas.push(calldata);

    this.description = `Update ${paramName} to ${paramValue}`;
    return this;
  }

  /**
   * Add custom call
   */
  addCustomCall(
    target: string,
    functionSignature: string,
    params: any[],
    description: string
  ): this {
    const iface = new ethers.Interface([
      `function ${functionSignature}`,
    ]);

    const functionName = functionSignature.split('(')[0];
    const calldata = iface.encodeFunctionData(functionName, params);

    this.targets.push(target);
    this.values.push(0n);
    this.calldatas.push(calldata);

    this.description = description;
    return this;
  }

  /**
   * Set voting parameters
   */
  setVotingParameters(
    governorAddress: string,
    votingDelay: number,
    votingPeriod: number,
    proposalThreshold: string
  ): this {
    const iface = new ethers.Interface([
      'function setVotingDelay(uint256 newVotingDelay)',
      'function setVotingPeriod(uint256 newVotingPeriod)',
      'function setProposalThreshold(uint256 newProposalThreshold)',
    ]);

    const thresholdBn = ethers.parseUnits(proposalThreshold, 18);

    // Add each parameter update as separate call
    this.targets.push(governorAddress);
    this.values.push(0n);
    this.calldatas.push(iface.encodeFunctionData('setVotingDelay', [votingDelay]));

    this.targets.push(governorAddress);
    this.values.push(0n);
    this.calldatas.push(iface.encodeFunctionData('setVotingPeriod', [votingPeriod]));

    this.targets.push(governorAddress);
    this.values.push(0n);
    this.calldatas.push(iface.encodeFunctionData('setProposalThreshold', [thresholdBn]));

    this.description = `Update voting parameters: delay=${votingDelay}, period=${votingPeriod}, threshold=${proposalThreshold}`;
    return this;
  }

  /**
   * Add emergency pause
   */
  emergencyPause(targetAddress: string): this {
    const iface = new ethers.Interface([
      'function pause() public',
    ]);

    const calldata = iface.encodeFunctionData('pause', []);

    this.targets.push(targetAddress);
    this.values.push(0n);
    this.calldatas.push(calldata);

    this.description = 'Emergency pause';
    return this;
  }

  /**
   * Add emergency unpause
   */
  emergencyUnpause(targetAddress: string): this {
    const iface = new ethers.Interface([
      'function unpause() public',
    ]);

    const calldata = iface.encodeFunctionData('unpause', []);

    this.targets.push(targetAddress);
    this.values.push(0n);
    this.calldatas.push(calldata);

    this.description = 'Emergency unpause';
    return this;
  }

  /**
   * Set proposal description
   */
  setDescription(desc: string): this {
    this.description = desc;
    return this;
  }

  /**
   * Get proposal for governance execution
   */
  getProposal(): {
    targets: string[];
    values: bigint[];
    calldatas: string[];
    description: string;
    descriptionHash: string;
  } {
    this.validate();
    return {
      targets: this.targets,
      values: this.values,
      calldatas: this.calldatas,
      description: this.description,
      descriptionHash: this.getDescriptionHash(),
    };
  }
}

/**
 * Bridge Transaction Builder
 */
export class BridgeTxBuilder extends TransactionBuilder {
  /**
   * Add cross-chain transfer
   */
  crossChainTransfer(
    bridgeAddress: string,
    destChain: number,
    receiver: string,
    amount: string
  ): this {
    const iface = new ethers.Interface([
      'function sendTokens(uint64 destChain, address receiver, uint256 amount, address recipient)',
    ]);

    const amountBn = ethers.parseUnits(amount, 18);
    const calldata = iface.encodeFunctionData('sendTokens', [
      destChain,
      receiver,
      amountBn,
      receiver, // recipient same as receiver in this context
    ]);

    this.targets.push(bridgeAddress);
    this.values.push(0n);
    this.calldatas.push(calldata);

    this.description = `Transfer ${amount} tokens to chain ${destChain}`;
    return this;
  }

  /**
   * Set rate limits
   */
  setRateLimits(
    bridgeAddress: string,
    maxPerMessage: string,
    maxPerDay: string
  ): this {
    const iface = new ethers.Interface([
      'function setRateLimits(uint256 maxPerMessage, uint256 maxPerDay)',
    ]);

    const maxPerMessageBn = ethers.parseUnits(maxPerMessage, 18);
    const maxPerDayBn = ethers.parseUnits(maxPerDay, 18);

    const calldata = iface.encodeFunctionData('setRateLimits', [maxPerMessageBn, maxPerDayBn]);

    this.targets.push(bridgeAddress);
    this.values.push(0n);
    this.calldatas.push(calldata);

    this.description = `Set rate limits: ${maxPerMessage}/msg, ${maxPerDay}/day`;
    return this;
  }

  /**
   * Set description
   */
  setDescription(desc: string): this {
    this.description = desc;
    return this;
  }
}

/**
 * Batch Transaction Builder - Combine multiple transaction types
 */
export class BatchTxBuilder {
  private batches: BuilderResult[] = [];
  private description: string = '';

  /**
   * Add vault transaction
   */
  addVault(builder: VaultTxBuilder): this {
    this.batches.push(builder.build());
    return this;
  }

  /**
   * Add token transaction
   */
  addToken(builder: TokenTxBuilder): this {
    this.batches.push(builder.build());
    return this;
  }

  /**
   * Add governance transaction
   */
  addGovernance(builder: GovernanceTxBuilder): this {
    this.batches.push(builder.build());
    return this;
  }

  /**
   * Add bridge transaction
   */
  addBridge(builder: BridgeTxBuilder): this {
    this.batches.push(builder.build());
    return this;
  }

  /**
   * Set overall description
   */
  setDescription(desc: string): this {
    this.description = desc;
    return this;
  }

  /**
   * Build combined transaction
   */
  build(): BuilderResult {
    const combined: BuilderResult = {
      targets: [],
      values: [],
      calldatas: [],
      description: this.description || 'Batch transaction',
    };

    for (const batch of this.batches) {
      combined.targets.push(...batch.targets);
      combined.values.push(...batch.values);
      combined.calldatas.push(...batch.calldatas);
    }

    return combined;
  }

  /**
   * Get transaction count
   */
  getCount(): number {
    return this.batches.reduce((sum, b) => sum + b.targets.length, 0);
  }

  /**
   * Clear all transactions
   */
  clear(): this {
    this.batches = [];
    this.description = '';
    return this;
  }
}

export default {
  VaultTxBuilder,
  TokenTxBuilder,
  GovernanceTxBuilder,
  BridgeTxBuilder,
  BatchTxBuilder,
};
