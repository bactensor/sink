#!/usr/bin/env python3
"""
CLI for calling: registerNeuron(uint16 netuid, bytes32 hotkey)
Updated with detailed Gas Price debugging and overrides.
"""

import argparse
import os
import sys
import json
from pathlib import Path

# Add the tools directory to sys.path
current_dir = Path(__file__).resolve().parent
if str(current_dir) not in sys.path:
    sys.path.append(str(current_dir))

from utils.contract_loader import get_web3_provider, load_contract

def main():
    parser = argparse.ArgumentParser(description="Batch register neuron helper")
    parser.add_argument("contract", help="SuperBurn contract address (EVM 0x...)")
    parser.add_argument("--netuid", required=True, type=int)
    parser.add_argument("--hotkey", required=True, help="Validator Hotkey (Hex 32 bytes e.g., 0x...)")
    parser.add_argument("--amount", required=True, type=float, help="Amount of TAO to burn for registration")
    parser.add_argument("--rpc-url", required=True)
    parser.add_argument("--private-key", default=None)
    # New argument to manually force gas price if RPC is crazy
    parser.add_argument("--force-gas-price-gwei", type=float, help="Force a specific Gas Price in Gwei (e.g., 100)")
    args = parser.parse_args()

    private_key = args.private_key or os.getenv("PRIVATE_KEY")
    if not private_key:
        raise SystemExit("Error: Set PRIVATE_KEY env var or pass --private-key")

    # 1. Setup Web3 & Account & Check Balance
    try:
        w3 = get_web3_provider(args.rpc_url)
        account = w3.eth.account.from_key(private_key)
        balance_wei = w3.eth.get_balance(account.address)
        balance_eth = w3.from_wei(balance_wei, 'ether')

        print(f"--- WALLET INFO ---")
        print(f"Address: {account.address}")
        print(f"Balance: {balance_eth:.6f} TestTAO")

        if balance_wei == 0:
            print("\n[!] CRITICAL ERROR: Your wallet has 0 Balance.", file=sys.stderr)
            sys.exit(1)

    except Exception as e:
        print(f"CRITICAL ERROR connecting to Web3: {e}", file=sys.stderr)
        sys.exit(1)

    # 2. Prepare Data (Hotkey & Amount)
    try:
        # Convert Hotkey Hex String to Bytes32
        if args.hotkey.startswith("0x"):
            hotkey_bytes32 = bytes.fromhex(args.hotkey[2:])
        else:
            hotkey_bytes32 = bytes.fromhex(args.hotkey)

        if len(hotkey_bytes32) != 32:
            raise ValueError(f"Hotkey must be 32 bytes, got {len(hotkey_bytes32)}")

        # Convert Amount to Wei (Rao)
        amount_wei = w3.to_wei(args.amount, 'ether')

        print(f"--- REGISTRATION DATA ---")
        print(f"NetUID: {args.netuid}")
        print(f"Hotkey: {args.hotkey}")
        print(f"Burn Amount: {args.amount} TAO ({amount_wei} Rao)")

    except ValueError as e:
        print(f"CRITICAL ERROR: Invalid input data: {e}", file=sys.stderr)
        sys.exit(1)

    # 3. Load Contract
    try:
        # Assumes the same folder structure as the previous script
        artifact_path = current_dir.parent / "out" / "SuperBurn.sol" / "SuperBurn.json"
        contract = load_contract(w3, args.contract, artifact_path)
    except Exception as e:
        print(f"CRITICAL ERROR loading contract: {e}", file=sys.stderr)
        sys.exit(1)

    # 4. Execute
    # UPDATED: Function signature is now registerNeuron(uint16 netuid, bytes32 hotkey)
    fn = contract.functions.registerNeuron(args.netuid, hotkey_bytes32)

    print("--- GAS & COST CALCULATION ---")
    try:
        # Estimate Gas Limit - NOTE: We must pass 'value' for accurate estimation
        gas_estimate = fn.estimate_gas({
            "from": account.address,
            "value": amount_wei
        })
        gas_limit = int(gas_estimate * 1.2) # 20% buffer
        print(f"Gas Limit (Estimated): {gas_limit}")

        # Get Gas Price
        if args.force_gas_price_gwei:
            gas_price = w3.to_wei(args.force_gas_price_gwei, 'gwei')
            print(f"Gas Price (FORCED):    {args.force_gas_price_gwei} Gwei")
        else:
            gas_price = w3.eth.gas_price
            print(f"Gas Price (Node):      {w3.from_wei(gas_price, 'gwei'):.2f} Gwei")

        # Calculate Total Cost (Gas + Burn Amount)
        gas_cost_wei = gas_limit * gas_price
        total_cost_wei = gas_cost_wei + amount_wei
        total_cost_eth = w3.from_wei(total_cost_wei, 'ether')

        print(f"Gas Cost (Max):        {w3.from_wei(gas_cost_wei, 'ether'):.6f} TAO")
        print(f"Burn Amount:           {args.amount:.6f} TAO")
        print(f"Total Required:        {total_cost_eth:.6f} TAO")

        if balance_wei < total_cost_wei:
            print(f"\n[!] ERROR: Insufficient funds (Gas + Burn Amount).")
            print(f"[!] Balance: {balance_eth} < Cost: {total_cost_eth}")
            print(f"[!] TIP: Try running with --force-gas-price-gwei 100")
            sys.exit(1)

    except Exception as exc:
        print(f"Gas estimation warning: {exc}. Using fallback.", file=sys.stderr)
        gas_limit = 500_000 # Standard fallback for complex calls
        gas_price = w3.to_wei(100, 'gwei')

    # FIX: Use 'pending' block to avoid "already known" nonce errors
    nonce = w3.eth.get_transaction_count(account.address, "pending")

    tx = fn.build_transaction({
        "from": account.address,
        "nonce": nonce,
        "gas": gas_limit,
        "gasPrice": gas_price,
        "chainId": w3.eth.chain_id,
        "value": amount_wei, # CRITICAL: Sending the TAO to be burned
    })

    print(f"Sending transaction (Nonce: {nonce})...")
    signed = w3.eth.account.sign_transaction(tx, private_key=private_key)

    try:
        tx_hash = w3.eth.send_raw_transaction(signed.raw_transaction)
        print(f"Sent tx: {tx_hash.hex()}")
    except Exception as e:
        print(f"Transaction failed locally: {e}")
        sys.exit(1)

    print("Waiting for receipt...")
    receipt = w3.eth.wait_for_transaction_receipt(tx_hash)

    if receipt["status"] == 1:
        print(f"SUCCESS! Block: {receipt['blockNumber']}, Gas Used: {receipt['gasUsed']}")
    else:
        print("FAILED!")
        # Try decoding revert
        try:
            tx_input = w3.eth.get_transaction(tx_hash)["input"]
            revert_data = w3.eth.call(
                {"to": receipt["to"], "from": receipt["from"], "data": tx_input, "value": amount_wei},
                block_identifier=receipt["blockNumber"]
            )
            print(f"Revert Reason (Hex): {revert_data.hex()}")
        except Exception as e:
            print(f"Could not decode revert: {e}")

if __name__ == "__main__":
    main()