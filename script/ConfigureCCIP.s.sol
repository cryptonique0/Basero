// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {CCIPRebaseTokenSender} from "../src/CCIPRebaseTokenSender.sol";
import {CCIPRebaseTokenReceiver} from "../src/CCIPRebaseTokenReceiver.sol";

/**
 * @title ConfigureCCIP
 * @dev Script to configure cross-chain connections between sender and receiver
 */
contract ConfigureCCIP is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Get deployed contract addresses (update these after deployment)
        address senderAddress = vm.envAddress("SENDER_ADDRESS");
        address receiverAddress = vm.envAddress("RECEIVER_ADDRESS");

        // Get destination chain info
        uint64 destinationChainSelector = uint64(vm.envUint("ARBITRUM_SEPOLIA_CHAIN_SELECTOR"));

        vm.startBroadcast(deployerPrivateKey);

        CCIPRebaseTokenSender sender = CCIPRebaseTokenSender(senderAddress);
        CCIPRebaseTokenReceiver receiver = CCIPRebaseTokenReceiver(receiverAddress);

        console.log("Configuring sender...");
        // Allowlist destination chain on sender
        sender.allowlistDestinationChain(destinationChainSelector, true);
        // Allowlist receiver on destination chain
        sender.allowlistReceiver(destinationChainSelector, receiverAddress);

        console.log("Configuring receiver...");
        // Get source chain selector
        uint64 sourceChainSelector = uint64(vm.envUint("SEPOLIA_CHAIN_SELECTOR"));
        // Allowlist source chain on receiver
        receiver.allowlistSourceChain(sourceChainSelector, true);
        // Allowlist sender on source chain
        receiver.allowlistSender(sourceChainSelector, senderAddress);

        vm.stopBroadcast();

        console.log("\n=== Configuration Complete ===");
        console.log("Sender configured for chain:", destinationChainSelector);
        console.log("Receiver configured for chain:", sourceChainSelector);
        console.log("==============================\n");
    }
}
