# Changelog

## v0.1.1

- Fix native PropertyManager OK/Cancel mouse clicks with a scoped Wine v6 capture guard.
  Enable automatically only for a matching installed library/prefix DLL pair.
- Keep Fresh shortcut storage and prefix selectors separate from main configuration,
  with functional checks and refusal of shared main prefix/image paths.
- Use STA and the current dimension setter in the part regression; require an ordinary
  incremental rebuild without a forced-rebuild fallback.
- Add read-only extrusion-commit observation and bounded mouse/focus diagnostics.

## v0.1.0

Initial experimental source/setup release for SOLIDWORKS Makers 2026 on Apple Silicon.

- Wine Staging 11.16 compatibility patches for installation, licensing startup,
  official account sign-in and WebView2.
- Browser-local DXMT and bounded targeted login-window helpers.
- Mac OpenGL/GDI presentation driver restoring the FeatureManager tree.
- Portable checkout/configuration paths and locally bundled Finder launch scripts.
- Dashboard Chrome for Testing selection for Apple Silicon and Intel Macs.
- CAD regression sources covering parts, assemblies, drawings and PDF export.
- Validation notes and remaining rebuild, I/O, stability and platform limitations.

Source only. No proprietary installers, account sessions or prebuilt runtime.
