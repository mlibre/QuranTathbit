# QuranTathbit

<div align="center">

<img src="docs/media/qurantathbit_banner.svg" alt="QuranTathbit — a calm app for memorizing the Qur'an" width="800"/>

[![Play in your browser](https://img.shields.io/badge/%E2%96%B6%EF%B8%8F%20Play%20in%20your%20browser-GitHub%20Pages-1E6B52?style=for-the-badge&labelColor=14513D)](https://mlibre.github.io/QuranTathbit/)
[![Download APK](https://img.shields.io/badge/Download-Android%20APK-C29A3B?style=for-the-badge&labelColor=14513D)](https://github.com/mlibre/QuranTathbit/releases/latest/download/QuranTathbit-Android.apk)
![Made with Godot](https://img.shields.io/badge/made%20with-Godot%204.7-478cbf?style=for-the-badge&labelColor=14513D)

**English** · [فارسی](README.fa.md) · [العربية](README.ar.md)

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

## 📱 Put it on your phone (Android)

The app ships as a plain APK — no store, no account, no install wizard:

### **[⬇️ Download QuranTathbit-Android.apk](https://github.com/mlibre/QuranTathbit/releases/latest/download/QuranTathbit-Android.apk)**

(Android 5.0 or newer; the one file carries both 32- and 64-bit phones.)

1. Open the link on your phone — the file downloads.
2. Tap it (or open it from Downloads). Android asks to *allow installs
   from this source* once — allow it.
3. Install, open. That is the whole app; it works offline from the first
   run, and it never asks for an account.

Prefer a browser instead? The [web app](https://mlibre.github.io/QuranTathbit/)
installs the same way — **Install app** in Chrome/Edge or **Add to Home
Screen** in Safari.

## ⬇️ Desktop builds

Grab a build from the [**Releases**](https://github.com/mlibre/QuranTathbit/releases) page:

| Platform    | File                                             | How to run                                           |
| ----------- | ------------------------------------------------ | ---------------------------------------------------- |
| **Windows** | `QuranTathbit-Windows.zip` → `QuranTathbit.exe`  | unzip anywhere, double-click                         |
| **Linux**   | `QuranTathbit-Linux.zip` → `QuranTathbit.x86_64` | `chmod +x`, then run                                 |

No installer, no dependencies. The download *is* the app.

## How a day works

![The app at work — home, a card, its answer, the library, a search](docs/media/app.gif)

1. **Home** shows how many cards wait today, and one big **Study** button.
2. A **question** appears: the surah and verse, set large in the middle of the page. Press **Space** or **Show answer** when you are ready.
3. The **answer** shows the verse with its Persian translation, and each side can be played — in Arabic, or spoken in Persian. Four buttons ask how it went: **Again**, **Hard**, **Good**, **Easy** — each says when the card comes back.
4. Under **Show answer** (question side only) wait two quiet ways out: **Not today** puts the card back until tomorrow's new cards; **Not at all** takes it out of the schedule for good — as if you never started studying it. (To bring a "not at all" card back, delete its entry from `progress.json`.)
5. When the queue is empty, the app says so. Come back tomorrow.

A few quiet extras:

- **Edit anything, anywhere.** The pencil on a card opens a simple editor — **Ctrl+C/V** copy and paste work there, in the browser too. Words are saved as plain files, scripture written in the verses' own hand.
- **Browse the whole deck like a book.** Every verse flush right the way the Quran is read, its Persian translation as a second quiet line under it; search by verse (`2:93` or `۲:۹۳`) or by meaning, with filters for due, new, or resting cards.
- **Set your own pace.** Settings → *New cards each day* (default 2; set 0 for review-only days).
- **Size the app for your eyes.** Settings → *Display*: an *interface scale* grows the whole page at once, a *text scale* grows the words alone — both per-device comforts.
- **Choose the verse's typeface.** In Settings → *Reading*, or mid-session (the alif button beside the speaker): **Amiri Quran** (default), **Amiri**, or **Noto Naskh Arabic** — each shown by its own drawing of the Basmala, and your pick follows the deck.
- **The app speaks your language.** English, فارسی or العربية — asked once, changeable anytime in Settings. Numbers come in the language's own digits (۱ ۲ ۳), waits are spoken in words (۱ روز, not 1d), and a right-reading tongue lays every page out from the right.
- **Every mark is drawn, whole.** The app measures where the ink really goes — in whatever face, at whatever size — so a damma above a hamza'd alef (أُنزِلَ) is never hidden, on the card, in the library, or in the editor.
- **Edit by touch, precisely.** One tap places the caret under your finger, a double tap takes the word, a triple takes the line, and a held tap selects as it moves.
- **Every page scrolls under your finger** — even when the drag starts on a button. A flick coasts and slows the way paper slows, a tap still taps, and the phone's back button closes what stands over the page first.
- **Keep the deck as one file.** Settings → *Backup* packs verses, recitations and all your progress into a single zip; import joins a backup back in card by card, so a restore can never take a review away.
- **Copy any verse or translation** — drag or long-press, and paste it anywhere.
- **Runs on the phone you already have.** The web build loads even on Firefox 68 / Chrome 57-era browsers, says plainly when a device cannot run it or a download stalls, and its service worker takes over the moment an update arrives; the APK ships both 32- and 64-bit (`armeabi-v7a` + `arm64-v8a`) — Android 5.0 or newer.
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
| **S**                 | **Not today** — put the card back for the day  |
| **Esc**               | close the session                              |

While editing a card: **Esc** closes without saving, **Ctrl+Enter** saves, and **Ctrl+C / Ctrl+V** copy and paste.

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
app, [docs/README.npm.md](docs/README.npm.md) the npm package. The technical
documentation lives in [docs/TEXT.md](docs/TEXT.md) (type and the page's
chrome), [docs/INPUT.md](docs/INPUT.md) (the writing field, touch, the back
key), [docs/DECK.md](docs/DECK.md) (folders, the package's audio, the
repair) and [docs/WEB.md](docs/WEB.md) (the web build's pipeline). To run
from source: `godot --headless --path . --import`, then open the project and
press F5.

## 🇵🇸 In Support of Palestine

This project supports Palestine. If you can, donate to [UNRWA](https://www.unrwa.org).

The people of Palestine endure daily suffering and loss, too often unseen and
unhelped. They are asking for support — and we can give our voice, our care,
and our help. Even a small act can matter. Please do what you can. 🤲

And if you ever doubt what is right and what is wrong, remember: when someone
kills a baby to loot baby’s belongings, he is the devil — and he stands on the
wrong side. ✊
