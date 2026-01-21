# Basero Protocol - Monitoring Dashboard Setup Guide

## Overview

This guide covers the complete setup of monitoring infrastructure for the Basero protocol, including:

- **Health Check Contract**: On-chain health monitoring
- **Prometheus**: Metrics collection and alerting
- **Grafana**: Visualization dashboards
- **Datadog**: Alternative monitoring platform
- **Alertmanager**: Alert routing and notifications

---

## Architecture

```
┌─────────────────┐
│  Basero Smart   │
│    Contracts    │
└────────┬────────┘
         │
         ↓
┌─────────────────┐
│  HealthChecker  │ ← On-chain health checks
│    Contract     │
└────────┬────────┘
         │
         ↓
┌─────────────────┐
│   Prometheus    │ ← Scrapes metrics via exporter
│    Exporter     │
└────────┬────────┘
         │
         ├──────────────┬──────────────┐
         ↓              ↓              ↓
  ┌───────────┐  ┌───────────┐  ┌──────────┐
  │ Prometheus│  │  Grafana  │  │ Datadog  │
  └─────┬─────┘  └───────────┘  └──────────┘
        │
        ↓
  ┌───────────┐
  │Alertmanager│ → Slack / PagerDuty / Email
  └───────────┘
```

---

## Part 1: Deploy Health Check Contract

### 1.1 Deployment Script

Create deployment script:

```javascript
// scripts/deploy-health-checker.js
const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  
  console.log("Deploying HealthChecker with account:", deployer.address);

  // Get deployed contract addresses
  const addresses = {
    token: process.env.TOKEN_ADDRESS,
    vault: process.env.VAULT_ADDRESS,
    bridge: process.env.BRIDGE_ADDRESS,
    governor: process.env.GOVERNOR_ADDRESS,
    timelock: process.env.TIMELOCK_ADDRESS,
    votingEscrow: process.env.VOTING_ESCROW_ADDRESS,
  };

  // Deploy HealthChecker
  const HealthChecker = await ethers.getContractFactory("HealthChecker");
  const healthChecker = await HealthChecker.deploy(
    addresses.token,
    addresses.vault,
    addresses.bridge,
    addresses.governor,
    addresses.timelock,
    addresses.votingEscrow
  );

  await healthChecker.waitForDeployment();
  const address = await healthChecker.getAddress();

  console.log("HealthChecker deployed to:", address);
  
  // Test health check
  console.log("\nTesting health check...");
  const health = await healthChecker.getSystemHealth();
  console.log("System operational:", health.allSystemsOperational);
  console.log("Token operational:", health.token.isOperational);
  console.log("Vault operational:", health.vault.isOperational);
  
  // Save address
  const fs = require('fs');
  fs.writeFileSync(
    'deployments/health-checker.json',
    JSON.stringify({ address, timestamp: Date.now() }, null, 2)
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
```

### 1.2 Deploy

```bash
# Set environment variables
export TOKEN_ADDRESS=0x...
export VAULT_ADDRESS=0x...
export BRIDGE_ADDRESS=0x...
export GOVERNOR_ADDRESS=0x...
export TIMELOCK_ADDRESS=0x...
export VOTING_ESCROW_ADDRESS=0x...

# Deploy
npx hardhat run scripts/deploy-health-checker.js --network sepolia

# Verify on Etherscan
npx hardhat verify --network sepolia HEALTH_CHECKER_ADDRESS \
  $TOKEN_ADDRESS $VAULT_ADDRESS $BRIDGE_ADDRESS \
  $GOVERNOR_ADDRESS $TIMELOCK_ADDRESS $VOTING_ESCROW_ADDRESS
```

---

## Part 2: Set Up Prometheus Exporter

### 2.1 Install Dependencies

```bash
cd monitoring/prometheus
npm init -y
npm install ethers express prom-client
```

### 2.2 Configure Environment

Create `.env` file:

