/**
 * @fileoverview Basero Protocol SDK
 * Complete TypeScript/JavaScript SDK for interacting with Basero Protocol
 * 
 * Features:
 * - Contract wrappers with type safety
 * - Transaction builders for all operations
 * - Event decoders and listeners
 * - Utility functions for amounts, fees, validation
 * - Ethers.js v6 integration
 */

import { ethers, Contract, Provider, Signer, ContractTransactionResponse } from 'ethers';

/**
 * SDK Version and Configuration
 */
export const SDK_VERSION = '1.0.0';
export const SUPPORTED_CHAINS = {
  SEPOLIA: 11155111,
  BASE_SEPOLIA: 84532,
  MAINNET: 1,
  BASE_MAINNET: 8453,
};

/**
 * Contract ABI Interfaces (minimal for demonstration)
 */
export interface RebaseTokenABI {
  totalSupply(): Promise<bigint>;
  balanceOf(account: string): Promise<bigint>;
  transfer(to: string, amount: bigint): Promise<ContractTransactionResponse | null>;
  approve(spender: string, amount: bigint): Promise<ContractTransactionResponse | null>;
  allowance(owner: string, spender: string): Promise<bigint>;
  rebase(percent: bigint): Promise<ContractTransactionResponse | null>;
}

export interface VaultABI {
  deposit(amount: bigint, receiver: string): Promise<ContractTransactionResponse | null>;
  withdraw(shares: bigint, receiver: string, owner: string): Promise<ContractTransactionResponse | null>;
  balanceOf(account: string): Promise<bigint>;
  totalAssets(): Promise<bigint>;
  convertToShares(assets: bigint): Promise<bigint>;
  convertToAssets(shares: bigint): Promise<bigint>;
}

export interface BridgeABI {
  sendTokens(destChain: number, receiver: string, amount: bigint, recipient: string): Promise<ContractTransactionResponse | null>;
  pause(): Promise<ContractTransactionResponse | null>;
  unpause(): Promise<ContractTransactionResponse | null>;
}

export interface GovernorABI {
  propose(targets: string[], values: bigint[], calldatas: string[], description: string): Promise<ContractTransactionResponse | null>;
  castVote(proposalId: bigint, support: number): Promise<ContractTransactionResponse | null>;
  queue(targets: string[], values: bigint[], calldatas: string[], descriptionHash: string): Promise<ContractTransactionResponse | null>;
  execute(targets: string[], values: bigint[], calldatas: string[], descriptionHash: string): Promise<ContractTransactionResponse | null>;
}

/**
 * Type definitions
 */
export interface NetworkConfig {
  chainId: number;
  rpcUrl: string;
  explorerUrl?: string;
  tokenAddress: string;
  vaultAddress: string;
  bridgeAddress: string;
  governorAddress: string;
  timelockAddress: string;
  votingEscrowAddress: string;
}

export interface TransactionOptions {
  gasLimit?: bigint;
  gasPrice?: bigint;
  maxFeePerGas?: bigint;
  maxPriorityFeePerGas?: bigint;
  value?: bigint;
  nonce?: number;
}

export interface Amount {
  raw: bigint;
  formatted: string;
  decimals: number;
}

export interface Balance {
  token: Amount;
  vault: Amount;
  votingEscrow: Amount;
}

export interface OperationResult<T = any> {
  success: boolean;
  data?: T;
  hash?: string;
  error?: Error;
  receipt?: any;
}

/**
 * Main Basero SDK Class
 */
export class BaseroSDK {
  private provider: Provider;
  private signer?: Signer;
  private config: NetworkConfig;
  private constants = {
    DECIMALS: 18,
    ZERO_ADDRESS: '0x' + '0'.repeat(40),
    MAX_UINT256: ethers.MaxUint256,
  };

  /**
   * Initialize SDK with network configuration
   */
  constructor(
    provider: Provider | string,
    config: NetworkConfig,
    signer?: Signer
  ) {
    this.provider = typeof provider === 'string'
      ? new ethers.JsonRpcProvider(provider)
      : provider;
    
    this.config = config;
    this.signer = signer;

    this.validateConfig();
  }

  /**
   * Set signer for transaction execution
   */
  setSigner(signer: Signer): void {
    this.signer = signer;
  }

