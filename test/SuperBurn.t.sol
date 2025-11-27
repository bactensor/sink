// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/SuperBurn.sol";
import "./Mocks.sol";

contract SuperBurnTest is Test {
    SuperBurn public superBurn;
    MockStaking public stakingMock;
    MockNeuron public neuronMock;
    RevertingReceiver public revertingReceiver;

    address constant STAKING_PRECOMPILE = 0x0000000000000000000000000000000000000805;
    address constant NEURON_PRECOMPILE = 0x0000000000000000000000000000000000000804;
    address constant BURN_ADDRESS = 0x0000000000000000000000000000000000000000;

    address owner = address(0xABCD);
    address user = address(0x1234);
    bytes32 hotkey = bytes32(uint256(1));
    uint256 netuid = 1;

    event StakeAdded(bytes32 indexed hotkey, uint256 amount, uint256 netuid);
    event UnstakedAndBurned(bytes32 indexed hotkey, uint256 amount, uint256 burnedAmount);
    event RegisterAttempt(uint16 indexed netuid, bytes32 hotkey, uint256 amountBurned, address indexed caller, bool success);

    function setUp() public {
        stakingMock = new MockStaking();
        neuronMock = new MockNeuron();

        bytes memory stakingCode = address(stakingMock).code;
        bytes memory neuronCode = address(neuronMock).code;

        vm.etch(STAKING_PRECOMPILE, stakingCode);
        vm.etch(NEURON_PRECOMPILE, neuronCode);

        vm.prank(owner);
        superBurn = new SuperBurn();

        vm.deal(owner, 1000 ether);
        vm.deal(user, 1000 ether);
        vm.deal(address(STAKING_PRECOMPILE), 10000 ether);
    }

    function test_OwnerIsSet() public view {
        assertEq(superBurn.owner(), owner);
    }

    function test_Receive_AcceptsFunds() public {
        vm.prank(user);
        (bool success, ) = address(superBurn).call{value: 10 ether}("");
        assertTrue(success);
        assertEq(address(superBurn).balance, 10 ether);
    }

    function test_Stake_Success() public {
        uint256 amount = 10 ether;
        vm.prank(owner);

        vm.expectEmit(true, false, false, true);
        emit StakeAdded(hotkey, amount, netuid);

        superBurn.stake{value: amount}(hotkey, netuid);

        assertEq(address(STAKING_PRECOMPILE).balance, 10000 ether + amount);
    }

    function testFuzz_Stake_Success(uint96 amount, uint16 fuzzNetuid, bytes32 fuzzHotkey) public {
        vm.assume(amount > 0);
        vm.prank(owner);

        vm.expectEmit(true, false, false, true);
        emit StakeAdded(fuzzHotkey, amount, fuzzNetuid);

        superBurn.stake{value: amount}(fuzzHotkey, fuzzNetuid);

        assertEq(address(STAKING_PRECOMPILE).balance, 10000 ether + amount);
    }

    function test_Stake_RevertIf_NotOwner() public {
        vm.prank(user);
        vm.expectRevert("Only owner can call this function");
        superBurn.stake{value: 1 ether}(hotkey, netuid);
    }

    function test_Stake_RevertIf_AmountZero() public {
        vm.prank(owner);
        vm.expectRevert("Amount must be greater than 0");
        superBurn.stake{value: 0}(hotkey, netuid);
    }

    function test_Stake_RevertIf_PrecompileFails() public {
        MockStaking(STAKING_PRECOMPILE).setShouldFail(true);

        vm.prank(owner);
        vm.expectRevert("addStake call failed");
        superBurn.stake{value: 1 ether}(hotkey, netuid);
    }

    function test_UnstakeAndBurn_Success_Single() public {
        bytes32[] memory hotkeys = new bytes32[](1);
        uint256[] memory amounts = new uint256[](1);
        hotkeys[0] = hotkey;
        amounts[0] = 5 ether;

        vm.expectEmit(true, false, false, true);
        emit UnstakedAndBurned(hotkey, 5 ether, 5 ether);

        superBurn.unstakeAndBurn(hotkeys, netuid, amounts);

        assertEq(BURN_ADDRESS.balance, 5 ether);
    }

    function test_UnstakeAndBurn_Success_Multiple() public {
        bytes32[] memory hotkeys = new bytes32[](2);
        uint256[] memory amounts = new uint256[](2);
        hotkeys[0] = bytes32(uint256(1));
        hotkeys[1] = bytes32(uint256(2));
        amounts[0] = 2 ether;
        amounts[1] = 3 ether;

        superBurn.unstakeAndBurn(hotkeys, netuid, amounts);

        assertEq(BURN_ADDRESS.balance, 5 ether);
    }

    function test_UnstakeAndBurn_MixedBatch_PartialBurn() public {
        bytes32[] memory hotkeys = new bytes32[](2);
        uint256[] memory amounts = new uint256[](2);
        hotkeys[0] = bytes32(uint256(1));
        hotkeys[1] = bytes32(uint256(2));
        amounts[0] = 1 ether;
        amounts[1] = 1 ether;

        superBurn.unstakeAndBurn(hotkeys, netuid, amounts);

        assertEq(BURN_ADDRESS.balance, 2 ether);
    }

    function test_UnstakeAndBurn_RevertIf_LengthMismatch() public {
        bytes32[] memory hotkeys = new bytes32[](1);
        uint256[] memory amounts = new uint256[](2);

        vm.expectRevert("Length mismatch");
        superBurn.unstakeAndBurn(hotkeys, netuid, amounts);
    }

    function test_UnstakeAndBurn_RevertIf_PrecompileFails() public {
        MockStaking(STAKING_PRECOMPILE).setShouldFail(true);

        bytes32[] memory hotkeys = new bytes32[](1);
        uint256[] memory amounts = new uint256[](1);
        hotkeys[0] = hotkey;
        amounts[0] = 1 ether;

        vm.expectRevert("removeStake call failed");
        superBurn.unstakeAndBurn(hotkeys, netuid, amounts);
    }

    function test_UnstakeAndBurn_NoBurnIfNoReceivedTao() public {
        vm.etch(STAKING_PRECOMPILE, address(0).code);

        bytes32[] memory hotkeys = new bytes32[](1);
        uint256[] memory amounts = new uint256[](1);
        hotkeys[0] = hotkey;
        amounts[0] = 1 ether;

        uint256 burnBalanceBefore = BURN_ADDRESS.balance;

        (bool success, ) = address(superBurn).call(
            abi.encodeWithSelector(SuperBurn.unstakeAndBurn.selector, hotkeys, netuid, amounts)
        );
        require(success);

        assertEq(BURN_ADDRESS.balance, burnBalanceBefore);
    }

    function test_BurnedRegisterNeuron_Success() public {
        uint256 amountToBurn = 1 ether;
        uint256 extra = 0.5 ether;

        vm.prank(user);
        vm.expectEmit(true, false, false, true);
        emit RegisterAttempt(uint16(netuid), hotkey, amountToBurn, user, true);

        bool result = superBurn.burnedRegisterNeuron{value: amountToBurn + extra}(
            uint16(netuid),
            hotkey,
            amountToBurn
        );

        assertTrue(result);
        assertEq(address(NEURON_PRECOMPILE).balance, amountToBurn);
        assertEq(user.balance, 1000 ether - amountToBurn);
    }

    function testFuzz_BurnedRegisterNeuron_Success(uint96 amountToBurn, uint96 extraAmount) public {
        vm.assume(amountToBurn > 0);
        uint256 totalToSend = uint256(amountToBurn) + uint256(extraAmount);
        vm.deal(user, totalToSend);

        vm.prank(user);
        bool result = superBurn.burnedRegisterNeuron{value: totalToSend}(
            uint16(netuid),
            hotkey,
            amountToBurn
        );

        assertTrue(result);
        assertEq(address(NEURON_PRECOMPILE).balance, amountToBurn);
        assertEq(user.balance, extraAmount);
    }

    function test_BurnedRegisterNeuron_Success_PreExistingBalance() public {
        vm.deal(address(superBurn), 10 ether);
        uint256 amountToBurn = 2 ether;

        vm.prank(user);
        bool result = superBurn.burnedRegisterNeuron{value: 0}(
            uint16(netuid),
            hotkey,
            amountToBurn
        );

        assertTrue(result);
        assertEq(user.balance, 1008 ether);
    }

    function test_BurnedRegisterNeuron_ExactAmount_NoRefundAttempt() public {
        uint256 amountToBurn = 1.5 ether;

        vm.prank(user);
        bool result = superBurn.burnedRegisterNeuron{value: amountToBurn}(
            uint16(netuid),
            hotkey,
            amountToBurn
        );

        assertTrue(result);
        assertEq(address(superBurn).balance, 0);
        assertEq(user.balance, 1000 ether - amountToBurn);
    }

    function test_BurnedRegisterNeuron_RevertIf_AmountZero() public {
        vm.expectRevert(SuperBurn.InsufficientValue.selector);
        superBurn.burnedRegisterNeuron(uint16(netuid), hotkey, 0);
    }

    function test_BurnedRegisterNeuron_RevertIf_InsufficientBalance() public {
        vm.expectRevert(SuperBurn.InsufficientValue.selector);
        superBurn.burnedRegisterNeuron{value: 0.5 ether}(uint16(netuid), hotkey, 1 ether);
    }

    function test_BurnedRegisterNeuron_PrecompileFail_RefundsFullAmount() public {
        MockNeuron(NEURON_PRECOMPILE).setShouldFail(true);
        uint256 amountToBurn = 1 ether;

        vm.prank(user);
        vm.expectEmit(true, false, false, true);
        emit RegisterAttempt(uint16(netuid), hotkey, amountToBurn, user, false);

        bool result = superBurn.burnedRegisterNeuron{value: amountToBurn}(
            uint16(netuid),
            hotkey,
            amountToBurn
        );

        assertFalse(result);
        assertEq(user.balance, 1000 ether);
    }

    function test_BurnedRegisterNeuron_RefundFail_Reverts() public {
        revertingReceiver = new RevertingReceiver();
        vm.deal(address(revertingReceiver), 10 ether);

        MockNeuron(NEURON_PRECOMPILE).setShouldFail(true);

        vm.prank(address(revertingReceiver));
        vm.expectRevert(SuperBurn.RefundFailed.selector);
        superBurn.burnedRegisterNeuron{value: 1 ether}(
            uint16(netuid),
            hotkey,
            1 ether
        );
    }

    function test_BurnedRegisterNeuron_SuccessButRefundFails_Reverts() public {
        revertingReceiver = new RevertingReceiver();
        vm.deal(address(revertingReceiver), 10 ether);
        uint256 amountToBurn = 1 ether;
        uint256 extra = 0.5 ether;

        vm.prank(address(revertingReceiver));
        vm.expectRevert(SuperBurn.RefundFailed.selector);

        superBurn.burnedRegisterNeuron{value: amountToBurn + extra}(
            uint16(netuid),
            hotkey,
            amountToBurn
        );
    }

    function test_Constants_AreCorrect() public view {
        address constant_burn = address(0);
        assertEq(BURN_ADDRESS, constant_burn);
    }


    function test_Exploit_DrainFunds_OnFailure() public {
        vm.deal(address(superBurn), 100 ether);

        uint256 attackerStartBalance = user.balance;
        uint256 amountToBurn = 10 ether;

        MockNeuron(NEURON_PRECOMPILE).setShouldFail(true);

        vm.prank(user);

        superBurn.burnedRegisterNeuron{value: 0}(
            uint16(netuid),
            hotkey,
            amountToBurn
        );

        assertEq(address(superBurn).balance, 0);
        assertEq(user.balance, attackerStartBalance + 100 ether);
    }
}