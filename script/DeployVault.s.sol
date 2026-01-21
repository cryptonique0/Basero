// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {RebaseTokenVault} from "../src/RebaseTokenVault.sol";

/**
 * @title DeployVault
 * @dev Deployment script for RebaseToken and Vault
 */
contract DeployVault is Script {
    function run() external returns (RebaseToken, RebaseTokenVault) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);

        // Deploy RebaseToken
        console.log("Deploying RebaseToken...");
        RebaseToken token = new RebaseToken(
            "Cross-Chain Rebase Token",
            "CCRT"
        );
        console.log("RebaseToken deployed at:", address(token));

        // Deploy Vault
        console.log("Deploying Vault...");
        RebaseTokenVault vault = new RebaseTokenVault(address(token));
        console.log("Vault deployed at:", address(vault));

        // Transfer token ownership to vault
        console.log("Transferring token ownership to vault...");
        token.transferOwnership(address(vault));

        vm.stopBroadcast();

        console.log("\n=== Deployment Summary ===");
        console.log("RebaseToken:", address(token));
        console.log("Vault:", address(vault));
        console.log("==========================\n");

        return (token, vault);
    }
}
