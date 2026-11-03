#!/usr/bin/env python3
"""Refuse a runtime replacement while this Wine bundle's server is running."""
import os
import subprocess
import sys
wanted = os.path.realpath(sys.argv[1])
for command in subprocess.check_output(['ps','-axo','comm='],text=True).splitlines():
    command=command.strip()
    if os.path.basename(command)=='wineserver' and os.path.realpath(command)==wanted:
        sys.exit('Save and close applications, then stop this Wine prefix before replacing its runtime.')
