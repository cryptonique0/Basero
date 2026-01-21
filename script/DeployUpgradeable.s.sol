// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UpgradeableRebaseToken} from "../src/upgradeable/UpgradeableRebaseToken.sol";
import {UpgradeableRebaseTokenVault} from "../src/upgradeable/UpgradeableRebaseTokenVault.sol";
import {StorageLayoutValidator} from "../src/upgradeable/StorageLayoutValidator.sol";

/**
 * @title DeployUpgradeableSystem
 * @dev Deploy UUPS upgradeable contracts with proxies
 */
contract DeployUpgradeableSystem is Script {
    
    UpgradeableRebaseToken public tokenImplementation;
    UpgradeableRebaseToken public token;
    
    UpgradeableRebaseTokenVault public vaultImplementation;
    UpgradeableRebaseTokenVault public vault;
    
    StorageLayoutValidator public validator;
    
    ERC1967Proxy public tokenProxy;
    ERC1967Proxy public vaultProxy;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deploying upgradeable system...");
        console.log("Deployer:", deployer);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // 1. Deploy storage layout validator
        validator = new StorageLayoutValidator();
        console.log("Validator deployed:", address(validator));
        
        // 2. Deploy token implementation
        tokenImplementation = new UpgradeableRebaseToken();
        console.log("Token implementation:", address(tokenImplementation));
        
        // 3. Deploy token proxy
        bytes memory tokenInitData = abi.encodeCall(
            UpgradeableRebaseToken.initialize,
            ("Rebase Token", "REBASE", deployer)
        );
        
        tokenProxy = new ERC1967Proxy(
            address(tokenImplementation),
            tokenInitData
        );
        token = UpgradeableRebaseToken(address(tokenProxy));
        console.log("Token proxy:", address(tokenProxy));
        
        // 4. Deploy vault implementation
        vaultImplementation = new UpgradeableRebaseTokenVault();
        console.log("Vault implementation:", address(vaultImplementation));
        
        // 5. Deploy vault proxy
        bytes memory vaultInitData = abi.encodeCall(
            UpgradeableRebaseTokenVault.initialize,
            (address(token), deployer)
        );
        
        vaultProxy = new ERC1967Proxy(
            address(vaultImplementation),
            vaultInitData
        );
        vault = UpgradeableRebaseTokenVault(payable(address(vaultProxy)));
        console.log("Vault proxy:", address(vaultProxy));
        
        // 6. Register initial storage layouts
        _registerStorageLayouts();
        
        // 7. Grant vault minter role
        token.transferOwnership(address(vault));
        console.log("Vault granted ownership of token");
        
        vm.stopBroadcast();
        
        // Print deployment summary
        _printSummary();
    }
    
    function _registerStorageLayouts() internal {
        // Register token storage layout
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
            1, // version
            token.getStorageLayoutHash(),
            token.getStorageSlots(),
            tokenVars
        );
        
        // Register vault storage layout
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
            1, // version
            vault.getStorageLayoutHash(),
            vault.getStorageSlots(),
            vaultVars
        );
        
        console.log("Storage layouts registered");
    }
    
    function _printSummary() internal view {
        console.log("\n=== Deployment Summary ===");
        console.log("Validator:", address(validator));
        console.log("\nToken:");
        console.log("  Implementation:", address(tokenImplementation));
        console.log("  Proxy:", address(tokenProxy));
        console.log("  Version:", token.getVersion());
        console.log("\nVault:");
        console.log("  Implementation:", address(vaultImplementation));
        console.log("  Proxy:", address(vaultProxy));
        console.log("  Version:", vault.getVersion());
    }
}
