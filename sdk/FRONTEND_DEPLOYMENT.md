# Frontend Deployment Guide

## Quick Start

### 1. Create React App with TypeScript

```bash
npx create-react-app basero-dapp --template typescript
cd basero-dapp
npm install @basero/sdk ethers@^6.0.0
```

### 2. Project Structure

```
basero-dapp/
├── public/
│   ├── index.html
│   └── favicon.ico
├── src/
│   ├── components/
│   │   ├── WalletConnect.tsx
│   │   ├── AccountDisplay.tsx
│   │   ├── TokenBalance.tsx
│   │   ├── VaultInterface.tsx
│   │   └── GovernanceInterface.tsx
│   ├── hooks/
│   │   ├── useBaseroSDK.ts
│   │   ├── useTokenBalance.ts
│   │   ├── useVaultMetrics.ts
│   │   └── useTransaction.ts
│   ├── contexts/
│   │   └── ToastContext.tsx
│   ├── config/
│   │   └── network.ts
│   ├── styles/
│   │   └── App.css
│   ├── App.tsx
│   └── index.tsx
├── package.json
└── tsconfig.json
```

### 3. Environment Configuration

Create `.env` file:

```bash
REACT_APP_NETWORK_RPC_URL=https://sepolia.drpc.org
REACT_APP_CHAIN_ID=11155111
REACT_APP_TOKEN_ADDRESS=0x...
REACT_APP_VAULT_ADDRESS=0x...
REACT_APP_BRIDGE_ADDRESS=0x...
REACT_APP_GOVERNOR_ADDRESS=0x...
REACT_APP_TIMELOCK_ADDRESS=0x...
REACT_APP_VOTING_ESCROW_ADDRESS=0x...
```

### 4. Network Configuration

```typescript
// src/config/network.ts
import { NetworkConfig } from '@basero/sdk';

export const getNetworkConfig = (): NetworkConfig => ({
  chainId: parseInt(process.env.REACT_APP_CHAIN_ID || '11155111'),
  rpcUrl: process.env.REACT_APP_NETWORK_RPC_URL || '',
  explorerUrl: 'https://sepolia.etherscan.io',
  addresses: {
    token: process.env.REACT_APP_TOKEN_ADDRESS || '',
    vault: process.env.REACT_APP_VAULT_ADDRESS || '',
    bridge: process.env.REACT_APP_BRIDGE_ADDRESS || '',
    governor: process.env.REACT_APP_GOVERNOR_ADDRESS || '',
    timelock: process.env.REACT_APP_TIMELOCK_ADDRESS || '',
    votingEscrow: process.env.REACT_APP_VOTING_ESCROW_ADDRESS || '',
  },
});
```

---

## Production Build

### Build Configuration

```json
// package.json
{
  "name": "basero-dapp",
  "version": "1.0.0",
  "scripts": {
    "start": "react-scripts start",
    "build": "react-scripts build",
    "test": "react-scripts test",
    "eject": "react-scripts eject"
  },
  "dependencies": {
    "@basero/sdk": "^1.0.0",
    "ethers": "^6.0.0",
    "react": "^18.2.0",
    "react-dom": "^18.2.0"
  },
  "devDependencies": {
    "@types/react": "^18.2.0",
    "@types/react-dom": "^18.2.0",
    "typescript": "^4.9.0"
  }
}
```

### TypeScript Configuration

```json
// tsconfig.json
{
  "compilerOptions": {
    "target": "ES2020",
    "lib": ["ES2020", "DOM", "DOM.Iterable"],
    "allowJs": true,
    "skipLibCheck": true,
    "esModuleInterop": true,
    "allowSyntheticDefaultImports": true,
    "strict": true,
    "forceConsistentCasingInFileNames": true,
    "noFallthroughCasesInSwitch": true,
    "module": "ESNext",
    "moduleResolution": "Node",
    "resolveJsonModule": true,
    "isolatedModules": true,
    "noEmit": true,
    "jsx": "react-jsx"
  },
  "include": ["src"]
}
```

### Build for Production

```bash
npm run build
```

This creates an optimized production build in the `build/` directory.

---

## Deployment Options

### Option 1: Vercel (Recommended)

```bash
# Install Vercel CLI
npm install -g vercel

# Deploy
vercel

# Production deployment
vercel --prod
```

