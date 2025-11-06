#!/bin/bash

# PRIVATE_KEY needs to be exported with 0x-prefixed private key

export BITTENSOR_RPC_URL="https://test.chain.opentensor.ai"

forge script script/Deploy.s.sol:Deploy --rpc-url $BITTENSOR_RPC_URL --broadcast  --chain-id 945
