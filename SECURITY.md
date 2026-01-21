# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |

## Reporting a Vulnerability

If you discover a security vulnerability within this project, please follow these steps:

1. **Do NOT** open a public issue
2. Email the details to: security@yourproject.com (replace with actual email)
3. Include:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)

### What to expect

- Acknowledgment within 48 hours
- Regular updates on the progress
- Credit for responsible disclosure (if desired)

## Security Best Practices

When using this project:

1. **Never commit private keys** to version control
2. **Always audit** contracts before mainnet deployment
3. **Use multi-sig wallets** for contract ownership
4. **Test thoroughly** on testnets before production
5. **Keep dependencies updated** to latest secure versions
6. **Monitor transactions** for unexpected behavior
7. **Fund CCIP contracts** appropriately for cross-chain operations

## Known Considerations

### Rebase Mechanism
- Balances change automatically on rebase
- External contracts must handle dynamic balances
- Consider rounding errors in calculations

### Cross-Chain Operations
- Requires LINK tokens for CCIP fees
- Messages may take time to process
- Ensure proper allowlisting before transfers

### Access Control
- Owner has significant privileges (rebase, mint, burn)
- Consider using Timelock or multi-sig for production
- Regularly audit owner permissions

## Audit Status

This project has not yet been professionally audited. Use at your own risk.

For production deployments, we strongly recommend:
- Professional security audit
- Bug bounty program
- Gradual rollout strategy
- Emergency pause mechanism

## Dependencies

This project relies on:
- OpenZeppelin Contracts (audited)
- Chainlink CCIP (audited)
- Foundry (development tool)

Always ensure you're using the latest stable versions.

## License

This security policy is licensed under MIT License.