```bash
# RPC Configuration
RPC_URL=https://sepolia.drpc.org
CHAIN_ID=11155111

# Contract Addresses
HEALTH_CHECKER_ADDRESS=0x...
TOKEN_ADDRESS=0x...
VAULT_ADDRESS=0x...
BRIDGE_ADDRESS=0x...
GOVERNOR_ADDRESS=0x...
TIMELOCK_ADDRESS=0x...
VOTING_ESCROW_ADDRESS=0x...

# Exporter Configuration
PORT=9090
SCRAPE_INTERVAL=30000
```

### 2.3 Run Exporter

```bash
# Development
node exporter.js

# Production (with PM2)
npm install -g pm2
pm2 start exporter.js --name basero-exporter

# Check status
pm2 status
pm2 logs basero-exporter

# Test metrics endpoint
curl http://localhost:9090/metrics
```

### 2.4 Docker Deployment

Create `Dockerfile`:

```dockerfile
FROM node:18-alpine

WORKDIR /app

COPY package*.json ./
RUN npm ci --only=production

COPY exporter.js ./

EXPOSE 9090

CMD ["node", "exporter.js"]
```

Build and run:

```bash
docker build -t basero-exporter .
docker run -d \
  --name basero-exporter \
  -p 9090:9090 \
  --env-file .env \
  basero-exporter
```

---

## Part 3: Set Up Prometheus

### 3.1 Install Prometheus

**Docker (Recommended):**

```bash
docker run -d \
  --name prometheus \
  -p 9091:9090 \
  -v $(pwd)/prometheus.yml:/etc/prometheus/prometheus.yml \
  -v $(pwd)/alerts.yml:/etc/prometheus/alerts.yml \
  prom/prometheus
```

**Binary Installation:**

```bash
wget https://github.com/prometheus/prometheus/releases/download/v2.45.0/prometheus-2.45.0.linux-amd64.tar.gz
tar xvf prometheus-2.45.0.linux-amd64.tar.gz
cd prometheus-2.45.0.linux-amd64/

# Copy config
cp ../prometheus.yml ./
cp ../alerts.yml ./

# Run
./prometheus --config.file=prometheus.yml
```

### 3.2 Verify Setup

```bash
# Check targets
curl http://localhost:9091/api/v1/targets

# Check metrics
curl http://localhost:9091/api/v1/query?query=basero_system_operational

# Open UI
open http://localhost:9091
```

---

## Part 4: Set Up Alertmanager

### 4.1 Install

```bash
docker run -d \
  --name alertmanager \
  -p 9093:9093 \
  -v $(pwd)/alertmanager.yml:/etc/alertmanager/alertmanager.yml \
  prom/alertmanager
```

### 4.2 Configure Notifications

Edit `alertmanager.yml` with your credentials:

```yaml
global:
  slack_api_url: 'https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK'
  
receivers:
  - name: 'basero-critical'
    pagerduty_configs:
      - service_key: 'YOUR_PAGERDUTY_KEY'
    slack_configs:
      - channel: '#basero-critical'
```

### 4.3 Test Alerts

```bash
# Send test alert
curl -X POST http://localhost:9093/api/v1/alerts \
  -H 'Content-Type: application/json' \
  -d '[{
    "labels": {
      "alertname": "TestAlert",
      "severity": "warning"
    },
    "annotations": {
      "summary": "Test alert from Basero monitoring"
    }
  }]'
```

---

## Part 5: Set Up Grafana

### 5.1 Install Grafana

```bash
docker run -d \
  --name grafana \
  -p 3000:3000 \
  -e GF_SECURITY_ADMIN_PASSWORD=admin \
  grafana/grafana
```

### 5.2 Add Prometheus Data Source

1. Open Grafana: http://localhost:3000
2. Login (admin/admin)
3. Configuration → Data Sources → Add data source
4. Select "Prometheus"
5. URL: `http://prometheus:9091` (or `http://localhost:9091`)
6. Save & Test

### 5.3 Import Dashboards

**Option 1: Via UI**
1. Dashboards → Import
2. Upload JSON file from `monitoring/grafana/`
3. Select Prometheus data source
4. Import

**Option 2: Via API**

