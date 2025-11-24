// SPDX-License-Identifier: GPL-3.0
//
// This example demonstrates calling of IStaking precompile
// from another smart contract

pragma solidity ^0.8.20;

address constant ISTAKING_ADDRESS = 0x0000000000000000000000000000000000000805;

address constant DEAD = 0x000000000000000000000000000000000000dEaD;


interface Staking {
    function addStakeLimit(
        bytes32 hotkey,
        uint256 amount,
        uint256 limit_price,
        bool allow_partial,
        uint256 netuid
    ) external;

    function addStake(bytes32 hotkey, uint256 amount, uint256 netuid) external;

    function removeStake(
        bytes32 hotkey,
        uint256 amount,
        uint256 netuid
    ) external;
}

contract UnstakeV2Test {
    address public owner;
    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    receive() external payable {}

    function stake(
        bytes32 hotkey,
        uint256 netuid,
        uint256 amount
    ) external onlyOwner {
        // can't call precompile like this way, the call never go to runtime precompile
        //Staking(ISTAKING_ADDRESS).addStake(hotkey, amount, netuid);

        bytes memory data = abi.encodeWithSelector(
            Staking.addStake.selector,
            hotkey,
            amount,
            netuid
        );
        (bool success, ) = ISTAKING_ADDRESS.call{gas: gasleft()}(data);
        require(success, "addStake call failed");
    }

    function stakeLimit(
        bytes32 hotkey,
        uint256 netuid,
        uint256 limitPrice,
        uint256 amount,
        bool allowPartial
    ) external onlyOwner {
        // can't call precompile like this way, the call never go to runtime precompile
        // Staking(ISTAKING_ADDRESS).addStakeLimit(
        //     hotkey,
        //     amount,
        //     limitPrice,
        //     allowPartial,
        //     netuid
        // );

        bytes memory data = abi.encodeWithSelector(
            Staking.addStakeLimit.selector,
            hotkey,
            amount,
            limitPrice,
            allowPartial,
            netuid
        );
        (bool success, ) = ISTAKING_ADDRESS.call{gas: gasleft()}(data);
        require(success, "addStakeLimit call failed");
    }

    function removeStake(
        bytes32 hotkey,
        uint256 netuid,
        uint256 amount
    ) external onlyOwner {
        bytes memory data = abi.encodeWithSelector(
            Staking.removeStake.selector,
            hotkey,
            amount,
            netuid
        );
        (bool success, ) = ISTAKING_ADDRESS.call{gas: gasleft()}(data);
        require(success, "addStake call failed");
    }

    function removeStakeAndBurn(
        bytes32 hotkey,
        uint256 netuid,
        uint256 amount
    ) external onlyOwner {
        bytes memory data = abi.encodeWithSelector(
            Staking.removeStake.selector,
            hotkey,
            amount,
            netuid
        );

        (bool success, ) = ISTAKING_ADDRESS.call{gas: gasleft()}(data);
        require(success, "removeStake call failed");

        (bool burnSuccess, ) = payable(DEAD).call{value: amount}("");
        require(burnSuccess, "Burn failed");
    }



}