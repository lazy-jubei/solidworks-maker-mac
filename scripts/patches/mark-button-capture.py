#!/usr/bin/env python3
"""Mark a matching library/prefix pair that contains the opt-in capture guard."""
from pathlib import Path
import hashlib
import sys
library,prefix=map(Path,sys.argv[1:])
data=library.read_bytes()
if 'SW_BUTTON_CAPTURE_GUARD'.encode('utf-16-le') not in data:
    sys.exit('Capture guard is absent from the built DLL; not enabling it')
if prefix.read_bytes()!=data:
    sys.exit('Library/prefix DLLs differ; not enabling the capture guard')
marker=library.with_name(library.name+'.capture.sha256')
tmp=marker.with_name(marker.name+'.new')
tmp.write_text(hashlib.sha256(data).hexdigest()+'\n')
tmp.replace(marker)
print('Marked matching capture-guard runtime')
