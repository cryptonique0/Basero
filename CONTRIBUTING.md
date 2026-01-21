# Contributing to Cross-Chain Rebase Token

Thank you for your interest in contributing! This document provides guidelines for contributing to the project.

## Code of Conduct

- Be respectful and inclusive
- Welcome newcomers and help them learn
- Focus on constructive feedback
- Maintain professional communication

## How to Contribute

### Reporting Bugs

1. **Check existing issues** to avoid duplicates
2. **Use the issue template** when creating new issues
3. **Include details**:
   - Clear description of the bug
   - Steps to reproduce
   - Expected vs actual behavior
   - Environment details (OS, Foundry version, etc.)
   - Error messages or logs

### Suggesting Features

1. **Open an issue** to discuss the feature first
2. **Explain the use case** and benefits
3. **Consider backwards compatibility**
4. **Be open to feedback** and iteration

### Pull Requests

1. **Fork the repository**
2. **Create a feature branch**: `git checkout -b feature/AmazingFeature`
3. **Make your changes**
4. **Write or update tests**
5. **Ensure all tests pass**: `forge test`
6. **Format your code**: `forge fmt`
7. **Commit with clear messages**
8. **Push to your fork**
9. **Open a Pull Request**

## Development Guidelines

### Code Style

- Follow Solidity style guide
- Use descriptive variable and function names
- Add NatSpec comments for all public functions
- Keep functions focused and concise
- Use custom errors instead of require strings (gas optimization)

### Testing

- Write comprehensive tests for all new features
- Include edge cases and failure scenarios
- Use descriptive test names: `testFeatureName_Condition_ExpectedBehavior`
- Aim for >90% code coverage
- Use fuzz testing where appropriate

Example test structure:
```solidity
function testRebase_WhenSupplyIncreases_ShouldUpdateBalances() public {
    // Arrange
    uint256 newSupply = 2_000_000 * 10 ** 18;
    
    // Act
    token.rebase(newSupply);
    
    // Assert
    assertEq(token.totalSupply(), newSupply);
}
```

### Documentation

- Update README.md for significant changes
- Add inline comments for complex logic
- Update NatSpec documentation
- Include examples in documentation

### Git Commit Messages

Use clear, descriptive commit messages:

```
feat: Add percentage-based rebase function
fix: Correct shares calculation in transfer
docs: Update deployment instructions
test: Add fuzz tests for rebase mechanism
refactor: Optimize gas usage in mint function
```

Prefixes:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `test`: Test additions/changes
- `refactor`: Code refactoring
- `style`: Code style changes
- `chore`: Build/tool changes

### Pull Request Process

1. **Update documentation** as needed
2. **Ensure CI passes** (tests, formatting, etc.)
3. **Request review** from maintainers
4. **Address feedback** promptly
5. **Squash commits** if requested
6. **Wait for approval** before merging

### Review Criteria

PRs will be evaluated on:
- Code quality and style
- Test coverage
- Documentation completeness
- Backwards compatibility
- Security considerations
- Gas optimization

## Project Structure

```
src/
├── RebaseToken.sol              # Core token logic
├── CCIPRebaseTokenSender.sol    # Cross-chain sending
└── CCIPRebaseTokenReceiver.sol  # Cross-chain receiving

test/
├── RebaseToken.t.sol            # Token tests
└── CCIPRebaseToken.t.sol        # CCIP tests

script/
├── Deploy*.s.sol                # Deployment scripts
└── Configure*.s.sol             # Configuration scripts
```

## Development Setup

1. **Install Foundry**:
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

2. **Clone and setup**:
```bash
git clone https://github.com/your-username/crossChainRebaseToken.git
cd crossChainRebaseToken
./setup.sh
```

3. **Run tests**:
```bash
forge test
```

## Testing Checklist

Before submitting a PR, ensure:

- [ ] All tests pass: `forge test`
- [ ] Code is formatted: `forge fmt`
- [ ] Coverage is adequate: `forge coverage`
- [ ] Gas usage is optimized: `forge test --gas-report`
- [ ] Documentation is updated
- [ ] No compiler warnings
- [ ] Security considerations addressed

## Security

- Report security vulnerabilities privately
- See [SECURITY.md](SECURITY.md) for details
- Never commit private keys or sensitive data
- Consider gas optimization and reentrancy

## Questions?

- Open an issue for questions
- Check existing documentation
- Review closed issues and PRs
- Ask in discussions

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

---

Thank you for contributing to Cross-Chain Rebase Token! 🎉
