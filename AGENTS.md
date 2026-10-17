# QuranTathbit — Design Rules

## What this app is

One deck, studied one card at a time, kept as plain folders and files, synced
through the user's own GitHub repository. Cross-platform (Android, Linux,
Windows, web) in Godot 4.7 with GDScript only.

- **One deck, no deck manager.** No deck creation and no deck manager in
  the app — the deck is folders and files, studied, read, synced, and
  edited on the spot through the one editor the session and the library
  share (it writes the card's own front.md/back.md, nothing else). A deck
  of scripture is also a book to read through, so the library belongs
  here. A feature that needs a second deck does not belong here.
- **Anki's math, exactly.** The scheduler is Anki's SM-2 with Anki's
  parameters, not an approximation. No FSRS, no custom scheduler. The one
  number the reader owns is the deck option Anki itself exposes — how many
  new cards a day offers (default 20) — a setting in Settings, never a
  change to the algorithm.
- **Folders and files, no database.** The deck is folders and markdown; the
  converter that seeds it is a developer tool, and the app never parses
  Anki's formats. The app writes `progress.json`; the on-the-spot editor
  writes the card's own `front.md`/`back.md`; and the installer may deliver
  bundled media a deck does not yet have (the Persian translation
  recitations) — additively, never overwriting what is already there.
- **The backup joins; it never takes away.** A zip of the deck is the same
  deck in one file, and bringing one back is a merge, not a restore:
  progress card by card (the better-informed entry wins), the travelling
  choices by their own moments, files only where the deck lacks them —
  the sync engine's own rules, so every door into the deck agrees on what
  a merge means. An export carries deck content only: editor metadata
  never rides, and the app's settings never ride (the token among them is
  a secret). The backup's filename is a literal, not chrome — it is said
  as written, digits and all, because dressing it would name a file that
  does not exist.
- **Local first.** The deck is fully usable offline, forever. Sync never
  blocks study and never loses work: a failed transfer is reported and
  retried, and progress merges card by card so two offline devices both keep
  their reviews.
- **Gentle, never nagging.** No streaks, no timers-as-pressure, no FOMO. The
  app invites; it does not push. Leaving whenever is supported, and cards
  you miss simply wait.

## Look and feel

- **Calm and bright.** Warm paper, a deep green, a gold accent, a choice of
  Quranic typefaces for the verses (Google Fonts only, licenses carried in
  `assets/fonts/`), Vazirmatn for everything else. Never dark, grim
  or clinical — this is a companion for something revered.
