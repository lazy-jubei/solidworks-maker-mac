# solidworks-maker-mac

Run **SOLIDWORKS Design Professional for Makers 2026** on macOS using Wine Staging
11.16, without CrossOver or XQuartz. This is an experimental compatibility project,
independent of Dassault Systèmes.

Validated on an **Apple M4, macOS 15.7.9**, with R2026x HotFix 5.9 / 2026 SP4.0:
normal account sign-in, local part modeling, a two-component assembly, drawing views,
and PDF export. Save/reopen checks verified geometry volumes. See
[validation and limitations](docs/validation.md).

![Saved drawing in the main installation](docs/codex-main-drawing.png)

## What this release contains

Setup/build scripts, Wine source patchers, targeted sign-in helpers and CAD regression
sources. **No SOLIDWORKS media, account data, Wine prefixes or prebuilt Wine runtime
are included.** You need your own Makers subscription and official installers.
This is a setup kit, not a one-click installer.

The complete first-time installation and first media download have not been tested
from this published kit. An empty-prefix offline installation and official sign-in
were tested during development. Some setup steps remain manual.

## Requirements

- Apple Silicon Mac with Rosetta 2; Xcode Command Line Tools, Python 3 and Homebrew
  `bison` and `cabextract`.
- Space for a 200 GB dynamically growing HFS+ sparsebundle. Only used space is
  allocated; the application media and build tree consume tens of GB.
- Your own 3DEXPERIENCE Makers dashboard and SOLIDWORKS license.

The dashboard browser launcher also selects native **Intel mac-x64** Chrome.
Intel hardware was not tested; the complete Wine/CAD path is supported here only
as an Apple Silicon experiment. Browser selection is not full Intel CAD support.

## Configure

Keep this checkout in a stable, writable location. The scripts use its directory
rather than a developer-specific network share. Local storage is recommended for
responsiveness; share-backed sparsebundles can pause during I/O.

```sh
cp config.example.zsh config.local.zsh
```

Edit `config.local.zsh`: set `SW_TENANT` and `SW_REGISTRY` from your own installed
SOLIDWORKS Design desktop shortcut. Optional `SW_IMAGE`, `SW_VOL` and `SW_PREFIX`
choose storage locations. Do not put passwords in this file. It is excluded from Git
and release packages. The default image is `swwine.sparsebundle` in this checkout,
mounted at `/Volumes/SWWine`.

## Install

Run from the checkout root, in order. Save and close all applications using the
selected Wine bundle before replacing its DLLs or stopping its server.

```sh
scripts/01-storage.sh
scripts/02-wine.sh
scripts/03-prefix.sh
# No Launcher service is installed yet, so stop this prefix before building.
( source scripts/env.sh; wineserver -k; wineserver -w )
scripts/build-shell32.sh
scripts/install-ntdll-shim.sh
scripts/build-mac-gdi.sh
```

Obtain `3DEXPERIENCELauncher.msi` from your own official dashboard and save it as
`cache/installers/3DEXPERIENCELauncher.msi`. The dashboard hides Install on macOS.
This helper downloads **unmodified Chrome for Testing** for the native Mac CPU,
uses a temporary profile, and applies a Windows user agent plus a bundled identity
extension scoped to the 3DEXPERIENCE website:

```sh
scripts/open-dashboard.sh 'https://YOUR-OFFICIAL-DASHBOARD-URL'
```

It does not alter your usual Chrome profile. Alternatively, configure a Windows
Chrome user-agent switcher in your own browser. The browser helper requires the
mounted image because its temporary profile lives there.

```sh
scripts/04-launcher.sh
scripts/05-webview2.sh
scripts/06-settings.sh
( source scripts/env.sh; wineserver -k; wineserver -w )
scripts/install-dxmt.sh
scripts/build-signin-tools.sh
```

Use the dashboard to install SOLIDWORKS. The Launcher may ask you to trust your
platform URL; check it matches your dashboard. The dashboard-to-installer workflow
is still experimental. `07-install-offline.sh` is an alternative for users who
already have saved media **from their own installation**; its saved answer file is
account-specific and must remain private. It is pinned to the tested 2026 media.

After installation and tenant configuration:

```sh
scripts/09-mac-launcher.sh
scripts/10-fresh-signin.sh
```

Sign in using the official vendor form. Future launches can use
`~/Applications/SolidWorks (Wine).app`. macOS may request Desktop-folder or
network/removable-volume access for Wine. Complete those permission dialogs yourself.
A first Save As can wait for Desktop-folder access even when its destination is
inside the Wine prefix. If CAD appears frozen during a save, check for a macOS
permission prompt before force-quitting; in testing, the Wine server waited inside
the native file-open call while macOS requested Desktop access. Allow access if
you want Wine to use that location. Permission prompts need your own interaction.
Regenerate the shortcut
if you move the checkout or change its runtime scripts. CLI logs are under `logs/`;
Finder shortcut logs are under `~/Library/Logs/SolidWorksWine/`. Logs can contain
private vendor session information: do not publish them without review.

For an existing installation built with this kit, save and exit CAD, stop its selected
prefix, then run `scripts/build-button-capture.sh` and regenerate the shortcut with
`09-mac-launcher.sh`. The guard defaults on only for a matching installed DLL pair;
`SW_BUTTON_CAPTURE_GUARD=0` in local configuration disables it.

The optional `09-mac-launcher.sh --test` shortcut uses a separate image and prefix.
Main storage selectors in local configuration cannot override its fresh selectors.
Use `SW_TEST_IMAGE`, `SW_TEST_VOL` and `SW_TEST_PREFIX` for custom test locations;
the generated shortcut refuses the main prefix or image. The two Launcher services
still must not run simultaneously.

On first File > New, select units/standard/orientation to generate default templates.
The validated setup uses MMGS, ISO and Y-up.

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
  see [capture investigation](docs/button-capture.md).
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
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and [LICENSE](LICENSE).
