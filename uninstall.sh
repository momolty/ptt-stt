#!/usr/bin/env bash
set -euo pipefail

echo "Uninstalling ptt-stt files..."
rm -f "$HOME/stt/bin/stt-local.sh"
rm -f "$HOME/.hammerspoon/init.lua"
echo "Removed scripts/config."
echo "Optional cleanup: rm -rf $HOME/stt"
