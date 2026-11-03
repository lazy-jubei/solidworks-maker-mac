#!/bin/zsh
# Read-only prerequisite checks for the first-time preparation entry point.
set -eu
[[ "$(uname -s)" == Darwin ]] || { print -u2 'This setup requires macOS.'; exit 1; }
for dependency in python3 cabextract; do
  command -v "$dependency" >/dev/null || { print -u2 "Install $dependency first (see README.md)."; exit 1; }
done
[[ -x /opt/homebrew/opt/bison/bin/bison ]] || { print -u2 'Install Homebrew bison first: brew install bison'; exit 1; }
xcrun --find clang >/dev/null || { print -u2 'Install Xcode Command Line Tools first: xcode-select --install'; exit 1; }
arch -x86_64 /usr/bin/true || { print -u2 'Install Rosetta 2 first.'; exit 1; }
