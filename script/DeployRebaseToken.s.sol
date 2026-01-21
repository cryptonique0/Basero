// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {RebaseToken} from "../src/RebaseToken.sol";

/**
 * @title DeployRebaseToken
 * @dev Deployment script for RebaseToken
 */
contract DeployRebaseToken is Script {
    function run() external returns (RebaseToken) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);

        // Deploy RebaseToken with 1 million tokens initial supply
        RebaseToken token = new RebaseToken(
            "Cross-Chain Rebase Token",
            "CCRT",
            1_000_000 * 10 ** 18
        );

        vm.stopBroadcast();

        return token;
    }
}