```bash
# Import system overview dashboard
curl -X POST http://admin:admin@localhost:3000/api/dashboards/db \
  -H 'Content-Type: application/json' \
  -d @monitoring/grafana/basero-system-overview.json

# Import vault metrics dashboard
curl -X POST http://admin:admin@localhost:3000/api/dashboards/db \
  -H 'Content-Type: application/json' \
  -d @monitoring/grafana/basero-vault-metrics.json

# Import alerts & SLO dashboard
curl -X POST http://admin:admin@localhost:3000/api/dashboards/db \
  -H 'Content-Type: application/json' \
  -d @monitoring/grafana/basero-alerts-slo.json
```

### 5.4 Configure Alerts

1. Alerting → Alert rules
2. Alerts are defined in dashboards (check graph panels)
3. Configure notification channels:
   - Alerting → Notification channels → New channel
   - Add Slack, PagerDuty, Email, etc.

---

## Part 6: Set Up Datadog (Alternative)

### 6.1 Install Datadog Agent

```bash
DD_API_KEY=your_api_key DD_SITE="datadoghq.com" bash -c "$(curl -L https://s3.amazonaws.com/dd-agent/scripts/install_script.sh)"
```

### 6.2 Configure Prometheus Integration

Edit `/etc/datadog-agent/conf.d/prometheus.d/conf.yaml`:

```yaml
instances:
  - prometheus_url: http://localhost:9090/metrics
    namespace: basero
    metrics:
      - basero_*
```

Restart agent:

```bash
sudo systemctl restart datadog-agent
```

### 6.3 Import Dashboard

```bash
# Using Datadog API
curl -X POST "https://api.datadoghq.com/api/v1/dashboard" \
  -H "DD-API-KEY: ${DD_API_KEY}" \
  -H "DD-APPLICATION-KEY: ${DD_APP_KEY}" \
  -H "Content-Type: application/json" \
  -d @monitoring/datadog/dashboard.json
```

### 6.4 Create Monitors

```bash
# Import monitors from YAML
# (Use Datadog Terraform provider or web UI)
```

---

## Part 7: Docker Compose Setup (All-in-One)

Create `monitoring/docker-compose.yml`:

```yaml
version: '3.8'

services:
  # Metrics exporter
  basero-exporter:
    build: ./prometheus
    container_name: basero-exporter
    ports:
      - "9090:9090"
    environment:
      - RPC_URL=${RPC_URL}
      - HEALTH_CHECKER_ADDRESS=${HEALTH_CHECKER_ADDRESS}
    restart: unless-stopped
    
  # Prometheus
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    ports:
      - "9091:9090"
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml
      - ./prometheus/alerts.yml:/etc/prometheus/alerts.yml
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
    restart: unless-stopped
    
  # Alertmanager
  alertmanager:
    image: prom/alertmanager:latest
    container_name: alertmanager
    ports:
      - "9093:9093"
    volumes:
      - ./prometheus/alertmanager.yml:/etc/alertmanager/alertmanager.yml
    restart: unless-stopped
    
  # Grafana
  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASSWORD:-admin}
      - GF_SERVER_ROOT_URL=http://localhost:3000
    volumes:
      - grafana_data:/var/lib/grafana
    restart: unless-stopped

volumes:
  prometheus_data:
  grafana_data:
```

Start all services:

```bash
cd monitoring
docker-compose up -d

# Check logs
docker-compose logs -f

# Access services
# Grafana: http://localhost:3000
# Prometheus: http://localhost:9091
# Alertmanager: http://localhost:9093
# Exporter: http://localhost:9090
```

---

## Part 8: Testing & Validation

### 8.1 Test Health Checks

```bash
# Check exporter metrics
curl http://localhost:9090/metrics | grep basero

# Expected metrics:
# basero_system_operational 1
# basero_components_operational 6
# basero_vault_utilization_bps 4500
# basero_token_total_supply 1e24
```

### 8.2 Test Alerts

**Simulate high utilization:**

