# PropertyManager confirmation capture workaround

A native mouse click on the extrusion PropertyManager's green OK button could leave
it pressed and the edit open. A typed depth was visible in the preview but had not
been committed. Cancel showed the same problem.

A bounded, mouse-only hook on the CAD UI thread confirmed that both WM_LBUTTONDOWN
and WM_LBUTTONUP arrived. Between them, the button received WM_CAPTURECHANGED to
itself, followed by a release. It retained pushed/focus state but produced no
BN_CLICKED notification. Sending the ordinary notification directly completed the
edit and produced the expected geometry; that was diagnostic recovery, not the fix.

The Wine v6 button implementation calls SetCapture during mouse-down even when
SolidWorks' tracking already captured that button. This interaction cancels its
pressed state before release. The workaround skips that redundant internal capture
only when all of these conditions hold:

- The executable is sldworks.exe.
- The control ID is 4900 (OK) or 4903 (Cancel), as observed in the tested UI.
- The same button already owns mouse capture.
- SW_BUTTON_CAPTURE_GUARD is 1.

It changes no global SetCapture behavior, performs no external button clicks and
changes no CAD geometry. It is a scoped compatibility workaround, not a claim about
every detail of the native Windows control implementation.

The launch script automatically enables the guard only when the library and prefix DLL both match
the installed build marker. `SW_BUTTON_CAPTURE_GUARD=0` disables it for comparison.
`build-shell32.sh` applies it to new builds; `build-button-capture.sh` updates an
existing configured Wine 11.16 build, after the selected prefix has stopped. Originals
are backed up as `.before-button-capture`. Save and exit CAD before stopping its server.

## Validation

On the tested Apple M4 setup, using normal feature commands, native mouse events and
numeric keyboard input, with no automatic confirmation helper:

| Configuration | Result |
| --- | --- |
| Original behavior | Repeated OK clicks left the editor open for the 60-second observation |
| Guard enabled | 45 to 50 mm and 50 to 55 mm edits committed; exact volumes matched |
| Same DLL, guard disabled | 55 to 60 mm edit stayed open for 60 seconds |
| Guard restored through normal Finder shortcut | 60 to 65 mm edit committed; volume 0.0000975 m³ |
| Initial incomplete Cancel scope | Native Cancel stayed open; inspection identified its actual ID as 4903 |
| Corrected Cancel scope | Preview change to 70 mm cancelled; prior 65 mm depth and volume preserved |
| Corrected DLL, normal Finder shortcut | Subsequent native OK committed 70 mm; volume 0.000105 m³ |

The initial prototype included the wrong Cancel ID, 4901; the source patcher upgrades
that prototype to 4903. The corrected DLL was built and installed with backups and
validated through the normal Finder shortcut. The optional diagnostic trace captures
mouse/focus and confirmation messages only, no keyboard text, and unhooks after 35 seconds.

Further checks are recorded in [validation](validation.md). Private account/session
logs and compiled diagnostic DLLs are excluded from the release.

Implementation references: [Wine 11.16 v6 button source](https://github.com/wine-mirror/wine/blob/wine-11.16/dlls/comctl32_v6/button.c),
[Microsoft WM_CAPTURECHANGED documentation](https://learn.microsoft.com/en-us/windows/win32/inputdev/wm-capturechanged).
