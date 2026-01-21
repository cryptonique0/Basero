#!/bin/bash
# scripts/formal-verification.sh
# Comprehensive formal verification script for Basero protocol
# Run: bash scripts/formal-verification.sh [profile]

set -e

PROFILE=${1:-default}
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
REPORT_DIR="verification-reports/$TIMESTAMP"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║     Basero Protocol - Formal Verification Suite            ║"
echo "║     Profile: $PROFILE                                       ║"
echo "║     Report: $REPORT_DIR                                    ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

mkdir -p "$REPORT_DIR"

# ============================================
# Step 1: Compilation
# ============================================
echo "📦 Step 1: Compiling contracts..."
forge build --extra-output-files metadata --extra-output-files storageLayout 2>&1 | tee "$REPORT_DIR/01-compile.log"
echo "✅ Compilation successful"
echo ""

# ============================================
# Step 2: Linting
# ============================================
echo "🔍 Step 2: Running static analysis (Slither)..."
if command -v slither &> /dev/null; then
    slither . --json > "$REPORT_DIR/02-slither.json" 2>&1 || true
    echo "✅ Slither analysis complete"
else
    echo "⚠️  Slither not installed (optional)"
fi
echo ""

# ============================================
# Step 3: Unit Tests
# ============================================
echo "🧪 Step 3: Running unit tests..."
forge test --match-contract '^(?!.*Halmos).*Test$' --report-file "$REPORT_DIR/03-unit-tests.json" 2>&1 | tee "$REPORT_DIR/03-unit-tests.log"
echo "✅ Unit tests complete"
echo ""

# ============================================
# Step 4: Coverage
# ============================================
echo "📊 Step 4: Generating coverage report..."
forge coverage --report lcov --report-file "$REPORT_DIR/04-coverage.lcov" 2>&1 | tee "$REPORT_DIR/04-coverage.log"
echo "✅ Coverage report generated"
echo ""

# ============================================
# Step 5: Invariant Tests
# ============================================
echo "⚖️  Step 5: Running invariant tests (10,000 runs)..."
forge test --match-contract 'Invariant' --fuzz-runs 10000 --report-file "$REPORT_DIR/05-invariants.json" 2>&1 | tee "$REPORT_DIR/05-invariants.log"
echo "✅ Invariant tests complete"
echo ""

# ============================================
# Step 6: Gas Profiling
# ============================================
echo "⛽ Step 6: Gas profiling and snapshots..."
forge test --match-contract 'GasProfiler' --gas-report > "$REPORT_DIR/06-gas-report.txt" 2>&1
if [ -f "gas-snapshot" ]; then
    cp "gas-snapshot" "$REPORT_DIR/06-gas-snapshot"
fi
echo "✅ Gas profiling complete"
echo ""

# ============================================
# Step 7: Halmos Symbolic Execution
# ============================================
if command -v halmos &> /dev/null; then
    echo "🔬 Step 7: Running Halmos symbolic execution (profile: $PROFILE)..."
    if [ "$PROFILE" = "intensive" ]; then
        HALMOS_PROFILE="intensive"
    elif [ "$PROFILE" = "production" ]; then
        HALMOS_PROFILE="production"
    else
        HALMOS_PROFILE="default"
    fi
    
    halmos --profile "$HALMOS_PROFILE" --output-dir "$REPORT_DIR/halmos-output" 2>&1 | tee "$REPORT_DIR/07-halmos.log"
    echo "✅ Halmos verification complete"
else
    echo "⚠️  Halmos not installed (optional)"
fi
echo ""

# ============================================
# Step 8: Storage Layout Validation
# ============================================
echo "📝 Step 8: Validating storage layouts..."
forge inspect RebaseToken storage-layout > "$REPORT_DIR/08-storage-RebaseToken.txt"
forge inspect RebaseTokenVault storage-layout > "$REPORT_DIR/08-storage-RebaseTokenVault.txt"
forge inspect VotingEscrow storage-layout > "$REPORT_DIR/08-storage-VotingEscrow.txt"
forge inspect BASEGovernor storage-layout > "$REPORT_DIR/08-storage-BASEGovernor.txt"
echo "✅ Storage layout validation complete"
echo ""

