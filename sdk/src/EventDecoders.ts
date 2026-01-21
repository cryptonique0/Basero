/**
 * @fileoverview Basero Protocol Event Decoders
 * Parse and decode protocol events
 */

import { ethers, Log, EventLog } from 'ethers';

/**
 * Decoded event result
 */
export interface DecodedEvent {
  eventName: string;
  args: Record<string, any>;
  indexed: Record<string, any>;
  raw?: Log;
}

/**
 * Event parser utility
 */
export class EventDecoder {
  private interfaces: Map<string, ethers.Interface> = new Map();

  constructor() {
    this.initializeInterfaces();
  }

  /**
   * Initialize contract interfaces
   */
  private initializeInterfaces(): void {
    // Token events
    const tokenAbi = [
      'event Transfer(address indexed from, address indexed to, uint256 value)',
      'event Approval(address indexed owner, address indexed spender, uint256 value)',
      'event Rebase(int256 indexed percent, uint256 newTotalSupply)',
    ];
    this.interfaces.set('RebaseToken', new ethers.Interface(tokenAbi));

    // Vault events
    const vaultAbi = [
      'event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares)',
      'event Withdraw(address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares)',
    ];
    this.interfaces.set('RebaseTokenVault', new ethers.Interface(vaultAbi));

    // Bridge events
    const bridgeAbi = [
      'event MessageSent(bytes32 indexed messageId, uint64 destChain, uint256 amount)',
      'event MessageReceived(bytes32 indexed messageId, uint256 amount)',
      'event MessageFailed(bytes32 indexed messageId, string reason)',
    ];
    this.interfaces.set('EnhancedCCIPBridge', new ethers.Interface(bridgeAbi));

    // Governor events
    const governorAbi = [
      'event ProposalCreated(uint256 indexed proposalId, address indexed proposer, address[] targets, uint256[] values, string[] signatures, bytes[] calldatas, uint256 startBlock, uint256 endBlock, string description)',
      'event VoteCast(address indexed voter, uint256 proposalId, uint8 support, uint256 weight, string reason)',
      'event ProposalQueued(uint256 indexed proposalId, uint256 eta)',
      'event ProposalExecuted(uint256 indexed proposalId)',
    ];
    this.interfaces.set('BASEGovernor', new ethers.Interface(governorAbi));
  }

  /**
   * Decode event from log
   */
  decodeEvent(log: Log, contractName: string): DecodedEvent | null {
    const iface = this.interfaces.get(contractName);
    if (!iface) return null;

    try {
      const parsed = iface.parseLog(log);
      if (!parsed) return null;

      const indexed: Record<string, any> = {};
      const args: Record<string, any> = {};

      // Separate indexed and regular arguments
      for (let i = 0; i < parsed.fragment.inputs.length; i++) {
        const input = parsed.fragment.inputs[i];
        const value = parsed.args[i];

        if (input.indexed) {
          indexed[input.name] = value;
        } else {
          args[input.name] = value;
        }
      }

      return {
        eventName: parsed.name,
        args,
        indexed,
        raw: log,
      };
    } catch (error) {
      return null;
    }
  }

  /**
   * Decode multiple logs
   */
  decodeLogs(logs: Log[], contractName: string): DecodedEvent[] {
    return logs
      .map(log => this.decodeEvent(log, contractName))
      .filter((event): event is DecodedEvent => event !== null);
  }

  /**
   * Format event for display
   */
  formatEvent(event: DecodedEvent): string {
    const lines: string[] = [
      `Event: ${event.eventName}`,
      'Indexed Parameters:',
      ...Object.entries(event.indexed).map(([key, value]) => `  ${key}: ${this.formatValue(value)}`),
      'Parameters:',
      ...Object.entries(event.args).map(([key, value]) => `  ${key}: ${this.formatValue(value)}`),
    ];
    return lines.join('\n');
  }

  /**
   * Format value for display
   */
  private formatValue(value: any): string {
    if (typeof value === 'bigint') {
      return ethers.formatUnits(value, 18);
    }
    if (typeof value === 'boolean') {
      return value ? 'true' : 'false';
    }
    if (Array.isArray(value)) {
      return `[${value.map(v => this.formatValue(v)).join(', ')}]`;
    }
    return String(value);
  }
}

/**
 * Token event parser
 */
export class TokenEventParser {
  private decoder: EventDecoder;

  constructor() {
    this.decoder = new EventDecoder();
  }

  /**
   * Parse Transfer event
   */
  parseTransfer(log: Log): {
    from: string;
    to: string;
    amount: bigint;
  } | null {
    const event = this.decoder.decodeEvent(log, 'RebaseToken');
    if (!event || event.eventName !== 'Transfer') return null;

    return {
      from: event.indexed.from,
      to: event.indexed.to,
      amount: event.args.value,
    };
  }