  /**
   * Validate network configuration
   */
  private validateConfig(): void {
    const required = [
      'chainId',
      'rpcUrl',
      'tokenAddress',
      'vaultAddress',
      'bridgeAddress',
      'governorAddress',
    ];

    for (const field of required) {
      if (!this.config[field as keyof NetworkConfig]) {
        throw new Error(`Missing required config: ${field}`);
      }
    }

    // Validate addresses
    const addresses = [
      this.config.tokenAddress,
      this.config.vaultAddress,
      this.config.bridgeAddress,
      this.config.governorAddress,
    ];

    for (const addr of addresses) {
      if (!ethers.isAddress(addr)) {
        throw new Error(`Invalid address: ${addr}`);
      }
    }
  }

  /**
   * Get token contract wrapper
   */
  getToken(): TokenHelper {
    return new TokenHelper(
      this.provider,
      this.config.tokenAddress,
      this.signer
    );
  }

  /**
   * Get vault contract wrapper
   */
  getVault(): VaultHelper {
    return new VaultHelper(
      this.provider,
      this.config.vaultAddress,
      this.config.tokenAddress,
      this.signer
    );
  }

  /**
   * Get bridge contract wrapper
   */
  getBridge(): BridgeHelper {
    return new BridgeHelper(
      this.provider,
      this.config.bridgeAddress,
      this.config.tokenAddress,
      this.signer
    );
  }

  /**
   * Get governance contract wrapper
   */
  getGovernance(): GovernanceHelper {
    return new GovernanceHelper(
      this.provider,
      this.config.governorAddress,
      this.config.timelockAddress,
      this.config.votingEscrowAddress,
      this.signer
    );
  }

  /**
   * Get user balance across all contracts
   */
  async getBalance(address: string): Promise<Balance> {
    const token = this.getToken();
    const vault = this.getVault();
    const ve = this.getGovernance();

    const [tokenBal, vaultBal, veBal] = await Promise.all([
      token.getBalance(address),
      vault.getBalance(address),
      ve.getVotingPower(address),
    ]);

    return {
      token: tokenBal,
      vault: vaultBal,
      votingEscrow: veBal,
    };
  }

  /**
   * Get network configuration
   */
  getConfig(): NetworkConfig {
    return { ...this.config };
  }

  /**
   * Check if signer is available
   */
  hasSigner(): boolean {
    return !!this.signer;
  }

  /**
   * Get provider
   */
  getProvider(): Provider {
    return this.provider;
  }

  /**
   * Get signer
   */
  getSigner(): Signer | undefined {
    return this.signer;
  }
}

/**
 * Token Helper - Wraps RebaseToken contract
 */
export class TokenHelper {
  private contract: Contract;
  private provider: Provider;
  private signer?: Signer;
  private decimals: number = 18;

  constructor(provider: Provider, address: string, signer?: Signer) {
    this.provider = provider;
    this.signer = signer;

    const abi = [
      'function name() public view returns (string)',
      'function symbol() public view returns (string)',
      'function decimals() public view returns (uint8)',
      'function totalSupply() public view returns (uint256)',
      'function balanceOf(address account) public view returns (uint256)',
      'function transfer(address to, uint256 amount) public returns (bool)',
      'function approve(address spender, uint256 amount) public returns (bool)',
      'function allowance(address owner, address spender) public view returns (uint256)',
      'function transferFrom(address from, address to, uint256 amount) public returns (bool)',
      'function rebase(int256 percent) public returns (bool)',
      'event Transfer(address indexed from, address indexed to, uint256 value)',
      'event Approval(address indexed owner, address indexed spender, uint256 value)',
      'event Rebase(int256 indexed percent, uint256 newTotalSupply)',
    ];

    this.contract = new Contract(
      address,
      abi,
      signer || provider
    );
  }

  /**
   * Get token metadata
   */
  async getMetadata(): Promise<{
    name: string;
    symbol: string;
    decimals: number;
    totalSupply: string;
  }> {
    const [name, symbol, decimals, totalSupply] = await Promise.all([
      this.contract.name(),
      this.contract.symbol(),
      this.contract.decimals(),
      this.contract.totalSupply(),
    ]);

    return {
      name,
      symbol,
      decimals,
      totalSupply: this.formatAmount(totalSupply, decimals),
    };
  }

