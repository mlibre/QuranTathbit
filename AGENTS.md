# QuranTathbit — Design Rules

## What this app is

One deck, studied one card at a time, kept as plain folders and files, synced
through the user's own GitHub repository. Cross-platform (Android, Linux,
Windows, web) in Godot 4.7 with GDScript only.

- **One deck, no deck manager.** There is no deck browser, no deck creation,
  no card editor in the app. Cards are edited as files, in any editor, on any
  machine; the app only studies and syncs them. A feature that needs a second
  deck does not belong here.
- **Anki's math, exactly.** The scheduler is Anki's SM-2 with Anki's
  parameters, not an approximation. If a number changes, it changes because
  Anki changed it — say so in the file where it lives. No FSRS, no custom
  scheduler.
- **Folders and files, no database.** The deck is folders and markdown; the
  converter that seeds it is a developer tool. The app never parses Anki's
  formats. `progress.json` is the only file the app writes.
- **Local first.** The deck is fully usable offline, forever. Sync is a
  convenience that never blocks study and never loses work: a failed transfer
  is reported plainly and retried next time, and progress merges card by card
  so two offline devices both keep their reviews.
- **Gentle, never nagging.** No streaks, no timers-as-pressure, no FOMO, no
  "you haven't studied today" guilt. The app invites; it does not push.
  Leaving whenever is a supported way to use it. Cards you miss simply wait.

## Look and feel

- **Calm and bright.** Warm paper, a deep green, a gold accent, a Quranic
  typeface for the verses, Vazirmatn for everything else. Never dark, grim,
  spooky or clinical — this is a companion for something revered.
- **Still at rest, alive in answer.** Nothing loops, pulses, drifts or
  parallaxes on its own; the screen at rest is a page. Motion answers
  three things only: input (hover grows a breath, a held press settles,
  focus arrives like a hover so the keyboard feels like the mouse), a
  change of screen or state (one-shot arrivals that settle -- deeper
  screens come from below, coming home comes from above, numbers count
  in, cards assemble a beat apart), and work actually under way (the
  recitation's breathing bars, the sync mark turning while a sync runs).
  Feedback motion ends when its cause ends. Motion inside containers
  uses scale, never position -- containers own position, and a tween
  that fights them loses.
- **One name per thing.** front/back, again/hard/good/easy, deck, card,
  progress. A word that means two things teaches the user to stop trusting the
  signposts.
- **Pleasant to hold.** One expanding canvas with a centred column: the same
  layout is comfortable on a phone, a tablet and a window. Every input gets
  immediate, visible feedback; nothing waits without a sign of life.
- **Icons and visuals, not instructions.** A play button plays; a gold pill
  offers the code to type. Text explains only what a picture cannot.
- **Numbers die with the world, not on it**: what matters continuously — how
  many are due, how many learned — is stated once, plainly, on the home card.

## Engineering

- **One indent style per file**, one `class_name` per script, code-built UI (no external scenes
  beyond the entry point), headless SceneTree test suites.
- **Cache-free boot safety.** A fresh clone has no editor-built class cache,
  so every cross-file class reference is pinned behind a `preload` constant
  and quoted `extends` paths. `tools/battery.sh`'s second pass enforces this
  by running the suites with the class cache removed.
- **Fail visibly.** A deck that will not load, a sync that cannot finish, a
  card whose media is missing — each says so in the interface or the console,
  never silently.
- **Simple, deep, robust.** Handle the real inputs (a hand-corrupted
  progress.json, a shared deck with unseen cards, a repo with the user's own
  files in it). The simplest design that fully solves the problem, not the
  shallowest.
- **Delete what is not needed.** No dead code, no leftovers, no documents
  describing a world the app never built.
