# Testing

The app is verified headlessly: every suite is a Godot SceneTree script that
runs, prints what it checked, and exits non-zero on failure. Nothing needs a
display, a GPU, or an editor.

```bash
scripts/check_indent.sh     # indentation guard
tools/battery.sh            # the whole battery
godot --headless --path . --script tests/regression_<name>.gd   # one suite
```

## The suites

| suite | what it holds the app to |
| --- | --- |
| `regression_scheduler` | Anki's SM-2, with Anki's own numbers: interval bands, fuzz bounds, step delays, lapse/relearn round trips, ease moves, queue caps |
| `regression_deck` | the deck as folders and files: load, card discovery, media resolution, progress round-trip, and repair of a hand-corrupted or partial `progress.json` |
| `regression_sync` | sync against a fake GitHub: first push, second device pulling, local-edit-wins vs remote-follows, progress merge by card, failed transfers retrying, foreign repo files untouched, a shared deck arriving |
| `regression_markdown` | the card markdown subset, and the Arabic/Persian/Latin script detection that dresses each block |
| `regression_boot` | a cold first run: the bundled deck installs itself into `user://`, home shows the real numbers, a session renders a real card and records its answer, settings opens and returns |

## Why the battery runs twice

Pass 1 runs the suites as the machine sits. Pass 2 removes
`.godot/global_script_class_cache.cfg` first and restores it afterwards — the
state of any machine that pulled new classes but has not opened the editor
since. GDScript resolves bare `class_name` references through that cache, so a
project that references another file's class by name boots in the editor and
fails everywhere else.

Every cross-file reference is therefore pinned behind a `preload` constant
(`const DeckScript := preload("res://scripts/data/deck.gd")`) and `extends`
paths are quoted. The cold pass is what proves it; a suite that only passes
warm is not green.

## Live checks

Two tools speak to GitHub's real servers, for when the fakes are not enough.
They cost nothing, store nothing, and never need credentials to pass:

```bash
godot --headless --path . --script tools/live_http_check.gd   # the HTTP pipeline
godot --headless --path . --script tools/live_auth_check.gd   # the sign-in path
```

`live_http_check` sends one request through the app's own `HttpClient` and
accepts any HTTP status back — it proves the network plumbing, not GitHub's
answer. `live_auth_check` goes further with the real OAuth app id: it mints a
genuine device/user code pair, polls once and expects the specific
`authorization_pending` answer (a bad id would return `invalid_client`
instead), and — if you export `QURAN_TATHBIT_LIVE_TOKEN` with a classic token
first — ends with the same `whoami` call every sign-in path finishes with.
The token is read from the environment and never written anywhere.

## Adding a suite

Name it `tests/regression_<subject>.gd`; the battery picks it up
automatically. Extend `SceneTree`, set a `_failures` counter, and finish with:

```gdscript
if _failures > 0:
    print("subject: %d FAILURE(S)" % _failures)
    quit(1)
print("subject: all checks passed")
quit(0)
```

Two conventions worth keeping:

- **Test the contract, not the implementation.** The sync suite drives the
  engine through a fake `HttpClient` that speaks the slice of GitHub's API the
  app uses — no network, no fixtures to record.
- **Assert on observable state.** Read `progress.json` off disk, walk the
  scene tree, count the cards in the repo. A suite that could pass while the
  app is broken is worse than no suite.

## Visual QA

Headless runs cannot prove what a person sees. `tests/capture_shots.gd`
drives the real app through a fresh install and its first session and saves a
PNG at each step; `tools/shot_qa.py` reads them back (luminance, dark voids,
palette). It needs a display — Xvfb is enough:

```bash
Xvfb :99 -screen 0 1280x800x24 &
godot --path . --script tests/capture_shots.gd -- /tmp/shots
python3 tools/shot_qa.py /tmp/shots
```

## Deck fidelity

The deck ships from one source: `quran-cards-2026-10-14.apkg`. Nothing may
alter it on its way into the app. `tools/verify_deck.py` enforces that: it
re-extracts the package into a scratch folder through the converter's own
code and compares the shipped deck file by file.

```bash
python3 -m pip install zstandard
python3 tools/verify_deck.py
```

- `front.md`, `back.md` and every media file must be **byte-identical** to
  the extraction.
- `deck.json` may differ only in the deck's *name* (the package calls it
  "Default"; the app ships "Quran") — the card list and the recorded source
  URL (`https://quran.makarem.ir/`) must match exactly.
- `*.import` files (Godot editor metadata) and `progress.json` (runtime
  state) are ignored; anything else in the deck folder fails the run.

CI runs it before every Pages deploy and release build, so a deck that
drifted from the package — edited by hand, mangled by a tool, or written
from memory — fails the build instead of reaching a user.
