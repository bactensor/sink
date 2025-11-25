from __future__ import annotations

import base58
import hashlib

def ss58_to_pub32(ss58_address: str, as_hex: bool = True) -> str | bytes:
    """
    Convert SS58 address to raw 32-byte public key (Pub32).

    Parameters:
        ss58_address: str - SS58 address
        as_hex: bool - If True, returns hex string with '0x'. If False, returns bytes.

    Returns:
        str (hex) or bytes
    """
    # Decode Base58
    data = base58.b58decode(ss58_address)

    # Determine prefix length and extract pubkey
    if data[0] < 64:
        prefix = data[:1]
        pubkey = data[1:33]
        checksum = data[33:35]
    else:
        prefix = data[:2]
        pubkey = data[2:34]
        checksum = data[34:36]

    # Verify checksum
    h = hashlib.blake2b(b'SS58PRE' + prefix + pubkey, digest_size=64).digest()
    if checksum != h[:2]:
        raise ValueError("Invalid SS58 checksum")

    if as_hex:
        return '0x' + pubkey.hex()
    else:
        return pubkey