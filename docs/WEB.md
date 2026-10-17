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

- **the gz shim** — swaps the engine's `fetch` of `index.wasm` for
  `index.wasm.gz` (CI gzips it; static hosts serve the wasm raw) and
  decompresses with `DecompressionStream`, falling back to the raw file;
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
  (in its own tongue) instead of downloading an engine at it;
- **the boot watch** — a page that cannot start says why (every error,
  every promise nothing caught), and a load gone quiet for a long spell
  says so too;
- **the debug log** (`qt-debug-log`, new in v1.0.27) — from the page's
  first breath it collects the environment (UA, screen, WebGL2 + GPU
  string, wasm + wasm-SIMD, DecompressionStream, service worker state),
  every error and rejection, `console.error`/`warn`, and a five-second
  loading heartbeat (progress value + status visibility). Five taps on the
  loading screen — only while it is still loading — open the whole log
  full-screen with a Copy button (clipboard API with an `execCommand`
  fallback for old phones). This is how a reader on a phone the app cannot
  start on hands the developer the story; a stuck Firefox was the report.

## The loader speaks older browsers

The engine's own `index.js` ships speaking only today's browsers; CI
lowers it once through esbuild (`--target=firefox68,chrome57`) and fails
the build loudly, by token, if any post-2017 parse-breaker survives. The
same discipline governs the hand-written head scripts: ES5 only, verified
in CI by marker and working parts (`check_presets.gd` before export, the
Pages checks after it).

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
