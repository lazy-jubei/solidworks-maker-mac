# SOLIDWORKS Maker on Mac

Run **SOLIDWORKS Design Professional for Makers 2026** on macOS with Wine,
without CrossOver or XQuartz.

This is an experimental community project, independent of Dassault Systèmes.
It has been used on an **Apple M4 running macOS 15.7.9** for sign-in, part
modeling, assemblies, drawings and PDF export. Local CAD is the main focus.

![SOLIDWORKS drawing on macOS](docs/codex-main-drawing.png)

## Requirements

You’ll need:

- An Apple Silicon Mac with Rosetta 2.
- Your own SOLIDWORKS Makers subscription and official installers.
- Xcode Command Line Tools, Python 3, and Homebrew `bison` and `cabextract`.
- Tens of GB of free storage; local storage is recommended.

## Install

Run these steps in Terminal, in order. Keep the project folder in a permanent location.

### 1. Get the project

```sh
git clone https://github.com/lazy-jubei/solidworks-maker-mac.git
cd solidworks-maker-mac
```

### 2. Prepare Wine

```sh
./setup.sh
```

### 3. Install SOLIDWORKS

Open your Makers dashboard with the browser helper, replacing the example URL:

```sh
scripts/open-dashboard.sh 'https://YOUR-MAKERS-DASHBOARD-URL'
```

Sign in and download the 3DEXPERIENCE Launcher. Save its installer as
`cache/installers/3DEXPERIENCELauncher.msi`, then run:

```sh
scripts/04-launcher.sh
scripts/05-webview2.sh
scripts/06-settings.sh
( source scripts/env.sh; wineserver -k; wineserver -w )
scripts/install-dxmt.sh
scripts/build-signin-tools.sh
```

Return to the dashboard and use its Install button to install SOLIDWORKS.

### 4. Sign in and launch

Edit `config.local.zsh` and set `SW_TENANT` and `SW_REGISTRY` from your installed
`SOLIDWORKS Design` desktop shortcut. Then run:

```sh
scripts/09-mac-launcher.sh
scripts/10-fresh-signin.sh
```

Sign in using your SOLIDWORKS account. Afterward, open **SolidWorks (Wine)** in
`~/Applications` to launch it.

On first File → New, choose your units and drawing standard. Respond to any macOS
folder-access prompts so Wine can open and save files.

For help with a step, see the [full setup guide](docs/setup.md).

## More information

- [Setup and troubleshooting](docs/setup.md)
- [Compatibility details](docs/compatibility.md)
- [Validation and known issues](docs/validation.md)
- [Optional CAD checks](docs/cad-checks.md)

Licensed under [LGPL-2.1-or-later](LICENSE). See [third-party notices](THIRD_PARTY_NOTICES.md).
