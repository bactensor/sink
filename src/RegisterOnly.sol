// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract RegisterOnly {
    address constant NEURON_PRECOMPILE = 0x0000000000000000000000000000000000000804;

    function burnedRegisterNeuron(uint16 netuid, bytes32 hotkey) external payable {
        require(msg.value > 0, "Need TAO to burn");
        bytes memory data = abi.encodeWithSelector(bytes4(keccak256("burnedRegister(uint16,bytes32)")), netuid, hotkey);
        (bool success,) = NEURON_PRECOMPILE.call{value: msg.value, gas: gasleft()}(data);
        require(success, "burnedRegister call failed");
    }
}
