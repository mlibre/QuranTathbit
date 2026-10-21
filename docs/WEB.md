# The web build: what ships, what streams, and what a stuck page says

How QuranTathbit's web build is made. The principles live in `AGENTS.md`;
the engine-generic lessons (lowering the loader for old browsers, worker
takeover, dual ABI) live in
`.agents/skills/godot/references/export-platforms.md`. This file describes
how *this app's* pipeline applies them (`.github/workflows/pages.yml`,
mirrored by `npm.yml`).

## What the package carries

The web preset excludes the deck's audio entirely — the `.pck` carries the
deck's text and none of its sound (13 MB smaller before the first card is
even seen). The recitations are laid beside `index.html` instead: CI copies
`assets/decks/quran` to `builds/web/decks/`, keeping only the `*.mp3`, and
the app streams them from the site at study time (`card_view`'s
`_stream_from_site`, `_site_url` maps a deck path onto the page's own
origin). A fetched recitation is cached for the session.

## The page's head

`html/head_include` (in `export_presets.cfg`) carries the page's own
scripts, all hand-written ES5, single-quoted (the value lives inside a
double-quoted config line). In order of installation:

- **the notice builder** (`qt-notice`, new in v1.0.36) — the page's
  bad-news box, installed before every script that may need it: when a
  browser cannot run the app, the reader sees **two boxes** — English
  (left-to-right) and Persian (right-to-left), one short line each — and
  a direct link to the Android APK (`releases/latest/download/…`, so the
  link never goes stale with a release). The guards and the boot watch
  all speak through `window.__qtNotice(en, fa, {why, apk})`, so every
  warning wears the same face;
- **the gz shim** (`qt-wasm-gz`) — swaps the engine's `fetch` of
  `index.wasm` for `index.wasm.gz` (CI gzips it; static hosts serve the
  wasm raw) and decompresses with `DecompressionStream`, falling back to
  the raw file. The engine is handed a whole file or nothing: the bytes
  are read to their end *before* the response is returned, so a link
  that drops mid-download becomes a clean rejection the engine's own
  retry (four attempts) takes again — never a stream that breaks under
  the compiler with the failure leaking out as an unhandled promise
  (the report: a desktop Firefox that sometimes could not load, and a
  takeover notice for a page that had merely lost its connection);
- **the browser-keys gate** — capture-phase window listener that stops
  propagation for the browser-reserved combos (F5, Ctrl+R/L/T, and
  friends) so the engine's canvas cannot eat them, and hands the page's
  own paste events to the app (no permission sheet);
- **the update watch** — asks the service worker to re-check itself every
  fifteen minutes and whenever the tab is looked at again; a newer waiting
  worker becomes the engine's `pwa_update_available`, which Home answers
  with a quiet Update offer; on `controllerchange` the page turns itself
  once into the fresh cache;
- **the paste and zip bridges** — the page's own events for pasting and
  for choosing a `.zip`, handed to the app through the JS bridge;
- **the WebGL2 guard** — a pre-flight that tells a device it cannot run
  (one short line, through the notice builder's two boxes and APK link)
  instead of downloading an engine at it;
- **the SIMD guard** (`qt-simd-guard`, new in v1.0.35) — the engine's wasm
  is built on WebAssembly SIMD, which 32-bit browser builds cannot run
  (an ARMv7 phone Firefox has WebGL2, DecompressionStream, everything a
  modern page asks for — and still fails the wasm at validation, and
  before this guard it said nothing while the loading bar stood still).
  The guard probes with the canonical SIMD module before the engine
  downloads and says so through the notice builder (both ABIs ship in
  the APK, so the same phone installs it fine);
- **the boot watch** — the takeover notice belongs to the guards
  alone: a browser that cannot run the app is told so, but an ordinary
  error or an unhandled promise (a dropped link, a fetch that failed) is
  said to the console, never over the reader's page. The watch's one
  word to the reader is the stall line: a load gone quiet for a long
  spell (45 seconds, or 10 once a rejection has been seen) is told the
  connection may be slow and invited to reload — gently, through the
  same two-box notice, with no APK link.

## The loader speaks older browsers

The engine's own `index.js` ships speaking only today's browsers; CI
lowers it once through esbuild (`--target=firefox68,chrome57`) and fails
the build loudly, by token, if any post-2017 parse-breaker survives. The
same discipline governs the hand-written head scripts: ES5 only, verified
in CI by marker and working parts (`check_presets.gd` before export, the
Pages checks after it). And since a script can carry its marker and still
be dead — a missing `</script>` once merged three scripts into one JS blob
that died on a literal `<`, and a `\n` written for a JS string once became
a real line break no literal may span (the config parser expands it), both
leaving a phone at a silent loading bar — two further rules hold: the
value in the preset carries no real line break (write `\\n` when a script
means a newline) and every `<script>` it opens closes before the next
opens (`check_presets.gd`), and after export `tools/check_head_scripts.py`
takes the built page apart the way a browser does and hands every inline
script to `node --check`, so a head script that cannot parse fails the
build itself.

## The worker takes over at once

The stock service worker serves its cache first, so a returning reader
keeps the files their first visit cached while a newer deploy sits
"waiting" beside it — and the very page that cannot run is the one that
must say claim. CI patches the worker to `skipWaiting()` on install and
`clients.claim()` on activate (failing loudly if the exporter's worker
ever changes shape), the manifest gains the app's colours and portrait
orientation, and a 192px icon makes the app installable on a home screen.

## The Android build

The same resource rules as every other package (see `docs/DECK.md` for how
the audio rides), with both ABIs shipped (`armeabi-v7a` + `arm64-v8a`) so
32-bit phones can install it at all, and the version fields bumped in
lockstep with every release (`version.gd`, the presets, `package.json`).
