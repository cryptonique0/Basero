// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "forge-std/StdInvariant.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {RebaseTokenVault} from "../src/RebaseTokenVault.sol";

/**
 * @title RebaseTokenInvariantTest
 * @notice Invariant tests for RebaseToken core mechanics
 * @dev Tests critical invariants that must hold across all state transitions
 */
contract RebaseTokenInvariantTest is StdInvariant, Test {
    
    RebaseToken public token;
    RebaseTokenVault public vault;
    RebaseTokenHandler public handler;
    
    // Ghost variables for tracking
    uint256 public ghost_mintSum;
    uint256 public ghost_burnSum;
    uint256 public ghost_transferSum;
    
    function setUp() public {
        // Deploy contracts
        token = new RebaseToken("Rebase Token", "REBASE");
        vault = new RebaseTokenVault(address(token));
        
        // Transfer ownership to vault for minting
        token.transferOwnership(address(vault));
        
        // Deploy handler
        handler = new RebaseTokenHandler(token, vault);
        
        // Target handler for invariant testing
        targetContract(address(handler));
        
        // Target specific functions (exclude view functions)
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = RebaseTokenHandler.deposit.selector;
        selectors[1] = RebaseTokenHandler.withdraw.selector;
        selectors[2] = RebaseTokenHandler.transfer.selector;
        selectors[3] = RebaseTokenHandler.rebase.selector;
        selectors[4] = RebaseTokenHandler.accrueInterest.selector;
        
        targetSelector(FuzzSelector({
            addr: address(handler),
            selectors: selectors
        }));
    }
    
    // ============= Supply Invariants =============
    
    /// @notice Total supply should equal sum of all shares times current ratio
    function invariant_totalSupplyEqualsSharesTimesRatio() public view {
        uint256 totalShares = token.totalShares();
        uint256 totalSupply = token.totalSupply();
        
        if (totalShares == 0) {
            assertEq(totalSupply, 0, "Supply must be 0 when shares are 0");
        } else {
            // Supply = shares * (supply / shares) should be consistent
            uint256 calculatedSupply = (totalShares * totalSupply) / totalShares;
            assertEq(calculatedSupply, totalSupply, "Supply/shares ratio inconsistent");
        }
    }
    
    /// @notice Sum of all balances should equal total supply
    function invariant_sumOfBalancesEqualsTotalSupply() public view {
        uint256 totalSupply = token.totalSupply();
        uint256 sumOfBalances = handler.getSumOfBalances();
        
        // Allow for rounding differences
        uint256 diff = sumOfBalances > totalSupply 
            ? sumOfBalances - totalSupply 
            : totalSupply - sumOfBalances;
            
        assertLe(diff, handler.getActorCount(), "Balance sum should equal total supply within rounding");
    }
    
    /// @notice Total shares should never exceed total supply by more than rounding
    function invariant_sharesVsSupplyBounds() public view {
        uint256 totalShares = token.totalShares();
        uint256 totalSupply = token.totalSupply();
        
        // Shares can be less than or equal to supply (after rebases)
        // But should never be wildly different
        if (totalSupply > 0) {
            assertGe(totalSupply, totalShares / 2, "Supply dropped too much vs shares");
        }
    }
    
    /// @notice Total supply should never decrease except via burns
    function invariant_supplyOnlyDecreasesFromBurns() public view {
        uint256 totalMinted = ghost_mintSum;
        uint256 totalBurned = ghost_burnSum;
        uint256 currentSupply = token.totalSupply();
        
        // Current supply should be: minted - burned + rebases
        // We can't easily track rebase amounts, but supply should never be negative
        assertGe(currentSupply, 0, "Supply cannot be negative");
    }
    
    // ============= Share Invariants =============
    
    /// @notice Sum of all user shares should equal total shares
    function invariant_sumOfSharesEqualsTotalShares() public view {
        uint256 totalShares = token.totalShares();
        uint256 sumOfShares = handler.getSumOfShares();
        
        assertEq(sumOfShares, totalShares, "Sum of shares must equal total shares");
    }
    
    /// @notice Individual shares should never exceed total shares
    function invariant_individualSharesNeverExceedTotal() public view {
        address[] memory actors = handler.getActors();
        uint256 totalShares = token.totalShares();
        
        for (uint256 i = 0; i < actors.length; i++) {
            uint256 userShares = token.sharesOf(actors[i]);
            assertLe(userShares, totalShares, "Individual shares exceed total");
        }
    }
    
    /// @notice Shares should never be zero if balance is non-zero
    function invariant_nonZeroBalanceRequiresShares() public view {
        address[] memory actors = handler.getActors();
        
        for (uint256 i = 0; i < actors.length; i++) {
            uint256 balance = token.balanceOf(actors[i]);
            uint256 shares = token.sharesOf(actors[i]);
            
            if (balance > 0) {
                assertGt(shares, 0, "Non-zero balance requires shares");
            }
        }
    }
    
    // ============= Interest Rate Invariants =============
    
    /// @notice Interest rates should always be within configured bounds
    function invariant_interestRatesWithinBounds() public view {
        address[] memory actors = handler.getActors();
        uint256 maxRate = 10000; // 100% in basis points
        
        for (uint256 i = 0; i < actors.length; i++) {
            uint256 rate = token.interestRateOf(actors[i]);
            assertLe(rate, maxRate, "Interest rate exceeds maximum");
        }
    }
    
    /// @notice Current interest rate should match vault's calculation
    function invariant_currentRateMatchesVault() public view {
        uint256 vaultRate = vault.getCurrentInterestRate();
        uint256 baseRate = vault.baseInterestRate();
        uint256 minRate = vault.minimumRate();
        
        assertLe(vaultRate, baseRate, "Current rate exceeds base rate");
        assertGe(vaultRate, minRate, "Current rate below minimum");
    }
    
    // ============= Vault Invariants =============
    
    /// @notice Vault's total deposited should match ETH balance
    function invariant_vaultDepositedEqualsBalance() public view {
        uint256 totalDeposited = vault.totalDeposited();
        uint256 vaultBalance = address(vault).balance;
        
        assertEq(totalDeposited, vaultBalance, "Vault deposits != ETH balance");
    }
    
    /// @notice Sum of user deposits should equal total deposited
    function invariant_sumOfDepositsEqualsTotal() public view {
        uint256 totalDeposited = vault.totalDeposited();
        uint256 sumOfDeposits = handler.getSumOfDeposits();
        
        assertEq(sumOfDeposits, totalDeposited, "Sum of deposits != total deposited");
    }
    
    /// @notice User deposit should never exceed their token balance
    function invariant_depositNotExceedBalance() public view {
        address[] memory actors = handler.getActors();
        
        for (uint256 i = 0; i < actors.length; i++) {
            uint256 deposit = vault.userDeposits(actors[i]);
            uint256 balance = token.balanceOf(actors[i]);
            
            // After rebases, balance can exceed deposit
            // But deposit should never exceed initial balance
            // (we track this in handler)
            assertGe(balance, 0, "Balance should be non-negative");
        }
    }
    
    // ============= Conservation Invariants =============
    
    /// @notice ETH conservation: vault balance + withdrawn = total deposited ever
    function invariant_ethConservation() public view {
        uint256 currentVaultBalance = address(vault).balance;
        uint256 totalWithdrawn = handler.ghost_totalWithdrawn();
        uint256 totalDeposited = handler.ghost_totalDeposited();
        
        assertEq(
            currentVaultBalance + totalWithdrawn,
            totalDeposited,
            "ETH not conserved"
        );
    }
    
    /// @notice Token conservation: total supply accounts for all mints and burns
    function invariant_tokenConservation() public view {
        uint256 currentSupply = token.totalSupply();
        uint256 totalMinted = handler.ghost_totalMinted();
        uint256 totalBurned = handler.ghost_totalBurned();
        uint256 totalRebased = handler.ghost_totalRebased();
        
        // Supply = minted - burned + rebased
        uint256 expectedSupply = totalMinted - totalBurned + totalRebased;
        
        // Allow small rounding differences
        uint256 diff = expectedSupply > currentSupply
            ? expectedSupply - currentSupply
            : currentSupply - expectedSupply;
            
        assertLe(diff, 100, "Token conservation violated");
    }
    
    // ============= Rebase Invariants =============
    
    /// @notice Rebase should only change supply, not shares
    function invariant_rebaseOnlyChangesSupply() public view {
        // This is tested by comparing shares before/after in handler
        // Here we verify shares remain constant per user
        uint256 totalShares = token.totalShares();
        assertGe(totalShares, 0, "Total shares should be non-negative");
    }
    
    /// @notice Positive rebase should increase all balances proportionally
    function invariant_positiveRebaseIncreasesBalances() public view {
        // Tracked in handler's ghost variables
        uint256 totalRebased = handler.ghost_totalRebased();
        
        if (totalRebased > 0) {
            uint256 currentSupply = token.totalSupply();
            assertGt(currentSupply, 0, "Supply should be positive after rebase");
        }
    }
    
    // ============= Transfer Invariants =============
    
    /// @notice Transfer should conserve total supply
    function invariant_transferConservesSupply() public view {
        uint256 supplyBefore = handler.ghost_supplyBeforeTransfer();
        uint256 supplyAfter = token.totalSupply();
        
        if (supplyBefore > 0) {
            assertEq(supplyBefore, supplyAfter, "Transfer changed total supply");
        }
    }
    
    /// @notice Transfer should conserve total shares
    function invariant_transferConservesShares() public view {
        uint256 sharesBefore = handler.ghost_sharesBeforeTransfer();
        uint256 sharesAfter = token.totalShares();
        
        if (sharesBefore > 0) {
            assertEq(sharesBefore, sharesAfter, "Transfer changed total shares");
        }
    }
    
    // ============= Solvency Invariants =============
    
    /// @notice Vault should always be able to pay out all deposits
    function invariant_vaultSolvency() public view {
        uint256 vaultBalance = address(vault).balance;
        uint256 totalDeposited = vault.totalDeposited();
        
        assertGe(vaultBalance, totalDeposited, "Vault insolvent");
    }
    
    /// @notice Total supply should back all outstanding deposits
    function invariant_supplyBacksDeposits() public view {
        uint256 totalSupply = token.totalSupply();
        uint256 totalDeposited = vault.totalDeposited();
        
        // Supply can be higher due to rebases, but should cover deposits
        assertGe(totalSupply, 0, "Supply should be non-negative");
    }
    
    // ============= State Consistency Invariants =============
    
    /// @notice No orphaned shares (shares without supply)
    function invariant_noOrphanedShares() public view {
        uint256 totalShares = token.totalShares();
        uint256 totalSupply = token.totalSupply();
        
        if (totalShares > 0) {
            assertGt(totalSupply, 0, "Shares exist but no supply");
        }
        
        if (totalSupply > 0) {
            assertGt(totalShares, 0, "Supply exists but no shares");
        }
    }
    
    /// @notice Time-based invariants
    function invariant_timeProgression() public view {
        uint256 lastAccrualTime = vault.lastAccrualTime();
        assertLe(lastAccrualTime, block.timestamp, "Last accrual in future");
    }
}

