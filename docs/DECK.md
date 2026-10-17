# The deck: folders, the package, and the repair

How the deck lives on a device. The principles (one deck, folders and
files, the backup joins) live in `AGENTS.md`; the engine-generic law behind
the delivery (imported files in an exported package are invisible to the
file system) lives in
`.agents/skills/godot/references/assets-data-networking.md`. This file
describes how *this app* installs and keeps the deck whole.

## Shape

    user://decks/quran/
      deck.json            {"format": 1, "name": "Quran", "cards": [...]}
      progress.json        per-card state + the travelling choices
      001/
        front.md           the question
        back.md            the answer
        001001.mp3         the recitation (verse 1:1)
        001001-fa.mp3      its Persian translation

Progress is written only here; cards belong to their author and to the
user's own edits. The travelling choices (the day's pace, the verses' face,
the app's tongue) ride the same file, stamped with the moment of the
choice so a later choice wins the merge.

## The package's audio is a resource, not a file

In an exported package, an imported file — every one of the deck's mp3s —
is not a file the file system can see at its own path: the package carries
it as a resource under `.godot/imported`, with an `.import` remap beside
the name the deck knows. Measured on the engine, not guessed: in every
export, `FileAccess.file_exists` on the mp3's own path is false while
`ResourceLoader.load` of the same path returns the stream carrying the
original bytes as its data. An installer that copies through the file
system therefore installs no audio at all — every button honestly saying
it was unavailable was exactly this (v1.0.27's report from an Android
phone).

`main.gd`'s delivery therefore reads the bundle through the loader
(`_bundled_bytes`: `AudioStreamMP3` first, the file system only for files
that were never imported — the markdown, the deck's own json), and
enumerates what a folder carries from the `.import` remaps plus the
derived Persian twins (`_bundled_audio_names`: a verse-numbered recitation
implies `NNNNNN-fa.mp3`, the study page's own rule).

## Every boot, in order

1. `_install_deck` — the whole bundled deck, once, on a fresh device.
2. `_deliver_cards` — card folders the installed deck lacks, copied in
   whole; a folder the deck already has is never touched, so an update to
   the app adds what is new without eating anything that is there.
3. `_ensure_deck_audio` — the deck's audio made whole: a file the deck
   lacks is filled from the bundle, and a file that is there but does not
   begin as audio (`_plays_audio`: an ID3 tag or an MPEG frame sync) is
   repaired the same way. A file that already plays is never touched,
   whatever wrote it — the user's own deck is the truth, and this only
   fills what is missing. On the web the package carries no audio at all,
   so there is nothing to ensure and the recitations stream from the site.
4. `_sweep_sidecars` — Godot's editor sidecars (`.import`, `.uid`) never
   ride the deck: sync and the zip refuse them by name, and one quiet walk
   removes any an earlier release planted.

## Never touch what is there

Every joining in this app lives by one law: a file that is already in
place is never overwritten by the bundle, a sync, or an import. The only
exception is the audio repair above, and it replaces only files that are
not playable audio at all — a file that would never decode serves nobody.
The zip (`scripts/data/deck_zip.gd`) merges the same way: progress card by
card (the better-informed entry wins), travelling choices by their own
moments, files only where the deck lacks them.
