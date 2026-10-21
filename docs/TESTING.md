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
| `regression_scheduler` | Anki's SM-2 with Anki's numbers: interval bands, fuzz bounds, step delays, lapse/relearn round trips, ease moves, queue caps — the per-day new-card offer as the algorithm defaults it and as the reader chooses it — and the reader's own defer: a card put back in the initial basket waits out its day without spending the day's count and returns with tomorrow's fresh cards |
| `regression_deck`      | the deck as folders and files: load, card discovery, media resolution, progress round-trip, byte-stable saves (an int never re-saves as a float), a deferred card's day round-tripping while untouched cards stay out of the file, the reader's travelling choices — pace, verse face, app tongue — riding the same file, repair of a hand-corrupted `progress.json` |
| `regression_sync`      | sync against a fake GitHub: first push, second device, local-edit-wins, progress merge by card, the travelling choices (pace, verse face, app tongue) riding with it and merging by each one's own moment, single-commit runs, ref-conflict retry, foreign files untouched, editor metadata never travelling, web builds skipping media, the sync-conflict ask (local hard-forces, remote hard-forces, a stood-down ask replaces nothing and asks again next sync), the reader studying mid-sync (an answer that lands while the merge's fetch flies survives it — the local file is read after the fetch, never before), the push landing before the pull (this machine's word reaches the repo first), an answer landing while the commit flies still pushed on the next run (the baseline is the bytes that flew, never a re-reading of the disk) — and a quiet sync that asks for nothing: no upload, no tree, no commit, not even a file download, while both sides match the last sync's record |
| `regression_zip`       | the deck as one file: export packs deck.json, every card's words and media, and progress.json (editor metadata never rides), the destination chain always offering the app's own corner last, the picker offering only zips; import joins rather than replaces — a fresh deck receives everything, the better-informed card history wins and a later answer breaks ties, the travelling choices merge by their own moments, a file the deck already has keeps its own word while a missing one arrives, a whole unknown card joins as one card, a wrapped archive (one folder around the deck) is understood, a deck meeting its own backup moves nothing and does not even rewrite progress.json, and a stranger zip, a future format, twin folders, garbage bytes, and a zip-slip climb out of the deck are each refused by name |
| `regression_markdown`  | the card markdown subset, and the Arabic/Persian/Latin script detection that dresses each block |
| `regression_boot`      | a cold first run: the bundled deck installs itself with all 151 cards (Al-Baqarah 94-145 riding in additively — text-only, so a card offers no Listen buttons, and the mushaf's own section mark carried where the source has it), home says no holding on the card at all any more — the total-card box gone with its lonely figure, the day's numbers living only in the pills below, the card between owning the day's one news: the next reference standing as the card's hero at the hero's own measure, under the deck's calm name and its own ornament, the app's first question is asked (the language picker standing over home until a tongue is chosen, remembered on the device and carried with the deck), a session renders a real card in the mushaf cut at its own wider measure with the question's eyebrow a breath larger above the answer (its Listen button saying only what it does — شنیدن, never the address the page already says twice — and returning to rest the moment the sound runs out, its selections wearing the page's gold), the answer buttons' word and wait centred on one axis, the way out standing beneath the way forward (the quiet Not today centred under the page's one loud word, and standing on the question side alone — once the answer is seen, the card is answered, not put back), the volume coin opens a page that hangs from its own coin (its roof pointing up at it, never past the window's edge) and sets the player's loudness — the quiet name over the live figure said large and centered, and beneath them the tower the rule stands in: the loud speaker at its head (one press filling the rule), the rule the height of its own page that the hand drags anywhere it is touched (a touch near the foot a whisper, the fill rising from the foot to the round knob standing on the loudness), the quiet speaker at its foot (one press for silence, one back for what was), the box the reader called wrong twice being neither, the alif coin beside it offers the verse's own faces mid-session (a choice re-said on the standing card at once and stamped into the deck's file), every number the chrome says arrives in the tongue's own script (۱۰۰ and ۱ روز in Persian, ١٠٠ and ١ يوم in Arabic, the arithmetic English has always read), the pencil opens the card's own page (its fields writing flush right with each line reading its own direction, both fields wearing the verses' own hand — the answer's face falling back to its book twin for what the mushaf cut does not draw — opened on the words alone so no phantom blank line rides in from the file's trailing newline, its boxes named at the reading's edge in a right-reading tongue, its unsaved-changes guard asking before it lets the work go, its Read mode laying both sides out as the reader will see them), the library with its filter pills and running head (a right-reading page asking its questions from the right: the entry line's placeholder at the reading's start, the pills running همه first from the right hand) (an empty due list saying so warmly, a scrolled surah naming itself at the top, every pill keeping air on both sides of its words; each row carrying its verse's Persian as a second quiet line under the Arabic, its tail trimmed with an ellipsis rather than cut mid-letter; the pencil at the page's foot standing at the reading's edge in a right-reading tongue, its mark a breath larger), settings opens (the deck's name line and folder note gone from its pace card — the card carries its own running title and the stepper, nothing else — never the machine's own user:// address, the home page's middle card carrying no figures at all — its hero the next reference under the deck's name, the total box gone, tooltips speaking a face that carries the reader's letters, token field, Show/Save standing, no paste button — paste happens in the field itself — and the new-cards stepper answering a press, its choice stamped into the deck's own progress file; the quiet promise carrying its one label and no explainer beneath; the Backup card wired both ways and the real deck packed and joined back inside the app's own storage — every card's words and media riding, a deck meeting its own backup moving nothing, the picker offering the backup a test made, a row press joining it and saying so, Cancel putting the page away; the Reading card offering every verse face judged by its own basmala and every tongue, each choice shown as what it is with no explainer under it, a chosen face stamped into the same file, a chosen tongue re-saying the whole page and back; the Display card stepping both sizes through their real handlers — the interface scale re-flowing the window under the new factor, the text scale re-saying the page in its own new size, the percentages arriving in the tongue's own digits), and returns; the ink's own room is measured honestly per face (Amiri's damma standing past its font's box, the mushaf cut carrying its marks inside it, Vazirmatn's at the editor's size), the verse paragraph, the shelf's preview and the editor's mirror each carrying that room while the mirror keeps the engine's own line pitch, and a page said in Persian laid out from the right (root turned, titles and fields set LEFT — which under an RTL layout is the right edge, the reading's start — while every RichTextLabel explanation line is told RIGHT in so many words, because a RichTextLabel's LEFT stays the visual left edge under an RTL layout too, measured — the source line and the backup card's own words standing at the reading's edge (the source card carrying its link and no button beside it), the backup note still centred; card titles one breath larger than their captions in every tongue; the token hint and the browser's recitation note gone with their words while the repo hint stayed, standing at the reading's edge with the account line (وصل شده به …) beside the source line and the backup card's own words) with the Persian source line saying its say and stopping; and the editor's field answering the press itself — the caret landing at the word the finger meant on every edge of a right-reading line and inside the very row the finger pressed on a wrapped one (the engine's own flush-left hit-test answered with the slide the mirror travels, the row found by its own band of y rather than the wrap-boundary column a press at x=0 returns), a second press taking the word, a third the line, a held press choosing across; a card's page is said once the frame has laid its containers out, never shaped at a width that does not yet exist — and the settings file survives its own handwriting: JSON's floats read back as the ints they were saved as |
| `regression_touch_scroll` | a phone's finger, replayed event by event through the engine's own input path: the page under a shelf of buttons scrolls (down and up, one-to-one, from the middle where no edge can clamp the answer), a press between rows scrolls like a press on one, a tap still clicks through the touch's mouse echo, a jittery tap stays a tap (no scroll), a drag in the writing field and a drag on the volume rule leave the page alone (the rule's own drag still moving the rule), a scroll that begins and ends inside one row never lands as a click on that row, a fast release carries the page on and the coast is bounded, any new finger catches the coasting page at once — and the real library, driven by the app's own boot, scrolls under a finger on a real row |
| `regression_back_button` | the phone's back key, replayed as the window message the engine sends it as: the project hands the key to the app (quit_on_go_back off), the first question is put away by it and the page beneath stays, settings and the library each leave for home, the volume popover closes before the page beneath it, the search field gives up its keys before the library gives up its page, the editor over the library closes alone (a second back leaving the library), a session ends at the key and lands on home, and a sync under way keeps the key: nothing moves |
| `regression_extra_card` | the day's offer, spent or set to reviews alone, still leaves a deck with unseen cards: the caught-up home page offers one more new card (the offer standing only while an unseen card remains, never offering back a card deferred or suspended today, the session it opens holding exactly that one card), the merge law told once for both doors that merge a progress document (deck.gd's own state comparison and choice reading — a deliberate reset judged by its moment, noise never travelling), the deck's in-place adoption of its folder's next word (the card objects a session holds keep their identity — never orphaned by a wholesale replacement — and a local answer newer than the file keeps its ground), and the settings page's font segments and the session's face rows sized by the faces' own measured samples, so no preview outgrows the box that offers it |
| `regression_http` | the network client against a real socket: a local server answers on 127.0.0.1, and the client's requests — one at a time, the app never asking the network for two things at once — must complete against it, every HTTPRequest node sitting inside the tree before request() is called, the regression of a first sync that died in front of the user (ERR_UNCONFIGURED on a node started outside the tree) |
| `regression_install` | the deck a package installs is the deck the package carries, heard as well as read: the bundle's mp3s are read through the loader (an imported file is invisible to the file system at its own path), a fresh install lands playable audio, a deck that arrived without it is filled in and repaired, a file that already plays is never touched, and the editor's sidecars never ride the deck |
| `regression_editor_clipboard` | the editor's fields and the page's clipboard, joined: a paste lands in the field being written (one line in a reference, the whole shape in a verse), a selection chosen by the mouse is carried to the page and a cut lets it go only once it has truly arrived, the deck's patches (an install that still carries the basmala's retired leading star is repaired byte-exactly, a card the reader edited keeps its own word), and the ground walk that decides where a right press opens the browser's own menu |
| `regression_copy_chip` | the copy a chosen text is owed, where no keyboard and no system menu stands over the app's own ink (an Android phone above all): the pill stands over the very label holding the choice and centres on it, the press carries the chosen words to the clipboard and says so, the beat that follows keeps its place while the choice lives and lets the choice go when it ends, the pill leaves with a choice that goes un-copied, a freed label is pruned from the watch, and a second choice made during a copy's beat is answered with the same copy |
| `regression_device_code` | the device code the connect card shows, standing as a code stands: one line across — never the column of falling tiles a wrapping label's empty least width stacked it into — wider than tall, its chip closing around it with only its sleeve to spare, the same stance for a dashed code and a bare one |

## What CI adds beyond the battery

Every workflow that runs the battery also runs `tools/check_presets.gd`:
the export presets must parse, the head scripts must carry all their working
parts, and the Android preset must ship both ABIs with a version code that
has moved. The head scripts' shape is demanded too, both rules learned from
a phone left at a silent loading bar: the value may carry no real line
break (the config parser turns a `\n` escape into one, and no JS string
literal may span a line), and every `<script>` the value opens must close
before the next opens (a missing closer merges two scripts into one blob
that dies on a literal `<`).

The Pages and npm workflows lower the engine's web loader through esbuild to
`firefox68,chrome57` — the browsers a reader keeps longest cannot parse
optional chaining and its kin, so an unlowered loader leaves the page's bar
motionless forever — and the build fails loudly, by token, if the lowered
file still carries any post-2017 parse-breaker. The page's head also carries
a WebGL2 pre-flight guard and a WebAssembly SIMD one: a device that cannot
run the app is told so through the notice builder — two boxes, English and
Persian, one short line each, with a direct link to the Android APK — and
the engine-sized download never starts on it (a 32-bit phone Firefox passes
the WebGL2 check and still cannot validate the engine's SIMD-built wasm —
the guard is what turns that silent stuck into words). After export, every
inline script the built page carries is taken apart the way a browser reads
it and handed to `node --check` (`tools/check_head_scripts.py`) — a head
script that cannot parse fails the build, whatever its markers say. The
Android release ships
both `armeabi-v7a` and `arm64-v8a` — an arm64-only APK refuses to install on
the 32-bit phones a reader keeps longest.

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

The page's head scripts are proven the same way, on the exact bytes the
built page carries. Two node suites take the built `index.html` apart and
drive the scripts in a world the suite controls:

```bash
node tools/test_wasm_gz_whole.js   # the gz shim's whole-file-or-nothing law
node tools/test_boot_watch.js      # the boot watch's console-only law
```

The first proves the engine is handed a whole file or a clean rejection
(a good `.gz` hands over the whole decompressed file; a truncated one —
a link that dropped mid-download — and a missing one both fall back to
the raw wasm, whole; a non-wasm URL passes through untouched; when both
sides are missing the rejection is one the engine's own retry can take).
The second proves an unhandled promise is said to the console and never
over the reader's page, the gentle stall line arriving at 45 s of a
frozen bar — 10 s once a rejection has been seen — with no APK link,
and a guard that has spoken keeping the watch quiet for good. And
`bash tools/test_web_boot_watch.sh` proves both ends to end in a real
browser: the app boots through the buffered shim, a stray rejection
after boot leaves the page untouched, and a load that cannot finish
(the wasm deleted, the engine's retries exhausted) shows the reader
the stall line alone — never the takeover notice, never the Android
download button. The failure run serves on a fresh port every time: the
service worker an earlier run registered would serve its cached whole
build, and the page would boot, failure or no failure.

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