- **Still at rest, alive in answer.** Nothing loops, pulses or drifts on its
  own; the screen at rest is a page. Motion answers three things only:
  input (hover grows a breath, a held press settles, focus arrives like a
  hover), a change of screen or state (one-shot arrivals that settle —
  deeper screens from below, home from above, numbers count in), and work
  under way (the recitation's breathing bars, the sync mark turning).
  Feedback ends when its cause ends. Motion inside containers uses scale,
  never position — a tween that fights the container loses.
- **One name per thing.** front/back, again/hard/good/easy, deck, card,
  progress. A word that means two things teaches the user to stop trusting
  the signposts.
- **Pleasant to hold.** One expanding canvas with a centred column — the
  same layout on a phone, a tablet and a window. Every input gets
  immediate, visible feedback.
- **Icons and visuals, not instructions.** A play button plays; a gold pill
  offers the code to type. Text explains only what a picture cannot.
- **Numbers die with the world, not on it**: what matters continuously — how
  many are due, how many learned — is stated once, plainly, on the home
  card. The deck's whole holding is the one number no pill below says, so
  it stands alone on the card; the day's own story (due, new, learned)
  lives only in the pills, never said a second time above them.
- **Every size goes through fs()**: the font scale multiplies only the
  words, so every size a control displays — and every size a measurement
  takes beside it (a pill measured from its widest line, a mirror kept on
  the engine's own pitch, the ink's room) — is said through theme.gd's
  fs(), once, at the derivation. A size baked into a control at build time
  and a size measured at the same number must never drift apart.

## Engineering

- **One indent style per file**, one `class_name` per script, code-built UI
  (no external scenes beyond the entry point), headless SceneTree test
  suites.
- **Cache-free boot safety.** A fresh clone has no editor-built class cache,
  so every cross-file class reference is pinned behind a `preload` constant
  and quoted `extends` paths — `tools/battery.sh`'s cold pass enforces it.
- **The whole word is drawn, whatever its marks reach.** A verse's stacked
  vowels reach past the box its font declares, and every text control in the
  engine clips at that box — so the app measures the ink itself
  (`ThemeScript.ink_room`, from the shaped glyphs) and gives each surface the
  room it asks for: a RichTextLabel via its "normal" stylebox's content
  margins, a clipped Label via extra height around a centred line, the
  editor's mirror via per-line margins paid back out of the VBox separation
  so the pitch the TextEdit lays never drifts. Never pad by a guessed
  constant, never blame the font, never clip a mark.
- **A page reads from the edge its tongue reads from.** When the UI language
  is right-to-left (`I18n.is_rtl()`), the page's root turns
  (`LAYOUT_DIRECTION_RTL`), every title, label, field and line stands at the
  right edge, and the way back points right from the right corner; a page
  said again in another tongue says its own direction again. The alignment
  that puts a line there is `LEFT`, in both tongues — measured, not guessed:
  under an RTL layout the engine reads `LEFT` as the reading's start (the
  right edge) and `RIGHT` as the far end, so a `RIGHT` on an RTL page stands
  the title at the left margin, exactly the corner a reader once reported it
  stuck in. `LEFT` means "where the reading begins" on every page the app
  speaks.
- **The engine's own chrome still wears the app's hand.** A tooltip is
  raised by the engine, dressed by the theme alone — and the engine's
  default face carries no Arabic letters, so a Persian tooltip was a row of
  empty boxes in no language at all. The window's theme
  (`ThemeScript.tooltip_theme()`) carries a Vazirmatn `TooltipLabel` and the
  page's own panel behind it, and says nothing about anything else: a Theme
  holds only what it is given.
- **A field's two layers wear one font.** The RTL field is an input engine
  and a visible mirror, and every width the caret and the clicks are placed
  by is read from the font — so both layers share one face, always. The
  editor tells scripture from prose not by per-line faces (which would
  desync the caret from the ink) but by fallback: the verses' chosen hand as
  the base, its book twin behind it for what it does not draw (Amiri Quran
  writes no پ), and prose's own face beneath that (`ThemeScript.editor_face()`).
  And the field is opened on the words, never on the file's trailing
  newline — a phantom blank line under every reference is where a reader's
  eye goes first.
- **The chrome speaks the reader's tongue; the deck never changes.** Every
  user-visible string of the interface goes through `scripts/ui/i18n.gd`'s
  `t()` (English is the key and the fallback), in English, فارسی and
  العربية. The verses and their Persian translation are the deck's own
  content and are never translated. The language is asked once on first run
  and afterwards lives in Settings; like the day's pace, it travels with the
  deck's `progress.json`, merging by its own moment. Numbers are chrome too:
  a line carrying them is formatted through `f()` and a bare number through
  `num()`, so Persian and Arabic read their own digits (۱۰ دقیقه, ۱ روز —
  never "10m", "1d"); mark-up is never passed through `num()` wholesale,
  because a `[color=#B4553F]` tag's own hex digits would be dressed along
  with the count it colours.
- **Fail visibly.** A deck that will not load, a sync that cannot finish, a
  card whose media is missing — each says so, never silently.
- **Simple, deep, robust.** Handle the real inputs (a hand-corrupted
  `progress.json`, a shared deck with unseen cards, a repo with the user's
  own files). The simplest design that fully solves the problem, not the
  shallowest.
- **Delete what is not needed.** No dead code, no leftovers, no documents
  describing a world the app never built.
