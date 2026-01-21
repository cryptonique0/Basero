#!/bin/bash
# Setup pre-commit hooks for Basero project

echo "🔧 Setting up pre-commit hooks..."

# Create hooks directory if it doesn't exist
mkdir -p .git/hooks

# Copy and make executable
if [ -f .githooks/pre-commit ]; then
    cp .githooks/pre-commit .git/hooks/pre-commit
    chmod +x .git/hooks/pre-commit
    echo "✅ Pre-commit hook installed"
else
    echo "❌ .githooks/pre-commit not found"
    exit 1
fi

# Configure git to use hooks directory
git config core.hooksPath .githooks 2>/dev/null || true

echo "✅ Git hooks configured!"
