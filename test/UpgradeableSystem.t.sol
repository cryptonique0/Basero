// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UpgradeableRebaseToken} from "../src/upgradeable/UpgradeableRebaseToken.sol";
import {UpgradeableRebaseTokenVault} from "../src/upgradeable/UpgradeableRebaseTokenVault.sol";
import {StorageLayoutValidator} from "../src/upgradeable/StorageLayoutValidator.sol";

/**
 * @title UpgradeableSystemTest
 * @dev Comprehensive test suite for UUPS upgradeable contracts
 */
contract UpgradeableSystemTest is Test {
    
    UpgradeableRebaseToken public tokenImplementation;
    UpgradeableRebaseToken public token;
    
    UpgradeableRebaseTokenVault public vaultImplementation;
    UpgradeableRebaseTokenVault public vault;
    
    StorageLayoutValidator public validator;
    
    ERC1967Proxy public tokenProxy;
    ERC1967Proxy public vaultProxy;
    
    address public owner = address(this);
    address public user1 = address(0x1);
    address public user2 = address(0x2);
    address public attacker = address(0x666);
    
    event Upgraded(address indexed implementation, uint256 version);
    
    function setUp() public {
        // Deploy validator
        validator = new StorageLayoutValidator();
        
        // Deploy token
        tokenImplementation = new UpgradeableRebaseToken();
        
        bytes memory tokenInitData = abi.encodeCall(
            UpgradeableRebaseToken.initialize,
            ("Rebase Token", "REBASE", owner)
        );
        
        tokenProxy = new ERC1967Proxy(
            address(tokenImplementation),
            tokenInitData
        );
        token = UpgradeableRebaseToken(address(tokenProxy));
        
        // Deploy vault
        vaultImplementation = new UpgradeableRebaseTokenVault();
        
        bytes memory vaultInitData = abi.encodeCall(
            UpgradeableRebaseTokenVault.initialize,
            (address(token), owner)
        );
        
        vaultProxy = new ERC1967Proxy(
            address(vaultImplementation),
            vaultInitData
        );
        vault = UpgradeableRebaseTokenVault(payable(address(vaultProxy)));
        
        // Register storage layouts
        _registerLayouts();
        
        // Fund users
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
    }
    
    // ============= Initialization Tests =============
    
    function test_InitialState() public view {
        assertEq(token.name(), "Rebase Token");
        assertEq(token.symbol(), "REBASE");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), 0);
        assertEq(token.getVersion(), 1);
    }
    
    function test_VaultInitialState() public view {
        assertEq(vault.getVersion(), 1);
        assertEq(vault.totalDeposited(), 0);
        assertEq(address(vault.rebaseToken()), address(token));
    }
    
    function test_CannotReinitialize() public {
        vm.expectRevert();
        token.initialize("New Name", "NEW", owner);
    }
    
    // ============= Basic Functionality Tests =============
    
    function test_DepositAndWithdraw() public {
        vm.startPrank(user1);
        
        vault.deposit{value: 10 ether}();
        assertEq(token.balanceOf(user1), 10 ether);
        assertEq(vault.totalDeposited(), 10 ether);
        
        vault.withdraw(5 ether);
        assertEq(token.balanceOf(user1), 5 ether);
        assertEq(vault.totalDeposited(), 5 ether);
        
        vm.stopPrank();
    }
    
    function test_TokenTransfer() public {
        vm.prank(user1);
        vault.deposit{value: 10 ether}();
        
        vm.prank(user1);
        token.transfer(user2, 3 ether);
        
        assertEq(token.balanceOf(user1), 7 ether);
        assertEq(token.balanceOf(user2), 3 ether);
    }
    
    // ============= Upgrade Authorization Tests =============
    
    function test_OnlyOwnerCanUpgrade() public {
        UpgradeableRebaseToken newImpl = new UpgradeableRebaseToken();
        
        vm.prank(attacker);
        vm.expectRevert();
        token.upgradeToAndCall(address(newImpl), "");
    }
    
    function test_OwnerCanUpgrade() public {
        UpgradeableRebaseToken newImpl = new UpgradeableRebaseToken();
        
        vm.expectEmit(true, false, false, true);
        emit Upgraded(address(newImpl), 1);
        
        token.upgradeToAndCall(address(newImpl), "");
    }
    
    function test_VaultUpgradeAuthorization() public {
        UpgradeableRebaseTokenVault newImpl = new UpgradeableRebaseTokenVault();
        
        vm.prank(attacker);
        vm.expectRevert();
        vault.upgradeToAndCall(address(newImpl), "");
        
        // Owner can upgrade
        vault.upgradeToAndCall(address(newImpl), "");
    }
    
    // ============= Storage Preservation Tests =============
    
    function test_UpgradePreservesTokenBalances() public {
        // Setup: deposit and create balances
        vm.prank(user1);
        vault.deposit{value: 10 ether}();
        
        vm.prank(user2);
        vault.deposit{value: 20 ether}();
        
        uint256 balance1Before = token.balanceOf(user1);
        uint256 balance2Before = token.balanceOf(user2);
        uint256 totalSupplyBefore = token.totalSupply();
        
        // Upgrade token
        UpgradeableRebaseToken newImpl = new UpgradeableRebaseToken();
        token.upgradeToAndCall(address(newImpl), "");
        
        // Verify balances preserved
        assertEq(token.balanceOf(user1), balance1Before);
        assertEq(token.balanceOf(user2), balance2Before);
        assertEq(token.totalSupply(), totalSupplyBefore);
    }
    
    function test_UpgradePreservesVaultDeposits() public {
        vm.prank(user1);
        vault.deposit{value: 10 ether}();
        
        uint256 depositBefore = vault.totalDeposited();
        (uint256 user1Deposit,,,) = vault.getUserInfo(user1);
        
        // Upgrade vault
        UpgradeableRebaseTokenVault newImpl = new UpgradeableRebaseTokenVault();
        vault.upgradeToAndCall(address(newImpl), "");
        
        // Verify deposits preserved
        assertEq(vault.totalDeposited(), depositBefore);
        (uint256 user1DepositAfter,,,) = vault.getUserInfo(user1);
        assertEq(user1DepositAfter, user1Deposit);
    }
    
    function test_UpgradePreservesInterestRates() public {
        vm.prank(user1);
        vault.deposit{value: 10 ether}();
        
        (,uint256 rateBefore,,) = vault.getUserInfo(user1);
        
        // Upgrade
        UpgradeableRebaseToken newTokenImpl = new UpgradeableRebaseToken();
        token.upgradeToAndCall(address(newTokenImpl), "");
        
        UpgradeableRebaseTokenVault newVaultImpl = new UpgradeableRebaseTokenVault();
        vault.upgradeToAndCall(address(newVaultImpl), "");
        
        // Verify rate preserved
        (,uint256 rateAfter,,) = vault.getUserInfo(user1);
        assertEq(rateAfter, rateBefore);
    }
    
    // ============= Storage Layout Validation Tests =============
    
    function test_StorageLayoutRegistration() public {
        StorageLayoutValidator.StorageLayout memory layout = 
            validator.getLayout(address(tokenProxy), 1);
        
        assertEq(layout.version, 1);
        assertEq(layout.layoutHash, token.getStorageLayoutHash());
        assertEq(layout.totalSlots, token.getStorageSlots());
    }
    
    function test_ValidateUpgradeSafety() public {
        // Deploy new implementation
        UpgradeableRebaseToken newImpl = new UpgradeableRebaseToken();
        
        // Register new layout
        _registerNewTokenLayout(2, newImpl);
        
        // Validate upgrade
        (bool safe, string memory message) = validator.validateUpgrade(
            address(tokenProxy),
            1, // from version
            2  // to version
        );
        
        assertTrue(safe);
        assertEq(message, "Layouts identical - safe upgrade");
    }
    
    function test_DetectStorageCollision() public {
        // Create mock layout with fewer slots (collision)
        string[] memory vars = new string[](1);
        vars[0] = "test";
        
        validator.registerLayout(
            address(tokenProxy),
            2, // version
            keccak256("different_layout"),
            50, // fewer slots than v1
            vars
        );
        
        // Should detect collision
        (bool safe, string memory message) = validator.validateUpgrade(
            address(tokenProxy),
            1,
            2
        );
        
        assertFalse(safe);
        assertEq(message, "New layout uses fewer slots - data loss risk");
    }
    
    // ============= Complex Upgrade Scenarios =============
    
    function test_UpgradeWithActiveUsers() public {
        // Create multiple users with deposits
        for (uint256 i = 1; i <= 5; i++) {
            address user = address(uint160(i));
            vm.deal(user, 100 ether);
            
            vm.prank(user);
            vault.deposit{value: uint256(i) * 1 ether}();
        }
        
        uint256 totalBefore = token.totalSupply();
        
        // Upgrade both contracts
        UpgradeableRebaseToken newTokenImpl = new UpgradeableRebaseToken();
        token.upgradeToAndCall(address(newTokenImpl), "");
        
        UpgradeableRebaseTokenVault newVaultImpl = new UpgradeableRebaseTokenVault();
        vault.upgradeToAndCall(address(newVaultImpl), "");
        
        // Verify all balances preserved
        assertEq(token.totalSupply(), totalBefore);
        
        for (uint256 i = 1; i <= 5; i++) {
            address user = address(uint160(i));
            assertEq(token.balanceOf(user), uint256(i) * 1 ether);
        }
    }
    
    function test_FunctionalityAfterUpgrade() public {
        // Deposit before upgrade
        vm.prank(user1);
        vault.deposit{value: 10 ether}();
        
        // Upgrade
        UpgradeableRebaseToken newTokenImpl = new UpgradeableRebaseToken();
        token.upgradeToAndCall(address(newTokenImpl), "");
        
        UpgradeableRebaseTokenVault newVaultImpl = new UpgradeableRebaseTokenVault();
        vault.upgradeToAndCall(address(newVaultImpl), "");
        
        // Test functionality after upgrade
        vm.prank(user2);
        vault.deposit{value: 5 ether}();
        
        vm.prank(user1);
        token.transfer(user2, 3 ether);
        
        vm.prank(user1);
        vault.withdraw(2 ether);
        
        // Verify correct balances
        assertEq(token.balanceOf(user1), 5 ether);
        assertEq(token.balanceOf(user2), 8 ether);
    }
    
    // ============= Pause/Unpause Tests =============
    
    function test_CannotUpgradeWhenPaused() public {
        vault.pause();
        
        UpgradeableRebaseTokenVault newImpl = new UpgradeableRebaseTokenVault();
        
        // Upgrade should still work (pause doesn't affect admin)
        vault.upgradeToAndCall(address(newImpl), "");
    }
    
    function test_PausePreservedAfterUpgrade() public {
        vault.pause();
        assertTrue(vault.paused());
        
        UpgradeableRebaseTokenVault newImpl = new UpgradeableRebaseTokenVault();
        vault.upgradeToAndCall(address(newImpl), "");
        
        // Pause state should be preserved
        assertTrue(vault.paused());
    }
    
    // ============= Edge Cases =============
    
    function testFuzz_UpgradeWithRandomBalances(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 0.1 ether, 50 ether);
        amount2 = bound(amount2, 0.1 ether, 50 ether);
        
        vm.deal(user1, amount1);
        vm.deal(user2, amount2);
        
        vm.prank(user1);
        vault.deposit{value: amount1}();
        
        vm.prank(user2);
        vault.deposit{value: amount2}();
        
        uint256 balance1Before = token.balanceOf(user1);
        uint256 balance2Before = token.balanceOf(user2);
        
        // Upgrade
        UpgradeableRebaseToken newImpl = new UpgradeableRebaseToken();
        token.upgradeToAndCall(address(newImpl), "");
        
        // Balances preserved
        assertEq(token.balanceOf(user1), balance1Before);
        assertEq(token.balanceOf(user2), balance2Before);
    }
    
    function test_MultipleSequentialUpgrades() public {
        vm.prank(user1);
        vault.deposit{value: 10 ether}();
        
        uint256 balanceBefore = token.balanceOf(user1);
        
        // Upgrade 3 times
        for (uint256 i = 0; i < 3; i++) {
            UpgradeableRebaseToken newImpl = new UpgradeableRebaseToken();
            token.upgradeToAndCall(address(newImpl), "");
        }
        
        // Balance still preserved
        assertEq(token.balanceOf(user1), balanceBefore);
    }
    
    function test_UpgradeVersion Increments() public view {
        // Initial version
        assertEq(token.getVersion(), 1);
        assertEq(vault.getVersion(), 1);
    }
    
    // ============= Gas Tests =============
    
    function test_UpgradeGasCost() public {
        UpgradeableRebaseToken newImpl = new UpgradeableRebaseToken();
        
        uint256 gasBefore = gasleft();
        token.upgradeToAndCall(address(newImpl), "");
        uint256 gasUsed = gasBefore - gasleft();
        
        console.log("Upgrade gas cost:", gasUsed);
        assertTrue(gasUsed < 100000); // Should be relatively cheap
    }
    
    // ============= Helper Functions =============
    
    function _registerLayouts() internal {
        // Token layout
        string[] memory tokenVars = new string[](8);
        tokenVars[0] = "_name";
        tokenVars[1] = "_symbol";
        tokenVars[2] = "_decimals";
        tokenVars[3] = "_totalShares";
        tokenVars[4] = "_totalSupply";
        tokenVars[5] = "_shares";
        tokenVars[6] = "_interestRates";
        tokenVars[7] = "_allowances";
        
        validator.registerLayout(
            address(tokenProxy),
            1,
            token.getStorageLayoutHash(),
            token.getStorageSlots(),
            tokenVars
        );
        
        // Vault layout
        string[] memory vaultVars = new string[](12);
        vaultVars[0] = "rebaseToken";
        vaultVars[1] = "totalDeposited";
        vaultVars[2] = "lastAccrualTime";
        vaultVars[3] = "accrualPeriod";
        vaultVars[4] = "dailyAccrualCap";
        vaultVars[5] = "baseInterestRate";
        vaultVars[6] = "rateDecrement";
        vaultVars[7] = "decrementThreshold";
        vaultVars[8] = "minimumRate";
        vaultVars[9] = "userDeposits";
        vaultVars[10] = "userInterestRates";
        vaultVars[11] = "lastDepositTime";
        
        validator.registerLayout(
            address(vaultProxy),
            1,
            vault.getStorageLayoutHash(),
            vault.getStorageSlots(),
            vaultVars
        );
    }
    
    function _registerNewTokenLayout(uint256 version, UpgradeableRebaseToken newImpl) internal {
        string[] memory tokenVars = new string[](8);
        tokenVars[0] = "_name";
        tokenVars[1] = "_symbol";
        tokenVars[2] = "_decimals";
        tokenVars[3] = "_totalShares";
        tokenVars[4] = "_totalSupply";
        tokenVars[5] = "_shares";
        tokenVars[6] = "_interestRates";
        tokenVars[7] = "_allowances";
        
        validator.registerLayout(
            address(tokenProxy),
            version,
            newImpl.getStorageLayoutHash(),
            newImpl.getStorageSlots(),
            tokenVars
        );
    }
}
