#!/usr/bin/env python3
"""Fix a one-block mismatch in Wine 11.16's wow64_NtAllocateVirtualMemory.

A 32-bit top-down reservation can return 0x7fff0000, but committing that address is refused
because it's above highest_user_address (0x7ffeffff). The CLR reports this as
OutOfMemoryException, which makes 32-bit regasm.exe fail and SOLIDWORKS.msi return 1603.

Usage: wow64-commit-limit.py <wine source dir>
"""
import pathlib
import sys

path = pathlib.Path(sys.argv[1]) / "dlls" / "wow64" / "virtual.c"
code = path.read_text()
old = """    if (!addr && (type & MEM_COMMIT)) type |= MEM_RESERVE;
    if (*addr32 > highest_user_address) return STATUS_CONFLICTING_ADDRESSES;
"""
new = """    if (!addr && (type & MEM_COMMIT)) type |= MEM_RESERVE;
    if (*addr32 > 0x7fffffff) return STATUS_CONFLICTING_ADDRESSES;
"""
if code.count(old) != 1:
    sys.exit("expected exactly one match")
path.write_text(code.replace(old, new))
print("patched", path)
