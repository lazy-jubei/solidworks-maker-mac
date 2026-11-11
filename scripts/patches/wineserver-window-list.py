#!/usr/bin/env python3
"""Stop sibling enumeration at a window unlinked during WM_NCDESTROY.

Pinned to Gcenx Wine Staging 11.16 for x86-64 macOS. The server's
get_window_list() advances from a window on the unlinked list using the
Z-order list's sentinel. This can loop indefinitely. Keep the first window
in the result, and advance only if its is_linked bit is set.
"""
from pathlib import Path
import shutil
import sys

# These addresses are file offsets in the Mach-O __TEXT segment.
# Redirect the existing alignment padding to the list traversal's exit.
PATCHES = (
    (0x66EC9, "0f1f8000000000", "e98afeffff6690"),
    (
        0x66ED5,
        "488b4e48 488b5678 4883c158 4839ca 480f44d0 488d7288 4885d2 0f8463feffff",
        # if (!child->is_linked) goto exit;
        # if (child->entry.next == &child->parent->children) goto exit;
        # child = LIST_ENTRY(child->entry.next, struct window, entry);
        "f6860801000001 74eb 488b4e48 488b5678 4883c158 4839ca 74da 488d7288 6690",
    ),
)


def main(source, output):
    binary = bytearray(source.read_bytes())
    if binary[:8] != bytes.fromhex("cffaedfe07000001"):
        sys.exit("Expected an x86-64 Mach-O wineserver")
    for offset, original, replacement in PATCHES:
        original, replacement = bytes.fromhex(original), bytes.fromhex(replacement)
        assert len(original) == len(replacement)
        data = binary[offset:offset + len(original)]
        if data != original and data != replacement:
            sys.exit("Unexpected window enumeration code in wineserver")
        binary[offset:offset + len(original)] = replacement
    output.write_bytes(binary)
    shutil.copymode(source, output)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("Usage: wineserver-window-list.py <input wineserver> <output wineserver>")
    main(*map(Path, sys.argv[1:]))
