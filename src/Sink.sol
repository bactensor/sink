// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @dev Address of the Bittensor Staking Precompile contract.
address constant STAKING_PRECOMPILE = 0x0000000000000000000000000000000000000805;

/// @dev Address where tokens are sent to be burned.
address constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

interface Staking {
    function addStake(bytes32 hotkey, uint256 amount, uint256 netuid) external;
    function removeStake(bytes32 hotkey, uint256 amount, uint256 netuid) external;
}

contract Sink {
    address public owner;

    /// @notice Emitted when the owner adds stake.
    event StakeAdded(bytes32 indexed hotkey, uint256 amount, uint256 netuid);

    /// @notice Emitted when stake is removed and burned.
    event UnstakedAndBurned(bytes32 indexed hotkey, uint256 amount, uint256 burnedAmount);

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    /// @notice Allows the contract to receive TAO.
    receive() external payable {}

    /// @notice Stakes TAO to a validator. Only the owner can call this.
    /// @param hotkey The validator's hotkey (32 bytes).
    /// @param netuid The network UID (e.g., 1 for root).
    /// @param amount The amount of Rao to stake.
    function stake(
        bytes32 hotkey,
        uint256 netuid,
        uint256 amount
    ) external onlyOwner {
        bytes memory data = abi.encodeWithSelector(
            Staking.addStake.selector,
            hotkey,
            amount,
            netuid
        );

        (bool success, ) = STAKING_PRECOMPILE.call{gas: gasleft()}(data);
        require(success, "addStake call failed");

        emit StakeAdded(hotkey, amount, netuid);
    }

    /// @notice Unstakes TAO from validators and immediately burns it.
    /// @dev This function is open to everyone. Anyone can trigger the burn mechanism.
    /// @param hotkeys Array of validator hotkeys to unstake from.
    /// @param netuid The network UID.
    /// @param amounts Array of amounts (in Rao) to unstake corresponding to hotkeys.
    function unstakeAndBurn(
        bytes32[] calldata hotkeys,
        uint256 netuid,
        uint256[] calldata amounts
    ) external {
        require(hotkeys.length == amounts.length, "Length mismatch");

        uint256 gasStart = gasleft();
        uint256 balanceBeforeAll = address(this).balance;

        for (uint256 i = 0; i < hotkeys.length; i++) {

            // 1. Call removeStake on the precompile
            bytes memory data = abi.encodeWithSelector(
                Staking.removeStake.selector,
                hotkeys[i],
                amounts[i],
                netuid
            );

            (bool success, ) = STAKING_PRECOMPILE.call(data);
            require(success, "removeStake call failed");
        }

        uint256 totalReceivedTao = address(this).balance - balanceBeforeAll;
        require(totalReceivedTao > 0, "No TAO received");

        uint256 gasUsed = gasStart - gasleft();
        uint256 refundAmount = gasUsed * tx.gasprice;

        if (refundAmount > totalReceivedTao) {
            refundAmount = totalReceivedTao;
        }

        if (refundAmount > 0) {
            (bool refundSuccess, ) = payable(msg.sender).call{value: refundAmount}("");
            require(refundSuccess, "Gas refund failed");
        }

        uint256 burnAmount = totalReceivedTao - refundAmount;

        if (burnAmount > 0) {
            (bool burnSuccess, ) = payable(BURN_ADDRESS).call{value: burnAmount}("");
            require(burnSuccess, "Burn failed");
        }
    }
}