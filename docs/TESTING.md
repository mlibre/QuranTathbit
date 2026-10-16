# Testing

The app is verified headlessly: every suite is a Godot SceneTree script that
runs, prints what it checked, and exits non-zero on failure — no display,
no GPU, no editor.

```bash
scripts/check_indent.sh     # indentation guard
tools/battery.sh            # the whole battery
godot --headless --path . --script tests/regression_<name>.gd   # one suite
```

## The suites

| suite                  | what it holds the app to                                              |
| --- | --- |
| `regression_scheduler` | Anki's SM-2 with Anki's numbers: interval bands, fuzz bounds, step delays, lapse/relearn round trips, ease moves, queue caps |
| `regression_deck`      | the deck as folders and files: load, card discovery, media resolution, progress round-trip, repair of a hand-corrupted `progress.json` |
| `regression_sync`      | sync against a fake GitHub: first push, second device, local-edit-wins, progress merge by card, single-commit batches, ref-conflict retry, foreign files untouched, editor metadata never travelling, web builds skipping media |
| `regression_markdown`  | the card markdown subset, and the Arabic/Persian/Latin script detection that dresses each block |
| `regression_boot`      | a cold first run: the bundled deck installs itself, home shows the real numbers, a session renders a real card, settings opens and returns |

## Why the battery runs twice

Pass 1 runs the suites as the machine sits. Pass 2 removes
`.godot/global_script_class_cache.cfg` first — the state of any machine that
pulled new classes but has not opened the editor since. GDScript resolves
bare `class_name` references through that cache, so a project that references
another file's class by name boots in the editor and fails everywhere else.
Every cross-file reference is therefore pinned behind a `preload` constant
and quoted `extends` paths; the cold pass proves it — a suite that only
passes warm is not green.

## Live checks

Three tools speak to GitHub's real servers. They cost nothing, store nothing,
and never need credentials to pass:

```bash
godot --headless --path . --script tools/live_http_check.gd   # the HTTP pipeline
godot --headless --path . --script tools/live_auth_check.gd   # the sign-in path
godot --headless --path . --script tools/live_sync_check.gd   # the sync engine
```

`live_http_check` sends one request through the app's own `HttpClient` and
accepts any HTTP status back — it proves the plumbing, not GitHub's answer.
`live_auth_check` mints a genuine device/user code pair with the real OAuth
app id, polls once and expects `authorization_pending` (a bad id would
return `invalid_client`); with `QURAN_TATHBIT_LIVE_TOKEN` exported it ends
with the same `whoami` call every sign-in finishes with. `live_sync_check`
creates a scratch private repo (`quran-tathbit-smoke`, or
`QURAN_TATHBIT_LIVE_REPO`), pushes the bundled deck as a single commit,
reads the tree back — no editor metadata riding along — then runs a quiet
second sync that moves nothing; `QURAN_TATHBIT_LIVE_CLEANUP=1` deletes the
scratch repo at the end. Tokens are read from the environment and never
written anywhere.

## Adding a suite

Name it `tests/regression_<subject>.gd`; the battery picks it up
automatically. Extend `SceneTree`, set a `_failures` counter, and finish
with:

```gdscript
if _failures > 0:
        print("subject: %d FAILURE(S)" % _failures)
        quit(1)
print("subject: all checks passed")
quit(0)
```

Two conventions worth keeping:

- **Test the contract, not the implementation.** The sync suite drives the
  engine through a fake `HttpClient` that speaks the slice of GitHub's API
  the app uses — no network, no fixtures to record.
- **Assert on observable state.** Read `progress.json` off disk, walk the
  scene tree, count the cards in the repo. A suite that could pass while the
  app is broken is worse than no suite.

## Visual QA

Headless runs cannot prove what a person sees. `tests/capture_shots.gd`
drives the app through a fresh install and its first session, saving a PNG
at each step; `tools/shot_qa.py` reads them back (luminance, dark voids,
palette). It needs a display — Xvfb is enough:

```bash
Xvfb :99 -screen 0 1280x800x24 &
godot --path . --script tests/capture_shots.gd -- /tmp/shots
python3 tools/shot_qa.py /tmp/shots
```

The same rig films the app continuously:
`tests/capture_gif.gd` grabs a frame every tenth of a second through a
first session, and `tools/make_gif.py` assembles the frames into the GIF
the README carries (`python3 tools/make_gif.py /tmp/gifframes
docs/media/app.gif`).

The same rig answers the phone question. `tests/capture_window.gd` runs
the journey inside a window the caller names and asserts the layout
invariants for that shape — the design canvas the stretch mode hands the
app, the answer grid's column count, every button inside the window, the
corner coins on top where a tap lands. A phone window must get a phone
canvas: the app's base resolution is the phone's own width, so a window
narrower than the desktop's aspect lays out as a hand's page, and the
suite fails if the canvas, or anything on it, says otherwise:

```bash
Xvfb :99 -screen 0 1920x2400x24 &
godot --path . --script tests/capture_window.gd -- 390x844 /tmp/shots-phone
godot --path . --script tests/capture_window.gd -- 1280x800 /tmp/shots-desk
python3 tools/shot_qa.py /tmp/shots-phone
```

The window is asked for before the tree runs its first frame: under a bare
X server the canvas follows a programmatic resize only then, so each size
gets its own run rather than one run resizing midway.

## Deck fidelity

The deck ships from one source: `quran-cards-2026-10-14.apkg`, and nothing
may alter it on its way into the app. `tools/verify_deck.py` enforces that:
it re-extracts the package into a scratch folder through the converter's own
code and compares the shipped deck file by file.

```bash
python3 -m pip install zstandard
python3 tools/verify_deck.py
```

- `front.md`, `back.md` and every media file must be **byte-identical** to
  the extraction.
- `deck.json` may differ only in the deck's *name*; the card list and source
  URL must match exactly.
- `*.import` files and `progress.json` are ignored; anything else in the
  deck folder fails the run.

CI runs it before every Pages deploy and release build, so a deck that
drifted from the package fails the build instead of reaching a user. The
12 MB `.apkg` is intentionally absent from the repo; when it is missing,
`verify_deck.py` prints a `skip` line and exits 0. Drop a local copy into
the root to run the proof again.
