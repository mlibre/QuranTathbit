# Connecting the app to GitHub

QuranTathbit syncs your deck and progress into **your own** private GitHub
repository (default name `quran-tathbit`). Sign-in uses GitHub's OAuth
**device flow**: the app shows a short code, you type it at
`github.com/login/device`, done. No client secret is ever needed, and the same
flow works on Android, Windows, Linux and the web.

## One-time setup: register an OAuth app

GitHub → Settings → Developer settings → OAuth Apps → **Register a new OAuth
app**. Fill the form exactly like this:

| Field                         | Value                                                                                                                                                                                                                  |
| ----------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Application name**          | `QuranTathbit`                                                                                                                                                                                                         |
| **Homepage URL**              | `https://mlibre.github.io/QuranTathbit/`                                                                                                                                                                               |
| **Application description**   | `Quran flashcards. Sign in with GitHub to sync your deck and study progress across Android, Windows, Linux and Web.`                                                                                                   |
| **Redirect URI**              | `https://mlibre.github.io/QuranTathbit/` — the web build's home. (Optional, for a future browser-redirect sign-in: `http://localhost:8899/callback`. Leave **wildcard matching off**.)                                 |
| **Enable Device Flow**        | **checked** — this is the flow the app uses on every platform.                                                                                                                                                         |
| **Expire user access tokens** | Leave **unchecked** for now: the app does not yet refresh tokens, and expiring tokens would sign you out every few hours. Check it only if you prefer the stricter default and do not mind re-connecting occasionally. |

Submit the form, then copy the **Client ID** (a public value, not a secret —
nothing else on that page is needed).

## The client id this build uses

The project's OAuth app is registered and its client id
(`Ov23liUgUybWeux2DCcF`) already ships in `scripts/net/github_auth.gd` —
sign-in works in every build with no extra setup.

The **client secret** GitHub shows on the same page is *not* used anywhere:
the device flow does not need it, and a secret must never be committed to
this or any public repository. Keep it private; if it has ever been shared,
regenerate it on the app's settings page.

Forking the project? Register your own app with the table above and paste
your client id over the constant:

```gdscript
const CLIENT_ID := "your_client_id"
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
