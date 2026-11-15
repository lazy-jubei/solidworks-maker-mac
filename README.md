# SOLIDWORKS Maker on Mac

Run SOLIDWORKS for Makers on macOS with Wine.
Supports both Apple Silicon and Intel Macs.

![SOLIDWORKS on macOS](assets/solidworks.png)

## Install

Paste this into Terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/lazy-jubei/solidworks-maker-mac/main/install.sh -o /tmp/solidworks-maker-install.sh && zsh /tmp/solidworks-maker-install.sh
```

An installer window opens and walks you through the rest. You only need to do two things:

1. Sign in to your SolidWorks Maker account in the bundled Chrome window and download the
3DEXPERIENCE Launcher at the start.
2. Click Install SolidWorks in that Chrome window at the end.

Everything in between runs on its own (30–60 minutes the first time). If you close Chrome
too early, click Relaunch Chrome in the installer window.

After setup, open **SolidWorks (Wine)** in Applications.

![The SolidWorks Maker installer window](assets/installer.png)

## Update

Run the install command again. If an installation is found, click **Update** in the
installer window. Your SOLIDWORKS installation, settings and CAD files are kept.
To update Wine as well, quit SolidWorks and Wine before selecting **Also update Wine
patches and browser graphics** in the installer window.

## Details

The installer downloads the project, installs prerequisites, and builds a patched
Wine environment. A separate Chrome browser identifies itself as Windows so the
Makers dashboard offers the installer, without changing your usual browser.
You sign in and download SOLIDWORKS directly from Dassault Systèmes. The script
then reads your installed shortcut’s settings and creates the Mac app shortcut.

Wine 11.16 is patched to support the installer’s ZIP extraction and MSI feature
selection. bison and cabextract come from MacPorts, on Intel and Apple Silicon Macs;
the installer installs MacPorts from its notarized package if it isn't there, which
needs an administrator password once. Python and the compilers come from Apple's
Command Line Tools. On Apple Silicon, it also enables a Rosetta mode-switch workaround. On
every Mac, SolidWorks is told it runs as x64 on an ARM64 host, because its license loader
crashes under Wine on the native x64 path, Intel Macs included. A targeted mouse-capture fix
lets the feature editor’s OK/Cancel buttons receive clicks correctly. Browser graphics
libraries are scoped to the embedded browsers to support startup and reduce idle CPU use.

### Experimental embedded sign-in

On a test installation, add `export SW_EMBEDDED_SIGNIN=1` to `config.local.zsh` and use
the installer window to update Wine patches and browser graphics. This keeps the
3DEXPERIENCE sign-in browser inside the vendor dialog. The window fixture and SolidWorks
startup have been tested on Intel. Fresh sign-in and Apple Silicon verification are pending.
To return to the current sign-in workaround, remove the setting and use the same Wine
update option.

### Enhanced Graphics on Intel Radeon

On Intel Macs with macOS 15 or newer and an AMD Radeon default Metal device,
the installer uses WineMetalGL by default and enables Enhanced Graphics Performance
the first time it installs that renderer. The 3DEXPERIENCE launcher, browser and
SolidWorks process monitor continue to use Wine's standard OpenGL. The installer
keeps later changes you make to the Enhanced Graphics checkbox.

To switch back to Wine's standard renderer, set `SW_INTEL_ENHANCED_GRAPHICS=0`
in `config.local.zsh` and choose the Wine update in the existing installer window.
Apple Silicon keeps its current renderer while that configuration is being tested.

### Graphics performance

SolidWorks draws its 3D view with legacy OpenGL, one call per vertex. Under Wine on macOS
each call crossed into the Mac side with two system calls, which took over half of every
frame. A patched `opengl32` records simple calls and replays them in one crossing, with
identical output. The 3D view is drawn directly by the GPU and clipped so the FeatureManager,
task pane and toolbars stay visible; window images skip a color conversion. On an Intel Mac
with an RX 6900 XT, rotating a large mold assembly went from about 2.5 to about 15 redraws a
second, and a simple part from about 24 to about 70. `WINE_GL_BATCH=0` and `SW_OPENGL_GDI=1`
switch back to the older paths if something draws wrong. While a window is being resized the strip
the app has not painted yet shows in the window colour, as it does on Windows;
`SW_MAC_RESIZE_GRAVITY=0` restores the older behaviour of stretching the previous frame into it.
With more than one display, windows can
be dragged onto any of them, and menus and dialogs open on the display SolidWorks is on.

Licensed under [LGPL-2.1-or-later](LICENSE). [Third-party notices](THIRD_PARTY_NOTICES.md).