```bash
# In Prometheus UI (http://localhost:9091)
# Execute query:
basero_vault_utilization_bps > 9500

# Or manually trigger alert
curl -X POST http://localhost:9093/api/v1/alerts \
  -H 'Content-Type: application/json' \
  -d '[{
    "labels": {"alertname": "BaseroVaultHighUtilization", "severity": "high"},
    "annotations": {"summary": "Test alert"}
  }]'
```

### 8.3 Verify Dashboards

1. Open Grafana: http://localhost:3000
2. Navigate to dashboards
3. Check "Basero Protocol - System Overview"
4. Verify all panels show data
5. Check for any errors in panels

---

## Part 9: Production Deployment

### 9.1 Security Checklist

- [ ] Change default Grafana password
- [ ] Enable HTTPS for all services
- [ ] Restrict network access (firewall)
- [ ] Use secrets management (not .env files)
- [ ] Enable authentication for Prometheus
- [ ] Set up reverse proxy (nginx)
- [ ] Enable CORS restrictions
- [ ] Regular security updates

### 9.2 High Availability

**Prometheus HA:**
```yaml
# Use Prometheus federation or Thanos
```

**Grafana HA:**
```yaml
# Use external database (PostgreSQL/MySQL)
# Configure load balancer
```

### 9.3 Backup Strategy

```bash
# Backup Prometheus data
docker run --rm \
  -v prometheus_data:/prometheus \
  -v $(pwd)/backups:/backup \
  alpine tar czf /backup/prometheus-$(date +%Y%m%d).tar.gz /prometheus

# Backup Grafana dashboards
curl -H "Authorization: Bearer $GRAFANA_API_KEY" \
  http://localhost:3000/api/search | \
  jq -r '.[].uid' | \
  while read uid; do
    curl -H "Authorization: Bearer $GRAFANA_API_KEY" \
      "http://localhost:3000/api/dashboards/uid/$uid" \
      > "backups/grafana-$uid.json"
  done
```

---

## Part 10: Maintenance

### 10.1 Regular Tasks

**Daily:**
- Check alert status
- Review dashboard for anomalies
- Verify exporter is running

**Weekly:**
- Review SLO compliance
- Check Prometheus retention
- Update alert thresholds if needed

**Monthly:**
- Review and archive old alerts
- Update dashboards
- Check for software updates

### 10.2 Troubleshooting

**Exporter not collecting metrics:**
```bash
# Check RPC connection
curl $RPC_URL

# Check HealthChecker contract
cast call $HEALTH_CHECKER_ADDRESS "isHealthy()(bool)" --rpc-url $RPC_URL

# Check exporter logs
docker logs basero-exporter
pm2 logs basero-exporter
```

**Prometheus not scraping:**
```bash
# Check targets
curl http://localhost:9091/api/v1/targets

# Check config
docker exec prometheus promtool check config /etc/prometheus/prometheus.yml

# Reload config
curl -X POST http://localhost:9091/-/reload
```

**Grafana panels empty:**
```bash
# Test Prometheus data source
curl http://localhost:9091/api/v1/query?query=up

# Check Grafana logs
docker logs grafana

# Verify query in Prometheus UI first
```

---

## Part 11: Monitoring Best Practices

### 11.1 Alert Fatigue Prevention

- Set appropriate thresholds
- Use alert inhibition rules
- Implement proper alert routing
- Regular alert tuning based on feedback

### 11.2 Dashboard Organization

- System Overview (executives)
- Component Details (engineers)
- Alerts & SLOs (SRE team)
- User-facing Metrics (support)

### 11.3 SLO Tracking

Define Service Level Objectives:

- **System Uptime**: 99.9% (43min downtime/month)
- **Rebase Timeliness**: 99% within 25 hours
- **Vault Availability**: 99.5%
- **Bridge Success Rate**: 99%

Monitor error budgets and burn rates.

---

## Resources

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Datadog Integration Guide](https://docs.datadoghq.com/)
- [Basero Health Check Contract](../src/monitoring/HealthChecker.sol)
- [Metrics Exporter Source](./prometheus/exporter.js)

## Support

For issues or questions:
- GitHub Issues: [basero/monitoring](https://github.com/basero/monitoring/issues)
- Discord: #monitoring channel
- Email: sre@basero.io
