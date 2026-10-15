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
