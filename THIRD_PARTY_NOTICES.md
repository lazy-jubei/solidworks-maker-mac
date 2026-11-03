# Licenses and upstream work

This project's setup scripts, compatibility patches and helper sources are distributed
under LGPL-2.1-or-later; see LICENSE. Copyright 2026 lazy-jubei and contributors.
Existing upstream copyright and license notices remain applicable.

- Wine: https://www.winehq.org/ — LGPL-2.1-or-later. The scripts fetch Wine 11.16
  source and the Gcenx Wine Staging macOS build. Wine modifications are supplied as
  source patchers here; upstream source is downloaded by build-shell32.sh.
- The Rosetta mode-switch and wineserver patches originated in
  https://github.com/lazy-jubei/altium-wine (LGPL-2.1-or-later).
- The Mac OpenGL/GDI patch adapts GeanyBezna/winemac-offscreen-children v0.2.0
  (LGPL-2.1-or-later): https://github.com/GeanyBezna/winemac-offscreen-children.
  The original patch and LGPL text are retained in scripts/patches/.
- diagnostics/glchild-overlay-dpi.c adapts that project's MIT-licensed test;
  see diagnostics/LICENSE.glchild.
- DXMT v0.80: https://github.com/3Shain/dxmt — LGPL-2.1-or-later. Downloaded at
  setup time; not redistributed in this release. install-dxmt.sh changes only
  one byte of its Wine loader marker for browser-local loading.
- LLVM-MinGW, winetricks and Chrome for Testing are downloaded from their upstream
  distributions; their licenses and notices apply to those downloads.

SOLIDWORKS, 3DEXPERIENCE, WebView2 and their installers are not included. They remain
owned by their respective vendors and require the applicable licenses and accounts.
This project is independent of Dassault Systèmes, Microsoft and Apple.
