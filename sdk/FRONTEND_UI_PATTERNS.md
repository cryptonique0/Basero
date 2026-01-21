# Frontend UI Patterns - Basero dApp

## Complete Component Library

### 1. Dashboard Layout

```typescript
import React from 'react';
import { WalletConnect } from './components/WalletConnect';
import { AccountDisplay } from './components/AccountDisplay';
import { NetworkSwitcher } from './components/NetworkSwitcher';
import { VaultStats } from './components/VaultStats';
import { TokenBalance } from './components/TokenBalance';
import { useBaseroSDK } from './hooks/useBaseroSDK';

export function Dashboard() {
  const { sdk, isConnected } = useBaseroSDK(NETWORK_CONFIG);
  const [address, setAddress] = useState<string | null>(null);

  useEffect(() => {
    if (sdk && sdk.hasSigner()) {
      sdk.getSigner()?.getAddress().then(setAddress);
    }
  }, [sdk]);

  return (
    <div className="dashboard">
      {/* Header */}
      <header className="dashboard-header">
        <div className="logo">
          <h1>Basero Protocol</h1>
        </div>
        
        <div className="header-actions">
          <NetworkSwitcher />
          {isConnected ? (
            <AccountDisplay sdk={sdk} />
          ) : (
            <WalletConnect />
          )}
        </div>
      </header>

      {/* Main Content */}
      {isConnected ? (
        <main className="dashboard-content">
          {/* Overview Section */}
          <section className="overview-section">
            <h2>Overview</h2>
            <div className="stats-grid">
              <VaultStats sdk={sdk} />
              <TokenBalance 
                sdk={sdk} 
                address={address}
                showUSD={true}
                tokenPrice={10}
              />
            </div>
          </section>

          {/* Actions Section */}
          <section className="actions-section">
            <div className="action-tabs">
              <button className="tab active">Deposit</button>
              <button className="tab">Withdraw</button>
              <button className="tab">Governance</button>
            </div>
            
            <div className="action-content">
              {/* Dynamic content based on selected tab */}
            </div>
          </section>
        </main>
      ) : (
        <div className="connect-prompt">
          <h2>Welcome to Basero Protocol</h2>
          <p>Connect your wallet to get started</p>
          <WalletConnect />
        </div>
      )}
    </div>
  );
}
```

### 2. Deposit/Withdraw Interface

