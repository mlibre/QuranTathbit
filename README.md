# QuranTathbit

<div align="center">

<img src="docs/media/qurantathbit_banner.svg" alt="QuranTathbit — a calm app for memorizing the Qur'an" width="800"/>

[![Play in your browser](https://img.shields.io/badge/%E2%96%B6%EF%B8%8F%20Play%20in%20your%20browser-GitHub%20Pages-1E6B52?style=for-the-badge&labelColor=14513D)](https://mlibre.github.io/QuranTathbit/)
[![Download](https://img.shields.io/badge/Download-Releases-C29A3B?style=for-the-badge&labelColor=14513D)](https://github.com/mlibre/QuranTathbit/releases)
![Made with Godot](https://img.shields.io/badge/made%20with-Godot%204.7-478cbf?style=for-the-badge&labelColor=14513D)

</div>

A calm app for memorising the Qur'an. Open it, study the card in front
of you, mark how well it went, come back tomorrow. That is the whole thing —
no account on someone else's server, no cloud you cannot see, no deck to build
or import. Your deck lives on your own machine.

The deck ships with the app: 99 cards from Al-Fātiḥah and Al-Baqarah, each one
a verse, its Persian translation, and a recitation — all from
[quran.makarem.ir](https://quran.makarem.ir), and from nowhere else (see the
[LICENSE](LICENSE) for the full attribution). Cards you found hard come back
sooner, easy ones later — the well-known SM-2 schedule decides, so each day
you sit down to exactly what is due that day. No streaks, no notifications:
the app invites, it never pushes, and cards you miss simply wait.

## ▶️ Play it in your browser

### **[▶️ Open QuranTathbit](https://mlibre.github.io/QuranTathbit/)**

Nothing to install, nothing to sign up for. Each recitation streams on
demand, and the app caches itself — after the first visit it opens instantly
and works offline, on any modern browser: desktop, tablet, or phone. A tab
or installed app left open hears about a new version on its own and quietly
offers **Update** — no refresh needed.

Want it on your home screen like any other app? Your browser's menu offers
**Install app** (Chrome, Edge) or **Add to Home Screen** (Safari, any
phone): it then opens full-screen and offline, with its own icon — no store,
no tab, no browser bars.

> In a browser you sign in with a one-minute token: press **Connect GitHub**
> and the app walks you through it. On desktop and Android the full
> device-code sign-in works.

## ⬇️ Download it for your computer

Grab a build from the [**Releases**](https://github.com/mlibre/QuranTathbit/releases) page:

| Platform    | File                                             | How to run                                           |
| ----------- | ------------------------------------------------ | ---------------------------------------------------- |
| **Windows** | `QuranTathbit-Windows.zip` → `QuranTathbit.exe`  | unzip anywhere, double-click                         |
| **Linux**   | `QuranTathbit-Linux.zip` → `QuranTathbit.x86_64` | `chmod +x`, then run                                 |
| **Android** | `QuranTathbit-Android.apk`                       | sideload; allow installs from this source when asked |

No installer, no dependencies, no account: the download *is* the app.

## A study session

![The app at work — home, a card, its answer, the next card](docs/media/app.gif)

On a phone the same session lays out for a hand — a phone's own page
width, two answer buttons to a row, every target a thumb tall:

<p>
  <img src="docs/media/phone_home.png" alt="Home on a phone" width="200"/>
  <img src="docs/media/phone_answer.png" alt="A card's answer on a phone" width="200"/>
</p>

1. **Home** — today's waiting count and one big **Study** button.
2. **Question** — the surah and āyāt in Arabic, set large in the middle of
   the page. Press **Space** (or **Show answer**) when you are ready.
3. **Answer** — the verse again, the Persian translation a step behind, and
   the recitation, each button saying which verse will speak. Four buttons
   ask how it went — **Again**, **Hard**, **Good**, **Easy** — each carrying
   its next interval as its biggest word, so the cost of each choice is
   visible up front.
4. **Rest** — when the queue is empty, the app says so and tells you to come
   back tomorrow. Progress is saved automatically.

Every verse, translation and explanation is selectable — drag, or long-press
on a touch screen — so you can paste any of it into your notes.

## Sync, in plain words

On **Settings → Connect GitHub** the app shows a short code; you type it at
`github.com/login/device` and the app is signed in. The first sync creates a
private repository named `quran-tathbit` (renameable) and pushes the deck
there. After that, every sync is a three-way merge: what changed only here is
pushed, what changed only there is pulled, and what changed on both sides
keeps your local edit (for cards) or merges card by card (for progress). A
small overlay with a progress bar covers the screen while it runs — a slow
first sync never looks frozen.

## Keyboard shortcuts

| Key                   | What it does                                   |
| --------------------- | ---------------------------------------------- |
| **Space** / **Enter** | show the answer, then answer **Good**          |
| **1** – **4**         | answer **Again**, **Hard**, **Good**, **Easy** |
| **Esc**               | close the session                              |

In the browser, keys the browser owns — **F5**, **F11**, **Ctrl+F** and
friends — keep working as on any other page.

## Credits

- **Card data** — verses, Persian translation, and recitations from
  [quran.makarem.ir](https://quran.makarem.ir); no other source is used.
- **Code** — MIT; **algorithm** — SM-2. Both attributions live in the
  [LICENSE](LICENSE).
- **Typefaces** — Amiri for the Arabic verses, Vazirmatn for the Persian
  text, each under its SIL OFL license in `assets/fonts/`.

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
