#!/usr/bin/env python3
"""Let IsWow64Process2 report the real ARM64 machine in Wine 11.16's dlls/kernelbase.

Under Rosetta, Wine reports native x64. JS0GROUP.dll has code that only continues for x64 on ARM64
(RVA 0x85b80), which is what an Apple Silicon Mac is. Only active when SW_REPORT_ARM64 is set.

Usage: kernelbase-report-arm64.py <wine source dir>
"""
import pathlib
import sys

path = pathlib.Path(sys.argv[1]) / "dlls" / "kernelbase" / "process.c"
code = path.read_text()
old = """    return set_ntstatus( RtlWow64GetProcessMachines( process, machine, native_machine ));
"""
new = """    NTSTATUS status = RtlWow64GetProcessMachines( process, machine, native_machine );

    if (!status && native_machine && *native_machine == IMAGE_FILE_MACHINE_AMD64
            && GetEnvironmentVariableW( L"SW_REPORT_ARM64", NULL, 0 ))
        *native_machine = IMAGE_FILE_MACHINE_ARM64;
    return set_ntstatus( status );
"""
if code.count(old) != 1:
    sys.exit("expected code not found")
path.write_text(code.replace(old, new))
print("patched", path)
