# ptt-stt

Local, **zero-API-cost** **Push-To-Talk STT** for macOS.

- Hotkey: **hold Right Shift + Space**
- Release to transcribe and paste into the focused app
- Uses local `whisper-cpp` (no paid API)

## One-command install

```bash
curl -fsSL https://raw.githubusercontent.com/momolty/ptt-stt/main/install.sh | bash
```

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/momolty/ptt-stt/main/uninstall.sh | bash
```

## Homebrew tap install (standard)

```bash
brew tap momolty/ptt
brew install ptt-stt
ptt-stt install
```

## Requirements

- macOS
- Homebrew
- Grant Hammerspoon permissions:
  - Privacy & Security → Microphone → Hammerspoon = ON
  - Privacy & Security → Accessibility → Hammerspoon = ON

## What gets installed

- `~/stt/bin/stt-local.sh`
- `~/stt/models/ggml-small.en.bin`
- `~/.hammerspoon/init.lua`

## Notes

If you already have a custom `~/.hammerspoon/init.lua`, back it up first.
