# Technical notes

Implementation details and development commands for this setup kit.

## Compatibility changes

- Wine shell32 ZIP extraction/file-copy support, installer/service fixes, licensing
  architecture reporting, a small ntdll forwarder, and Rosetta mode-switch fixes.
- Correct Cookie2 API behavior and opt-in Medium integrity reporting restricted to
  the login host/browser's Limited tokens. CAD and elevated services keep their
  original integrity report. Sign-in uses the normal licensed vendor path.
- Browser-local DXMT v0.80 supplies WebView2's required D3D feature level. CAD keeps
  its original D3D libraries. Software browser flags include `--no-sandbox`, a
  compatibility compromise; use this prefix for trusted vendor software.
- Opt-in OpenGL presentation through GDI restores FeatureManager visibility without
  moving CAD child windows. The launch script enables it only when the installed
  driver matches its build marker. Synchronous readback can affect performance.
- A bounded helper cancels the spurious HTTP Basic prompt for the tested Makers
  IAM host and detaches the official login browser window. It does not read credentials.
- A scoped v6 button capture guard fixes native PropertyManager OK/Cancel clicks;
  see [capture investigation](button-capture.md).
- The optional PLM Services add-in is disabled. Local CAD is the validated focus.

Do not run two Launcher prefixes simultaneously: both use TCP port 20250. Do not
launch `SLDWORKS.exe` directly; the official CATSTART/platform context is required.
The old `SwViewportFix` is diagnostic only and never starts automatically: external
viewport resizing caused sketch crashes.

## Development and release

`scripts/build-signin-tools.sh` compiles the x64 Win32 and COM helper sources.
The tools act on visible windows or the active SolidWorks API session; save your
work before running regressions. `SwOperations` creates a new part and checks
extrusion, depth edit, cut, suppression and save/reopen volumes. `SwDocumentOps`
checks an assembly, drawing and PDF export. See their source headers for arguments.

`python3 scripts/check-release.py` checks syntax, tracked paths and publication
content. `scripts/make-release.sh v0.1.1` packages the committed source with SHA256SUMS.
This release contains no compiled Wine modules. Rebuilding uses pinned Wine 11.16
source and patchers; preserve originals and use a separate prefix for experiments.

Licensed under LGPL-2.1-or-later, with upstream exceptions/notices documented in
[THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md) and [LICENSE](../LICENSE).
