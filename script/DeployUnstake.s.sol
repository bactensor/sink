// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/UnstakeV2Test.sol";

contract DeployUnstake is Script {
    function run() external {
        // Load deployer private key from environment variable
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy UnstakeV2Test contract
        UnstakeV2Test unstake = new UnstakeV2Test();

        console.log("Deployed UnstakeV2Test at:", address(unstake));

        vm.stopBroadcast();
    }
}
