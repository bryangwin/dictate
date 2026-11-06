# dictate — hold-Fn voice typing for macOS

Hold the **Fn** key, talk, let go. Your words appear wherever your cursor is.

Speech recognition runs **entirely on your Mac** (OpenAI's Whisper large-v3-turbo
via whisper.cpp). A short grammar pass through Claude Haiku then fixes
punctuation, capitalization, mishearings, and strips "um"/"uh"/"you know".

Roughly 1.6 seconds from releasing the key to text on screen.

It is a replacement for MacWhisper's dictation, built because the upgrade fees
were annoying. No app to install, no subscription, no Xcode.

---

## Requirements

- macOS (Apple silicon or Intel)
- [Homebrew](https://brew.sh) — the installer uses it
- ~2 GB of disk (1.5 GB of that is the speech model)
- Optional: an Anthropic API key for the grammar pass. Without one it still
  works, you just get raw Whisper output.

## Install

```bash
cd dictate
./install.sh
```

It is safe to re-run, and every step checks before it acts. To see what it
*would* do without changing anything:

```bash
./install.sh --check
```

The installer handles: Homebrew packages (`whisper-cpp`, `ffmpeg`, Hammerspoon),
the model download, wiring into Hammerspoon, your API key, and freeing the Fn
key. **If you already use Hammerspoon it will not overwrite your config** — it
appends one `require("dictate")` line to your existing `init.lua`.

## Three things the installer cannot do for you

1. **Accessibility permission.** System Settings → Privacy & Security →
   Accessibility → enable **Hammerspoon**. Without this, Fn does nothing.
2. **Microphone permission.** Same place, Microphone → enable Hammerspoon.
   macOS will also prompt the first time you hold Fn.
3. **Log out and back in.** Frees the Fn key from macOS's emoji picker. You can
   skip it and see if Fn behaves; if the emoji panel appears, do the logout.

## Getting an API key

[console.anthropic.com](https://console.anthropic.com) → API Keys → create one,
and the installer will ask you to paste it. It is stored at
`~/.config/dictate/api-key` with `600` permissions, outside this folder so it
can never be committed to git.

**Cost:** Claude Haiku 4.5 at $1 / $5 per million tokens. A dictation is about
400 tokens round trip, so **roughly $0.0012 each** — a few dollars a month even
if you dictate constantly. Set `CLEANUP=0` in `config` to make it free.

## Using it

| Action | What happens |
|---|---|
| **Hold Fn**, talk, release | Push-to-talk. Text pastes at your cursor. |
| **Double-tap Fn** | Hands-free. Keeps recording with your hands free. **Tap Fn once to stop.** Use this for anything long. |

While recording, a pill appears at the bottom of the screen with a pulsing red
dot and a timer, and the menu-bar 🎙 shows the same. The menu also has "Copy last
dictation" and shortcuts to the logs and config.

## Your privacy

- **Audio never leaves your Mac.** Transcription is local; recordings are
  deleted immediately after transcription.
- **Only the resulting text** is sent to Anthropic for the grammar pass, and
  only if you set up a key.
- **Every dictation is logged** to `logs/YYYY-MM-DD.md` in this folder so a bad
  paste never loses your words. That is a transcript of everything you have ever
  said into the tool — it is git-ignored on purpose. Set `LOG=0` in `config` to
  turn it off.

## Settings (`config`)

| Key | Default | What it does |
|---|---|---|
| `CLEANUP` | `1` | Grammar pass. `0` = raw Whisper, free and offline |
| `REMOVE_FILLERS` | `1` | Strip "um", "uh", "you know" |
| `OVERLAY` | `1` | The floating pill. `0` = menu bar only |
| `SOUND` | `0` | `1` = quiet tick on start/stop |
| `MIN_SECONDS` | `0.4` | Ignore Fn presses shorter than this |
| `LOG` | `1` | Write the daily dictation log |
| `MIC` | `:default` | Run `dictate-mic` to list and pin a microphone |
| `MODEL` | large-v3-turbo | Point at a smaller model for faster, rougher output |

The grammar prompt is `prompt.md` — plain markdown, edit it and the next
dictation uses it. No reload needed.

## If it misbehaves

```bash
tail -30 debug.log
```

Every stage is logged. `README.md` has a table mapping each log line to its
cause, plus the full file layout and how to uninstall.

Most common: **silence / empty transcripts** usually means the wrong microphone
was picked (a virtual device like Zoom's often wins "default"). Run
`dictate-mic` to list them, then `dictate-mic 1` to pin the built-in one.

## Uninstall

```bash
brew uninstall --cask hammerspoon && brew uninstall whisper-cpp
rm -rf ~/.hammerspoon ~/.config/dictate ~/.local/share/dictate
defaults delete -g AppleFnUsageType
```
Then delete this folder.
