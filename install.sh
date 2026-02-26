#!/usr/bin/env bash
set -euo pipefail

# ptt-stt installer (macOS)
# Installs local push-to-talk STT with Hammerspoon + whisper.cpp

if [[ "${PTT_STT_DEBUG:-0}" == "1" ]]; then set -x; fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

say() { printf "%b\n" "$*"; }
step() { say "${BLUE}${BOLD}▶${NC} $*"; }
ok() { say "${GREEN}✓${NC} $*"; }
warn() { say "${YELLOW}⚠${NC} $*"; }
fail() { say "${RED}✗${NC} $*"; exit 1; }

say "${BOLD}ptt-stt installer${NC} — local Push-To-Talk STT for macOS"
say

[[ "$(uname -s)" == "Darwin" ]] || fail "This installer currently supports macOS only."

command -v brew >/dev/null 2>&1 || fail "Homebrew is required. Install from https://brew.sh and run again."

BREW_PREFIX="$(brew --prefix)"
FFMPEG_BIN="$BREW_PREFIX/bin/ffmpeg"
WHISPER_CLI_BIN="$BREW_PREFIX/bin/whisper-cli"
MODEL_PATH="$HOME/stt/models/ggml-small.en.bin"
STT_SCRIPT="$HOME/stt/bin/stt-local.sh"
HS_CONFIG="$HOME/.hammerspoon/init.lua"

step "Installing dependencies (ffmpeg, whisper-cpp, Hammerspoon)"
brew install ffmpeg whisper-cpp
brew install --cask hammerspoon
ok "Dependencies installed"

step "Preparing directories"
mkdir -p "$HOME/stt/bin" "$HOME/stt/models" "$HOME/stt/tmp" "$HOME/.hammerspoon"
ok "Directories ready"

if [[ ! -f "$MODEL_PATH" ]]; then
  step "Downloading Whisper model (small.en)"
  curl -fL -o "$MODEL_PATH" \
    "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin"
  ok "Model downloaded to $MODEL_PATH"
else
  ok "Model already present at $MODEL_PATH"
fi

step "Writing local STT script"
cat > "$STT_SCRIPT" <<EOF
#!/usr/bin/env bash
set -euo pipefail

# Local, zero-cost STT using whisper.cpp
# Usage: stt-local.sh /path/to/audio.m4a