  /**
   * Get balance of address
   */
  async getBalance(address: string): Promise<Amount> {
    const balance = await this.contract.balanceOf(address);
    return {
      raw: balance,
      formatted: this.formatAmount(balance),
      decimals: this.decimals,
    };
  }

  /**
   * Get total supply
   */
  async getTotalSupply(): Promise<Amount> {
    const supply = await this.contract.totalSupply();
    return {
      raw: supply,
      formatted: this.formatAmount(supply),
      decimals: this.decimals,
    };
  }

  /**
   * Get allowance
   */
  async getAllowance(owner: string, spender: string): Promise<Amount> {
    const allowance = await this.contract.allowance(owner, spender);
    return {
      raw: allowance,
      formatted: this.formatAmount(allowance),
      decimals: this.decimals,
    };
  }

  /**
   * Transfer tokens
   */
  async transfer(
    to: string,
    amount: string | bigint,
    options?: TransactionOptions
  ): Promise<OperationResult> {
    if (!this.signer) throw new Error('Signer not available');

    try {
      const amountBn = this.parseAmount(amount);
      const tx = await this.contract.transfer(to, amountBn, options || {});
      const receipt = await tx.wait();

      return {
        success: true,
        hash: tx.hash,
        receipt,
      };
    } catch (error) {
      return {
        success: false,
        error: error as Error,
      };
    }
  }

  /**
   * Approve spending
   */
  async approve(
    spender: string,
    amount: string | bigint,
    options?: TransactionOptions
  ): Promise<OperationResult> {
    if (!this.signer) throw new Error('Signer not available');

    try {
      const amountBn = this.parseAmount(amount);
      const tx = await this.contract.approve(spender, amountBn, options || {});
      const receipt = await tx.wait();

      return {
        success: true,
        hash: tx.hash,
        receipt,
      };
    } catch (error) {
      return {
        success: false,
        error: error as Error,
      };
    }
  }

  /**
   * Apply rebase
   */
  async rebase(percent: bigint, options?: TransactionOptions): Promise<OperationResult> {
    if (!this.signer) throw new Error('Signer not available');

    try {
      const tx = await this.contract.rebase(percent, options || {});
      const receipt = await tx.wait();

      return {
        success: true,
        hash: tx.hash,
        receipt,
      };
    } catch (error) {
      return {
        success: false,
        error: error as Error,
      };
    }
  }

  /**
   * Format amount to decimal string
   */
  private formatAmount(amount: bigint, decimals: number = this.decimals): string {
    return ethers.formatUnits(amount, decimals);
  }

  /**
   * Parse amount string to bigint
   */
  private parseAmount(amount: string | bigint): bigint {
    if (typeof amount === 'bigint') return amount;
    return ethers.parseUnits(amount, this.decimals);
  }
}

/**
 * Vault Helper - Wraps RebaseTokenVault contract
 */
export class VaultHelper {
  private contract: Contract;
  private tokenHelper: TokenHelper;
  private signer?: Signer;
  private decimals: number = 18;

  constructor(
    provider: Provider,
    vaultAddress: string,
    tokenAddress: string,
    signer?: Signer
  ) {
    this.signer = signer;
    this.tokenHelper = new TokenHelper(provider, tokenAddress, signer);

    const abi = [
      'function deposit(uint256 assets, address receiver) public returns (uint256)',
      'function withdraw(uint256 shares, address receiver, address owner) public returns (uint256)',
      'function redeem(uint256 shares, address receiver, address owner) public returns (uint256)',
      'function balanceOf(address account) public view returns (uint256)',
      'function totalAssets() public view returns (uint256)',
      'function totalSupply() public view returns (uint256)',
      'function convertToShares(uint256 assets) public view returns (uint256)',
      'function convertToAssets(uint256 shares) public view returns (uint256)',
      'event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares)',
      'event Withdraw(address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares)',
    ];

    this.contract = new Contract(
      vaultAddress,
      abi,
      signer || provider
    );
  }

