// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {Sink} from "../src/Sink.sol";

/**
 * @title Deploy
 * @notice Deployment script for Sink contract
 * @dev Usage:
 *   forge script script/Deploy.s.sol:Deploy --rpc-url <rpc_url> --broadcast --verify
 *
 * For local testing:
 *   forge script script/Deploy.s.sol:Deploy --fork-url <rpc_url>
 */
contract Deploy is Script {
    function run() external returns (Sink) {
        // Get deployer private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy Sink contract
        Sink sink = new Sink();

        console2.log("==== Sink Contract Deployed ====");
        console2.log("Contract Address:", address(sink));
        console2.log("Current Balance (staked):", sink.getBalance());
        console2.log("");
        console2.log("Precompile Addresses:");
        console2.log("  Unstake:", "0x0000000000000000000000000000000000000801");
        console2.log("");
        console2.log("Process: Unstake staked TAO -> Burn liquid TAO (send to address(0)) -> Reimburse caller");
        console2.log("");
        console2.log("Note: This contract has no owner or admin functions.");
        console2.log("Anyone can call burnAll() to unstake & burn tokens and receive gas reimbursement.");

        vm.stopBroadcast();

        return sink;
    }
}
