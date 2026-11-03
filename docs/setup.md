# Setup guide

Run all commands from the repository root. This is an experimental setup kit;
some installation steps are manual, and a complete first-time installation from
the published kit has not yet been verified.

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

For a first installation, `./setup.sh` runs the Wine preparation commands below
in order and creates `config.local.zsh` if needed. It stops on a failed step and
refuses a running Wine bundle or a prefix with the Launcher already installed.
Use `./setup.sh --dry-run` to list its steps without changing anything.

Storage preparation verifies that the configured mount belongs to the configured
disk image. It refuses an ordinary folder, a different mounted image, or an image
already attached elsewhere. New attachments use the requested mount point and are
verified before Wine directories are created; existing images are not detached.

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
scripts/build-button-capture.sh
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

For optional CAD regressions after installation, see
[CAD checks](cad-checks.md). These use separate local test files.

The optional `09-mac-launcher.sh --test` shortcut uses a separate image and prefix.
Main storage selectors in local configuration cannot override its fresh selectors.
Use `SW_TEST_IMAGE`, `SW_TEST_VOL` and `SW_TEST_PREFIX` for custom test locations;
the generated shortcut refuses the main prefix or image. The two Launcher services
still must not run simultaneously.

On first File > New, select units/standard/orientation to generate default templates.
The validated setup uses MMGS, ISO and Y-up.