```typescript
import React, { useState } from 'react';
import { useBaseroSDK } from './hooks/useBaseroSDK';
import { useTokenBalance } from './hooks/useTokenBalance';
import { useVaultMetrics } from './hooks/useVaultMetrics';
import { useTransaction } from './hooks/useTransaction';
import { AmountInput } from './components/AmountInput';
import { AmountFormatter } from '@basero/sdk';

export function VaultInterface() {
  const { sdk } = useBaseroSDK(NETWORK_CONFIG);
  const [address, setAddress] = useState<string | null>(null);
  const [activeTab, setActiveTab] = useState<'deposit' | 'withdraw'>('deposit');
  const [amount, setAmount] = useState('');
  
  const { balance } = useTokenBalance(sdk, address);
  const { metrics } = useVaultMetrics(sdk);
  const { submit, isLoading, txHash, error } = useTransaction();

  useEffect(() => {
    if (sdk && sdk.hasSigner()) {
      sdk.getSigner()?.getAddress().then(setAddress);
    }
  }, [sdk]);

  const handleDeposit = async () => {
    if (!sdk || !address) return;

    await submit(async () => {
      const vault = sdk.getVault();
      return await vault.deposit(amount, address);
    });
    
    setAmount(''); // Reset after success
  };

  const handleWithdraw = async () => {
    if (!sdk || !address) return;

    await submit(async () => {
      const vault = sdk.getVault();
      const shares = AmountFormatter.toBN(amount);
      return await vault.withdraw(shares.toString(), address, address);
    });
    
    setAmount(''); // Reset after success
  };

  const previewShares = async () => {
    if (!sdk || !amount) return '0';
    
    const vault = sdk.getVault();
    const preview = await vault.previewDeposit(amount);
    return AmountFormatter.toDecimal(preview.shares, 18, 4);
  };

  return (
    <div className="vault-interface">
      {/* Tab Switcher */}
      <div className="tab-switcher">
        <button
          className={activeTab === 'deposit' ? 'active' : ''}
          onClick={() => setActiveTab('deposit')}
        >
          Deposit
        </button>
        <button
          className={activeTab === 'withdraw' ? 'active' : ''}
          onClick={() => setActiveTab('withdraw')}
        >
          Withdraw
        </button>
      </div>

      {/* Deposit Tab */}
      {activeTab === 'deposit' && (
        <div className="deposit-tab">
          <AmountInput
            value={amount}
            onChange={setAmount}
            max={balance?.raw}
            label="Amount to Deposit"
          />

          <div className="info-row">
            <span>You will receive:</span>
            <span className="value">
              {amount ? `~${previewShares()} shares` : '--'}
            </span>
          </div>

          <div className="info-row">
            <span>Current share price:</span>
            <span className="value">
              {metrics ? AmountFormatter.toDecimal(metrics.sharePrice) : '--'}
            </span>
          </div>

          <button
            onClick={handleDeposit}
            disabled={isLoading || !amount}
            className="primary-button"
          >
            {isLoading ? 'Depositing...' : 'Deposit'}
          </button>
        </div>
      )}

      {/* Withdraw Tab */}
      {activeTab === 'withdraw' && (
        <div className="withdraw-tab">
          <AmountInput
            value={amount}
            onChange={setAmount}
            label="Shares to Withdraw"
          />

          <button
            onClick={handleWithdraw}
            disabled={isLoading || !amount}
            className="primary-button"
          >
            {isLoading ? 'Withdrawing...' : 'Withdraw'}
          </button>
        </div>
      )}

      {/* Transaction Status */}
      {(txHash || error) && (
        <div className="transaction-status">
          {txHash && (
            <div className="success">
              ✅ Transaction successful!
              <a 
                href={`https://sepolia.etherscan.io/tx/${txHash}`}
                target="_blank"
                rel="noopener noreferrer"
              >
                View on Etherscan
              </a>
            </div>
          )}
          {error && (
            <div className="error">
              ❌ {error}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
```

### 3. Governance Interface

```typescript
import React, { useState, useEffect } from 'react';
import { useBaseroSDK } from './hooks/useBaseroSDK';
import { useTransaction } from './hooks/useTransaction';

interface Proposal {
  id: bigint;
  description: string;
  forVotes: bigint;
  againstVotes: bigint;
  abstainVotes: bigint;
  startBlock: bigint;
  endBlock: bigint;
  state: number;
}

export function GovernanceInterface() {
  const { sdk } = useBaseroSDK(NETWORK_CONFIG);
  const [proposals, setProposals] = useState<Proposal[]>([]);
  const [votingPower, setVotingPower] = useState<string>('0');
  const { submit, isLoading, txHash, error } = useTransaction();

  useEffect(() => {
    fetchProposals();
    fetchVotingPower();
  }, [sdk]);

  const fetchProposals = async () => {
    // Fetch proposals from contract events or API
    // This is a simplified example
  };

  const fetchVotingPower = async () => {
    if (!sdk || !sdk.hasSigner()) return;

    const governance = sdk.getGovernance();
    const signer = sdk.getSigner();
    const address = await signer?.getAddress();
    
    if (address) {
      const power = await governance.getVotingPower(address);
      setVotingPower(power.formatted);
    }
  };

  const handleVote = async (proposalId: bigint, support: number) => {
    if (!sdk) return;

    await submit(async () => {
      const governance = sdk.getGovernance();
      return await governance.castVote(proposalId, support);
    });
  };

  return (
    <div className="governance-interface">
      {/* Voting Power Display */}
      <div className="voting-power-card">
        <h3>Your Voting Power</h3>
        <div className="power-amount">{votingPower} veBASE</div>
        <button className="lock-tokens-button">
          Lock Tokens to Get Voting Power
        </button>
      </div>

      {/* Proposals List */}
      <div className="proposals-section">
        <h2>Active Proposals</h2>
        
        {proposals.length === 0 ? (
          <div className="no-proposals">
            No active proposals at this time
          </div>
        ) : (
          <div className="proposals-list">
            {proposals.map(proposal => (
              <ProposalCard
                key={proposal.id.toString()}
                proposal={proposal}
                onVote={handleVote}
                isLoading={isLoading}
              />
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

function ProposalCard({ 
  proposal, 
  onVote, 
  isLoading 
}: {
  proposal: Proposal;
  onVote: (id: bigint, support: number) => void;
  isLoading: boolean;
}) {
  const totalVotes = proposal.forVotes + proposal.againstVotes + proposal.abstainVotes;
  const forPercent = totalVotes > 0n 
    ? Number((proposal.forVotes * 100n) / totalVotes) 
    : 0;
  const againstPercent = totalVotes > 0n 
    ? Number((proposal.againstVotes * 100n) / totalVotes) 
    : 0;

  return (
    <div className="proposal-card">
      <h3>Proposal #{proposal.id.toString()}</h3>
      <p className="proposal-description">{proposal.description}</p>

      {/* Vote Breakdown */}
      <div className="vote-breakdown">
        <div className="vote-bar">
          <div 
            className="vote-bar-for" 
            style={{ width: `${forPercent}%` }}
          />
          <div 
            className="vote-bar-against" 
            style={{ width: `${againstPercent}%` }}
          />
        </div>
        
        <div className="vote-stats">
          <div className="stat">
            <span className="label">For:</span>
            <span className="value">{forPercent.toFixed(1)}%</span>
          </div>
          <div className="stat">
            <span className="label">Against:</span>
            <span className="value">{againstPercent.toFixed(1)}%</span>
          </div>
        </div>
      </div>

      {/* Vote Buttons */}
      <div className="vote-buttons">
        <button
          onClick={() => onVote(proposal.id, 1)}
          disabled={isLoading}
          className="vote-for"
        >
          👍 Vote For
        </button>
        <button
          onClick={() => onVote(proposal.id, 0)}
          disabled={isLoading}
          className="vote-against"
        >
          👎 Vote Against
        </button>
        <button
          onClick={() => onVote(proposal.id, 2)}
          disabled={isLoading}
          className="vote-abstain"
        >
          🤷 Abstain
        </button>
      </div>
    </div>
  );
}
```

### 4. Transaction History

```typescript
import React, { useState, useEffect } from 'react';
import { useBaseroSDK } from './hooks/useBaseroSDK';
import { TokenEventParser } from '@basero/sdk';
import { AmountFormatter, ChainUtils } from '@basero/sdk';

interface Transaction {
  hash: string;
  type: 'transfer' | 'deposit' | 'withdraw' | 'vote';
  amount: string;
  timestamp: number;
  status: 'success' | 'pending' | 'failed';
}

export function TransactionHistory() {
  const { sdk } = useBaseroSDK(NETWORK_CONFIG);
  const [transactions, setTransactions] = useState<Transaction[]>([]);
  const [isLoading, setIsLoading] = useState(false);

  useEffect(() => {
    fetchTransactions();
  }, [sdk]);

  const fetchTransactions = async () => {
    if (!sdk || !sdk.hasSigner()) return;

    setIsLoading(true);

    try {
      const provider = sdk.getProvider();
      const signer = sdk.getSigner();
      const address = await signer?.getAddress();

      if (!address) return;

      const latestBlock = await provider.getBlockNumber();
      const fromBlock = latestBlock - 10000; // Last ~10k blocks

      // Fetch transfer events
      const logs = await provider.getLogs({
        address: sdk.getConfig().addresses.token,
        topics: [
          ethers.id('Transfer(address,address,uint256)'),
          null,
          ethers.zeroPadValue(address, 32), // To address
        ],
        fromBlock,
        toBlock: latestBlock,
      });

      const parser = new TokenEventParser();
      const transfers = logs
        .map(log => parser.parseTransfer(log))
        .filter(Boolean)
        .map(transfer => ({
          hash: transfer!.raw?.transactionHash || '',
          type: 'transfer' as const,
          amount: AmountFormatter.toDecimal(transfer!.amount),
          timestamp: Date.now(), // Would fetch from block
          status: 'success' as const,
        }));

      setTransactions(transfers);
    } catch (error) {
      console.error('Failed to fetch transactions:', error);
    } finally {
      setIsLoading(false);
    }
  };

  if (isLoading) {
    return <div className="loading">Loading transaction history...</div>;
  }

  return (
    <div className="transaction-history">
      <h2>Transaction History</h2>
      
      {transactions.length === 0 ? (
        <div className="no-transactions">
          No transactions found
        </div>
      ) : (
        <div className="transactions-list">
          {transactions.map((tx, index) => (
            <div key={index} className="transaction-item">
              <div className="tx-icon">
                {tx.type === 'transfer' && '💸'}
                {tx.type === 'deposit' && '⬇️'}
                {tx.type === 'withdraw' && '⬆️'}
                {tx.type === 'vote' && '🗳️'}
              </div>
              
              <div className="tx-details">
                <div className="tx-type">{tx.type}</div>
                <div className="tx-hash">
                  {tx.hash.slice(0, 10)}...{tx.hash.slice(-8)}
                </div>
              </div>
              
              <div className="tx-amount">
                {tx.amount} BASE
              </div>
              
              <div className={`tx-status ${tx.status}`}>
                {tx.status === 'success' && '✅'}
                {tx.status === 'pending' && '⏳'}
                {tx.status === 'failed' && '❌'}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
```

### 5. Portfolio Overview

```typescript
import React, { useState, useEffect } from 'react';
import { useBaseroSDK } from './hooks/useBaseroSDK';
import { useTokenBalance } from './hooks/useTokenBalance';
import { useVaultMetrics } from './hooks/useVaultMetrics';
import { AmountFormatter } from '@basero/sdk';

export function PortfolioOverview() {
  const { sdk } = useBaseroSDK(NETWORK_CONFIG);
  const [address, setAddress] = useState<string | null>(null);
  const { balance: tokenBalance } = useTokenBalance(sdk, address);
  const { balance: vaultBalance } = useVaultBalance(sdk, address);
  const { metrics } = useVaultMetrics(sdk);

  useEffect(() => {
    if (sdk && sdk.hasSigner()) {
      sdk.getSigner()?.getAddress().then(setAddress);
    }
  }, [sdk]);

  const calculateTotalValue = () => {
    if (!tokenBalance || !vaultBalance || !metrics) return '0.00';

    const tokenValue = tokenBalance.raw;
    const vaultValue = vaultBalance.raw * metrics.sharePrice / BigInt(1e18);
    const total = tokenValue + vaultValue;

    return AmountFormatter.toDecimal(total, 18, 2);
  };

  const tokenPrice = 10; // USD price per token
  const totalValueUSD = parseFloat(calculateTotalValue()) * tokenPrice;

  return (
    <div className="portfolio-overview">
      <div className="portfolio-header">
        <h2>Portfolio Overview</h2>
        <div className="total-value">
          <div className="value-label">Total Value</div>
          <div className="value-amount">
            ${totalValueUSD.toLocaleString(undefined, { 
              minimumFractionDigits: 2,
              maximumFractionDigits: 2 
            })}
          </div>
          <div className="value-tokens">
            {calculateTotalValue()} BASE
          </div>
        </div>
      </div>

      <div className="portfolio-breakdown">
        <div className="asset-card">
          <div className="asset-icon">💰</div>
          <div className="asset-info">
            <div className="asset-name">Wallet Balance</div>
            <div className="asset-amount">
              {tokenBalance?.formatted || '0.00'} BASE
            </div>
            <div className="asset-value">
              ${(parseFloat(tokenBalance?.formatted || '0') * tokenPrice).toFixed(2)}
            </div>
          </div>
        </div>

        <div className="asset-card">
          <div className="asset-icon">🏦</div>
          <div className="asset-info">
            <div className="asset-name">Vault Deposit</div>
            <div className="asset-amount">
              {vaultBalance?.formatted || '0.00'} shares
            </div>
            <div className="asset-value">
              ${(parseFloat(vaultBalance?.formatted || '0') * tokenPrice).toFixed(2)}
            </div>
          </div>
        </div>
      </div>

      <div className="portfolio-actions">
        <button className="action-button">
          Deposit More
        </button>
        <button className="action-button secondary">
          Withdraw
        </button>
      </div>
    </div>
  );
}
```

### 6. Loading States

```typescript
import React from 'react';

export function LoadingSkeleton() {
  return (
    <div className="skeleton">
      <div className="skeleton-header" />
      <div className="skeleton-content">
        <div className="skeleton-line" />
        <div className="skeleton-line" />
        <div className="skeleton-line short" />
      </div>
    </div>
  );
}

export function LoadingSpinner() {
  return (
    <div className="spinner-container">
      <div className="spinner" />
    </div>
  );
}

export function LoadingOverlay({ message = 'Loading...' }) {
  return (
    <div className="loading-overlay">
      <div className="loading-content">
        <LoadingSpinner />
        <div className="loading-message">{message}</div>
      </div>
    </div>
  );
}
```

### 7. Toast Notifications

```typescript
import React, { createContext, useContext, useState, useCallback } from 'react';

interface Toast {
  id: string;
  type: 'success' | 'error' | 'info' | 'warning';
  message: string;
  duration?: number;
}

interface ToastContextValue {
  showToast: (toast: Omit<Toast, 'id'>) => void;
  hideToast: (id: string) => void;
}

const ToastContext = createContext<ToastContextValue | null>(null);

export function ToastProvider({ children }: { children: React.ReactNode }) {
  const [toasts, setToasts] = useState<Toast[]>([]);

  const showToast = useCallback((toast: Omit<Toast, 'id'>) => {
    const id = Math.random().toString(36);
    const newToast = { ...toast, id };
    
    setToasts(prev => [...prev, newToast]);

    setTimeout(() => {
      setToasts(prev => prev.filter(t => t.id !== id));
    }, toast.duration || 5000);
  }, []);

  const hideToast = useCallback((id: string) => {
    setToasts(prev => prev.filter(t => t.id !== id));
  }, []);

  return (
    <ToastContext.Provider value={{ showToast, hideToast }}>
      {children}
      <div className="toast-container">
        {toasts.map(toast => (
          <div key={toast.id} className={`toast toast-${toast.type}`}>
            <span className="toast-message">{toast.message}</span>
            <button 
              onClick={() => hideToast(toast.id)}
              className="toast-close"
            >
              ✕
            </button>
          </div>
        ))}
      </div>
    </ToastContext.Provider>
  );
}

export function useToast() {
  const context = useContext(ToastContext);
  if (!context) {
    throw new Error('useToast must be used within ToastProvider');
  }
  return context;
}
```

### Complete App Structure

```typescript
import React from 'react';
import { ToastProvider } from './contexts/ToastContext';
import { ErrorBoundary } from './components/ErrorBoundary';
import { Dashboard } from './components/Dashboard';
import './styles/App.css';

export function App() {
  return (
    <ErrorBoundary>
      <ToastProvider>
        <Dashboard />
      </ToastProvider>
    </ErrorBoundary>
  );
}
```

---

## CSS Styling

```css
/* Complete Stylesheet for Basero dApp */

:root {
  --primary: #667eea;
  --primary-dark: #5568d3;
  --secondary: #764ba2;
  --success: #10b981;
  --error: #ef4444;
  --warning: #f59e0b;
  --info: #3b82f6;
  
  --bg-primary: #ffffff;
  --bg-secondary: #f9fafb;
  --bg-tertiary: #f3f4f6;
  
  --text-primary: #111827;
  --text-secondary: #6b7280;
  --border: #e5e7eb;
  
  --radius: 12px;
  --shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1);
  --shadow-lg: 0 10px 15px -3px rgba(0, 0, 0, 0.1);
}

* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

body {
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
  background: var(--bg-secondary);
  color: var(--text-primary);
}

.dashboard {
  min-height: 100vh;
}

.dashboard-header {
  background: var(--bg-primary);
  padding: 1.5rem 2rem;
  display: flex;
  justify-content: space-between;
  align-items: center;
  border-bottom: 1px solid var(--border);
  box-shadow: var(--shadow);
}

.header-actions {
  display: flex;
  gap: 1rem;
  align-items: center;
}

.dashboard-content {
  max-width: 1200px;
  margin: 0 auto;
  padding: 2rem;
}

.stats-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
  gap: 1.5rem;
  margin-top: 1.5rem;
}

.primary-button {
  background: linear-gradient(135deg, var(--primary), var(--secondary));
  color: white;
  padding: 0.875rem 2rem;
  border: none;
  border-radius: var(--radius);
  font-weight: 600;
  cursor: pointer;
  transition: all 0.2s;
  width: 100%;
}

.primary-button:hover:not(:disabled) {
  transform: translateY(-2px);
  box-shadow: var(--shadow-lg);
}

.primary-button:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}

.vault-interface {
  background: var(--bg-primary);
  border-radius: var(--radius);
  padding: 2rem;
  box-shadow: var(--shadow);
}

.tab-switcher {
  display: flex;
  gap: 0.5rem;
  margin-bottom: 2rem;
  border-bottom: 2px solid var(--border);
}

.tab-switcher button {
  background: none;
  border: none;
  padding: 1rem 1.5rem;
  cursor: pointer;
  font-weight: 600;
  color: var(--text-secondary);
  border-bottom: 3px solid transparent;
  transition: all 0.2s;
}

.tab-switcher button.active {
  color: var(--primary);
  border-bottom-color: var(--primary);
}

.info-row {
  display: flex;
  justify-content: space-between;
  padding: 0.75rem 0;
  color: var(--text-secondary);
}

.info-row .value {
  font-weight: 600;
  color: var(--text-primary);
}

.proposal-card {
  background: var(--bg-primary);
  border-radius: var(--radius);
  padding: 1.5rem;
  margin-bottom: 1rem;
  box-shadow: var(--shadow);
}

.vote-breakdown {
  margin: 1.5rem 0;
}

.vote-bar {
  height: 8px;
  background: var(--bg-tertiary);
  border-radius: 4px;
  overflow: hidden;
  display: flex;
}

.vote-bar-for {
  background: var(--success);
}

.vote-bar-against {
  background: var(--error);
}

.vote-buttons {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 0.5rem;
  margin-top: 1rem;
}

.vote-buttons button {
  padding: 0.75rem;
  border: 2px solid var(--border);
  background: var(--bg-primary);
  border-radius: var(--radius);
  cursor: pointer;
  font-weight: 600;
  transition: all 0.2s;
}

.vote-buttons button:hover:not(:disabled) {
  border-color: var(--primary);
  background: var(--bg-secondary);
}

.toast-container {
  position: fixed;
  top: 2rem;
  right: 2rem;
  z-index: 1000;
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
}

.toast {
  background: var(--bg-primary);
  padding: 1rem 1.5rem;
  border-radius: var(--radius);
  box-shadow: var(--shadow-lg);
  display: flex;
  align-items: center;
  gap: 1rem;
  min-width: 300px;
  animation: slideIn 0.3s ease-out;
}

@keyframes slideIn {
  from {
    transform: translateX(100%);
    opacity: 0;
  }
  to {
    transform: translateX(0);
    opacity: 1;
  }
}

.toast-success {
  border-left: 4px solid var(--success);
}

.toast-error {
  border-left: 4px solid var(--error);
}

.skeleton {
  background: var(--bg-tertiary);
  border-radius: var(--radius);
  padding: 1.5rem;
  animation: pulse 2s cubic-bezier(0.4, 0, 0.6, 1) infinite;
}

@keyframes pulse {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.5; }
}

.spinner {
  border: 3px solid var(--bg-tertiary);
  border-top-color: var(--primary);
  border-radius: 50%;
  width: 40px;
  height: 40px;
  animation: spin 1s linear infinite;
}

@keyframes spin {
  to { transform: rotate(360deg); }
}
```

This complete UI pattern library provides everything needed to build a production-ready Basero dApp frontend!
