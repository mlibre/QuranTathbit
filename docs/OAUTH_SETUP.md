# Connecting the app to GitHub

QuranTathbit syncs your deck and progress into **your own** private GitHub
repository (default name `quran-tathbit`). Sign-in uses GitHub's OAuth
**device flow**: the app shows a short code, you type it at
`github.com/login/device`, done. No client secret is ever needed, and the same
flow works on Android, Windows, Linux and the web.

## One-time setup: register an OAuth app

GitHub → Settings → Developer settings → OAuth Apps → **Register a new OAuth
app**. Fill the form exactly like this:

| Field | Value |
| --- | --- |
| **Application name** | `QuranTathbit` |
| **Homepage URL** | `https://mlibre.github.io/QuranTathbit/` |
| **Application description** | `Anki-style Quran flashcards. Sign in with GitHub to sync your deck and study progress across Android, Windows, Linux and Web.` |
| **Redirect URI** | `https://mlibre.github.io/QuranTathbit/` — the web build's home. (Optional, for a future browser-redirect sign-in: `http://localhost:8899/callback`. Leave **wildcard matching off**.) |
| **Enable Device Flow** | **checked** — this is the flow the app uses on every platform. |
| **Expire user access tokens** | Leave **unchecked** for now: the app does not yet refresh tokens, and expiring tokens would sign you out every few hours. Check it only if you prefer the stricter default and do not mind re-connecting occasionally. |

Submit the form, then copy the **Client ID** (a public value, not a secret —
nothing else on that page is needed).

## Give the app the client id

Open `scripts/net/github_auth.gd` and paste it:

```gdscript
const CLIENT_ID := "Iv1.xxxxxxxxxxxxxxxx"
```

Commit and push; the next builds carry it. Until a build has a client id, the
Settings screen says so plainly and offers the fallback: paste a classic
personal access token with the `repo` scope (GitHub → Settings → Developer
settings → Personal access tokens). A pasted token works on every platform,
including the web build, where a browser's cross-origin rules can block the
device-flow endpoints.

## Where your deck lives

On first sync the app creates a **private** repository named `quran-tathbit`
(renameable in Settings) and pushes the deck as plain folders and files:

```
deck.json              deck metadata and card order
001/front.md           the question
001/back.md            verse, translation, recitation
001/001001.mp3         media referenced from the markdown
002/ ...
progress.json          what you have learned, one entry per card
```

You can read, edit and diff it in any editor. Every device that signs in as
you merges against the same repo, so phone, laptop and browser stay in step.

## Security notes

- The device-flow token has the `repo` scope only. It is stored in the
  platform's user-data folder (`user://settings.json`), never in the deck,
  never in the repo.
- Disconnecting (Settings → Disconnect) erases the local token. To revoke it
  fully, go to GitHub → Settings → Applications → Authorized OAuth Apps.
