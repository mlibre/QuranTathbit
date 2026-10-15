# QuranTathbit

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

### Picking the client id

`scripts/net/github_auth.gd` holds `CLIENT_ID`, empty by default. Create one
OAuth app (GitHub → Settings → Developer settings → OAuth Apps → New
application; the device flow needs no callback URL) and paste its client id —
it is public by design, not a secret. With it empty the app says so plainly
instead of failing mysteriously, and a pasted classic token with `repo` scope
is always accepted as an alternative.

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
| `scripts/ui/settings_screen.gd` | connect, name the repo, sync |

## Running it

```bash
godot --path .            # run on the desktop
godot --headless --path . --import   # import assets once after a fresh clone
```

Export presets cover **Web**, **Windows**, **Linux** and **Android**; artifacts
land in `builds/`.

## Tests

```bash
scripts/check_indent.sh    # indentation guard
tools/battery.sh           # the regression battery
```

The battery runs every `tests/regression_*.gd` suite twice over: once in the
machine's current state, and once with `.godot/global_script_class_cache.cfg`
removed — the state of any machine that pulled new classes but has not opened
the editor since. A suite is green only if it passes both ways. See
`docs/TESTING.md`.

## Converting an Anki deck

The app never reads Anki's formats. `tools/apkg_to_deck.py` converts one once,
as a developer tool, and writes the folder layout above:

```bash
python3 tools/apkg_to_deck.py quran-cards-2026-10-14.apkg assets/decks/quran
```

Needs `zstandard` (or the `zstd` binary) for modern packages, which compress
both the collection and its media.

## Fonts

`assets/fonts/` ships two open-licensed typefaces, licenses beside them:

- **Amiri** — a Naskh typeface cut for Quranic text, for the verses.
- **Vazirmatn** — a calm Persian sans, for the translations and the interface.

## Credits

The deck content — verses, Persian translation and recitations — comes from
[quran.makarem.ir](https://quran.makarem.ir), converted from the public
`quran-cards-2026-10-14.apkg` export.
