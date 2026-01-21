/**
 * @fileoverview Basero SDK Utility Functions
 * Formatting, validation, and helper utilities
 */

import { ethers } from 'ethers';

/**
 * Amount formatting utilities
 */
export class AmountFormatter {
  /**
   * Convert amount to BigNumber
   */
  static toBN(amount: string | number | bigint, decimals: number = 18): bigint {
    if (typeof amount === 'bigint') {
      return amount;
    }
    return ethers.parseUnits(String(amount), decimals);
  }

  /**
   * Convert BigNumber to decimal string
   */
  static toDecimal(amount: bigint, decimals: number = 18, displayDecimals: number = 2): string {
    const formatted = ethers.formatUnits(amount, decimals);
    return parseFloat(formatted).toFixed(displayDecimals);
  }

  /**
   * Convert amount to percentage
   */
  static toPercent(amount: bigint, total: bigint, decimals: number = 2): string {
    if (total === 0n) return '0.00';
    const percentage = (Number(amount) / Number(total)) * 100;
    return percentage.toFixed(decimals);
  }

  /**
   * Convert amount to USD with price
   */
  static toUSD(amount: bigint, priceUSD: number, decimals: number = 18, displayDecimals: number = 2): string {
    const amountDecimal = parseFloat(ethers.formatUnits(amount, decimals));
    const usd = amountDecimal * priceUSD;
    return `$${usd.toFixed(displayDecimals)}`;
  }

  /**
   * Format amount with abbreviation (K, M, B)
   */
  static toAbbreviated(amount: bigint, decimals: number = 18, displayDecimals: number = 2): string {
    const amountDecimal = parseFloat(ethers.formatUnits(amount, decimals));

    if (amountDecimal >= 1e9) {
      return `${(amountDecimal / 1e9).toFixed(displayDecimals)}B`;
    }
    if (amountDecimal >= 1e6) {
      return `${(amountDecimal / 1e6).toFixed(displayDecimals)}M`;
    }
    if (amountDecimal >= 1e3) {
      return `${(amountDecimal / 1e3).toFixed(displayDecimals)}K`;
    }

    return amountDecimal.toFixed(displayDecimals);
  }

  /**
   * Convert between tokens with different decimals
   */
  static convert(amount: bigint, fromDecimals: number, toDecimals: number): bigint {
    if (fromDecimals === toDecimals) {
      return amount;
    }

    if (fromDecimals < toDecimals) {
      return amount * BigInt(10 ** (toDecimals - fromDecimals));
    } else {
      return amount / BigInt(10 ** (fromDecimals - toDecimals));
    }
  }

  /**
   * Safe amount addition (checks for overflow)
   */
  static safeAdd(a: bigint, b: bigint, max: bigint = ethers.MaxUint256): bigint {
    const result = a + b;
    if (result > max) {
      throw new Error('Amount overflow');
    }
    return result;
  }

  /**
   * Safe amount subtraction (checks for underflow)
   */
  static safeSub(a: bigint, b: bigint): bigint {
    if (a < b) {
      throw new Error('Insufficient amount');
    }
    return a - b;
  }
}

/**
 * Address validation and formatting utilities
 */
export class AddressUtils {
  /**
   * Validate Ethereum address
   */
  static isValidAddress(address: string): boolean {
    try {
      return ethers.getAddress(address) === address || ethers.getAddress(address) === address.toLowerCase();
    } catch {
      return false;
    }
  }

  /**
   * Checksum address
   */
  static toChecksum(address: string): string {
    try {
      return ethers.getAddress(address);
    } catch {
      throw new Error(`Invalid address: ${address}`);
    }
  }

  /**
   * Format address for display (0x1234...5678)
   */
  static formatAddress(address: string, charsStart: number = 4, charsEnd: number = 4): string {
    const valid = AddressUtils.toChecksum(address);
    return `${valid.substring(0, charsStart)}...${valid.substring(valid.length - charsEnd)}`;
  }

  /**
   * Compare addresses (case-insensitive)
   */
  static compare(address1: string, address2: string): boolean {
    try {
      return ethers.getAddress(address1).toLowerCase() === ethers.getAddress(address2).toLowerCase();
    } catch {
      return false;
    }
  }

  /**
   * Check if address is zero address
   */
  static isZeroAddress(address: string): boolean {
    return AddressUtils.compare(address, ethers.ZeroAddress);
  }

  /**
   * Multiple address comparison
   */
  static compareMultiple(address: string, addresses: string[]): boolean {
    return addresses.some(addr => AddressUtils.compare(address, addr));
  }
}

/**
 * Chain utilities
 */
