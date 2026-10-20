# Connecting the app to GitHub

QuranTathbit syncs your deck and progress into **your own** private GitHub
repository (default name `quran-tathbit`). Sign-in uses GitHub's OAuth
**device flow**: the app shows a short code, you type it at
`github.com/login/device`, done — no client secret, same flow on every
platform.

## One-time setup: register an OAuth app

GitHub → Settings → Developer settings → OAuth Apps → **Register a new OAuth
app**. Fill the form exactly like this:

| Field                         | Value                                                                                                                                          |
| ----------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| **Application name**          | `QuranTathbit`                                                                                                                                 |
| **Homepage URL**              | `https://mlibre.github.io/QuranTathbit/`                                                                                                       |
| **Application description**   | `Quran flashcards. Sign in with GitHub to sync your deck and study progress across Android, Windows, Linux and Web.`                           |
| **Redirect URI**              | `https://mlibre.github.io/QuranTathbit/` (optional future browser-redirect: `http://localhost:8899/callback`; leave **wildcard matching off**) |
| **Enable Device Flow**        | **checked** — the flow the app uses on every platform.                                                                                         |
| **Expire user access tokens** | leave **unchecked** — the app does not yet refresh tokens, and expiring tokens would sign you out every few hours.                             |

Submit the form, then copy the **Client ID** (a public value, not a secret —
nothing else on that page is needed).

## The client id this build uses

The project's app is registered and its client id
(`Ov23liUgUybWeux2DCcF`) ships in `scripts/net/github_auth.gd` — sign-in
works in every build with no setup.

The **client secret** GitHub shows on the same page is *not* used anywhere:
the device flow does not need it, and a secret must never be committed to a
public repository. If it has ever been shared, regenerate it.

Forking the project? Register your own app with the table above and paste
your client id over the constant:

```gdscript
const CLIENT_ID := "your_client_id"
```

Until a build has a client id, Settings offers the fallback: paste a classic
personal access token with the `repo` scope (GitHub → Settings → Developer
settings → Personal access tokens). It works on every platform, including
the web build, where a browser's cross-origin rules can block the
device-flow endpoints.

## Where your deck lives

On first sync the app creates a **private** repository named `quran-tathbit`
(renameable in Settings) and pushes the deck as plain folders and files:

```
deck.json              deck metadata and card order
001/front.md           the question
001/back.md            verse, translation, recitation
001/001001.mp3         media referenced from the markdown
progress.json          what you have learned, one entry per card
```

Readable, editable and diffable in any editor; every device that signs in as
you merges against the same repo.

## Security notes

- The device-flow token has the `repo` scope only. It is stored in the
  platform's user-data folder (`user://settings.json`), never in the deck,
  never in the repo.
- Disconnecting (Settings → Disconnect) erases the local token. To revoke it
  fully: GitHub → Settings → Applications → Authorized OAuth Apps.
