from substrateinterface.utils.ss58 import ss58_decode

ss58 = "5ETsYe7MLH6Mf9xAMgrLhYL2K1fQXBzn7g7bFHXRgFP3FZvT"
bytes32_hex = hex(int.from_bytes(ss58_decode(ss58), "big"))
print(bytes32_hex)