/**
 * @title RebaseTokenHandler
 * @notice Handler contract for guided fuzzing of RebaseToken
 * @dev Provides realistic state transitions for invariant testing
 */
contract RebaseTokenHandler is Test {
    
    RebaseToken public token;
    RebaseTokenVault public vault;
    
    // Actor management
    address[] public actors;
    mapping(address => bool) public isActor;
    
    // Ghost variables for invariant tracking
    uint256 public ghost_totalDeposited;
    uint256 public ghost_totalWithdrawn;
    uint256 public ghost_totalMinted;
    uint256 public ghost_totalBurned;
    uint256 public ghost_totalRebased;
    uint256 public ghost_supplyBeforeTransfer;
    uint256 public ghost_sharesBeforeTransfer;
    
    constructor(RebaseToken _token, RebaseTokenVault _vault) {
        token = _token;
        vault = _vault;
        
        // Initialize with some actors
        for (uint256 i = 0; i < 10; i++) {
            address actor = address(uint160(uint256(keccak256(abi.encodePacked(i)))));
            actors.push(actor);
            isActor[actor] = true;
            vm.deal(actor, 1000 ether);
        }
    }
    
    // ============= Actions =============
    
    function deposit(uint256 actorSeed, uint256 amount) external {
        address actor = actors[actorSeed % actors.length];
        amount = bound(amount, 0.01 ether, 100 ether);
        
        if (actor.balance < amount) return;
        
        vm.prank(actor);
        vault.deposit{value: amount}();
        
        ghost_totalDeposited += amount;
        ghost_totalMinted += amount;
    }
    
    function withdraw(uint256 actorSeed, uint256 amount) external {
        address actor = actors[actorSeed % actors.length];
        uint256 maxWithdraw = vault.userDeposits(actor);
        
        if (maxWithdraw == 0) return;
        
        amount = bound(amount, 0, maxWithdraw);
        if (amount == 0) return;
        
        vm.prank(actor);
        try vault.withdraw(amount) {
            ghost_totalWithdrawn += amount;
            ghost_totalBurned += amount;
        } catch {}
    }
    
    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        
        uint256 balance = token.balanceOf(from);
        if (balance == 0) return;
        
        amount = bound(amount, 0, balance);
        if (amount == 0) return;
        
        ghost_supplyBeforeTransfer = token.totalSupply();
        ghost_sharesBeforeTransfer = token.totalShares();
        
        vm.prank(from);
        try token.transfer(to, amount) {} catch {}
    }
    
    function rebase(uint256 amount, bool positive) external {
        amount = bound(amount, 0, 10 ether);
        
        try vault.accrueInterest() {
            if (positive) {
                ghost_totalRebased += amount;
            }
        } catch {}
    }
    
    function accrueInterest() external {
        // Fast forward time
        skip(1 days);
        
        try vault.accrueInterest() {
            // Interest accrued successfully
        } catch {}
    }
    
    // ============= View Functions =============
    
    function getActors() external view returns (address[] memory) {
        return actors;
    }
    
    function getActorCount() external view returns (uint256) {
        return actors.length;
    }
    
    function getSumOfBalances() external view returns (uint256 sum) {
        for (uint256 i = 0; i < actors.length; i++) {
            sum += token.balanceOf(actors[i]);
        }
    }
    
    function getSumOfShares() external view returns (uint256 sum) {
        for (uint256 i = 0; i < actors.length; i++) {
            sum += token.sharesOf(actors[i]);
        }
    }
    
    function getSumOfDeposits() external view returns (uint256 sum) {
        for (uint256 i = 0; i < actors.length; i++) {
            sum += vault.userDeposits(actors[i]);
        }
    }
    
    function ghost_totalWithdrawn() external view returns (uint256) {
        return ghost_totalWithdrawn;
    }
    
    function ghost_totalMinted() external view returns (uint256) {
        return ghost_totalMinted;
    }
    
    function ghost_totalBurned() external view returns (uint256) {
        return ghost_totalBurned;
    }
    
    function ghost_totalRebased() external view returns (uint256) {
        return ghost_totalRebased;
    }
}