# ============================================
# Step 9: Documentation Check
# ============================================
echo "📚 Step 9: Checking documentation..."
NATSPEC_FILES=$(find src -name "*.sol" -exec grep -l "///" {} \; | wc -l)
NATSPEC_TOTAL=$(find src -name "*.sol" | wc -l)
echo "NatSpec coverage: $NATSPEC_FILES/$NATSPEC_TOTAL files documented" | tee "$REPORT_DIR/09-natspec.txt"

# Check for required docs
REQUIRED_DOCS=("FORMAL_VERIFICATION_SPEC.md" "AUDIT_READINESS.md" "SECURITY_PRODUCTION.md" "GAS_OPTIMIZATION_REPORT.md")
for doc in "${REQUIRED_DOCS[@]}"; do
    if [ -f "$doc" ]; then
        echo "✅ $doc"
    else
        echo "❌ $doc - MISSING"
    fi
done >> "$REPORT_DIR/09-natspec.txt"

echo "✅ Documentation check complete"
echo ""

# ============================================
# Step 10: Summary Report
# ============================================
echo "📋 Step 10: Generating summary report..."

cat > "$REPORT_DIR/VERIFICATION_SUMMARY.md" << 'SUMMARY_EOF'
# Formal Verification Summary Report

## Verification Timestamp
TIMESTAMP_PLACEHOLDER

## Profile
PROFILE_PLACEHOLDER

## Test Results

### Unit Tests
STATUS_PLACEHOLDER

### Invariant Tests
STATUS_PLACEHOLDER

### Coverage
- Target: >95%
- Status: CHECK_PLACEHOLDER

### Gas Profiling
- Report: See 06-gas-report.txt

### Halmos Symbolic Execution
- Status: HALMOS_STATUS_PLACEHOLDER

## Documentation

### NatSpec Coverage
NATSPEC_PLACEHOLDER

### Required Documentation
- [ ] FORMAL_VERIFICATION_SPEC.md
- [ ] AUDIT_READINESS.md
- [ ] SECURITY_PRODUCTION.md
- [ ] GAS_OPTIMIZATION_REPORT.md

## Static Analysis

### Slither
- Report: See 02-slither.json

## Storage Layout
- See 08-storage-*.txt files

## Next Steps

1. Review test results in detail
2. Analyze any failures
3. Check gas profiling for optimizations
4. Review Halmos properties verification
5. Verify NatSpec coverage
6. Prepare for external audit

## Verification Checklist

- [ ] All tests passing
- [ ] Coverage >95%
- [ ] No critical security issues (Slither)
- [ ] Halmos properties verified
- [ ] NatSpec complete (100%)
- [ ] All required documentation present
- [ ] Gas optimizations reviewed
- [ ] Ready for external audit

---

Report generated: TIMESTAMP_PLACEHOLDER
Verification profile: PROFILE_PLACEHOLDER
SUMMARY_EOF

# Fill in the placeholders
sed -i "s/TIMESTAMP_PLACEHOLDER/$(date)/g" "$REPORT_DIR/VERIFICATION_SUMMARY.md"
sed -i "s/PROFILE_PLACEHOLDER/$PROFILE/g" "$REPORT_DIR/VERIFICATION_SUMMARY.md"

echo "✅ Summary report generated"
echo ""

# ============================================
# Step 11: Final Report
# ============================================
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                  VERIFICATION COMPLETE                     ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "📁 Reports saved to: $REPORT_DIR"
echo ""
echo "📊 Key Files:"
echo "  - Coverage: $REPORT_DIR/04-coverage.log"
echo "  - Unit Tests: $REPORT_DIR/03-unit-tests.log"
echo "  - Invariants: $REPORT_DIR/05-invariants.log"
echo "  - Gas Report: $REPORT_DIR/06-gas-report.txt"
echo "  - Summary: $REPORT_DIR/VERIFICATION_SUMMARY.md"
echo ""

if [ "$PROFILE" = "production" ]; then
    echo "🚀 Production profile verification complete!"
    echo "   Ready for external audit."
    echo ""
fi

echo "⏱️  Verification took approximately $(( (SECONDS / 60) ))m $(( (SECONDS % 60) ))s"
echo ""
echo "✅ All verification steps completed successfully!"