**vercel.json:**
```json
{
  "buildCommand": "npm run build",
  "outputDirectory": "build",
  "framework": "create-react-app",
  "env": {
    "REACT_APP_NETWORK_RPC_URL": "@network-rpc-url",
    "REACT_APP_CHAIN_ID": "@chain-id",
    "REACT_APP_TOKEN_ADDRESS": "@token-address",
    "REACT_APP_VAULT_ADDRESS": "@vault-address",
    "REACT_APP_BRIDGE_ADDRESS": "@bridge-address",
    "REACT_APP_GOVERNOR_ADDRESS": "@governor-address",
    "REACT_APP_TIMELOCK_ADDRESS": "@timelock-address",
    "REACT_APP_VOTING_ESCROW_ADDRESS": "@voting-escrow-address"
  }
}
```

### Option 2: Netlify

```bash
# Install Netlify CLI
npm install -g netlify-cli

# Build
npm run build

# Deploy
netlify deploy

# Production deployment
netlify deploy --prod
```

**netlify.toml:**
```toml
[build]
  command = "npm run build"
  publish = "build"

[[redirects]]
  from = "/*"
  to = "/index.html"
  status = 200
```

### Option 3: IPFS (Decentralized)

```bash
# Build
npm run build

# Install IPFS Desktop or use Pinata
# Upload build/ folder to IPFS

# Get CID and access via:
# https://ipfs.io/ipfs/<CID>
# or use custom domain with DNSLink
```

### Option 4: AWS S3 + CloudFront

```bash
# Install AWS CLI
aws configure

# Build
npm run build

# Create S3 bucket
aws s3 mb s3://basero-dapp

# Upload build
aws s3 sync build/ s3://basero-dapp

# Enable static website hosting
aws s3 website s3://basero-dapp --index-document index.html

# (Optional) Set up CloudFront for CDN
```

---

## Performance Optimization

### Code Splitting

```typescript
import React, { lazy, Suspense } from 'react';

const VaultInterface = lazy(() => import('./components/VaultInterface'));
const GovernanceInterface = lazy(() => import('./components/GovernanceInterface'));

function App() {
  return (
    <Suspense fallback={<LoadingSpinner />}>
      <Router>
        <Route path="/vault" component={VaultInterface} />
        <Route path="/governance" component={GovernanceInterface} />
      </Router>
    </Suspense>
  );
}
```

### Bundle Size Optimization

```bash
# Analyze bundle size
npm install --save-dev source-map-explorer

# Add to package.json scripts:
# "analyze": "source-map-explorer 'build/static/js/*.js'"

npm run build
npm run analyze
```

### Caching Strategy

```javascript
// src/serviceWorker.ts (for PWA)
const CACHE_NAME = 'basero-v1';
const urlsToCache = [
  '/',
  '/static/css/main.css',
  '/static/js/main.js',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then((cache) => cache.addAll(urlsToCache))
  );
});
```

---

## Security Best Practices

### 1. Environment Variables

Never commit `.env` to version control:

```bash
# .gitignore
.env
.env.local
.env.production
```

### 2. Content Security Policy

```html
<!-- public/index.html -->
<meta http-equiv="Content-Security-Policy" 
      content="default-src 'self'; 
               script-src 'self' 'unsafe-inline'; 
               style-src 'self' 'unsafe-inline'; 
               connect-src 'self' https://sepolia.drpc.org">
```

### 3. Subresource Integrity

```html
<!-- For CDN resources -->
<script 
  src="https://cdn.example.com/library.js"
  integrity="sha384-..."
  crossorigin="anonymous">
</script>
```

### 4. Input Validation

```typescript
import { Validators } from '@basero/sdk';

function validateInput(value: string): boolean {
  // Sanitize input
  const sanitized = value.trim();
  
  // Validate format
  if (!Validators.isValidAmount(sanitized)) {
    return false;
  }
  
  // Additional checks
  const amount = parseFloat(sanitized);
  if (amount < 0 || amount > 1e12) {
    return false;
  }
  
  return true;
}
```

---

## Monitoring & Analytics

### Error Tracking (Sentry)

```bash
npm install @sentry/react @sentry/tracing
```

