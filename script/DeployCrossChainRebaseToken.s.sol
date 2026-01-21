// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {CCIPRebaseTokenSender} from "../src/CCIPRebaseTokenSender.sol";
import {CCIPRebaseTokenReceiver} from "../src/CCIPRebaseTokenReceiver.sol";

/**
 * @title DeployCrossChainRebaseToken
 * @dev Complete deployment script for cross-chain rebase token system
 */
contract DeployCrossChainRebaseToken is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Get network-specific addresses from environment
        address ccipRouter = vm.envAddress("SEPOLIA_CCIP_ROUTER");
        address linkToken = vm.envAddress("SEPOLIA_LINK");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy RebaseToken
        console.log("Deploying RebaseToken...");
        RebaseToken token = new RebaseToken(
            "Cross-Chain Rebase Token",
            "CCRT",
            1_000_000 * 10 ** 18
        );
        console.log("RebaseToken deployed at:", address(token));

        // 2. Deploy CCIPRebaseTokenSender
        console.log("Deploying CCIPRebaseTokenSender...");
        CCIPRebaseTokenSender sender = new CCIPRebaseTokenSender(
            ccipRouter,
            linkToken,
            address(token)
        );
        console.log("CCIPRebaseTokenSender deployed at:", address(sender));

        // 3. Deploy CCIPRebaseTokenReceiver
        console.log("Deploying CCIPRebaseTokenReceiver...");
        CCIPRebaseTokenReceiver receiver = new CCIPRebaseTokenReceiver(
            ccipRouter,
            address(token)
        );
        console.log("CCIPRebaseTokenReceiver deployed at:", address(receiver));

        // 4. Grant sender contract permission to burn tokens
        console.log("Transferring token ownership to sender...");
        token.transferOwnership(address(sender));

        vm.stopBroadcast();

        console.log("\n=== Deployment Summary ===");
        console.log("RebaseToken:", address(token));
        console.log("CCIPRebaseTokenSender:", address(sender));
        console.log("CCIPRebaseTokenReceiver:", address(receiver));
        console.log("==========================\n");
    }
}