  /**
   * Parse Approval event
   */
  parseApproval(log: Log): {
    owner: string;
    spender: string;
    amount: bigint;
  } | null {
    const event = this.decoder.decodeEvent(log, 'RebaseToken');
    if (!event || event.eventName !== 'Approval') return null;

    return {
      owner: event.indexed.owner,
      spender: event.indexed.spender,
      amount: event.args.value,
    };
  }

  /**
   * Parse Rebase event
   */
  parseRebase(log: Log): {
    percent: bigint;
    newTotalSupply: bigint;
  } | null {
    const event = this.decoder.decodeEvent(log, 'RebaseToken');
    if (!event || event.eventName !== 'Rebase') return null;

    return {
      percent: event.indexed.percent,
      newTotalSupply: event.args.newTotalSupply,
    };
  }

  /**
   * Filter transfers by address
   */
  filterTransfers(logs: Log[], filter?: { from?: string; to?: string }): Array<{
    from: string;
    to: string;
    amount: bigint;
  }> {
    return logs
      .map(log => this.parseTransfer(log))
      .filter((transfer): transfer is Exclude<typeof transfer, null> => transfer !== null)
      .filter(transfer => {
        if (filter?.from && transfer.from.toLowerCase() !== filter.from.toLowerCase()) {
          return false;
        }
        if (filter?.to && transfer.to.toLowerCase() !== filter.to.toLowerCase()) {
          return false;
        }
        return true;
      });
  }
}

/**
 * Vault event parser
 */
export class VaultEventParser {
  private decoder: EventDecoder;

  constructor() {
    this.decoder = new EventDecoder();
  }

  /**
   * Parse Deposit event
   */
  parseDeposit(log: Log): {
    caller: string;
    owner: string;
    assets: bigint;
    shares: bigint;
  } | null {
    const event = this.decoder.decodeEvent(log, 'RebaseTokenVault');
    if (!event || event.eventName !== 'Deposit') return null;

    return {
      caller: event.indexed.caller,
      owner: event.indexed.owner,
      assets: event.args.assets,
      shares: event.args.shares,
    };
  }

  /**
   * Parse Withdraw event
   */
  parseWithdraw(log: Log): {
    caller: string;
    receiver: string;
    owner: string;
    assets: bigint;
    shares: bigint;
  } | null {
    const event = this.decoder.decodeEvent(log, 'RebaseTokenVault');
    if (!event || event.eventName !== 'Withdraw') return null;

    return {
      caller: event.indexed.caller,
      receiver: event.indexed.receiver,
      owner: event.indexed.owner,
      assets: event.args.assets,
      shares: event.args.shares,
    };
  }

  /**
   * Get vault activity summary
   */
  getActivitySummary(logs: Log[]): {
    deposits: bigint;
    withdrawals: bigint;
    netFlow: bigint;
  } {
    let deposits = 0n;
    let withdrawals = 0n;

    for (const log of logs) {
      const deposit = this.parseDeposit(log);
      if (deposit) {
        deposits += deposit.assets;
        continue;
      }

      const withdraw = this.parseWithdraw(log);
      if (withdraw) {
        withdrawals += withdraw.assets;
      }
    }

    return {
      deposits,
      withdrawals,
      netFlow: deposits - withdrawals,
    };
  }
}

/**
 * Bridge event parser
 */
export class BridgeEventParser {
  private decoder: EventDecoder;

  constructor() {
    this.decoder = new EventDecoder();
  }

  /**
   * Parse MessageSent event
   */
  parseMessageSent(log: Log): {
    messageId: string;
    destChain: bigint;
    amount: bigint;
  } | null {
    const event = this.decoder.decodeEvent(log, 'EnhancedCCIPBridge');
    if (!event || event.eventName !== 'MessageSent') return null;

    return {
      messageId: event.indexed.messageId,
      destChain: event.args.destChain,
      amount: event.args.amount,
    };
  }

  /**
   * Parse MessageReceived event
   */
  parseMessageReceived(log: Log): {
    messageId: string;
    amount: bigint;
  } | null {
    const event = this.decoder.decodeEvent(log, 'EnhancedCCIPBridge');
    if (!event || event.eventName !== 'MessageReceived') return null;

    return {
      messageId: event.indexed.messageId,
      amount: event.args.amount,
    };
  }

  /**
   * Parse MessageFailed event
   */
  parseMessageFailed(log: Log): {
    messageId: string;
    reason: string;
  } | null {
    const event = this.decoder.decodeEvent(log, 'EnhancedCCIPBridge');
    if (!event || event.eventName !== 'MessageFailed') return null;

    return {
      messageId: event.indexed.messageId,
      reason: event.args.reason,
    };
  }

