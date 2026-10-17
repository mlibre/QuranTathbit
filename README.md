# QuranTathbit

<div align="center">

<img src="docs/media/qurantathbit_banner.svg" alt="QuranTathbit — a calm app for memorizing the Qur'an" width="800"/>

[![Play in your browser](https://img.shields.io/badge/%E2%96%B6%EF%B8%8F%20Play%20in%20your%20browser-GitHub%20Pages-1E6B52?style=for-the-badge&labelColor=14513D)](https://mlibre.github.io/QuranTathbit/)
[![Download](https://img.shields.io/badge/Download-Releases-C29A3B?style=for-the-badge&labelColor=14513D)](https://github.com/mlibre/QuranTathbit/releases)
![Made with Godot](https://img.shields.io/badge/made%20with-Godot%204.7-478cbf?style=for-the-badge&labelColor=14513D)

</div>

A calm app for memorising the Quran. Each day it shows you the cards that
are due — a verse, its Persian translation, and its recitation — and asks
how it went. Cards you found hard come back sooner, easy ones later.

It ships with 151 cards from Al-Fātiḥah and Al-Baqarah (through 2:145) —
the original 99, joined additively by Al-Baqarah 94-145, transcribed from
the same source the deck has always recorded. Everything is in
Arabic and Persian, set in proper Quranic typefaces.

No streaks, no notifications, no account needed. The app invites; it never
pushes.

## ▶️ Use it in your browser

### **[▶️ Open QuranTathbit](https://mlibre.github.io/QuranTathbit/)**

Nothing to install. It opens like any website and works offline after the
first visit. To keep it on your phone like a normal app, use your
browser's menu: **Install app** (Chrome, Edge) or **Add to Home Screen**
(Safari).

## ⬇️ Download it instead

Grab a build from the [**Releases**](https://github.com/mlibre/QuranTathbit/releases) page:

| Platform    | File                                             | How to run                                           |
| ----------- | ------------------------------------------------ | ---------------------------------------------------- |
| **Windows** | `QuranTathbit-Windows.zip` → `QuranTathbit.exe`  | unzip anywhere, double-click                         |
| **Linux**   | `QuranTathbit-Linux.zip` → `QuranTathbit.x86_64` | `chmod +x`, then run                                 |
| **Android** | `QuranTathbit-Android.apk`                       | sideload; allow installs from this source when asked |

No installer, no dependencies. The download *is* the app.

## How a day works

![The app at work — home, a card, its answer, the library, a search](docs/media/app.gif)

1. **Home** shows how many cards wait today, and one big **Study** button.
2. A **question** appears: the surah and verse, set large in the middle of
   the page. Press **Space** or **Show answer** when you are ready.
3. The **answer** shows the verse again with its Persian translation, and
   each verse can be played — in Arabic, or spoken in Persian. Four
   buttons ask how it went: **Again**, **Hard**, **Good**, **Easy**. Each
   button says when the card will come back.
4. When the queue is empty, the app says so. Come back tomorrow.

A few quiet extras:

- **Edit anything, anywhere.** The pencil on a card opens a simple editor;
  the words are saved as plain files, and scripture is written in the
  verses' own hand — the ayeh never set in a Persian UI face. Spotted a
  typo mid-session? Fix it mid-session.
- **Browse the whole deck like a book.** Every verse on the page, flush
  right the way the Quran is read, its Persian translation as a second
  quiet line under it — so you can find a card by what it means, not only
  by what it says — with search (`2:93` or `۲:۹۳` — either digits work) and
  filters for what is due, new, or resting. In a right-reading tongue the
  page asks its questions from the right too: the search line waits at the
  right edge and the pills read همه، سررسید، تازه، در مرور from the right
  hand.
- **Set your own pace.** Settings → *New cards each day* (default 20, set
  it to 0 for review-only days).
- **Size the app for your eyes.** Settings → *Display*: an *interface
  scale* that grows the whole page at once — cards, pills and words
  together, the way a phone's display-size setting does — and a *text
  scale* that grows the words alone, leaving the layout where it is. Both
  are per-device comforts, so a desk and a phone can read at different
  distances.
- **Choose the verse's typeface.** In Settings → *Reading*, or right in a
  study session (the alif button beside the speaker): **Amiri Quran** (the
  default), **Amiri**, or **Noto Naskh Arabic** — each shown by its own
  drawing of the Basmala, so you choose with your eyes. Your pick follows
  the deck to every device.
- **The app speaks your language.** Menus and messages in English, فارسی or
  العربية — asked once the first time you open the app, changeable anytime
  in Settings. Numbers come in the language's own digits (۱ ۲ ۳, not 1 2 3),
  and waits are spoken in words — ۱ روز, not 1d. When the tongue reads from
  the right, the pages are laid out from the right too — titles, labels,
  fields, explanation lines, the tooltips a hover raises and the way back
  all standing where the reading starts. The verses and their Persian
  translation always stay exactly as they are. A choice that shows itself
  carries no explainer: the Reading card offers each typeface as its own
  drawing of the Basmala and each tongue in its own name, and the source
  card carries its link with no button beside it.
- **Every mark is drawn, whole.** The vowels a verse stacks above its
  tallest letters reach past the box a font declares for itself, and a
  renderer that clips at that box would draw them nowhere at all. The app
  measures where the ink really goes — in whatever face you chose, at
  whatever size — and gives it the room it asks for, so a damma above a
  hamza'd alef (أُنزِلَ) is never hidden again, on the study card, in the
  library, or in the editor.
- **Edit by touch, precisely.** Tap anywhere in a verse or a translation and
  the caret lands under your finger — on the very word you meant, in text
  that reads from the right, on the very line you pressed when the words
  wrap. One tap places the caret, a double tap takes
  the word, a triple takes the line, and a held tap selects as it moves.
- **Every page scrolls under your finger** — the library, a session, the
  settings — even when the drag starts on a button, which is where drags
  usually start. The page follows the finger, a quick flick carries on and
  slows the way paper slows, a tap still taps, and a scroll never lands as
  a press on the row it began on. Fields you drag in (writing, the volume
  rule) keep their own drags. The phone's back button works the way back
  buttons work everywhere: it closes what stands over the page first — an
  editor, a popover, the search field's keyboard — then the page itself,
  and only from home does it leave the app.
- **Keep the deck as one file.** Settings → *Backup* packs the whole deck —
  verses, recitations, and all your progress — into a single zip that lands
  in your Downloads folder (in a browser, it downloads). Import joins a
  backup to this deck the same way sync does — card by card, choices by
  their moment — so bringing one back can never take a review away.
- **Copy any verse or translation** — drag or long-press, and paste it
  anywhere.
- **Runs on the phone you already have.** The web build's engine loader is
  lowered at build time to the syntax an older Firefox or WebView reads
  (Firefox 68 / Chrome 57 era), so the page opens instead of hanging
  forever; a device too old to run it at all is told so, in English and
  Persian, instead of being left watching a bar that never moves — and if
  the app still cannot start, or a download stalls, the page says that too,
  in plain words, rather than hanging in silence. The app's service worker
  takes over the moment an update arrives, so a returning reader is never
  left on the copy their first visit cached. The
  Android APK ships both 32- and 64-bit (`armeabi-v7a` + `arm64-v8a`), so
  it installs on the old phone too — Android 5.0 or newer.

## Your progress, kept safe

Your deck can live in **your own private GitHub repository** — free, and
yours. Press **Connect GitHub** in Settings, follow the short sign-in, and
the app keeps everything in step: study on your phone, and the same deck
waits on your computer. If two devices study apart from each other, both
keep their work when they meet again. Not interested? Everything also
works fully offline, forever, on one device — and the *Backup* card keeps
the whole deck as one file you can carry by hand.

## Keyboard shortcuts

| Key                   | What it does                                   |
| --------------------- | ---------------------------------------------- |
| **Space** / **Enter** | show the answer, then answer **Good**          |
| **1** – **4**         | answer **Again**, **Hard**, **Good**, **Easy** |
| **Esc**               | close the session                              |

While editing a card: **Esc** closes without saving, **Ctrl+Enter** saves.

## Credits

- **Card data** — verses, Persian translation, and recitations from
  [quran.makarem.ir](https://quran.makarem.ir); no other source is used.
  Al-Baqarah 94-145 was transcribed by hand from that source by the deck's
  own reader (`tools/extend_baqarah.py` carries the transcription); the
  extension cards are text-only — no recitation audio exists for them, and
  none was fetched or invented.
- **Code** — MIT; **algorithm** — SM-2 (the same spaced-repetition math
  Anki uses). Both attributions live in the [LICENSE](LICENSE).
- **Typefaces** — Amiri Quran for the verses, Amiri for references, Noto
  Naskh Arabic as the reader's alternative, Vazirmatn for Persian — all from
  Google Fonts, each under its SIL OFL license in `assets/fonts/`.

## For developers

[AGENTS.md](AGENTS.md) holds the design rules, [docs/TESTING.md](docs/TESTING.md)
the test battery, [docs/OAUTH_SETUP.md](docs/OAUTH_SETUP.md) your own GitHub
app, [docs/README.npm.md](docs/README.npm.md) the npm package. To run from
source: `godot --headless --path . --import`, then open the project and
press F5.

## 🇵🇸 In Support of Palestine

This project supports Palestine. If you can, donate to [UNRWA](https://www.unrwa.org).

The people of Palestine endure daily suffering and loss, too often unseen and
unhelped. They are asking for support — and we can give our voice, our care,
and our help. Even a small act can matter. Please do what you can. 🤲

And if you ever doubt what is right and what is wrong, remember: when someone
kills a baby to loot baby’s belongings, he is the devil — and he stands on the
wrong side. ✊
