# dictate — hold-Fn voice typing

Hold **Fn**, talk, let go. Whisper transcribes locally, Claude Haiku fixes the
grammar, the text pastes at your cursor. No app, no Xcode, no subscription.

**Double-tap Fn** for hands-free: it keeps recording with your hands free until
you tap Fn again. Use this for anything long.

A floating pill at the bottom of the screen shows a pulsing red dot and a live
timer while recording, then "transcribing…" — so you always know the state.

## Where things are

The real files live in this repo. Symlinks point at them from the places macOS
insists on, which `install.sh` creates for you:

| Real file (here) | Symlinked to | What it is |
|---|---|---|
| `dictate.lua` | `~/.hammerspoon/dictate.lua` | Fn hotkey, overlay, recording, pasting |
| `hammerspoon-init.lua` | `~/.hammerspoon/init.lua` | Hammerspoon bootstrap + auto-reload |
| `dictate-transcribe` | `~/bash_scripts/dictate-transcribe` | Whisper + Claude cleanup. WAV in, text out |
| `dictate-mic` | `~/bash_scripts/dictate-mic` | List / pin the microphone |
| `dictate-key` | `~/bash_scripts/dictate-key` | Add / test / remove the API key, with verification |
| `config` | `~/.config/dictate/config` | All the knobs |
| `prompt.md` | — | The cleanup prompt. Read fresh every dictation; edit and it takes effect on your next Fn press |
| `logs/` | — | One markdown file per day, every dictation. **Git-ignored** |
| `debug.log` | — | One line per record / stop / transcribe. **Git-ignored** |

Deliberately **not** in this folder, and git-ignored so they never get committed:

| Path | Why it stays out |
|---|---|
| `~/.config/dictate/api-key` | Secret. Never in a repo. |
| `logs/`, `debug.log` | Present in this folder but git-ignored: a record of everything you have ever said should not go to GitHub, private repo or not. Flip this by removing `logs/` from `.gitignore`. |
| `~/.local/share/dictate/models/` | 1.5 GB model file. |

Edit any file here and Hammerspoon reloads itself automatically — unless you are
mid-recording, in which case it waits until you finish.

## Knobs (`config`)

- `CLEANUP=0` — skip the Claude pass entirely (pure Whisper, zero cost)
- `REMOVE_FILLERS=0` — keep your "um"s and "you know"s
- `OVERLAY=0` — hide the floating pill, menu bar only
- `SOUND=1` — quiet tick when recording starts and stops
- `MIN_SECONDS` — ignore Fn presses shorter than this (anti-accident)
- `LOG=0` — stop the daily log
- `MODEL` — swap in a smaller Whisper model for faster-but-rougher

## How it protects you

- **Never answers your dictation.** The transcript is passed inside `<transcript>`
  tags with explicit instructions that nothing inside is addressed to the model.
- **Word-overlap guard.** If the cleanup returns text sharing under 55% of your
  spoken words — a refusal, an answer, a summary — it is thrown away and the raw
  Whisper text is used instead. The prompt can fail; this still catches it.
- **Raw fallback.** Any API failure falls back to raw Whisper output.
- **One clipboard rule.** After a dictation your clipboard holds that dictation
  — nothing is restored automatically. If you had something copied, the 🎙 menu
  has "Put back what I copied before". (Automatic restore was tried and removed;
  it raced each app's paste handling and broke in three different ways.)
- **Everything is logged** to `logs/YYYY-MM-DD.md` in this folder, with the
  raw transcript kept in an HTML comment whenever cleanup changed it. A bad paste
  never loses your words.

## Speed and cost

~1.6s from key release to pasted text for a 10-second utterance, warm. The first
run after a reboot takes ~6s while Metal compiles shaders — not a bug.

Haiku 4.5 at $1/$5 per million tokens, ~400 tokens per dictation — about
**$0.0012 each**, roughly $2–4/month at heavy use. `CLEANUP=0` makes it free.

## When it misbehaves

The debug log names the stage: `tail -30 debug.log` (in this folder)
(or 🎙 menu → Open debug log).

| Symptom in the log | Meaning |
|---|---|
| `WATCHDOG: flagWatcher was disabled` | macOS killed the event tap; it self-healed. Frequent = something else is fighting us. |
| `fn tap 0.21s discarded` | You tapped instead of holding. Hold longer, or lower `MIN_SECONDS`. |
| `heartbeat tap=true` but no `record start` | The press genuinely never arrived. |
| No heartbeat at all | Hammerspoon is not running. |
| `transcribe exit=4` | The recording vanished before Whisper read it. |
| `cleanup kept only N% of the spoken words` | The guard fired; you got raw Whisper. Working as intended. |

Other fixes:
- **Nothing happens on Fn** — System Settings → Privacy & Security → Accessibility → Hammerspoon on.
- **Silence / empty transcripts** — wrong mic. `dictate-mic`, then `dictate-mic 1`.
- **Fn opens the emoji picker** — `defaults write -g AppleFnUsageType -int 0`, then log out and back in.
- **Test without the hotkey** — `say -o /tmp/t.wav --data-format=LEI16@16000 "testing one two three" && dictate-transcribe /tmp/t.wav`

## Undo it all

```
brew uninstall --cask hammerspoon && brew uninstall whisper-cpp
rm -rf ~/.hammerspoon ~/.config/dictate ~/.local/share/dictate
rm ~/bash_scripts/dictate-transcribe ~/bash_scripts/dictate-mic
defaults delete -g AppleFnUsageType
```
Then delete this repo folder.
