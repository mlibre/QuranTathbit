# QuranTathbit (web build)

A quiet companion for keeping the Qur'an close — one deck, one card at a time,
with your own GitHub as the cloud.

This npm package contains the prebuilt **web build** of QuranTathbit, ready to
serve from any static host or run with a single command.

## Use it

```bash
npx qurantathbit
```

That downloads the package and starts a small static server at
<http://localhost:8080>. Open it in your browser, press **Study**, and you are
in.

If you prefer to serve the files yourself, every file in this package is
static — `index.html`, the engine's `.js` and `.wasm`, the deck's `.pck`, and
the `decks/quran/` folder the recitations stream from. Drop them on any static
host (nginx, Caddy, GitHub Pages, an S3 bucket, anything) and they just work.

## What it is

- A small Godot 4.7 web app for memorising the Qur'an.
- 99 cards from Al-Fātiḥah and Al-Baqarah: the verse, the Persian translation,
  and a recitation, all from [quran.makarem.ir](https://quran.makarem.ir).
- Spaced repetition (SM-2) that learns how well you remember.
- Optional sync through your own private GitHub repository.

## More

- **Project home:** <https://github.com/mlibre/QuranTathbit>
- **Play it on GitHub Pages:** <https://mlibre.github.io/QuranTathbit/>
- **Desktop builds:** <https://github.com/mlibre/QuranTathbit/releases>
- **License:** MIT (code); card data carries its own attribution (see LICENSE).

## 🇵🇸 In support of Palestine

This project stands with Palestine. If you are able, please consider donating
to [UNRWA](https://www.unrwa.org) or a trusted aid organization of your
choice.
