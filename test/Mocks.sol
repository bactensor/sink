// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MockStaking {
    bool public shouldFail;

    function addStake(bytes32 hotkey, uint256 amount, uint256 netuid) external payable {
        if (shouldFail) {
            revert("Mock: addStake failed");
        }
    }

    function removeStake(bytes32 hotkey, uint256 amount, uint256 netuid) external {
        if (shouldFail) {
            revert("Mock: removeStake failed");
        }
        payable(msg.sender).transfer(amount);
    }

    function setShouldFail(bool _fail) external {
        shouldFail = _fail;
    }
}

contract MockNeuron {
    bool public shouldFail;

    function burnedRegister(uint16 netuid, bytes32 hotkey) external payable {
        if (shouldFail) {
            revert("Mock: burnedRegister failed");
        }
    }

    function setShouldFail(bool _fail) external {
        shouldFail = _fail;
    }
}

contract RevertingReceiver {
    receive() external payable {
        revert("I refuse refunds");
    }
}