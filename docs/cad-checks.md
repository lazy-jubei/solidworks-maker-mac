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

The part, edge and STEP helpers use STA and late-bound COM. Timed API calls exclude console-log writes;
redirect logs to a local temporary file when investigating performance. macOS
may request Desktop or volume access during file operations. Complete those
prompts yourself before interpreting an apparent save freeze.

## Assembly and drawing checks

With the saved edge-test part, create a new assembly and drawing/PDF pair:

```zsh
wine "$VOL/tools/SwDocumentOps.exe" \
  'C:\users\Public\Documents\cad-check-edges.SLDPRT' \
  'C:\users\Public\Documents\cad-check-documents'
wine "$VOL/tools/SwAssemblyOps.exe" \
  'C:\users\Public\Documents\cad-check-documents.SLDASM' \
  'C:\users\Public\Documents\cad-check-assembly-edit.SLDASM'
```

The document check inserts two instances, checks their combined volume, saves
and reopens the assembly, creates front/isometric drawing views, checks their
bounds and count, exports PDF, and reopens the drawing. It refuses a stem when
any assembly, drawing or PDF output already exists. Render the PDF to inspect
its actual layout; a successful export or file header check is insufficient.

The assembly-edit check requires a saved assembly with two instances of the same
part and standard English Front Plane names. It refuses dirty open documents,
saves a new assembly copy, fixes the lower-X component, floats the other, moves
it 20 mm in X, then adds a 40 mm distance mate between their front planes. It
checks component transforms, combined volume, suppression/restore, native save
and reopen, and mate persistence. One distance mate leaves other degrees of
freedom; this is not a fully constrained assembly test. `AddMate5` status is
checked against `swAddMateError_NoError`, whose value is 1.

`build-cad-checks.sh` compiles the edge, STEP, assembly-edit and revolve helpers. The
document helper comes from `build-signin-tools.sh` and retains its original
threading behavior; the helpers built by `build-cad-checks.sh` use STA. Their timed API calls
exclude log-writing time.

## Revolve, body pattern and undo/redo

Create a blank part through the normal New Document dialog. Inspect its title
with `wine "$VOL/tools/SwInteractive.exe" status`, then pass that exact title:

```zsh
wine "$VOL/tools/SwRevolveOps.exe" 'Part1' \
  'C:\users\Public\Documents\cad-check-revolve.SLDPRT'
```

Replace `Part1` with the observed new title. This helper requires the active
document to be an untitled, clean part with no solid, Sketch1 or active sketch;
it refuses an existing output and expects standard English plane/sketch names.
It creates a rectangle and centreline, revolves
360 degrees, checks one hollow cylinder and saves a checkpoint. It then creates
a three-body linear pattern at 60 mm spacing, checks undo/redo and suppression/
restore, and saves/reopens the result. Direction and seed references use marked
selection before CreateDefinition. The build script also compiles this helper.

Each ring has 20 mm outer radius, 10 mm inner radius and 30 mm length, so its
volume is `π × (0.02² − 0.01²) × 0.03` m³. Checks cover body count, individual
volume, centres and 60 mm placement, using 1e-12 m³ volume and 1e-8 m position
tolerances. The helper verifies its saved test part is still active before
session-wide undo, redo and incremental rebuild calls.
