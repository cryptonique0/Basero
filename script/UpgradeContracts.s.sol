// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {UpgradeableRebaseToken} from "../src/upgradeable/UpgradeableRebaseToken.sol";
import {UpgradeableRebaseTokenVault} from "../src/upgradeable/UpgradeableRebaseTokenVault.sol";
import {StorageLayoutValidator} from "../src/upgradeable/StorageLayoutValidator.sol";

/**
 * @title UpgradeContract
 * @dev Safely upgrade UUPS contracts with validation
 */
contract UpgradeContract is Script {
    
    StorageLayoutValidator public validator;
    
    // Addresses from deployment
    address public tokenProxy;
    address public vaultProxy;
    address public validatorAddress;
    
    function run() external {
        // Load addresses from environment
        tokenProxy = vm.envAddress("TOKEN_PROXY");
        vaultProxy = vm.envAddress("VAULT_PROXY");
        validatorAddress = vm.envAddress("VALIDATOR");
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        console.log("Upgrading contracts...");
        console.log("Token proxy:", tokenProxy);
        console.log("Vault proxy:", vaultProxy);
        
        validator = StorageLayoutValidator(validatorAddress);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Upgrade token
        _upgradeToken();
        
        // Upgrade vault
        _upgradeVault();
        
        vm.stopBroadcast();
        
        console.log("Upgrades complete!");
    }
    
    function _upgradeToken() internal {
        console.log("\n=== Upgrading Token ===");
        
        UpgradeableRebaseToken proxy = UpgradeableRebaseToken(tokenProxy);
        uint256 currentVersion = proxy.getVersion();
        
        console.log("Current version:", currentVersion);
        
        // Deploy new implementation
        UpgradeableRebaseToken newImplementation = new UpgradeableRebaseToken();
        console.log("New implementation:", address(newImplementation));
        
        // Validate upgrade
        _validateTokenUpgrade(currentVersion, newImplementation);
        
        // Perform upgrade
        proxy.upgradeToAndCall(address(newImplementation), "");
        
        console.log("Token upgraded to version:", proxy.getVersion());
    }
    
    function _upgradeVault() internal {
        console.log("\n=== Upgrading Vault ===");
        
        UpgradeableRebaseTokenVault proxy = UpgradeableRebaseTokenVault(payable(vaultProxy));
        uint256 currentVersion = proxy.getVersion();
        
        console.log("Current version:", currentVersion);
        
        // Deploy new implementation
        UpgradeableRebaseTokenVault newImplementation = new UpgradeableRebaseTokenVault();
        console.log("New implementation:", address(newImplementation));
        
        // Validate upgrade
        _validateVaultUpgrade(currentVersion, newImplementation);
        
        // Perform upgrade
        proxy.upgradeToAndCall(address(newImplementation), "");
        
        console.log("Vault upgraded to version:", proxy.getVersion());
    }
    
    function _validateTokenUpgrade(
        uint256 fromVersion,
        UpgradeableRebaseToken newImpl
    ) internal {
        console.log("Validating token upgrade...");
        
        // Register new version layout
        string[] memory tokenVars = new string[](8);
        tokenVars[0] = "_name";
        tokenVars[1] = "_symbol";
        tokenVars[2] = "_decimals";
        tokenVars[3] = "_totalShares";
        tokenVars[4] = "_totalSupply";
        tokenVars[5] = "_shares";
        tokenVars[6] = "_interestRates";
        tokenVars[7] = "_allowances";
        
        uint256 newVersion = newImpl.getVersion();
        
        validator.registerLayout(
            tokenProxy,
            newVersion,
            newImpl.getStorageLayoutHash(),
            newImpl.getStorageSlots(),
            tokenVars
        );
        
        // Validate
        (bool safe, string memory message) = validator.validateUpgrade(
            tokenProxy,
            fromVersion,
            newVersion
        );
        
        console.log("Validation result:", message);
        require(safe, "Upgrade validation failed");
    }
    
    function _validateVaultUpgrade(
        uint256 fromVersion,
        UpgradeableRebaseTokenVault newImpl
    ) internal {
        console.log("Validating vault upgrade...");
        
        // Register new version layout
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
        
        uint256 newVersion = newImpl.getVersion();
        
        validator.registerLayout(
            vaultProxy,
            newVersion,
            newImpl.getStorageLayoutHash(),
            newImpl.getStorageSlots(),
            vaultVars
        );
        
        // Validate
        (bool safe, string memory message) = validator.validateUpgrade(
            vaultProxy,
            fromVersion,
            newVersion
        );
        
        console.log("Validation result:", message);
        require(safe, "Upgrade validation failed");
    }
}