export class ChainUtils {
  private static readonly CHAIN_DATA: Record<number, { name: string; rpc?: string; explorer?: string }> = {
    11155111: { name: 'Sepolia', explorer: 'https://sepolia.etherscan.io' },
    84532: { name: 'Base Sepolia', explorer: 'https://sepolia.basescan.org' },
    1: { name: 'Ethereum', explorer: 'https://etherscan.io' },
    8453: { name: 'Base', explorer: 'https://basescan.org' },
  };

  /**
   * Get chain name
   */
  static getChainName(chainId: number): string {
    return ChainUtils.CHAIN_DATA[chainId]?.name || `Unknown (${chainId})`;
  }

  /**
   * Get explorer URL for transaction
   */
  static getTxExplorerUrl(chainId: number, txHash: string): string | null {
    const explorer = ChainUtils.CHAIN_DATA[chainId]?.explorer;
    return explorer ? `${explorer}/tx/${txHash}` : null;
  }

  /**
   * Get explorer URL for address
   */
  static getAddressExplorerUrl(chainId: number, address: string): string | null {
    const explorer = ChainUtils.CHAIN_DATA[chainId]?.explorer;
    return explorer ? `${explorer}/address/${address}` : null;
  }

  /**
   * Check if testnet
   */
  static isTestnet(chainId: number): boolean {
    return [11155111, 84532].includes(chainId);
  }

  /**
   * Check if mainnet
   */
  static isMainnet(chainId: number): boolean {
    return [1, 8453].includes(chainId);
  }
}

/**
 * Validation utilities
 */
export class Validators {
  /**
   * Validate amount
   */
  static isValidAmount(amount: any): boolean {
    try {
      if (typeof amount === 'bigint') {
        return amount >= 0n;
      }
      if (typeof amount === 'string' || typeof amount === 'number') {
        const bn = AmountFormatter.toBN(amount);
        return bn >= 0n;
      }
      return false;
    } catch {
      return false;
    }
  }

  /**
   * Validate token amount (> 0)
   */
  static isValidTransferAmount(amount: bigint): boolean {
    return amount > 0n;
  }

  /**
   * Validate percentage (0-100)
   */
  static isValidPercent(percent: number): boolean {
    return typeof percent === 'number' && percent >= 0 && percent <= 100;
  }

  /**
   * Validate duration in seconds
   */
  static isValidDuration(duration: bigint | number): boolean {
    const durationNum = typeof duration === 'bigint' ? Number(duration) : duration;
    return durationNum > 0 && durationNum <= 4 * 365 * 24 * 60 * 60; // Max 4 years
  }

  /**
   * Validate chain ID
   */
  static isValidChainId(chainId: number): boolean {
    return [11155111, 84532, 1, 8453].includes(chainId);
  }

  /**
   * Validate network config
   */
  static validateNetworkConfig(config: any): boolean {
    if (!config || typeof config !== 'object') return false;
    if (!Validators.isValidChainId(config.chainId)) return false;
    if (typeof config.rpcUrl !== 'string' || !config.rpcUrl.startsWith('http')) return false;
    if (!config.addresses || typeof config.addresses !== 'object') return false;

    const requiredAddresses = ['token', 'vault', 'bridge', 'governor', 'timelock', 'votingEscrow'];
    for (const addr of requiredAddresses) {
      if (!AddressUtils.isValidAddress(config.addresses[addr])) return false;
    }

    return true;
  }
}

/**
 * Fee estimation utilities
 */
export class FeeEstimator {
  /**
   * Estimate gas for deposit (typical ~145k)
   */
  static estimateDepositGas(): bigint {
    return BigInt(145000);
  }

  /**
   * Estimate gas for withdrawal (typical ~148k)
   */
  static estimateWithdrawGas(): bigint {
    return BigInt(148000);
  }

  /**
   * Estimate gas for transfer (typical ~65k)
   */
  static estimateTransferGas(): bigint {
    return BigInt(65000);
  }

  /**
   * Estimate gas for approval (typical ~46k)
   */
  static estimateApprovalGas(): bigint {
    return BigInt(46000);
  }

  /**
   * Estimate gas for rebase (typical ~95k)
   */
  static estimateRebaseGas(): bigint {
    return BigInt(95000);
  }

  /**
   * Estimate gas for vote cast (typical ~85k)
   */
  static estimateVoteCastGas(): bigint {
    return BigInt(85000);
  }

  /**
   * Estimate gas for proposal creation (typical ~190k)
   */
  static estimateProposalGas(): bigint {
    return BigInt(190000);
  }

  /**
   * Estimate gas for cross-chain transfer (typical ~350k)
   */
  static estimateCrossChainGas(): bigint {
    return BigInt(350000);
  }

  /**
   * Calculate fee in ETH with gas price
   */
  static calculateFee(gas: bigint, gasPrice: bigint): bigint {
    return gas * gasPrice;
  }