  /**
   * Track message status
   */
  trackMessages(logs: Log[]): Map<string, 'sent' | 'received' | 'failed'> {
    const status = new Map<string, 'sent' | 'received' | 'failed'>();

    for (const log of logs) {
      const sent = this.parseMessageSent(log);
      if (sent) {
        status.set(sent.messageId, 'sent');
        continue;
      }

      const received = this.parseMessageReceived(log);
      if (received) {
        status.set(received.messageId, 'received');
        continue;
      }

      const failed = this.parseMessageFailed(log);
      if (failed) {
        status.set(failed.messageId, 'failed');
      }
    }

    return status;
  }
}

/**
 * Governance event parser
 */
export class GovernanceEventParser {
  private decoder: EventDecoder;

  constructor() {
    this.decoder = new EventDecoder();
  }

  /**
   * Parse ProposalCreated event
   */
  parseProposalCreated(log: Log): {
    proposalId: bigint;
    proposer: string;
    description: string;
    startBlock: bigint;
    endBlock: bigint;
  } | null {
    const event = this.decoder.decodeEvent(log, 'BASEGovernor');
    if (!event || event.eventName !== 'ProposalCreated') return null;

    return {
      proposalId: event.indexed.proposalId,
      proposer: event.indexed.proposer,
      description: event.args.description,
      startBlock: event.args.startBlock,
      endBlock: event.args.endBlock,
    };
  }

  /**
   * Parse VoteCast event
   */
  parseVoteCast(log: Log): {
    voter: string;
    proposalId: bigint;
    support: number;
    weight: bigint;
  } | null {
    const event = this.decoder.decodeEvent(log, 'BASEGovernor');
    if (!event || event.eventName !== 'VoteCast') return null;

    return {
      voter: event.indexed.voter,
      proposalId: event.indexed.proposalId,
      support: event.args.support,
      weight: event.args.weight,
    };
  }

  /**
   * Parse ProposalQueued event
   */
  parseProposalQueued(log: Log): {
    proposalId: bigint;
    eta: bigint;
  } | null {
    const event = this.decoder.decodeEvent(log, 'BASEGovernor');
    if (!event || event.eventName !== 'ProposalQueued') return null;

    return {
      proposalId: event.indexed.proposalId,
      eta: event.args.eta,
    };
  }

  /**
   * Get proposal voting summary
   */
  getVotingSummary(logs: Log[], proposalId: bigint): {
    votes: bigint;
    voters: string[];
    support: Map<number, bigint>;
  } {
    let votes = 0n;
    const voters = new Set<string>();
    const support = new Map<number, bigint>();

    for (const log of logs) {
      const vote = this.parseVoteCast(log);
      if (vote && vote.proposalId === proposalId) {
        votes += vote.weight;
        voters.add(vote.voter);
        support.set(vote.support, (support.get(vote.support) || 0n) + vote.weight);
      }
    }

    return {
      votes,
      voters: Array.from(voters),
      support,
    };
  }
}

/**
 * Combined event indexer
 */
export class EventIndexer {
  private tokenParser: TokenEventParser;
  private vaultParser: VaultEventParser;
  private bridgeParser: BridgeEventParser;
  private governanceParser: GovernanceEventParser;

  constructor() {
    this.tokenParser = new TokenEventParser();
    this.vaultParser = new VaultEventParser();
    this.bridgeParser = new BridgeEventParser();
    this.governanceParser = new GovernanceEventParser();
  }

  /**
   * Index all events from logs
   */
  indexLogs(logs: Log[]): {
    tokens: any[];
    vault: any[];
    bridge: any[];
    governance: any[];
  } {
    return {
      tokens: [],
      vault: [],
      bridge: [],
      governance: [],
    };
  }

  /**
   * Get user activity summary
   */
  getUserActivity(logs: Log[], userAddress: string): {
    transfers: number;
    approvals: number;
    deposits: number;
    withdrawals: number;
    votes: number;
    messages: number;
  } {
    let transfers = 0;
    let approvals = 0;
    let deposits = 0;
    let withdrawals = 0;
    let votes = 0;
    let messages = 0;

    for (const log of logs) {
      const transfer = this.tokenParser.parseTransfer(log);
      if (transfer && (transfer.from.toLowerCase() === userAddress.toLowerCase() ||
        transfer.to.toLowerCase() === userAddress.toLowerCase())) {
        transfers++;
      }

      const deposit = this.vaultParser.parseDeposit(log);
      if (deposit && deposit.owner.toLowerCase() === userAddress.toLowerCase()) {
        deposits++;
      }

      const withdraw = this.vaultParser.parseWithdraw(log);
      if (withdraw && withdraw.owner.toLowerCase() === userAddress.toLowerCase()) {
        withdrawals++;
      }

      const vote = this.governanceParser.parseVoteCast(log);
      if (vote && vote.voter.toLowerCase() === userAddress.toLowerCase()) {
        votes++;
      }
    }

    return {
      transfers,
      approvals,
      deposits,
      withdrawals,
      votes,
      messages,
    };
  }
}

export default {
  EventDecoder,
  TokenEventParser,
  VaultEventParser,
  BridgeEventParser,
  GovernanceEventParser,
  EventIndexer,
};
