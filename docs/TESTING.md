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
| `regression_scheduler` | Anki's SM-2 with Anki's numbers: interval bands, fuzz bounds, step delays, lapse/relearn round trips, ease moves, queue caps — the per-day new-card offer as the algorithm defaults it and as the reader chooses it |
| `regression_deck`      | the deck as folders and files: load, card discovery, media resolution, progress round-trip, byte-stable saves (an int never re-saves as a float), the reader's travelling choices — pace, verse face, app tongue — riding the same file, repair of a hand-corrupted `progress.json` |
| `regression_sync`      | sync against a fake GitHub: first push, second device, local-edit-wins, progress merge by card, the travelling choices (pace, verse face, app tongue) riding with it and merging by each one's own moment, single-commit batches, ref-conflict retry, foreign files untouched, editor metadata never travelling, web builds skipping media — and a quiet sync that asks for nothing: no upload, no tree, no commit, not even a file download, while both sides match the last sync's record |
| `regression_zip`       | the deck as one file: export packs deck.json, every card's words and media, and progress.json (editor metadata never rides), the destination chain always offering the app's own corner last, the picker offering only zips; import joins rather than replaces — a fresh deck receives everything, the better-informed card history wins and a later answer breaks ties, the travelling choices merge by their own moments, a file the deck already has keeps its own word while a missing one arrives, a whole unknown card joins as one card, a wrapped archive (one folder around the deck) is understood, a deck meeting its own backup moves nothing and does not even rewrite progress.json, and a stranger zip, a future format, twin folders, garbage bytes, and a zip-slip climb out of the deck are each refused by name |
| `regression_markdown`  | the card markdown subset, and the Arabic/Persian/Latin script detection that dresses each block |
| `regression_boot`      | a cold first run: the bundled deck installs itself with all 151 cards (Al-Baqarah 94-145 riding in additively — text-only, so a card offers no Listen buttons, and the mushaf's own section mark carried where the source has it), home says no holding on the card at all any more — the total-card box gone with its lonely figure, the day's numbers living only in the pills below, the card between owning the day's one news: the next reference standing as the card's hero at the hero's own measure, under the deck's calm name and its own ornament, the app's first question is asked (the language picker standing over home until a tongue is chosen, remembered on the device and carried with the deck), a session renders a real card in the mushaf cut at its own wider measure with the question's eyebrow a breath larger above the answer (its Listen button saying only what it does — شنیدن, never the address the page already says twice — and returning to rest the moment the sound runs out, its selections wearing the page's gold), the answer buttons' word and wait centred on one axis, the volume coin opens a page that hangs from its own coin (its roof pointing up at it, never past the window's edge) and sets the player's loudness — one setting row said twice: the quiet name with the live figure at the row's far end, and beneath it the mute anchoring a rule that runs the width of the page and fills from the reading's own edge, the shape every volume rule the reader has ever dragged taught their hand, the box the reader called wrong twice being neither, the alif coin beside it offers the verse's own faces mid-session (a choice re-said on the standing card at once and stamped into the deck's file), every number the chrome says arrives in the tongue's own script (۱۰۰ and ۱ روز in Persian, ١٠٠ and ١ يوم in Arabic, the arithmetic English has always read), the pencil opens the card's own page (its fields writing flush right with each line reading its own direction, both fields wearing the verses' own hand — the answer's face falling back to its book twin for what the mushaf cut does not draw — opened on the words alone so no phantom blank line rides in from the file's trailing newline, its boxes named at the reading's edge in a right-reading tongue, its unsaved-changes guard asking before it lets the work go, its Read mode laying both sides out as the reader will see them), the library with its filter pills and running head (a right-reading page asking its questions from the right: the entry line's placeholder at the reading's start, the pills running همه first from the right hand) (an empty due list saying so warmly, a scrolled surah naming itself at the top, every pill keeping air on both sides of its words; each row carrying its verse's Persian as a second quiet line under the Arabic, its tail trimmed with an ellipsis rather than cut mid-letter; the pencil at the page's foot standing at the reading's edge in a right-reading tongue, its mark a breath larger), settings opens (the deck's name line and folder note gone from its pace card — the card carries its own running title and the stepper, nothing else — never the machine's own user:// address, the home page's middle card carrying no figures at all — its hero the next reference under the deck's name, the total box gone, tooltips speaking a face that carries the reader's letters, token field, Show/Save standing, no paste button — paste happens in the field itself — and the new-cards stepper answering a press, its choice stamped into the deck's own progress file; the quiet promise carrying its one label and no explainer beneath; the Backup card wired both ways and the real deck packed and joined back inside the app's own storage — every card's words and media riding, a deck meeting its own backup moving nothing, the picker offering the backup a test made, a row press joining it and saying so, Cancel putting the page away; the Reading card offering every verse face judged by its own basmala and every tongue, each choice shown as what it is with no explainer under it, a chosen face stamped into the same file, a chosen tongue re-saying the whole page and back; the Display card stepping both sizes through their real handlers — the interface scale re-flowing the window under the new factor, the text scale re-saying the page in its own new size, the percentages arriving in the tongue's own digits), and returns; the ink's own room is measured honestly per face (Amiri's damma standing past its font's box, the mushaf cut carrying its marks inside it, Vazirmatn's at the editor's size), the verse paragraph, the shelf's preview and the editor's mirror each carrying that room while the mirror keeps the engine's own line pitch, and a page said in Persian laid out from the right (root turned, titles and fields set LEFT — which under an RTL layout is the right edge, the reading's start — while every RichTextLabel explanation line is told RIGHT in so many words, because a RichTextLabel's LEFT stays the visual left edge under an RTL layout too, measured — the source line and the backup card's own words standing at the reading's edge (the source card carrying its link and no button beside it), the backup note still centred; card titles one breath larger than their captions in every tongue; the token hint and the browser's recitation note gone with their words while the repo hint stayed, standing at the reading's edge with the account line (وصل شده به …) beside the source line and the backup card's own words) with the Persian source line saying its say and stopping; and the editor's field answering the press itself — the caret landing at the word the finger meant on every edge of a right-reading line and inside the very row the finger pressed on a wrapped one (the engine's own flush-left hit-test answered with the slide the mirror travels, the row found by its own band of y rather than the wrap-boundary column a press at x=0 returns), a second press taking the word, a third the line, a held press choosing across; a card's page is said once the frame has laid its containers out, never shaped at a width that does not yet exist — and the settings file survives its own handwriting: JSON's floats read back as the ints they were saved as |

## What CI adds beyond the battery

Every workflow that runs the battery also runs `tools/check_presets.gd`:
the export presets must parse, the head scripts must carry all their working
parts, and the Android preset must ship both ABIs with a version code that
has moved.

The Pages and npm workflows lower the engine's web loader through esbuild to
`firefox68,chrome57` — the browsers a reader keeps longest cannot parse
optional chaining and its kin, so an unlowered loader leaves the page's bar
motionless forever — and the build fails loudly, by token, if the lowered
file still carries any post-2017 parse-breaker. The page's head also carries
a WebGL2 pre-flight guard: a device that cannot run the app is told so, in
English and Persian, and the engine-sized download never starts on it. The
Android release ships both `armeabi-v7a` and `arm64-v8a` — an arm64-only APK
refuses to install on the 32-bit phones a reader keeps longest.

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

The browser's own clipboard is not reachable headlessly, so pasting the
token is proven on a served web build instead:

```bash
bash tools/test_web_paste.sh       # boot, open settings, paste, show
```

It serves `builds/web`, boots the app at a phone viewport, opens Settings
with a canvas click, and dispatches a real paste event carrying a known
token while sweeping for the field — the page's own event, exactly what
Ctrl+V sends — and confirms the app's answer (stamped into a document
attribute: the length and first bytes of what the field now holds) matches
the token byte for byte. Show then reveals the field for a screenshot.

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
