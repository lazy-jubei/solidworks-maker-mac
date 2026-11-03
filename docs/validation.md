# Validation

Tests ran on Apple M4 / macOS 15.7.9, Wine Staging 11.16, SOLIDWORKS Design
Professional for Makers 2026 SP4.0, R2026x HotFix 5.9. The original development
installation and a separate clean-prefix installation were used. These results
validate those installations; they do not establish a clean installation from
this published setup kit on another Mac.

| Check | Result |
| --- | --- |
| Official clean-prefix sign-in | Passed using the normal licensed account form |
| Finder shortcut | Main launch, sign-in and startup completed |
| FeatureManager | Visible with the opt-in GDI presentation driver |
| Part modeling | Rectangle, extrusion, depth edit, circular through-cut, suppression/restore, save/reopen passed |
| Final part volume | 0.000035536504591506382 m³, matching analytical geometry |
| Interactive input | Native mouse rectangle, typed 20 mm extrusion, committed solid, save/reopen volume matched in test prefix |
| Assembly | Two components, save/reopen; combined volume 0.000071073009183012764 m³ |
| Drawing/PDF | Front and isometric views, save/reopen, PDF export; complete unclipped views verified by rendering |
| GDI diagnostic | Upright image, overlays visible, resize passed, GL state preserved |
| Intel dashboard selection | Implemented and syntax checked; hardware untested |

![Part and feature tree](codex-operations-gdi-tree.png)

## Remaining limitations

- An earlier main-prefix legacy-setter dimension edit changed the parameter but
  incremental `EditRebuild3` retained the old body; a full rebuild produced the
  expected geometry. Later STA/SetSystemValue3 regressions pass with incremental
  rebuild only, but the intermittent earlier failure is not conclusively explained.
- Share-backed disk-image I/O can pause the application and helper commands.
- The native PropertyManager OK/Cancel capture failure has a scoped workaround; see
  [capture investigation](button-capture.md). Other UI commands and long-session stability need further testing.
  Earlier intermittent CEF-related document-creation crashes were not conclusively
  diagnosed, although repeated later untraced modeling checks passed.
- OpenGL-to-GDI readback costs performance. A COM rotation test is not a manual FPS
  benchmark; smooth manual interaction has not been comprehensively measured.
- The background sldProcMon process has crashed while CAD continued. The Wine crash
  dialog is disabled by the settings script.
- The Content pane can remain blank. Cloud PLM operations are unvalidated.
- First media download and end-to-end setup from this release are unverified.
  Finder auto-mount from an unmounted image is also untested.
- Complete Intel Mac CAD compatibility is untested. The architecture selection added
  for Intel applies to the dashboard Chrome launcher.
- Updates to Wine, WebView2 or SOLIDWORKS can invalidate the workarounds. The patchers
  are pinned to Wine 11.16; WebView2 may need browser-local DXMT reinstalled after updates.

Private account logs and model files are intentionally excluded from the repository.

## Setup-kit configuration checks

The old Fresh shortcut could inherit main storage/prefix values from local configuration.
The generated launcher now applies fresh selectors after reading shared account settings,
skips reloading main selectors, and refuses the main prefix/image. Functional checks run
the generated configuration code without mounting or starting Wine: custom main paths,
paths with spaces, default images, fresh isolation and collision refusal pass. The v0.1.0
builder fails the same isolation check. These checks do not establish a full
first-time installation or a Finder auto-mount test.

## Post-fix modeling check

The complete part sequence passed after the OK/Cancel fix, with STA, SetSystemValue3,
an active-document check and ordinary EditRebuild3. No ForceRebuild3 fallback ran.
The final through-cut model saved/reopened with volume 0.000035536504591506382 m³.
A separate native edit committed 70 mm with volume 0.000105 m³; native Cancel had
preserved the preceding 65 mm geometry. These results do not conclusively explain
the earlier intermittent legacy-setter automation failure.

![Post-fix saved model with visible feature tree](codex-capture-fixed-model.png)

The rebuild diagnostic also refused to run inside an active extrusion editor. The
sketch remained active afterwards, and a native Cancel restored the saved cut model
with matching volume. This prevents the previously observed diagnostic mistake of
forcing a rebuild while an extrusion preview is still pending.

## Edge features and STEP round trip

In the main installation, a copy of the saved 50 × 30 × 25 mm through-cut part
passed a 2 mm constant-radius edge fillet and a 2 mm, 45° edge chamfer, followed
by chamfer suppression/restore, incremental rebuild, native save and reopen.
Each stage matched its analytical volume within 1e-12 m³. The final native volume
was 0.000035393584224185866 m³. The fillet uses CreateDefinition/CreateFeature.

The same part passed STEP export/import, one-solid verification, native save and
reopen. Export/import/native save reported zero errors; saves reported zero
warnings. The final reopened volume was 0.000035393584224185873 m³, within the
same tolerance. These are specific regression models, not general file-format
or long-session compatibility guarantees.

The first imported-part Save As waited for a macOS Desktop-folder permission
prompt. After the user allowed it, the same running operation completed and the
part reopened with matching volume; no CAD/server restart was needed. A second
native save of the more complex import completed in about 1.7 seconds. Do not
treat time spent waiting for an unanswered OS prompt as CAD save performance.

See [reproducing the CAD checks](cad-checks.md).
