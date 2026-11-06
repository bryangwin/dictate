# Instructions for an AI coding agent installing this repo

You have been pointed at this repo and asked to install it and make it work.
Follow this file. It is the authoritative install procedure; `INSTALL.md` is the
human version of the same thing.

**What this is:** hold-Fn voice typing for macOS. Hammerspoon provides a global
Fn hotkey, `ffmpeg` records, `whisper.cpp` transcribes locally, and an optional
Claude Haiku call fixes grammar. The text is pasted at the user's cursor.

**Your job:** run the installer, then get the user through the three steps that
require a human, then verify with the smoke test. Do not rewrite the tool.

---

## Hard rules

1. **Never invent an API key, never ask the user to paste one into your chat,
   and never write the key file yourself.** Direct them to `dictate-key`, which
   handles and verifies it locally. If there is no key, say so and continue —
   the tool works without one.
2. **Never overwrite an existing `~/.hammerspoon/init.lua`.** `install.sh`
   handles this correctly (it appends one `require("dictate")` line). Do not
   bypass it with your own `ln -sf`.
3. **Never commit `api-key`, `logs/`, or `debug.log`.** The dictation log is a
   transcript of everything the user has ever said. `.gitignore` covers these;
   do not weaken it.
4. **Never run `killall`/`pkill` on anything but Hammerspoon or this tool's own
   `ffmpeg`.** The ffmpeg recorder matches `avfoundation.*dictate`.
5. **This is macOS only.** On any other OS, stop and say so.

## Step 1 — install

```bash
./install.sh --check     # report only, changes nothing
./install.sh             # do it
```

`install.sh` is idempotent and safe to re-run. It handles: Homebrew packages
(`whisper-cpp`, `ffmpeg`, Hammerspoon cask), the 1.5 GB model download, the
Hammerspoon symlinks, the API key, and freeing the Fn key.

It **requires Homebrew**. If `brew` is missing it exits 1 — tell the user to
install it from https://brew.sh rather than trying to work around it.

If your stdin is not a terminal, the installer skips the API-key prompt and
prints what to do instead. That is expected; do not try to feed it input.

## Step 2 — the three things you cannot do

Report these to the user **explicitly**. The tool will not work without the
first two, and it will misbehave without the third.

1. **Accessibility permission** — System Settings → Privacy & Security →
   Accessibility → enable **Hammerspoon**. Without it, the Fn key does nothing
   and nothing is logged. You can confirm afterwards: the line
   `accessibility=true` appears in `debug.log` on each Hammerspoon load.
2. **Microphone permission** — same pane, Microphone → enable Hammerspoon.
   macOS also prompts on the first Fn hold.
3. **Log out and back in** — this is what makes `AppleFnUsageType=0` take
   effect, freeing Fn from the emoji picker. Optional; if the user holds Fn and
   an emoji panel appears, it is required.

## Step 3 — the API key (optional)

The grammar pass needs an Anthropic API key. A Claude Code or Claude.ai
subscription does **not** work for this; it must be a key from
https://console.anthropic.com → API Keys.

**Do not write the key file by hand, and do not ask the user to paste a key to
you.** Tell them to run this in their own terminal:

```bash
dictate-key        # or ./dictate-key from this repo
```

It opens the console, takes the paste, and **verifies the key with a real API
call before saving** — so a bad paste fails loudly now instead of silently
degrading to raw transcription later. You can confirm afterwards without ever
seeing the key:

```bash
./dictate-key --test
# EXPECT: "Key works. Grammar cleanup is active."
```

If the user has no key yet, that is fine — stop here and report it. The 🎙 menu
will show "⚠︎ Add API key — grammar cleanup is off" until they do.

Cost is about $0.0012 per dictation (Haiku 4.5, ~400 tokens round trip). To run
with no key and no cost, set `CLEANUP=0` in `config`.

## Step 4 — verify

This is the definition of done. Run it and check each line.

