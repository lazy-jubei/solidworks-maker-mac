# CAD regression checks

Run these only after installing SOLIDWORKS and signing in. Save all open documents
first. The checks create local test files and leave their saved documents open.
They do not test PLM. Choose new output paths for every run.

Compile the ordinary helpers with `scripts/build-signin-tools.sh`, then compile
the edge and STEP checks with `scripts/build-cad-checks.sh`. The latter locates
the installed API constants assembly; if multiple installations exist, set
`SW_SWCONST_DLL` to the macOS path of the intended `SolidWorks.Interop.swconst.dll`.
It compiles helpers without starting a CAD regression.

With CAD running, use a shell from this checkout:

```zsh
source scripts/env.sh
wine "$VOL/tools/SwOperations.exe" \
  'C:\users\Public\Documents\cad-check-base.SLDPRT'
wine "$VOL/tools/SwEdgeOps.exe" \
  'C:\users\Public\Documents\cad-check-base.SLDPRT' \
  'C:\users\Public\Documents\cad-check-edges.SLDPRT'
wine "$VOL/tools/SwExportOps.exe" \
  'C:\users\Public\Documents\cad-check-edges.SLDPRT' \
  'C:\users\Public\Documents\cad-check-step'
```

Run commands individually and check each exits zero before continuing. The base
check creates a 50 × 30 × 25 mm box with a central 10 mm through-hole; its volume
is `(0.05 × 0.03 − π × 0.005²) × 0.025` m³. The edge check requires that geometry,
saves a separate copy before editing, and refuses dirty open documents. It finds
the target 50 mm edges by their endpoints. A 2 mm fillet removes
`0.05 × 0.002² × (1 − π/4)` m³, and a separate 45° chamfer removes
`0.05 × 0.002² / 2` m³. It checks these volumes, suppression/restore and reopen.

The STEP check requires its specified source to be the active, saved part, with
no active sketch. It refuses existing outputs. It verifies solid/cylinder STEP
entities, one imported solid, matching volume, native save and reopened path.
All three checks use a volume tolerance of 1e-12 m³ and refuse existing output
files. Build the current helpers before using them; older base-helper versions
could overwrite an existing output.

The helpers use STA and late-bound COM. API timings exclude console-log writes;
redirect logs to a local temporary file when investigating performance. macOS
may request Desktop or volume access during file operations. Complete those
prompts yourself before interpreting an apparent save freeze.
