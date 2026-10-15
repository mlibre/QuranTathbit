# QuranTathbit

[![Web app](https://img.shields.io/badge/play_in_browser-github_pages-1E6B52)](https://mlibre.github.io/QuranTathbit/)
[![CI](https://github.com/mlibre/QuranTathbit/actions/workflows/pages.yml/badge.svg)](https://github.com/mlibre/QuranTathbit/actions/workflows/pages.yml)

A quiet companion for keeping the Qur'an close. One deck, studied one card at a
time, kept as plain folders and files, synced through your own GitHub repo.

Built with Godot 4.7 and GDScript. Runs on Android, Linux, Windows and the web
from one codebase.

## What it is

- **One deck, no deck manager.** There is nothing to create, name, import or
  browse. The deck ships with the app; you study it.
- **Anki's learning math.** The scheduler is a faithful port of Anki's SM-2
  (the classic SuperMemo-2 algorithm with Anki's exact parameters): again
  −0.20 ease, hard −0.15, easy +0.15, hard factor 1.2, easy bonus 1.3,
  learning steps 1m/10m, graduating at 1 day, easy at 4, lapse multiplier 0,
  maximum interval 100 years, and Anki's fuzz so cards do not all return on
  the same day.
- **Cards are folders and files.** A deck is a folder; a card is a folder of
  markdown plus its media. No database, no import, no proprietary format —
  every card is something you can read, edit and diff in any editor on any
  machine.
- **Sync is your own GitHub repo.** Sign in with GitHub's OAuth device flow
  (or paste a personal token) and the deck lives in your private repository as
  the same folders and files. Phone, laptop and browser stay in step.
- **The browser stays light.** The web build ships the deck's text in its .pck
  (under a megabyte) and streams each recitation from `decks/quran/` beside
  `index.html` on demand, so the page opens fast and the audio is where it
  needs to be, when it needs to be.

## The deck on disk

```
quran/
  deck.json                  {"format": 1, "name": "Quran", "cards": [...]}
  001/
    front.md                 the question
    back.md                  the answer
    001001.mp3               media named from the markdown
  002/
    ...
  progress.json              what you have learned, per card
```

`front.md` and `back.md` are plain markdown. The app understands paragraphs,
`**bold**`, `*italic*`, `[links](https://…)` and `![name](name)` media
references — an audio reference becomes a play button, an image becomes a
picture. A card's Arabic verses are set in Amiri at a size meant to be read
across the room; Persian translations sit beneath them in Vazirmatn; the
interface itself wears Vazirmatn. Anything the markdown names is resolved next
to the markdown, so a card folder is self-contained.

Progress lives in `progress.json` beside `deck.json` — one entry per card id.
Two devices that studied different cards merge cleanly when they sync (more
reviews wins, the later answer breaks ties).

The bundled deck is 99 cards from Al-Fātiḥah and Al-Baqarah: the front names
the surah and āyāt, the back carries the verse, the makarem.ir translation, and
the recitation as audio.

## Sync, in one paragraph

On **Settings → Connect GitHub** the app shows a short code; you type it at
`github.com/login/device` on any device you trust, and the app is signed in. On
first sync it creates a private repository named `quran-tathbit` (renameable)
and pushes the deck. After that, each sync is a three-way merge per file keyed
on the last-synced checksum: a file changed only here is pushed, a file changed
only there is pulled, a file changed on both sides keeps your local edit
(cards) or merges card by card (progress). Anything else in your repo is left
alone.

Tokens are stored in the platform's user-data folder. The card content itself
is never encrypted — that is the point of a deck you can read.

While a sync runs a small overlay covers the screen with a plain phase ("Signing
in to GitHub", "Fetching what changed", …) and a progress bar that knows how
far along it is — so the first sync, which can take a minute against a fresh
repo, never looks frozen. A sync where nothing moved says so plainly instead of
silently finishing.

### Signing in

Sign-in is wired to the project's own OAuth app out of the box: the device-flow
client id (`Ov23liUgUybWeux2DCcF`, a public value by design) ships inside
`scripts/net/github_auth.gd`, so **Settings → Connect GitHub** works in every
build with no extra setup. A pasted classic token with `repo` scope is still
accepted as an alternative (and is the reliable path in browsers, where
cross-origin rules can block the device-flow endpoints).

Forking the project? Register your own OAuth app — every field to put into the
github.com form is written out in
[docs/OAUTH_SETUP.md](docs/OAUTH_SETUP.md) — then paste your client id over
the constant in `scripts/net/github_auth.gd`.

## Scripts

| path | what it holds |
| --- | --- |
| `scripts/main.gd` | the app root: deck install, settings, session, screens |
| `scripts/data/deck.gd` | a deck as folders and files; loads and saves progress |
| `scripts/data/card.gd` | one card: question, answer, media, scheduling state |
| `scripts/data/scheduler.gd` | Anki's SM-2 math, ported |
| `scripts/data/settings.gd` | the one small settings file |
| `scripts/net/http_client.gd` | the app's only HTTP path |
| `scripts/net/github_auth.gd` | the OAuth device flow |
| `scripts/net/github_sync.gd` | the three-way merge with GitHub |
| `scripts/ui/theme.gd` | palette, typefaces, script detection |
| `scripts/ui/markdown.gd` | the card markdown subset |
| `scripts/ui/card_view.gd` | renders a card side |
| `scripts/ui/home.gd` | the one front door |
| `scripts/ui/study.gd` | a session: question, answer, four buttons |
| `scripts/ui/sync_overlay.gd` | the calm progress screen shown while sync runs |
| `scripts/ui/settings_screen.gd` | connect, name the repo, sync |

## Running it

```bash
godot --path .            # run on the desktop
godot --headless --path . --import   # import assets once after a fresh clone
```

Export presets cover **Web**, **Windows**, **Linux** and **Android**; artifacts
land in `builds/`. Every push to `main` runs the battery and publishes the web
build to <https://mlibre.github.io/QuranTathbit/>; a tag `v*` additionally
builds Windows, Linux and Android and attaches them to a GitHub release.

## Downloading a build

- **Web** — <https://mlibre.github.io/QuranTathbit/> (nothing to install).
- **Windows / Linux / Android** — the latest release's assets: unzip and run
  the executable, or install the APK (self-signed, so allow installs from this
  source when your phone asks).
- **From source** — clone, `godot --headless --path . --import` once, then
  open in Godot 4.7 or export with the presets above.

## Tests

```bash
scripts/check_indent.sh    # indentation guard
tools/battery.sh           # the regression battery
tools/verify_deck.py       # the deck is the package's, byte for byte
```

The battery runs every `tests/regression_*.gd` suite twice over: once in the
machine's current state, and once with `.godot/global_script_class_cache.cfg`
removed — the state of any machine that pulled new classes but has not opened
the editor since. A suite is green only if it passes both ways. See
`docs/TESTING.md`.

`tools/verify_deck.py` re-extracts `quran-cards-2026-10-14.apkg` into a
scratch folder and compares every shipped file with the extraction: the
markdown and media must be byte-identical, and `deck.json` may differ only by
the deck's name label. CI runs it before every deploy and release, so a deck
that drifted from the package — by hand or by accident — fails the build
instead of shipping. Needs `zstandard` (`pip install zstandard`) like the
converter. The 12 MB `.apkg` itself is intentionally not committed; the deck
was proven byte-identical at introduction and `deck.json` records the source.
With the package absent, the script prints a single `skip` line and exits 0;
drop the developer's local copy back into the root to re-run the proof.

## Converting an Anki deck

The app never reads Anki's formats. `tools/apkg_to_deck.py` converts one once,
as a developer tool, and writes the folder layout above:

```bash
python3 tools/apkg_to_deck.py quran-cards-2026-10-14.apkg assets/decks/quran \
  --source https://quran.makarem.ir/
```

Needs `zstandard` (or the `zstd` binary) for modern packages, which compress
both the collection and its media.

## Fonts

`assets/fonts/` ships two open-licensed typefaces, licenses beside them:

- **Amiri** — a Naskh typeface cut for Quranic text, for the verses.
- **Vazirmatn** — a calm Persian sans, for the translations and the interface.

## Credits

- **Card data** — the verses, the Persian translation and the recitations come
  from [quran.makarem.ir](https://quran.makarem.ir), extracted from the public
  `quran-cards-2026-10-14.apkg` export. No other source is used for card
  content; `deck.json` records the source beside the cards it describes. See
  the attribution section of [LICENSE](LICENSE).
- **Code** — MIT, as laid out in [LICENSE](LICENSE).
- **Typefaces** — Amiri and Vazirmatn, each under its SIL OFL license in
  `assets/fonts/`.