```bash
# 1. Transcription pipeline works end to end, no microphone needed.
say -o /tmp/dictate-check.wav --data-format=LEI16@16000 "testing one two three"
./dictate-transcribe /tmp/dictate-check.wav
# EXPECT: "Testing one two three." on stdout. Empty output is a failure.

# 2. Hammerspoon is running and its Fn watcher is alive.
pgrep -x Hammerspoon >/dev/null && echo RUNNING
tail -5 debug.log
# EXPECT a recent line: dictate loaded, flagWatcher running=true
# EXPECT a recent line: accessibility=true   (false = step 2.1 not done)

# 3. The microphone ffmpeg will use is the real one, not a virtual device.
./dictate-mic
# A virtual device (Zoom, Loopback, BlackHole) winning ":default" is the most
# common cause of silent transcripts. Pin the real mic: ./dictate-mic 1
```

Only after those pass, tell the user: **hold Fn and talk; double-tap Fn for
hands-free.**

## Troubleshooting map

Read `debug.log`. Each line maps to one cause:

| Log line | Meaning | Action |
|---|---|---|
| no `dictate loaded` line | Hammerspoon not running or config not loaded | `open -a Hammerspoon` |
| `accessibility=false` | Accessibility permission missing | Step 2.1 |
| `heartbeat tap=true` but no `record start` when Fn is held | The press is not reaching the tap | Confirm Fn is not remapped; check Karabiner/other remappers |
| `WATCHDOG: flagWatcher was disabled` repeatedly | Another tool is fighting for the event tap | Expected occasionally; constant means a conflict |
| `fn tap 0.21s discarded` | User tapped instead of holding | Hold longer, or lower `MIN_SECONDS` in `config` |
| `record start` then `gave up waiting` | ffmpeg produced no audio | Wrong mic — `./dictate-mic` |
| `transcribe exit=3` | Model file missing | Re-run `./install.sh` |
| `transcribe exit=0 chars=0` | Silence, or the wrong mic | `./dictate-mic` |
| `cleanup kept only N% of the spoken words` | Safety guard fired; raw Whisper was used instead | Working as intended, no action |

## Architecture, so you do not break it

- `dictate.lua` — Hammerspoon: the Fn `flagsChanged` tap, menu bar, floating
  overlay, ffmpeg start/stop, paste. Symlinked into `~/.hammerspoon/`.
- `hammerspoon-init.lua` — Hammerspoon bootstrap: auto-reload watcher,
  `hs.autoLaunch`, Accessibility check. Symlinked as `~/.hammerspoon/init.lua`.
- `dictate-transcribe` — WAV in, final text out. Usable standalone.
- `prompt.md` — the cleanup system prompt. Read fresh on every run;
  `{{FILLER_RULE}}` is substituted from `REMOVE_FILLERS` in `config`.
- `config` — shell assignments, sourced by `dictate-transcribe` and parsed by
  `dictate.lua`. **Must not contain machine-specific absolute paths**; both
  programs locate themselves by resolving their own symlink, and a hard-coded
  path in `config` silently overrides that.

Non-obvious things that are load-bearing — do not "simplify" them away:

- The flags tap is **suspended around the synthetic Cmd-V**, because our own
  paste re-enters the tap and macOS then disables it.
- A **2-second watchdog** restarts the tap whenever `isEnabled()` is false.
  macOS disables event taps silently; without this the tool works exactly once.
- After stopping ffmpeg the code **polls until the WAV size stops changing**
  rather than sleeping a fixed interval. A fixed sleep works most of the time,
  which is the worst kind of bug.
- Timers are retained on a `dictateTimers` table because anonymous Lua timers
  get garbage-collected before firing.
- The clipboard is **never restored automatically** after a paste, and must not
  be. That was tried and reverted: it resurrected old dictations, it ate pastes
  by firing before the paste landed, and it reverted the user's own copied text
  under them. It is a timer racing each app's paste handling and no delay is
  correct for every app. The rule is: after a dictation the clipboard holds that
  dictation, and the menu offers "Put back what I copied before" by hand.
- The cleanup output is accepted only if it reuses **≥55% of the spoken words**.
  This is what stops the model from pasting an answer or a refusal as the user's
  dictation. Keep it.
