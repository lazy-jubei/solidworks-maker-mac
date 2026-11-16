#!/usr/bin/env python3
"""List processes of this Wine installation that have files in this prefix."""
import os
import subprocess
import sys


def container_processes(prefix, runtime):
    prefix, runtime = (os.fsencode(os.path.realpath(path)) for path in (prefix, runtime))
    prefix_path, runtime_path = prefix + b'/', runtime + b'/'
    result = subprocess.run(['lsof', '-nP', '-u', str(os.geteuid()), '-F0pn'],
                            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    if result.returncode:
        return
    pid = None
    has_prefix = has_runtime = False
    # lsof separates fields with NUL and prefixes each process/file set with a newline.
    for field in result.stdout.split(b'\0'):
        field = field.lstrip(b'\n')
        if field.startswith(b'p'):
            pid = field[1:]
            has_prefix = has_runtime = False
        elif pid and field.startswith(b'n'):
            path = field[1:]
            has_prefix |= path == prefix or path.startswith(prefix_path)
            has_runtime |= path == runtime or path.startswith(runtime_path)
            if has_prefix and has_runtime:
                if pid.isdigit():
                    yield pid.decode('ascii')
                pid = None


if __name__ == '__main__':
    for process in container_processes(*sys.argv[1:]):
        print(process)
