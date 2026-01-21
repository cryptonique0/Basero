# Frontend Integration Guide - Basero SDK

## Table of Contents

- [Overview](#overview)
- [React Hooks](#react-hooks)
- [Wallet Integration](#wallet-integration)
- [Token Display Patterns](#token-display-patterns)
- [Error Handling](#error-handling)
- [Complete Examples](#complete-examples)
- [Best Practices](#best-practices)

---

## Overview

This guide shows how to integrate the Basero SDK into a React frontend application. It covers wallet connection, contract interaction, UI components, and error handling.

### Prerequisites

```bash
npm install @basero/sdk ethers@^6.0.0 react react-dom
```

### Required Imports

```typescript
import { BaseroSDK } from '@basero/sdk';
import { BrowserProvider, ethers } from 'ethers';
import { useState, useEffect, useCallback } from 'react';
```

---

## React Hooks

### useBaseroSDK Hook

Core hook for initializing and managing the SDK instance.

```typescript
import { useState, useEffect, useMemo } from 'react';
import { BaseroSDK } from '@basero/sdk';
import { BrowserProvider } from 'ethers';

interface UseBaseroSDKResult {
  sdk: BaseroSDK | null;
  isConnected: boolean;
  isLoading: boolean;
  error: string | null;
  connect: () => Promise<void>;
  disconnect: () => void;
}

export function useBaseroSDK(config: NetworkConfig): UseBaseroSDKResult {
  const [provider, setProvider] = useState<BrowserProvider | null>(null);
  const [signer, setSigner] = useState<ethers.Signer | null>(null);
  const [isConnected, setIsConnected] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Initialize SDK
  const sdk = useMemo(() => {
    if (!provider) return null;
    return new BaseroSDK(provider, config, signer || undefined);
  }, [provider, config, signer]);

  // Connect wallet
  const connect = useCallback(async () => {
    setIsLoading(true);
    setError(null);

    try {
      if (!window.ethereum) {
        throw new Error('Please install MetaMask');
      }

      const browserProvider = new BrowserProvider(window.ethereum);
      const accounts = await browserProvider.send('eth_requestAccounts', []);
      
      if (accounts.length === 0) {
        throw new Error('No accounts found');
      }

      const signer = await browserProvider.getSigner();
      
      setProvider(browserProvider);
      setSigner(signer);
      setIsConnected(true);
    } catch (err: any) {
      setError(err.message || 'Failed to connect wallet');
      setIsConnected(false);
    } finally {
      setIsLoading(false);
    }
  }, []);

  // Disconnect wallet
  const disconnect = useCallback(() => {
    setProvider(null);
    setSigner(null);
    setIsConnected(false);
  }, []);

  return {
    sdk,
    isConnected,
    isLoading,
    error,
    connect,
    disconnect,
  };
}
```

### useTokenBalance Hook

Hook for fetching and displaying token balances.

```typescript
import { useState, useEffect } from 'react';
import { BaseroSDK, Amount } from '@basero/sdk';

interface UseTokenBalanceResult {
  balance: Amount | null;
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
}

export function useTokenBalance(
  sdk: BaseroSDK | null,
  address: string | null
): UseTokenBalanceResult {
  const [balance, setBalance] = useState<Amount | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetchBalance = useCallback(async () => {
    if (!sdk || !address) return;

    setIsLoading(true);
    setError(null);

    try {
      const token = sdk.getToken();
      const result = await token.getBalance(address);
      setBalance(result);
    } catch (err: any) {
      setError(err.message || 'Failed to fetch balance');
    } finally {
      setIsLoading(false);
    }
  }, [sdk, address]);

  useEffect(() => {
    fetchBalance();
  }, [fetchBalance]);

  return {
    balance,
    isLoading,
    error,
    refetch: fetchBalance,
  };
}
```

### useVaultMetrics Hook

Hook for displaying vault metrics.

```typescript
import { useState, useEffect, useCallback } from 'react';
import { BaseroSDK } from '@basero/sdk';

interface VaultMetrics {
  totalAssets: bigint;
  totalSupply: bigint;
  sharePrice: bigint;
}

interface UseVaultMetricsResult {
  metrics: VaultMetrics | null;
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
}

export function useVaultMetrics(
  sdk: BaseroSDK | null
): UseVaultMetricsResult {
  const [metrics, setMetrics] = useState<VaultMetrics | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetchMetrics = useCallback(async () => {
    if (!sdk) return;

    setIsLoading(true);
    setError(null);

    try {
      const vault = sdk.getVault();
      const result = await vault.getMetrics();
      setMetrics(result);
    } catch (err: any) {
      setError(err.message || 'Failed to fetch metrics');
    } finally {
      setIsLoading(false);
    }
  }, [sdk]);

  useEffect(() => {
    fetchMetrics();
    
    // Refresh every 30 seconds
    const interval = setInterval(fetchMetrics, 30000);
    return () => clearInterval(interval);
  }, [fetchMetrics]);

  return {
    metrics,
    isLoading,
    error,
    refetch: fetchMetrics,
  };
}
```

### useTransaction Hook

Hook for handling transaction submission and tracking.

```typescript
import { useState, useCallback } from 'react';
import { OperationResult } from '@basero/sdk';

interface UseTransactionResult {
  submit: (fn: () => Promise<OperationResult>) => Promise<void>;
  isLoading: boolean;
  txHash: string | null;
  error: string | null;
  reset: () => void;
}

export function useTransaction(): UseTransactionResult {
  const [isLoading, setIsLoading] = useState(false);
  const [txHash, setTxHash] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const submit = useCallback(async (fn: () => Promise<OperationResult>) => {
    setIsLoading(true);
    setError(null);
    setTxHash(null);

    try {
      const result = await fn();
      
      if (!result.success) {
        throw new Error(result.error || 'Transaction failed');
      }

      setTxHash(result.hash || null);
    } catch (err: any) {
      setError(err.message || 'Transaction failed');
    } finally {
      setIsLoading(false);
    }
  }, []);

  const reset = useCallback(() => {
    setIsLoading(false);
    setTxHash(null);
    setError(null);
  }, []);

  return {
    submit,
    isLoading,
    txHash,
    error,
    reset,
  };
}
```

### useEventListener Hook

Hook for listening to protocol events.

```typescript
import { useState, useEffect } from 'react';
import { BaseroSDK } from '@basero/sdk';
import { Log } from 'ethers';

interface UseEventListenerResult {
  events: Log[];
  isLoading: boolean;
  error: string | null;
}

export function useEventListener(
  sdk: BaseroSDK | null,
  eventName: string,
  contractAddress: string
): UseEventListenerResult {
  const [events, setEvents] = useState<Log[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!sdk) return;

    setIsLoading(true);
    setError(null);

    const provider = sdk.getProvider();
    const filter = {
      address: contractAddress,
      topics: [ethers.id(eventName)],
    };

    // Listen for new events
    const listener = (log: Log) => {
      setEvents(prev => [...prev, log]);
    };

    provider.on(filter, listener);

    setIsLoading(false);

    return () => {
      provider.off(filter, listener);
    };
  }, [sdk, eventName, contractAddress]);

  return {
    events,
    isLoading,
    error,
  };
}
```

---

## Wallet Integration

### Wallet Connection Component

Complete wallet connection UI with MetaMask support.

```typescript
import React from 'react';
import { useBaseroSDK } from './hooks/useBaseroSDK';

const NETWORK_CONFIG = {
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

export function WalletConnect() {
  const { sdk, isConnected, isLoading, error, connect, disconnect } = 
    useBaseroSDK(NETWORK_CONFIG);

  return (
    <div className="wallet-connect">
      {!isConnected ? (
        <button 
          onClick={connect} 
          disabled={isLoading}
          className="connect-button"
        >
          {isLoading ? 'Connecting...' : 'Connect Wallet'}
        </button>
      ) : (
        <button 
          onClick={disconnect}
          className="disconnect-button"
        >
          Disconnect
        </button>
      )}
      
      {error && (
        <div className="error-message">
          {error}
        </div>
      )}
    </div>
  );
}
```

### Account Display Component

Display connected account with formatting.

```typescript
import React, { useState, useEffect } from 'react';
import { AddressUtils } from '@basero/sdk';

interface AccountDisplayProps {
  sdk: BaseroSDK | null;
}

export function AccountDisplay({ sdk }: AccountDisplayProps) {
  const [address, setAddress] = useState<string | null>(null);

  useEffect(() => {
    if (!sdk || !sdk.hasSigner()) return;

    const fetchAddress = async () => {
      const signer = sdk.getSigner();
      if (signer) {
        const addr = await signer.getAddress();
        setAddress(addr);
      }
    };

    fetchAddress();
  }, [sdk]);

  if (!address) return null;

  return (
    <div className="account-display">
      <div className="account-icon">👤</div>
      <div className="account-address">
        {AddressUtils.formatAddress(address, 6, 4)}
      </div>
    </div>
  );
}
```

### Network Switcher Component

Switch between supported networks.

```typescript
import React from 'react';
import { ChainUtils } from '@basero/sdk';

const SUPPORTED_CHAINS = [
  { id: 11155111, name: 'Sepolia' },
  { id: 84532, name: 'Base Sepolia' },
  { id: 1, name: 'Ethereum' },
  { id: 8453, name: 'Base' },
];

export function NetworkSwitcher() {
  const [currentChainId, setCurrentChainId] = useState<number | null>(null);

  useEffect(() => {
    const checkNetwork = async () => {
      if (!window.ethereum) return;
      
      const chainId = await window.ethereum.request({ 
        method: 'eth_chainId' 
      });
      setCurrentChainId(parseInt(chainId, 16));
    };

    checkNetwork();

    if (window.ethereum) {
      window.ethereum.on('chainChanged', (chainId: string) => {
        setCurrentChainId(parseInt(chainId, 16));
      });
    }
  }, []);

  const switchNetwork = async (chainId: number) => {
    if (!window.ethereum) return;

    try {
      await window.ethereum.request({
        method: 'wallet_switchEthereumChain',
        params: [{ chainId: `0x${chainId.toString(16)}` }],
      });
    } catch (err: any) {
      console.error('Failed to switch network:', err);
    }
  };

  return (
    <div className="network-switcher">
      <label>Network:</label>
      <select 
        value={currentChainId || ''} 
        onChange={(e) => switchNetwork(Number(e.target.value))}
      >
        {SUPPORTED_CHAINS.map(chain => (
          <option key={chain.id} value={chain.id}>
            {chain.name}
          </option>
        ))}
      </select>
    </div>
  );
}
```

---

## Token Display Patterns

### Token Balance Display

Component for displaying token balances with formatting.

```typescript
import React from 'react';
import { useTokenBalance } from './hooks/useTokenBalance';
import { AmountFormatter } from '@basero/sdk';

interface TokenBalanceProps {
  sdk: BaseroSDK | null;
  address: string | null;
  showUSD?: boolean;
  tokenPrice?: number;
}

export function TokenBalance({ 
  sdk, 
  address, 
  showUSD = false,
  tokenPrice = 0 
}: TokenBalanceProps) {
  const { balance, isLoading, error } = useTokenBalance(sdk, address);

  if (isLoading) {
    return <div className="balance-loading">Loading...</div>;
  }

  if (error) {
    return <div className="balance-error">Error: {error}</div>;
  }

  if (!balance) {
    return <div className="balance-empty">--</div>;
  }

  return (
    <div className="token-balance">
      <div className="balance-amount">
        {balance.formatted} BASE
      </div>
      {showUSD && tokenPrice > 0 && (
        <div className="balance-usd">
          {AmountFormatter.toUSD(balance.raw, tokenPrice)}
        </div>
      )}
    </div>
  );
}
```

### Amount Input Component

Input component with validation and formatting.

```typescript
import React, { useState, useCallback } from 'react';
import { AmountFormatter, Validators } from '@basero/sdk';

interface AmountInputProps {
  value: string;
  onChange: (value: string) => void;
  max?: bigint;
  placeholder?: string;
  label?: string;
}

export function AmountInput({ 
  value, 
  onChange, 
  max,
  placeholder = '0.00',
  label = 'Amount'
}: AmountInputProps) {
  const [error, setError] = useState<string | null>(null);

  const handleChange = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    const newValue = e.target.value;
    
    // Allow empty or valid number format
    if (newValue === '' || /^\d*\.?\d*$/.test(newValue)) {
      onChange(newValue);
      
      // Validate
      if (newValue && !Validators.isValidAmount(newValue)) {
        setError('Invalid amount');
      } else if (max && newValue) {
        const amount = AmountFormatter.toBN(newValue);
        if (amount > max) {
          setError('Amount exceeds maximum');
        } else {
          setError(null);
        }
      } else {
        setError(null);
      }
    }
  }, [onChange, max]);

  const handleMaxClick = useCallback(() => {
    if (max) {
      const maxFormatted = AmountFormatter.toDecimal(max, 18, 6);
      onChange(maxFormatted);
      setError(null);
    }
  }, [max, onChange]);

  return (
    <div className="amount-input">
      <label>{label}</label>
      <div className="input-wrapper">
        <input
          type="text"
          value={value}
          onChange={handleChange}
          placeholder={placeholder}
          className={error ? 'error' : ''}
        />
        {max && (
          <button 
            onClick={handleMaxClick}
            className="max-button"
            type="button"
          >
            MAX
          </button>
        )}
      </div>
      {error && <div className="input-error">{error}</div>}
    </div>
  );
}
```

### Vault Stats Display

Component for displaying vault statistics.

```typescript
import React from 'react';
import { useVaultMetrics } from './hooks/useVaultMetrics';
import { AmountFormatter } from '@basero/sdk';

interface VaultStatsProps {
  sdk: BaseroSDK | null;
}

export function VaultStats({ sdk }: VaultStatsProps) {
  const { metrics, isLoading, error } = useVaultMetrics(sdk);

  if (isLoading) return <div>Loading metrics...</div>;
  if (error) return <div>Error: {error}</div>;
  if (!metrics) return null;

  const totalAssetsFormatted = AmountFormatter.toAbbreviated(metrics.totalAssets);
  const totalSupplyFormatted = AmountFormatter.toAbbreviated(metrics.totalSupply);
  const sharePrice = AmountFormatter.toDecimal(metrics.sharePrice, 18, 4);

  return (
    <div className="vault-stats">
      <div className="stat-item">
        <div className="stat-label">Total Assets</div>
        <div className="stat-value">{totalAssetsFormatted}</div>
      </div>
      
      <div className="stat-item">
        <div className="stat-label">Total Shares</div>
        <div className="stat-value">{totalSupplyFormatted}</div>
      </div>
      
      <div className="stat-item">
        <div className="stat-label">Share Price</div>
        <div className="stat-value">{sharePrice}</div>
      </div>
    </div>
  );
}
```

---

## Error Handling

### Error Display Component

Reusable component for displaying errors.

```typescript
import React from 'react';
import { ErrorFormatter } from '@basero/sdk';

interface ErrorDisplayProps {
  error: any;
  onDismiss?: () => void;
}

export function ErrorDisplay({ error, onDismiss }: ErrorDisplayProps) {
  if (!error) return null;

  const message = ErrorFormatter.formatError(error);
  const revertReason = ErrorFormatter.extractRevertReason(error);
  
  let errorType = 'Error';
  if (ErrorFormatter.isInsufficientBalance(error)) {
    errorType = 'Insufficient Balance';
  } else if (ErrorFormatter.isTimeoutError(error)) {
    errorType = 'Transaction Timeout';
  } else if (ErrorFormatter.isInvalidAddress(error)) {
    errorType = 'Invalid Address';
  }

  return (
    <div className="error-display">
      <div className="error-header">
        <span className="error-icon">⚠️</span>
        <span className="error-type">{errorType}</span>
        {onDismiss && (
          <button onClick={onDismiss} className="error-dismiss">
            ✕
          </button>
        )}
      </div>
      
      <div className="error-message">{message}</div>
      
      {revertReason && (
        <div className="error-reason">
          Reason: {revertReason}
        </div>
      )}
    </div>
  );
}
```

### Transaction Status Component

Component for tracking transaction status.

```typescript
import React from 'react';
import { ChainUtils } from '@basero/sdk';

interface TransactionStatusProps {
  txHash: string | null;
  isLoading: boolean;
  error: string | null;
  chainId: number;
}

export function TransactionStatus({ 
  txHash, 
  isLoading, 
  error, 
  chainId 
}: TransactionStatusProps) {
  if (isLoading) {
    return (
      <div className="tx-status tx-loading">
        <div className="spinner"></div>
        <div>Transaction pending...</div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="tx-status tx-error">
        <div className="error-icon">❌</div>
        <div>{error}</div>
      </div>
    );
  }

  if (txHash) {
    const explorerUrl = ChainUtils.getTxExplorerUrl(chainId, txHash);
    
    return (
      <div className="tx-status tx-success">
        <div className="success-icon">✅</div>
        <div>Transaction successful!</div>
        {explorerUrl && (
          <a 
            href={explorerUrl} 
            target="_blank" 
            rel="noopener noreferrer"
            className="explorer-link"
          >
            View on Explorer →
          </a>
        )}
      </div>
    );
  }

  return null;
}
```

### Error Boundary Component

React error boundary for catching rendering errors.

```typescript
import React, { Component, ErrorInfo, ReactNode } from 'react';

interface Props {
  children: ReactNode;
  fallback?: ReactNode;
}

interface State {
  hasError: boolean;
  error: Error | null;
}

export class ErrorBoundary extends Component<Props, State> {
  constructor(props: Props) {
    super(props);
    this.state = {
      hasError: false,
      error: null,
    };
  }

  static getDerivedStateFromError(error: Error): State {
    return {
      hasError: true,
      error,
    };
  }

  componentDidCatch(error: Error, errorInfo: ErrorInfo) {
    console.error('Error boundary caught:', error, errorInfo);
  }

  render() {
    if (this.state.hasError) {
      return this.props.fallback || (
        <div className="error-boundary">
          <h2>Something went wrong</h2>
          <details>
            <summary>Error details</summary>
            <pre>{this.state.error?.message}</pre>
          </details>
          <button onClick={() => window.location.reload()}>
            Reload Page
          </button>
        </div>
      );
    }

    return this.props.children;
  }
}
```

---

## Complete Examples

### Deposit Form Component

Complete deposit form with validation and error handling.

```typescript
import React, { useState } from 'react';
import { useBaseroSDK } from './hooks/useBaseroSDK';
import { useTokenBalance } from './hooks/useTokenBalance';
import { useTransaction } from './hooks/useTransaction';
import { AmountInput } from './components/AmountInput';
import { TransactionStatus } from './components/TransactionStatus';
import { AmountFormatter } from '@basero/sdk';

export function DepositForm() {
  const { sdk, isConnected } = useBaseroSDK(NETWORK_CONFIG);
  const [address, setAddress] = useState<string | null>(null);
  const { balance } = useTokenBalance(sdk, address);
  const { submit, isLoading, txHash, error, reset } = useTransaction();
  const [amount, setAmount] = useState('');

  useEffect(() => {
    if (sdk && sdk.hasSigner()) {
      sdk.getSigner()?.getAddress().then(setAddress);
    }
  }, [sdk]);

  const handleDeposit = async () => {
    if (!sdk || !amount) return;

    await submit(async () => {
      const vault = sdk.getVault();
      return await vault.deposit(amount, address!);
    });
  };

  if (!isConnected) {
    return <div>Please connect your wallet</div>;
  }

  return (
    <div className="deposit-form">
      <h2>Deposit to Vault</h2>
      
      <AmountInput
        value={amount}
        onChange={setAmount}
        max={balance?.raw}
        label="Amount to Deposit"
        placeholder="0.00"
      />

      <div className="balance-display">
        Available: {balance?.formatted || '0.00'} BASE
      </div>

      <button
        onClick={handleDeposit}
        disabled={isLoading || !amount || parseFloat(amount) === 0}
        className="deposit-button"
      >
        {isLoading ? 'Depositing...' : 'Deposit'}
      </button>

      <TransactionStatus
        txHash={txHash}
        isLoading={isLoading}
        error={error}
        chainId={NETWORK_CONFIG.chainId}
      />
    </div>
  );
}
```

### Governance Voting Component

Complete component for casting votes on proposals.

```typescript
import React, { useState } from 'react';
import { useBaseroSDK } from './hooks/useBaseroSDK';
import { useTransaction } from './hooks/useTransaction';

interface VotingComponentProps {
  proposalId: bigint;
  proposalDescription: string;
}

export function VotingComponent({ 
  proposalId, 
  proposalDescription 
}: VotingComponentProps) {
  const { sdk } = useBaseroSDK(NETWORK_CONFIG);
  const { submit, isLoading, txHash, error } = useTransaction();
  const [selectedVote, setSelectedVote] = useState<number | null>(null);

  const handleVote = async (support: number) => {
    if (!sdk) return;

    setSelectedVote(support);
    
    await submit(async () => {
      const governance = sdk.getGovernance();
      return await governance.castVote(proposalId, support);
    });
  };

  return (
    <div className="voting-component">
      <h3>Proposal #{proposalId.toString()}</h3>
      <p>{proposalDescription}</p>

      <div className="vote-buttons">
        <button
          onClick={() => handleVote(1)}
          disabled={isLoading}
          className={selectedVote === 1 ? 'selected' : ''}
        >
          👍 For
        </button>
        
        <button
          onClick={() => handleVote(0)}
          disabled={isLoading}
          className={selectedVote === 0 ? 'selected' : ''}
        >
          👎 Against
        </button>
        
        <button
          onClick={() => handleVote(2)}
          disabled={isLoading}
          className={selectedVote === 2 ? 'selected' : ''}
        >
          🤷 Abstain
        </button>
      </div>

      {isLoading && <div>Submitting vote...</div>}
      {txHash && <div>Vote submitted! TX: {txHash}</div>}
      {error && <div className="error">{error}</div>}
    </div>
  );
}
```

---

## Best Practices

### 1. Always Validate Inputs

```typescript
import { Validators, AmountFormatter } from '@basero/sdk';

function validateDepositAmount(amount: string, balance: bigint): string | null {
  // Check if valid amount
  if (!Validators.isValidAmount(amount)) {
    return 'Invalid amount format';
  }

  // Convert and check
  const amountBN = AmountFormatter.toBN(amount);
  
  // Check if positive
  if (!Validators.isValidTransferAmount(amountBN)) {
    return 'Amount must be greater than 0';
  }

  // Check balance
  if (amountBN > balance) {
    return 'Insufficient balance';
  }

  return null;
}
```

### 2. Handle Network Changes

```typescript
useEffect(() => {
  if (!window.ethereum) return;

  const handleChainChanged = () => {
    window.location.reload();
  };

  const handleAccountsChanged = (accounts: string[]) => {
    if (accounts.length === 0) {
      disconnect();
    } else {
      window.location.reload();
    }
  };

  window.ethereum.on('chainChanged', handleChainChanged);
  window.ethereum.on('accountsChanged', handleAccountsChanged);

  return () => {
    window.ethereum.removeListener('chainChanged', handleChainChanged);
    window.ethereum.removeListener('accountsChanged', handleAccountsChanged);
  };
}, []);
```

### 3. Optimize Re-renders

```typescript
import { useMemo } from 'react';

function MyComponent({ sdk, address }) {
  // Memoize expensive calculations
  const formattedBalance = useMemo(() => {
    if (!balance) return '0.00';
    return AmountFormatter.toDecimal(balance.raw, 18, 2);
  }, [balance]);

  return <div>{formattedBalance}</div>;
}
```

### 4. Use Error Boundaries

```typescript
import { ErrorBoundary } from './components/ErrorBoundary';

function App() {
  return (
    <ErrorBoundary>
      <YourAppComponents />
    </ErrorBoundary>
  );
}
```

### 5. Debounce User Input

```typescript
import { useDebouncedValue } from './hooks/useDebounce';

function SearchComponent() {
  const [input, setInput] = useState('');
  const debouncedInput = useDebouncedValue(input, 500);

  useEffect(() => {
    // Only search when debounced value changes
    if (debouncedInput) {
      performSearch(debouncedInput);
    }
  }, [debouncedInput]);

  return (
    <input 
      value={input} 
      onChange={(e) => setInput(e.target.value)} 
    />
  );
}
```

### 6. Cache SDK Instance

```typescript
const SDK_CACHE = new Map<string, BaseroSDK>();

function getOrCreateSDK(provider, config, signer): BaseroSDK {
  const key = `${config.chainId}-${config.addresses.token}`;
  
  if (!SDK_CACHE.has(key)) {
    SDK_CACHE.set(key, new BaseroSDK(provider, config, signer));
  }
  
  return SDK_CACHE.get(key)!;
}
```

---

## TypeScript Types

### Extend Window Type

```typescript
// global.d.ts
interface Window {
  ethereum?: {
    request: (args: { method: string; params?: any[] }) => Promise<any>;
    on: (event: string, callback: (...args: any[]) => void) => void;
    removeListener: (event: string, callback: (...args: any[]) => void) => void;
    isMetaMask?: boolean;
  };
}
```

### Component Props Types

```typescript
import { BaseroSDK } from '@basero/sdk';
import { ReactNode } from 'react';

export interface BaseComponentProps {
  sdk: BaseroSDK | null;
  className?: string;
  children?: ReactNode;
}

export interface TransactionComponentProps extends BaseComponentProps {
  onSuccess?: (txHash: string) => void;
  onError?: (error: Error) => void;
}
```

---

## Styling Examples

### CSS for Components

```css
/* Wallet Connect Button */
.connect-button {
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  color: white;
  padding: 12px 24px;
  border: none;
  border-radius: 8px;
  font-weight: 600;
  cursor: pointer;
  transition: transform 0.2s;
}

.connect-button:hover {
  transform: translateY(-2px);
}

.connect-button:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}

/* Error Display */
.error-display {
  background: #fee;
  border: 1px solid #fcc;
  border-radius: 8px;
  padding: 16px;
  margin: 16px 0;
}

.error-header {
  display: flex;
  align-items: center;
  gap: 8px;
  font-weight: 600;
  color: #c33;
}

/* Transaction Status */
.tx-status {
  padding: 16px;
  border-radius: 8px;
  margin: 16px 0;
}

.tx-loading {
  background: #fef9e7;
  border: 1px solid #f9e79f;
}

.tx-success {
  background: #e8f8f5;
  border: 1px solid #a9dfbf;
}

.tx-error {
  background: #fee;
  border: 1px solid #fcc;
}

/* Amount Input */
.amount-input {
  margin: 16px 0;
}

.input-wrapper {
  position: relative;
  display: flex;
  gap: 8px;
}

.input-wrapper input {
  flex: 1;
  padding: 12px;
  border: 2px solid #ddd;
  border-radius: 8px;
  font-size: 16px;
}

.input-wrapper input.error {
  border-color: #f88;
}

.max-button {
  background: #667eea;
  color: white;
  border: none;
  padding: 0 16px;
  border-radius: 8px;
  cursor: pointer;
  font-weight: 600;
}
```

---

## Summary

This guide covers:

✅ **React Hooks** - 5 custom hooks for SDK integration
✅ **Wallet Integration** - Connection, account display, network switching
✅ **Token Display** - Balance display, amount input, vault stats
✅ **Error Handling** - Error display, transaction status, error boundaries
✅ **Complete Examples** - Deposit form, voting component
✅ **Best Practices** - Validation, optimization, caching

For more information, see the [SDK Guide](SDK_GUIDE.md) and [examples](examples/examples.ts).
