#!/usr/bin/env python3
"""Binary-patch wineserver (Gcenx wine-staging 11.16, x86_64 macOS) to fix a server crash
when a Wine process dies: "wineserver crashed, please enable coredumps", after which every
other program in the prefix (e.g. Altium) freezes for good.

Cause (found with an AddressSanitizer build of the same source; still present in upstream
master): wake_up() walks an object's wait queue and calls wake_thread() for each waiter.
If the waiting thread's process has already died (closed its main window, was killed, ...),
send_thread_wakeup() gets EPIPE writing the wakeup and calls kill_thread() on the spot.
For the last thread of a process that destroys the handle table, which can free the very
object wake_up() is iterating (here: the internal sync object of the dead thread's message
queue, signaled because another process posted a message to it). wake_up() then reads
freed memory and the server segfaults.

Fix: on EPIPE, send_thread_wakeup() just reports the failure (-1) and leaves the thread
alone. The dead client's closed request fd makes the main loop kill the thread moments
later, outside any wait-queue walk. This patch NOPs out that one kill_thread() call;
patches/0005-server-wakeup-epipe.patch is the same change in source form.

The result must be re-signed (ad hoc) before use: codesign -s - -f <out>

Usage: wineserver-wakeup-epipe.py <stock wineserver> <output wineserver>
"""
import shutil
import sys

# In send_thread_wakeup(), EPIPE branch:  mov rdi,rbx ; xor esi,esi ; call kill_thread
SITE = 0x47610                     # file offset (__TEXT vmaddr 0x100000000, fileoff 0)
OLD = bytes.fromhex("4889df" "31f6" "e8b60a0000" "eb55")
NEW = bytes.fromhex("4889df" "31f6" "0f1f440000" "eb55")   # 5-byte nop instead of the call
# The surrounding errno == EPIPE test, to make sure this is the right spot
CONTEXT = (0x4760B, bytes.fromhex("833820" "7541"))         # cmp dword [rax],0x20 ; jne


def main(src, dst):
    b = bytearray(open(src, "rb").read())
    if b[:4] != bytes.fromhex("cffaedfe"):
        raise SystemExit("not a 64-bit Mach-O file")
    at, ctx = CONTEXT
    if bytes(b[SITE:SITE + len(OLD)]) != OLD or bytes(b[at:at + len(ctx)]) != ctx:
        if bytes(b[SITE:SITE + len(NEW)]) == NEW:
            raise SystemExit("already patched")
        raise SystemExit("unexpected bytes; not the Gcenx wine-staging 11.16 wineserver")
    b[SITE:SITE + len(NEW)] = NEW
    open(dst, "wb").write(b)
    shutil.copymode(src, dst)
    print("patched %s (kill_thread on wakeup EPIPE removed); now run: codesign -s - -f %s" % (dst, dst))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    main(sys.argv[1], sys.argv[2])
