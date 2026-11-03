# SOLIDWORKS Maker on Mac

Run **SOLIDWORKS Design Professional for Makers 2026** on macOS with Wine,
without CrossOver or XQuartz.

This is an experimental community project, independent of Dassault Systèmes.
It has been used on an **Apple M4 running macOS 15.7.9** for sign-in, part
modeling, assemblies, drawings and PDF export. Local CAD is the main focus.

![SOLIDWORKS drawing on macOS](docs/codex-main-drawing.png)

## Getting started

You’ll need:

- An Apple Silicon Mac with Rosetta 2.
- Your own SOLIDWORKS Makers subscription and official installers.
- Xcode Command Line Tools, Python 3, and Homebrew `bison` and `cabextract`.
- Tens of GB of free storage; local storage is recommended.

Download the [latest release](https://github.com/lazy-jubei/solidworks-maker-mac/releases/latest)
or clone this repository, then follow the **[setup guide](docs/setup.md)**.
It covers configuration, downloading the installer through your dashboard,
installation and sign-in.

Once installed, launch **SolidWorks (Wine)** from `~/Applications`.
On first File → New, choose your units and drawing standard to create the templates.
If macOS asks Wine for folder or volume access, respond to the permission prompt.

The release contains scripts and compatibility patches. You supply the licensed
SOLIDWORKS software; no installers, accounts or preconfigured Wine environment
are bundled.

## Current limitations

- Setup still includes manual steps; a complete first-time install from the
  published kit has not yet been verified.
- Graphics performance and stability can vary. Network-backed storage may pause.
- Cloud/PLM features and full Intel Mac compatibility are unverified.

## More information

- [Setup and troubleshooting](docs/setup.md)
- [Compatibility details](docs/compatibility.md)
- [Validation and known issues](docs/validation.md)
- [Optional CAD checks](docs/cad-checks.md)

Licensed under [LGPL-2.1-or-later](LICENSE). See [third-party notices](THIRD_PARTY_NOTICES.md).
