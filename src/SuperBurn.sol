// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @dev Address of the Bittensor Staking Precompile contract.
address constant STAKING_PRECOMPILE = 0x0000000000000000000000000000000000000805;

/// @dev Address of the Neuron Registration Precompile contract.
address constant NEURON_PRECOMPILE = 0x0000000000000000000000000000000000000804;

/// @dev Address where tokens are sent to be burned.
address constant BURN_ADDRESS = 0x0000000000000000000000000000000000000000;

interface Staking {
    function addStake(bytes32 hotkey, uint256 amount, uint256 netuid) external;
    function removeStake(bytes32 hotkey, uint256 amount, uint256 netuid) external;
}

contract SuperBurn {
    address public owner;

    /// @notice Emitted when stake is removed and burned.
    event UnstakedAndBurned(bytes32 indexed hotkey, uint256 amount, uint256 burnedAmount);

    /// @notice Emitted for every register call (success or fail).
    event RegisterAttempt(
        uint16 indexed netuid,
        bytes32 hotkey,
        address indexed caller,
        bool success
    );

    error NeuronRegistrationFailed();
    error RemoveStakeError();
    error BurnError();
    error RefundError();
    error ReceivedTaoIsZeroError();

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
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
            if (!success) {
                revert RemoveStakeError();
            }
        }

        uint256 totalReceivedTao = address(this).balance - balanceBeforeAll;
        if (totalReceivedTao < 0) {
            revert ReceivedTaoIsZeroError();
        }

        uint256 gasUsed = gasStart - gasleft();
        uint256 refundAmount = gasUsed * tx.gasprice;

        if (refundAmount > totalReceivedTao) {
            refundAmount = totalReceivedTao;
        }

        if (refundAmount > 0) {
            (bool refundSuccess, ) = payable(msg.sender).call{value: refundAmount}("");
            if (!refundSuccess) {
                revert RefundError();
            }
        }

        uint256 burnAmount = totalReceivedTao - refundAmount;

        if (burnAmount > 0) {
            (bool burnSuccess, ) = payable(BURN_ADDRESS).call{value: burnAmount}("");
            if (!burnSuccess) {
                revert BurnError();
            }
        }
    }

    /// @notice Registers a neuron using burned TAO.
    /// @param netuid Network UID.
    /// @param hotkey Hotkey to register.
    function registerNeuron(
        uint16 netuid,
        bytes32 hotkey
    ) external payable returns (bool) {
        bytes memory data = abi.encodeWithSelector(
            bytes4(keccak256("burnedRegister(uint16,bytes32)")),
            netuid,
            hotkey
        );

        (bool success, ) = NEURON_PRECOMPILE.call{value: msg.value, gas: gasleft()}(
            data
        );

        if (!success) {
            emit RegisterAttempt(netuid, hotkey, msg.sender, false);
            revert NeuronRegistrationFailed();
        }

        emit RegisterAttempt(netuid, hotkey, msg.sender, true);
        return true;
    }
}