if [[ \$# -lt 1 ]]; then
  echo "Usage: \$0 <audio-file>" >&2
  exit 1
fi

AUDIO_IN="\$1"
MODEL="${WHISPER_MODEL:-$MODEL_PATH}"

if [[ ! -f "\$AUDIO_IN" ]]; then
  echo "Audio file not found: \$AUDIO_IN" >&2
  exit 1
fi
if [[ ! -f "\$MODEL" ]]; then
  echo "Model not found: \$MODEL" >&2
  echo "Set WHISPER_MODEL to a valid ggml model path." >&2
  exit 1
fi

FFMPEG_BIN="${FFMPEG_BIN:-$FFMPEG_BIN}"
WHISPER_CLI_BIN="${WHISPER_CLI_BIN:-$WHISPER_CLI_BIN}"

if [[ ! -x "\$FFMPEG_BIN" ]]; then
  echo "ffmpeg is required but not found at: \$FFMPEG_BIN" >&2
  exit 1
fi
if [[ ! -x "\$WHISPER_CLI_BIN" ]]; then
  echo "whisper-cli is required but not found at: \$WHISPER_CLI_BIN" >&2
  exit 1
fi

TMPDIR_LOCAL="\$(mktemp -d)"
trap 'rm -rf "\$TMPDIR_LOCAL"' EXIT

WAV="\$TMPDIR_LOCAL/in.wav"
OUT_BASE="\$TMPDIR_LOCAL/out"

"\$FFMPEG_BIN" -hide_banner -loglevel error -y \
  -i "\$AUDIO_IN" \
  -ar 16000 -ac 1 -c:a pcm_s16le \
  "\$WAV"

"\$WHISPER_CLI_BIN" \
  -m "\$MODEL" \
  -f "\$WAV" \
  -l en \
  -otxt \
  -of "\$OUT_BASE" \
  >/dev/null 2>/dev/null

cat "\$OUT_BASE.txt"
EOF
chmod +x "$STT_SCRIPT"
ok "STT script ready at $STT_SCRIPT"

step "Writing Hammerspoon config (Right Shift + Space hold-to-talk)"
cat > "$HS_CONFIG" <<'EOF'
-- ptt-stt: hold Right Shift+Space to record; release to transcribe + paste
pcall(require, "hs.ipc")

local ffmpeg = "/opt/homebrew/bin/ffmpeg"
local sttScript = os.getenv("HOME") .. "/stt/bin/stt-local.sh"

local state = {
  recTask = nil,
  recPath = nil,
  recStart = nil,
  recTimer = nil,
  sttTask = nil,
}

local badge = hs.menubar.new()
if badge then badge:setTitle("🎤 PTT") end

local endRecording

local function setBadge(text)
  if badge then badge:setTitle(text) end
end

local function stopTimer()
  if state.recTimer then
    state.recTimer:stop()
    state.recTimer = nil
  end
end

local function beginRecording()
  if state.recTask or state.sttTask then return end

  state.recPath = os.tmpname() .. ".m4a"
  state.recStart = hs.timer.secondsSinceEpoch()

  setBadge("● REC 00s")
  hs.alert.show("● Recording", 0.5)

  state.recTimer = hs.timer.doEvery(1, function()
    local dt = math.max(0, math.floor(hs.timer.secondsSinceEpoch() - state.recStart))
    setBadge(string.format("● REC %02ds", dt))
  end)

  state.recTask = hs.task.new(ffmpeg, nil, {
    "-hide_banner", "-loglevel", "error", "-y",
    "-f", "avfoundation", "-i", ":0",
    "-c:a", "aac", "-b:a", "96k",
    state.recPath,
  })

  if not state.recTask:start() then
    stopTimer()
    state.recTask = nil
    setBadge("⚠️ ffmpeg")
    hs.alert.show("Could not start recorder", 1.2)
    return
  end
end

local function runTranscription(path)
  setBadge("… STT")
  hs.alert.show("Transcribing…", 0.5)

  state.sttTask = hs.task.new(sttScript, function(code, stdout, stderr)
    state.sttTask = nil

    if code == 0 then
      local text = (stdout or ""):gsub("^%s+",""):gsub("%s+$","")
      if #text > 0 then
        hs.eventtap.keyStrokes(text)
        setBadge("✓ pasted")
      else
        setBadge("∅ no text")
      end
    else
      setBadge("⚠️ STT")
      hs.alert.show("STT failed", 1.0)
    end

    hs.timer.doAfter(1.2, function() setBadge("🎤 PTT") end)
    if path then os.remove(path) end

    return true
  end, { path })

  if not state.sttTask:start() then
    state.sttTask = nil
    setBadge("⚠️ STT")
    hs.alert.show("Could not start STT", 1.0)
    hs.timer.doAfter(1.2, function() setBadge("🎤 PTT") end)
  end
end

function endRecording()
  if not state.recTask then return end

  stopTimer()
  setBadge("… stopping")

  local path = state.recPath
  state.recPath = nil
  state.recStart = nil

  state.recTask:terminate()
  state.recTask = nil

  hs.timer.doAfter(0.45, function()
    if not path then
      setBadge("🎤 PTT")
      return
    end

    local attr = hs.fs.attributes(path)
    local size = attr and attr.size or 0
    if size < 200 then
      setBadge("⚠️ no mic")
      hs.alert.show("No audio captured. Check Hammerspoon Microphone permission.", 1.8)
      os.remove(path)
      hs.timer.doAfter(1.2, function() setBadge("🎤 PTT") end)
      return
    end

    runTranscription(path)
  end)
end

hs.hotkey.bind({"rightshift"}, "space", beginRecording, endRecording)
hs.alert.show("PTT ready: hold Right Shift+Space", 1.5)
EOF
ok "Hammerspoon config written"

step "Reloading Hammerspoon"
open -a Hammerspoon || true
osascript -e 'tell application "Hammerspoon" to reload config' >/dev/null 2>&1 || true
ok "Hammerspoon reloaded"

say
say "${GREEN}${BOLD}All set.${NC}"
say "Next: grant permissions in System Settings → Privacy & Security:"
say "  • Microphone: Hammerspoon = ON"
say "  • Accessibility: Hammerspoon = ON"
say
say "Then test in any text field: hold Right Shift + Space, speak, release."