```typescript
// src/index.tsx
import * as Sentry from '@sentry/react';
import { BrowserTracing } from '@sentry/tracing';

Sentry.init({
  dsn: 'your-sentry-dsn',
  integrations: [new BrowserTracing()],
  tracesSampleRate: 1.0,
});

ReactDOM.render(
  <Sentry.ErrorBoundary fallback={ErrorFallback}>
    <App />
  </Sentry.ErrorBoundary>,
  document.getElementById('root')
);
```

### Analytics (Google Analytics)

```bash
npm install react-ga4
```

```typescript
// src/analytics.ts
import ReactGA from 'react-ga4';

export const initGA = () => {
  ReactGA.initialize('G-XXXXXXXXXX');
};

export const logPageView = () => {
  ReactGA.send({ hitType: 'pageview', page: window.location.pathname });
};

export const logEvent = (category: string, action: string) => {
  ReactGA.event({ category, action });
};
```

---

## Testing

### Unit Tests

```typescript
// src/components/__tests__/TokenBalance.test.tsx
import { render, screen } from '@testing-library/react';
import { TokenBalance } from '../TokenBalance';

test('displays token balance', () => {
  const mockBalance = {
    raw: BigInt(1000000000000000000),
    formatted: '1.00',
    decimals: 18,
  };

  render(<TokenBalance balance={mockBalance} />);
  
  expect(screen.getByText('1.00 BASE')).toBeInTheDocument();
});
```

### Integration Tests

```typescript
// src/__tests__/integration/deposit.test.tsx
import { render, screen, fireEvent } from '@testing-library/react';
import { DepositForm } from '../components/DepositForm';

test('deposit flow', async () => {
  render(<DepositForm />);
  
  // Enter amount
  const input = screen.getByPlaceholderText('0.00');
  fireEvent.change(input, { target: { value: '100' } });
  
  // Click deposit
  const button = screen.getByText('Deposit');
  fireEvent.click(button);
  
  // Wait for success
  await screen.findByText(/Transaction successful/i);
});
```

---

## Checklist

### Pre-Deployment

- [ ] Environment variables configured
- [ ] Network addresses verified
- [ ] Build completes without errors
- [ ] All tests passing
- [ ] Security headers configured
- [ ] Error tracking setup
- [ ] Analytics configured

### Post-Deployment

- [ ] Wallet connection works
- [ ] Token balances display correctly
- [ ] Transactions execute successfully
- [ ] Error handling works
- [ ] Mobile responsive
- [ ] Cross-browser tested
- [ ] Performance metrics acceptable

---

## Maintenance

### Update Dependencies

```bash
# Check for updates
npm outdated

# Update packages
npm update

# Update SDK
npm install @basero/sdk@latest
```

### Monitor Performance

Use Lighthouse in Chrome DevTools:

```bash
# Install Lighthouse CLI
npm install -g lighthouse

# Run audit
lighthouse https://your-dapp.com --view
```

Target scores:
- Performance: 90+
- Accessibility: 95+
- Best Practices: 95+
- SEO: 90+

---

## Troubleshooting

### Common Issues

**Issue: Wallet not connecting**
```typescript
// Check if MetaMask is installed
if (!window.ethereum) {
  alert('Please install MetaMask');
}

// Check network
const chainId = await window.ethereum.request({ 
  method: 'eth_chainId' 
});
if (chainId !== '0xaa36a7') { // Sepolia
  await window.ethereum.request({
    method: 'wallet_switchEthereumChain',
    params: [{ chainId: '0xaa36a7' }],
  });
}
```

**Issue: Build errors**
```bash
# Clear cache
rm -rf node_modules
rm package-lock.json
npm install

# Clear build
rm -rf build
npm run build
```

**Issue: Large bundle size**
```typescript
// Use dynamic imports
const Component = lazy(() => import('./Component'));

// Tree shake unused imports
import { AmountFormatter } from '@basero/sdk/utils';
// instead of
import { AmountFormatter } from '@basero/sdk';
```

---

## Resources

- [React Documentation](https://react.dev)
- [ethers.js Documentation](https://docs.ethers.org/v6/)
- [Basero SDK Guide](SDK_GUIDE.md)
- [Frontend Integration Guide](FRONTEND_INTEGRATION_GUIDE.md)
- [UI Patterns](FRONTEND_UI_PATTERNS.md)
