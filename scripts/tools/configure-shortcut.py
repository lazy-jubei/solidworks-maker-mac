#!/usr/bin/env python3
"""Read the installed Shell Link arguments into the private local configuration."""
from pathlib import Path
import os
import re
import shlex
import struct
import sys
from urllib.parse import urlsplit


def settings(data):
    def uint(offset):
        return struct.unpack_from('<I', data, offset)[0]

    if uint(0) != 0x4c or data[4:20] != bytes.fromhex('0114020000000000c000000000000046'):
        raise ValueError('Invalid Windows shortcut')
    flags = uint(20)
    offset = 76
    if flags & 1:  # LinkTargetIDList
        offset += 2 + struct.unpack_from('<H', data, offset)[0]
    if flags & 2:  # LinkInfo
        offset += uint(offset)
    arguments = None
    for bit in (4, 8, 16, 32, 64):
        if not flags & bit:
            continue
        count = struct.unpack_from('<H', data, offset)[0]
        offset += 2
        length = count * (2 if flags & 128 else 1)
        if offset + length > len(data):
            raise ValueError('Truncated Windows shortcut')
        value = data[offset:offset + length].decode('utf-16-le' if flags & 128 else 'cp1252')
        offset += length
        if bit == 32:
            arguments = value
    if arguments is None:
        raise ValueError('Shortcut has no launch arguments')
    tenant = re.search(r'-tenant=([A-Za-z0-9_-]+)(?=[\s"\']|$)', arguments)
    registry = re.search(r'-3DRegistryURL=(https://[^\s"\']+)', arguments)
    if not tenant or not registry:
        raise ValueError('Shortcut is missing tenant or registry settings')
    url = urlsplit(registry[1])
    if not url.hostname or not url.hostname.endswith('.3dexperience.3ds.com') or url.username or url.password:
        raise ValueError('Shortcut registry is not a 3DEXPERIENCE registry')
    return tenant[1], registry[1]


def configure(shortcut, config):
    tenant, registry = settings(shortcut.read_bytes())
    previous = config.read_text() if config.exists() else ''
    # Retain storage selectors and any other local customizations.
    previous = re.sub(r'(?m)^(?:export\s+)?SW_(?:TENANT|REGISTRY)=.*\n?', '', previous)
    content = previous.rstrip() + '\n' + ''.join(
        f'export {key}={shlex.quote(value)}\n'
        for key, value in [('SW_TENANT', tenant), ('SW_REGISTRY', registry)])
    # Private file: no account settings are printed or committed.
    with config.open('w') as output:
        os.chmod(config, 0o600)
        output.write(content)


if __name__ == '__main__':
    try:
        configure(Path(sys.argv[1]), Path(sys.argv[2]))
    except (ValueError, UnicodeError, struct.error, OSError):
        sys.exit('Could not read SOLIDWORKS account settings from the installed desktop shortcut.')
