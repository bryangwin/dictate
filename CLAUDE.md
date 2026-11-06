# dictate

Hold-Fn voice typing for macOS: local Whisper transcription plus a Claude
grammar pass, pasted at the cursor.

**If you were asked to install this, read [AGENTS.md](AGENTS.md)** — it is the
authoritative procedure, including the steps a human must do (Accessibility and
Microphone permissions, the API key) and the smoke test that defines success.

Short version: `./install.sh --check`, then `./install.sh`, then verify with

```bash
say -o /tmp/dictate-check.wav --data-format=LEI16@16000 "testing one two three"
./dictate-transcribe /tmp/dictate-check.wav   # expect: Testing one two three.
```

The API key is the user's to enter: point them at `dictate-key` (it opens the
console, takes the paste, and verifies it). Never write the key file for them.

`README.md` is the maintainer reference; `INSTALL.md` is for humans.