  /**
   * Get vault metrics
   */
  async getMetrics(): Promise<{
    totalAssets: string;
    totalSupply: string;
    sharePrice: string;
  }> {
    const [totalAssets, totalSupply] = await Promise.all([
      this.contract.totalAssets(),
      this.contract.totalSupply(),
    ]);

    const sharePrice = totalSupply > 0n
      ? ethers.formatUnits((totalAssets * ethers.parseUnits('1', this.decimals)) / totalSupply, this.decimals)
      : '1';

    return {
      totalAssets: ethers.formatUnits(totalAssets, this.decimals),
      totalSupply: ethers.formatUnits(totalSupply, this.decimals),
      sharePrice,
    };
  }

  /**
   * Get user vault balance (shares)
   */
  async getBalance(address: string): Promise<Amount> {
    const balance = await this.contract.balanceOf(address);
    return {
      raw: balance,
      formatted: ethers.formatUnits(balance, this.decimals),
      decimals: this.decimals,
    };
  }

  /**
   * Preview deposit
   */
  async previewDeposit(amount: string | bigint): Promise<{
    shares: string;
    raw: bigint;
  }> {
    const amountBn = typeof amount === 'bigint'
      ? amount
      : ethers.parseUnits(amount, this.decimals);

    const shares = await this.contract.convertToShares(amountBn);

    return {
      shares: ethers.formatUnits(shares, this.decimals),
      raw: shares,
    };
  }

  /**
   * Deposit to vault
   */
  async deposit(
    amount: string | bigint,
    receiver?: string,
    options?: TransactionOptions
  ): Promise<OperationResult> {
    if (!this.signer) throw new Error('Signer not available');

    try {
      const signerAddress = await this.signer.getAddress();
      const amountBn = typeof amount === 'bigint'
        ? amount
        : ethers.parseUnits(amount as string, this.decimals);

      const tx = await this.contract.deposit(
        amountBn,
        receiver || signerAddress,
        options || {}
      );
      const receipt = await tx.wait();

      return {
        success: true,
        hash: tx.hash,
        receipt,
      };
    } catch (error) {
      return {
        success: false,
        error: error as Error,
      };
    }
  }

  /**
   * Withdraw from vault
   */
  async withdraw(
    shares: string | bigint,
    receiver?: string,
    owner?: string,
    options?: TransactionOptions
  ): Promise<OperationResult> {
    if (!this.signer) throw new Error('Signer not available');

    try {
      const signerAddress = await this.signer.getAddress();
      const sharesBn = typeof shares === 'bigint'
        ? shares
        : ethers.parseUnits(shares as string, this.decimals);

      const tx = await this.contract.withdraw(
        sharesBn,
        receiver || signerAddress,
        owner || signerAddress,
        options || {}
      );
      const receipt = await tx.wait();

      return {
        success: true,
        hash: tx.hash,
        receipt,
      };
    } catch (error) {
      return {
        success: false,
        error: error as Error,
      };
    }
  }
}

/**
 * Bridge Helper - Wraps EnhancedCCIPBridge contract
 */
export class BridgeHelper {
  private contract: Contract;
  private signer?: Signer;
  private decimals: number = 18;

  constructor(
    provider: Provider,
    bridgeAddress: string,
    tokenAddress: string,
    signer?: Signer
  ) {
    this.signer = signer;

    const abi = [
      'function sendTokens(uint64 destChain, address receiver, uint256 amount, address recipient) public returns (bytes32)',
      'function setRateLimits(uint256 maxPerMessage, uint256 maxPerDay) public',
      'function pause() public',
      'function unpause() public',
      'function isPaused() public view returns (bool)',
      'event MessageSent(bytes32 indexed messageId, uint64 destChain, uint256 amount)',
      'event MessageReceived(bytes32 indexed messageId, uint256 amount)',
    ];

    this.contract = new Contract(
      bridgeAddress,
      abi,
      signer || provider
    );
  }

  /**
   * Get bridge status
   */
  async getStatus(): Promise<{
    isPaused: boolean;
  }> {
    const isPaused = await this.contract.isPaused();
    return { isPaused };
  }

  /**
   * Send tokens across chains
   */
  async sendTokens(
    destChain: number,
    receiver: string,
    amount: string | bigint,
    options?: TransactionOptions
  ): Promise<OperationResult> {
    if (!this.signer) throw new Error('Signer not available');

    try {
      const signerAddress = await this.signer.getAddress();
      const amountBn = typeof amount === 'bigint'
        ? amount
        : ethers.parseUnits(amount as string, this.decimals);

      const tx = await this.contract.sendTokens(
        destChain,
        receiver,
        amountBn,
        signerAddress,
        options || {}
      );
      const receipt = await tx.wait();

      return {
        success: true,
        hash: tx.hash,
        receipt,
        data: receipt?.logs?.[0] || null,
      };
    } catch (error) {
      return {
        success: false,
        error: error as Error,
      };
    }
  }
}

