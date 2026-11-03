# SOLIDWORKS Maker on Mac

Run SOLIDWORKS for Makers on macOS with Wine.

![SOLIDWORKS on macOS](assets/solidworks.png)

## Install

Paste this into Terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/lazy-jubei/solidworks-maker-mac/main/install.sh -o /tmp/solidworks-maker-install.sh && zsh /tmp/solidworks-maker-install.sh
```

Follow the prompts. The script installs prerequisites and prepares Wine, then guides
you through installing SOLIDWORKS using your own Makers subscription and signing in.

After setup, open **SolidWorks (Wine)** in your Applications folder.

Licensed under [LGPL-2.1-or-later](LICENSE). [Third-party notices](THIRD_PARTY_NOTICES.md).
