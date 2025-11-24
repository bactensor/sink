#!/usr/bin/env python3
"""
Minimal CLI to call UnstakeV2Test.stake(hotkey, netuid, amountTao)
and print detailed info on failure.
"""
import argparse
import os
import json
from web3 import Web3

def main():
    parser = argparse.ArgumentParser(description="Minimal stake helper")
    parser.add_argument("contract", help="UnstakeV2Test contract address")
    parser.add_argument("--hotkey-bytes32", required=True, help="Hotkey as 32-byte hex string (0x...)")
    parser.add_argument("--netuid", required=True, type=int)
    parser.add_argument("--amount-tao", type=float, required=True, help="Amount of TAO to stake (e.g., 0.05)")
    parser.add_argument("--rpc-url", required=True)
    parser.add_argument("--private-key", default=None)
    args = parser.parse_args()

    private_key = args.private_key or os.getenv("PRIVATE_KEY")
    if not private_key:
        raise SystemExit("Set PRIVATE_KEY env var or pass --private-key")

    hotkey_bytes = bytes.fromhex(args.hotkey_bytes32.lower().removeprefix("0x"))
    if len(hotkey_bytes) != 32:
        raise SystemExit("Hotkey must be 32 bytes")

    w3 = Web3(Web3.HTTPProvider(args.rpc_url))
    if not w3.is_connected():
        raise SystemExit(f"Failed to connect to {args.rpc_url}")

    # Załaduj ABI kontraktu z pliku JSON (np. build/artifacts)
    abi_path = "UnstakeV2Test.json"
    try:
        abi = json.load(open(abi_path))["abi"]
    except Exception as e:
        raise SystemExit(f"Failed to load ABI from {abi_path}: {e}")

    contract = w3.eth.contract(address=Web3.to_checksum_address(args.contract), abi=abi)

    amount_rao = int(args.amount_tao * 1_000_000_000)  # TAO -> Rao
    account = w3.eth.account.from_key(private_key)
    fn = contract.functions.stake(hotkey_bytes, args.netuid, amount_rao)

    # Estymacja gazu
    try:
        gas_limit = fn.estimate_gas({"from": account.address, "value": 0})
    except Exception as exc:
        print(f"Gas estimation failed ({exc}); using fallback 500_000")
        gas_limit = 500_000

    tx = fn.build_transaction(
        {
            "from": account.address,
            "nonce": w3.eth.get_transaction_count(account.address),
            "value": 0,
            "gas": gas_limit,
            "gasPrice": w3.eth.gas_price,
            "chainId": w3.eth.chain_id,
        }
    )

    signed = w3.eth.account.sign_transaction(tx, account.key)
    tx_hash = w3.eth.send_raw_transaction(signed.raw_transaction)
    print(f"Sent tx: {tx_hash.hex()}")

    receipt = w3.eth.wait_for_transaction_receipt(tx_hash)
    success = receipt.get("status") == 1
    print(f"Status: {'SUCCESS' if success else 'FAILED'}")
    print(f"Gas used: {receipt['gasUsed']}")
    print(f"Block: {receipt['blockNumber']}")

    if not success:
        print("\n--- REVERT INFO ---")
        try:
            tx_data = w3.eth.get_transaction(tx_hash)
            revert_reason = w3.eth.call(
                {
                    "to": receipt["to"],
                    "from": receipt["from"],
                    "data": tx_data["input"],
                    "value": tx_data["value"],
                },
                block_identifier=receipt["blockNumber"],
            )
            print(f"Raw revert data: {revert_reason.hex()}")
        except Exception as exc:
            print(f"Could not get revert reason: {exc}")

    print("\n--- FULL RECEIPT ---")
    print(json.dumps(dict(receipt), default=str, indent=2))


if __name__ == "__main__":
    main()
