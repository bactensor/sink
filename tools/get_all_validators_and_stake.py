import json
import subprocess
import sys
import argparse

# ss58_to_pub32.py
from ss58_to_pub32 import ss58_to_pub32

# Parse command-line arguments
parser = argparse.ArgumentParser(description="Fetch stake info and optionally unstake/burn.")
parser.add_argument("--coldkey", required=True, help="Coldkey SS58 address")
parser.add_argument("--netuid", type=int, required=True, help="Network UID")
parser.add_argument("--rpc-url", required=True, help="RPC URL")
parser.add_argument("--private-key", required=True, help="Private key for signing transactions")
parser.add_argument("--unstake", action="store_true", help="If set, perform unstake and burn")
args = parser.parse_args()

COLDKEY = args.coldkey
NETUID = args.netuid
RPC_URL = args.rpc_url
PRIVATE_KEY = args.private_key

# Fetch stake information
cmd = [
    "btcli", "stake", "list",
    "--network", "test",
    "--ss58", COLDKEY,
    "--json-out"
]

result = subprocess.run(cmd, capture_output=True, text=True)
if result.returncode != 0:
    print("Error fetching stake info:", result.stderr)
    sys.exit(1)

data = json.loads(result.stdout)

hotkeys = list(data.get("stake_info", {}).keys())

# Calculate total stake for each hotkey and convert SS58 to pub32
amounts = []
pub32_list = []
for hk in hotkeys:
    stake_entries = data.get("stake_info", {}).get(hk, [])
    total_value = sum(entry.get("stake_value", 0) for entry in stake_entries)
    amounts.append(total_value)

    # Konwersja SS58 do pub32
    try:
        pub32 = ss58_to_pub32(hk)
    except ValueError as e:
        print(f"Error converting {hk} to pub32: {e}")
        pub32 = None
    pub32_list.append(pub32)

print(f"Hotkeys (validators): {hotkeys}")
print(f"Pub32 addresses: {pub32_list}")
print(f"Amounts to unstake: {amounts}")