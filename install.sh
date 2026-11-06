#!/usr/bin/env bash
# dictate installer. Safe to re-run: every step checks before it acts.
# Usage:  ./install.sh          install / repair
#         ./install.sh --check  report what is missing, change nothing
set -u

DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd -P)"
HS_DIR="$HOME/.hammerspoon"
CFG_DIR="$HOME/.config/dictate"
MODEL_DIR="$HOME/.local/share/dictate/models"
MODEL="$MODEL_DIR/ggml-large-v3-turbo.bin"
MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin"
CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
todo() { printf '  \033[33m→\033[0m %s\n' "$1"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; }
step() { printf '\n\033[1m%s\033[0m\n' "$1"; }

[ "$(uname -s)" = "Darwin" ] || { bad "macOS only."; exit 1; }

step "1. Command-line tools"
BREW="$(command -v brew || true)"
if [ -z "$BREW" ]; then
  bad "Homebrew not installed. Get it from https://brew.sh then re-run."
  exit 1
fi
ok "homebrew at $BREW"
NEED=""
command -v whisper-cli >/dev/null || NEED="$NEED whisper-cpp"
command -v ffmpeg      >/dev/null || NEED="$NEED ffmpeg"
if [ -n "$NEED" ]; then
  todo "need:$NEED"
  if [ "$CHECK_ONLY" = "0" ]; then
    # shellcheck disable=SC2086
    brew install $NEED || exit 1
  fi
else
  ok "whisper-cli and ffmpeg present"
fi
if [ -d "/Applications/Hammerspoon.app" ]; then
  ok "Hammerspoon installed"
else
  todo "need Hammerspoon"
  [ "$CHECK_ONLY" = "0" ] && { brew install --cask hammerspoon || exit 1; }
fi

step "2. Speech model (1.5 GB, one time)"
if [ -f "$MODEL" ]; then
  ok "model present ($(du -h "$MODEL" | cut -f1))"
else
  todo "model missing — downloading to $MODEL"
  if [ "$CHECK_ONLY" = "0" ]; then
    mkdir -p "$MODEL_DIR"
    curl -L --retry 3 --progress-bar -o "$MODEL.part" "$MODEL_URL" || exit 1
    mv "$MODEL.part" "$MODEL"
    ok "downloaded"
  fi
fi

step "3. Hook into Hammerspoon"
if [ "$CHECK_ONLY" = "0" ]; then
  mkdir -p "$HS_DIR"
  ln -sfn "$DIR/dictate.lua" "$HS_DIR/dictate.lua"
  if [ -e "$HS_DIR/init.lua" ] && [ ! -L "$HS_DIR/init.lua" ]; then
    # You already have a Hammerspoon config. Do not clobber it.
    if grep -q 'require("dictate")' "$HS_DIR/init.lua"; then
      ok "your existing init.lua already loads dictate"
    else
      printf '\n-- voice typing (hold Fn)\nrequire("dictate")\n' >> "$HS_DIR/init.lua"
      ok "appended require(\"dictate\") to your existing init.lua"
    fi
    todo "your init.lua is yours; consider adding hs.autoLaunch(true)"
  else
    ln -sfn "$DIR/hammerspoon-init.lua" "$HS_DIR/init.lua"
    ok "linked init.lua"
  fi
else
  [ -L "$HS_DIR/dictate.lua" ] && ok "dictate.lua linked" || todo "dictate.lua not linked"
fi

step "4. Convenience commands on your PATH (optional)"
BIN=""
for d in "$HOME/bash_scripts" "$HOME/bin" "$HOME/.local/bin"; do
  case ":$PATH:" in *":$d:"*) BIN="$d"; break ;; esac
done
if [ -n "$BIN" ]; then
  if [ "$CHECK_ONLY" = "0" ]; then
    ln -sfn "$DIR/dictate-transcribe" "$BIN/dictate-transcribe"
    ln -sfn "$DIR/dictate-mic"        "$BIN/dictate-mic"
  fi
  ok "dictate-transcribe and dictate-mic available in $BIN"
else
  todo "no writable PATH dir found; run the scripts as $DIR/dictate-transcribe"
fi

step "5. Anthropic API key (for the grammar cleanup)"
mkdir -p "$CFG_DIR"
if [ -s "$CFG_DIR/api-key" ]; then
  ok "key present at $CFG_DIR/api-key"
elif [ "$CHECK_ONLY" = "1" ]; then
  todo "no API key yet (the tool still works, without cleanup)"
else
  printf '  Create one at https://console.anthropic.com -> API Keys\n'
  printf '  Paste it here (or press Return to skip): '
  read -r KEY
  if [ -n "$KEY" ]; then
    printf '%s\n' "$KEY" > "$CFG_DIR/api-key"
    chmod 600 "$CFG_DIR/api-key"
    ok "key saved"
  else
    todo "skipped — set CLEANUP=0 in $DIR/config for raw transcription"
  fi
fi

step "6. Free up the Fn key"
FN="$(defaults read -g AppleFnUsageType 2>/dev/null || echo unset)"
if [ "$FN" = "0" ]; then
  ok "Fn does nothing on its own (what we want)"
else
  todo "macOS uses Fn for emoji / input source (currently: $FN)"
  if [ "$CHECK_ONLY" = "0" ]; then
    defaults write -g AppleFnUsageType -int 0
    ok "set to 'Do Nothing' — takes effect after you log out and back in"
  fi
fi

step "7. Permissions you must grant by hand"
todo "System Settings -> Privacy & Security -> Accessibility  -> enable Hammerspoon"
todo "System Settings -> Privacy & Security -> Microphone     -> enable Hammerspoon"
if [ "$CHECK_ONLY" = "0" ]; then
  open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" 2>/dev/null
fi

if [ "$CHECK_ONLY" = "1" ]; then
  step "Check complete — nothing was changed."
  exit 0
fi

step "8. Start it"
open -a Hammerspoon
sleep 3
if pgrep -x Hammerspoon >/dev/null; then ok "Hammerspoon running"; else bad "Hammerspoon did not start"; fi

step "Smoke test (no microphone needed)"
T="$(mktemp -t dictate-test).wav"
say -o "$T" --data-format=LEI16@16000 "testing one two three" 2>/dev/null
RESULT="$("$DIR/dictate-transcribe" "$T" 2>/dev/null)"
rm -f "$T"
if [ -n "$RESULT" ]; then
  ok "transcription works: \"$RESULT\""
else
  bad "transcription produced nothing — see $DIR/README.md"
fi

step "Done. Hold Fn and talk. Double-tap Fn for hands-free."
printf '  Log of every dictation: %s/logs/\n' "$DIR"
printf '  If something misbehaves: tail -30 %s/debug.log\n\n' "$DIR"