  /**
   * Calculate total cost (gas fee + amount)
   */
  static calculateTotalCost(amount: bigint, gas: bigint, gasPrice: bigint): bigint {
    return amount + FeeEstimator.calculateFee(gas, gasPrice);
  }
}

/**
 * Error formatting utilities
 */
export class ErrorFormatter {
  /**
   * Format error message
   */
  static formatError(error: any): string {
    if (error instanceof Error) {
      return error.message;
    }
    if (typeof error === 'string') {
      return error;
    }
    if (error?.reason) {
      return error.reason;
    }
    if (error?.message) {
      return error.message;
    }
    return 'Unknown error occurred';
  }

  /**
   * Extract revert reason
   */
  static extractRevertReason(error: any): string | null {
    const message = ErrorFormatter.formatError(error);

    // Try to extract revert reason from common patterns
    const revertMatch = message.match(/revert (.+)/i);
    if (revertMatch) {
      return revertMatch[1];
    }

    const reasonMatch = message.match(/reason: "(.+?)"/);
    if (reasonMatch) {
      return reasonMatch[1];
    }

    return null;
  }

  /**
   * Check if error is timeout
   */
  static isTimeoutError(error: any): boolean {
    const message = ErrorFormatter.formatError(error);
    return message.toLowerCase().includes('timeout') ||
      message.toLowerCase().includes('deadline');
  }

  /**
   * Check if error is insufficient balance
   */
  static isInsufficientBalance(error: any): boolean {
    const message = ErrorFormatter.formatError(error);
    return message.toLowerCase().includes('insufficient') ||
      message.toLowerCase().includes('balance');
  }

  /**
   * Check if error is invalid address
   */
  static isInvalidAddress(error: any): boolean {
    const message = ErrorFormatter.formatError(error);
    return message.toLowerCase().includes('invalid address') ||
      message.toLowerCase().includes('invalid checksum');
  }
}

/**
 * Time utilities
 */
export class TimeUtils {
  private static readonly SECONDS_PER_MINUTE = 60;
  private static readonly SECONDS_PER_HOUR = 60 * 60;
  private static readonly SECONDS_PER_DAY = 24 * 60 * 60;
  private static readonly SECONDS_PER_WEEK = 7 * 24 * 60 * 60;
  private static readonly SECONDS_PER_YEAR = 365 * 24 * 60 * 60;

  /**
   * Get current timestamp
   */
  static now(): bigint {
    return BigInt(Math.floor(Date.now() / 1000));
  }

  /**
   * Format duration in seconds to human-readable string
   */
  static formatDuration(seconds: bigint | number): string {
    const sec = typeof seconds === 'bigint' ? Number(seconds) : seconds;

    if (sec < TimeUtils.SECONDS_PER_MINUTE) {
      return `${sec}s`;
    }
    if (sec < TimeUtils.SECONDS_PER_HOUR) {
      return `${Math.floor(sec / TimeUtils.SECONDS_PER_MINUTE)}m`;
    }
    if (sec < TimeUtils.SECONDS_PER_DAY) {
      return `${Math.floor(sec / TimeUtils.SECONDS_PER_HOUR)}h`;
    }
    if (sec < TimeUtils.SECONDS_PER_WEEK) {
      return `${Math.floor(sec / TimeUtils.SECONDS_PER_DAY)}d`;
    }

    return `${Math.floor(sec / TimeUtils.SECONDS_PER_YEAR)}y`;
  }

  /**
   * Get duration from now in seconds
   */
  static getDurationFromNow(timestamp: bigint | number): bigint {
    const ts = typeof timestamp === 'bigint' ? timestamp : BigInt(timestamp);
    const now = TimeUtils.now();
    return ts > now ? ts - now : 0n;
  }

  /**
   * Check if time has passed
   */
  static hasTimePassed(timestamp: bigint | number): boolean {
    const ts = typeof timestamp === 'bigint' ? timestamp : BigInt(timestamp);
    return TimeUtils.now() >= ts;
  }

  /**
   * Convert hours to seconds
   */
  static hoursToSeconds(hours: number): bigint {
    return BigInt(hours * TimeUtils.SECONDS_PER_HOUR);
  }

  /**
   * Convert days to seconds
   */
  static daysToSeconds(days: number): bigint {
    return BigInt(days * TimeUtils.SECONDS_PER_DAY);
  }

  /**
   * Convert weeks to seconds
   */
  static weeksToSeconds(weeks: number): bigint {
    return BigInt(weeks * TimeUtils.SECONDS_PER_WEEK);
  }

  /**
   * Convert years to seconds
   */
  static yearsToSeconds(years: number): bigint {
    return BigInt(years * TimeUtils.SECONDS_PER_YEAR);
  }
}

export default {
  AmountFormatter,
  AddressUtils,
  ChainUtils,
  Validators,
  FeeEstimator,
  ErrorFormatter,
  TimeUtils,
};
