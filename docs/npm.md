# QuranTathbit (web build)

The prebuilt **web build** of [QuranTathbit](https://github.com/mlibre/QuranTathbit) — a calm app for memorising the Qur'an — ready to serve from any static host, or to run with one command.

## Use it

```bash
npx qurantathbit
```

Downloads the package and serves it at <http://localhost:8080>. Or serve
the files yourself: everything here is static — `index.html`, the engine,
the deck's `.pck`, and the `decks/quran/` folder the recitations stream
from. Drop them on any static host (nginx, Caddy, an S3 bucket, GitHub
Pages) and they just work. From the browser's menu the page installs onto
a phone's home screen like any app — full-screen, offline, its own icon.

## What's inside

151 cards from Al-Fātiḥah and Al-Baqarah (through 2:145) — each one a
verse, its Persian translation and (for the original 99) a recitation, all
from [quran.makarem.ir](https://quran.makarem.ir) — on an SM-2
spaced-repetition schedule, with optional sync through your own private
GitHub repository.

- **Play it on GitHub Pages:** <https://mlibre.github.io/QuranTathbit/>
- **Desktop builds:** <https://github.com/mlibre/QuranTathbit/releases>
- **License:** MIT (code); card data carries its own attribution (see
  LICENSE).

## 🇵🇸 In support of Palestine

This project stands with Palestine. If you are able, please consider donating
to [UNRWA](https://www.unrwa.org) or a trusted aid organization of your
choice.