/**
 * Governance Helper - Wraps governance contracts
 */
export class GovernanceHelper {
  private governorContract: Contract;
  private votingEscrowContract: Contract;
  private signer?: Signer;

  constructor(
    provider: Provider,
    governorAddress: string,
    timelockAddress: string,
    votingEscrowAddress: string,
    signer?: Signer
  ) {
    this.signer = signer;

    const governorAbi = [
      'function propose(address[] targets, uint256[] values, bytes[] calldatas, string description) public returns (uint256)',
      'function castVote(uint256 proposalId, uint8 support) public returns (uint128)',
      'function queue(address[] targets, uint256[] values, bytes[] calldatas, bytes32 descriptionHash) public',
      'function execute(address[] targets, uint256[] values, bytes[] calldatas, bytes32 descriptionHash) public payable',
      'function getVotes(address account, uint256 blockNumber) public view returns (uint256)',
      'function proposalDeadline(uint256 proposalId) public view returns (uint256)',
      'function proposalSnapshot(uint256 proposalId) public view returns (uint256)',
      'function proposalVotes(uint256 proposalId) public view returns (uint256, uint256, uint256)',
      'event ProposalCreated(uint256 indexed proposalId, address indexed proposer, address[] targets, uint256[] values, string[] signatures, bytes[] calldatas, uint256 startBlock, uint256 endBlock, string description)',
      'event VoteCast(address indexed voter, uint256 proposalId, uint8 support, uint256 weight, string reason)',
    ];

    const votingEscrowAbi = [
      'function lock(uint256 amount, uint256 duration) public returns (uint256)',
      'function getVotes(address account) public view returns (uint256)',
      'function balanceOf(address account) public view returns (uint256)',
    ];

    this.governorContract = new Contract(
      governorAddress,
      governorAbi,
      signer || provider
    );

    this.votingEscrowContract = new Contract(
      votingEscrowAddress,
      votingEscrowAbi,
      signer || provider
    );
  }

  /**
   * Get voting power
   */
  async getVotingPower(address: string): Promise<Amount> {
    const votes = await this.votingEscrowContract.getVotes(address);
    return {
      raw: votes,
      formatted: ethers.formatUnits(votes, 18),
      decimals: 18,
    };
  }

  /**
   * Lock tokens for voting
   */
  async lock(amount: string | bigint, duration: number, options?: TransactionOptions): Promise<OperationResult> {
    if (!this.signer) throw new Error('Signer not available');

    try {
      const amountBn = typeof amount === 'bigint'
        ? amount
        : ethers.parseUnits(amount as string, 18);

      const tx = await this.votingEscrowContract.lock(amountBn, duration, options || {});
      const receipt = await tx.wait();

      return {
        success: true,
        hash: tx.hash,
        receipt,
      };
    } catch (error) {
      return {
        success: false,
        error: error as Error,
      };
    }
  }

  /**
   * Create proposal
   */
  async propose(
    targets: string[],
    values: bigint[],
    calldatas: string[],
    description: string,
    options?: TransactionOptions
  ): Promise<OperationResult> {
    if (!this.signer) throw new Error('Signer not available');

    try {
      const tx = await this.governorContract.propose(
        targets,
        values,
        calldatas,
        description,
        options || {}
      );
      const receipt = await tx.wait();

      return {
        success: true,
        hash: tx.hash,
        receipt,
      };
    } catch (error) {
      return {
        success: false,
        error: error as Error,
      };
    }
  }

  /**
   * Cast vote
   */
  async castVote(proposalId: bigint, support: number, options?: TransactionOptions): Promise<OperationResult> {
    if (!this.signer) throw new Error('Signer not available');

    try {
      const tx = await this.governorContract.castVote(proposalId, support, options || {});
      const receipt = await tx.wait();

      return {
        success: true,
        hash: tx.hash,
        receipt,
      };
    } catch (error) {
      return {
        success: false,
        error: error as Error,
      };
    }
  }
}

export default BaseroSDK;
