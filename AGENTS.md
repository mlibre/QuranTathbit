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
  said again in another tongue says its own direction again. For **Label** and
  **LineEdit** the alignment that puts a line there is `LEFT`, in both
  tongues — measured, not guessed: under an RTL layout the engine reads a
  Label's `LEFT` as the reading's start (the right edge) and `RIGHT` as the
  far end, so a `RIGHT` on an RTL page stands the title at the left margin,
  exactly the corner a reader once reported it stuck in. A **RichTextLabel**
  answers the other way — its `LEFT` stays the visual left edge whatever the
  layout reads, measured on the same engine — so its lines must be told
  `RIGHT` in so many words (`settings_screen._text`), or every explanation
  line on a right-reading page hangs from the wrong edge, the corner a reader
  reported next. Two controls, two laws, one edge: measure which one you are
  holding before you align it. And a page whose root does not turn — the
  library, a popover — still asks its questions from the reading's edge: the
  shelf's entry line is told `TEXT_DIRECTION_RTL` and `RIGHT`, its pill row
  `LAYOUT_DIRECTION_RTL` (so همه stands at the right hand), and a slider
  inside an `LAYOUT_DIRECTION_RTL` container draws its fill growing from the
  right — measured, not guessed.
- **A bold run is told its own hand.** A `[b]` inside a RichTextLabel wears
  `bold_font` and `bold_font_size` — and when they are not overridden, the run
  falls to the theme's default face at the theme's default size, which on this
  app's theming carried no Arabic letters at all and drowned the number it
  dressed (card_view dresses all four faces and all four sizes; the home chip
  once dressed only one of each). Every run the bbcode can reach must find a
  face and a size the app chose, and a wash is a light tone by definition —
  a pill drawn in a text colour drowns its own words.
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
- **The field answers the press; the engine answers the key.** The engine
  lays a TextEdit's lines flush left while the field's mirror shows them
  flush right, so a raw click on the ink a reader sees is, to the engine, a
  click past the line's end — which a right-reading line answers with its
  very beginning, wherever the finger pressed. The field therefore takes
  every left press itself (`rtl_field._on_editor_input` accepts it), slides
  it back onto the engine's own words (`_hit`, through
  `get_line_column_at_pos` twice — once for the row, once for the column at
  the slid x), and gives the caret to the word the finger meant: one press
  places, two take the word, three the line, a held press chooses. The
  slide's row cannot be read from the column the first hit returns: that
  hit is asked at x=0, a wrapped row's far end, whose column belongs to the
  NEXT row — so every wrapped row but the last was slid by its neighbour's
  width and the caret landed a handful of words behind the finger (the
  reader's "waaay back" on a long translation). The row is found by its own
  place on the page instead: the wrap row whose band of y holds the press,
  said by the same rects that draw the caret. And because `select()` and
  `set_caret_*` move the caret without saying `caret_changed`, the field
  says it for them (`_mirror_follows`) or the mirror sits a whole hand
  behind.
- **A page scrolls under the finger, whatever the finger pressed.** The
  engine's own touch scrolling lives in ScrollContainer's mouse path, and
  it only ever receives a drag whose press landed on the container itself
  -- but a shelf is rows of buttons, a button takes the press, and on a
  phone the page behind the rows never moved. The hand's own scroller
  (`touch_scroll.gd`, one node standing above every page from the first)
  follows each real finger itself: past ten pixels the page follows the
  drag one-to-one, a fast release carries on alone and slows the way
  paper slows, any new finger catches it, and a press between rows
  scrolls like a press on one. Three laws hold the edges. Fields that own
  their own drags keep them (the writing fields, a rule the thumb slides,
  the scrollbar). A tap still clicks, because the touch's mouse echo --
  the press the engine makes from every touch -- is never touched. And a
  scroll never lands as a click on the row it began on: one far-off
  motion of the finger's own is delivered the moment the scroll starts,
  telling that row the hand has left (a scroll that ends inside its own
  row is the proof). The scroller's own drag is consumed before the GUI
  (so the engine's native scroller never double-scrolls), and the echo's
  motions are consumed while a scroll is afoot (so no row the finger
  passes over lights up) -- but its releases always pass, because they
  are what lets go cleanly. The engine's own finder for "the control a
  point stands on" went away with 4.7 (`gui_find_control`), so the walk
  is said once in the scroller itself -- children before parents, the
  last-added first, the invisible and the mouse-blind skipped -- at
  press-time only, never per frame.
- **The phone's back key is a page's way back, not the app's way out.**
  The engine quits on it by default; `quit_on_go_back` is off in the
  project settings, and the key is answered the way every page answers
  Esc -- whatever stands over the page closes first (the editor over the
  library, a popover, the search field's own keys), then the page, and
  only from home the app itself leaves. Work under way is not a page: a
  sync keeps the key. Two engine laws shape the answer: the key arrives
  while the engine walks the window's children, so the answer is deferred
  a frame (a page swapped mid-walk is refused outright); and a page still
  fading under its successor must give up its name to the page arriving
  (`_swap` renames the fading sibling), because the engine silently
  renames a clash to `@Control@44` and every hand that asks for Home
  would hold nothing -- a quick there-and-back is exactly when it
  happens.
- **A page's hero is its news, not its name.** The home page's middle card
  once carried the deck's name in shouting weight above a lonely figure-box
  a reader had to live under every day. The name is furniture, read daily
  and rarely hunted for; the next card is the news. The card now opens with
  the name at one calm measure, the deck's own ornament beneath it, and the
  next reference as the card's hero at the hero's own measure — and no
  figure at all, because the pills below own the numbers and nothing is
  said twice. A reader's latest report can also ask a removed line back:
  the repo hint left by an earlier round and returned by a later one, this
  time standing at the reading's edge.
- **The shelf says what a card means, not only what it says.** A browse row
  carries its verse in the mushaf cut and its Persian as a second quiet
  line under it, one line, ink soft, its tail trimmed with an ellipsis
  rather than cut mid-letter — so a reader hunting by meaning finds the
  card as surely as a reader hunting by words. The line comes from the
  card's own back (the first Persian text block), never from a table.
- **A rule a thumb drags runs the width of its page.** The volume popover
  was the app's worst box twice over — first a narrow slip, then a page of
  parts (a big number on its own line, a ticked rule) the reader still
  called wrong. It is one setting row said twice now: the quiet name with
  the live figure at the row's far end, and beneath it the mute anchoring
  one rule as wide as the page, its fill growing from the reading's own
  edge — the shape every volume rule the reader has ever dragged already
  taught their hand, because a control a hand rests on is sized for the
  hand, not for the panel it came in.
- **Yesterday's phones read the web too, or the build says no.** The
  engine's web loader ships speaking only today's browsers; a Firefox 68
  phone parses none of it and the page hangs forever, bar motionless. The
  Pages and npm workflows therefore lower `index.js` once through esbuild
  (`firefox68,chrome57`) and fail loudly, by token, if any post-2017
  parse-breaker survives; the page's head carries a WebGL2 pre-flight that
  tells a device it cannot run rather than downloading an engine at it.
  The same head carries a boot watch: a page that cannot start says why
  (every error, every promise nothing caught), and a load gone quiet for
  a long spell says so too, in both of the app's tongues -- a stuck page
  is never a silent one. And the worker that serves the page's own cache
  would keep a returning reader on the files their first visit cached
  while a newer deploy sat "waiting" beside it -- the very page that
  cannot run is the one that must say claim, so it never does; the worker
  is therefore patched in CI to take over the moment it installs
  (skipWaiting on install, clients.claim on activate), and the page turns
  itself once into the fresh cache when the takeover arrives
  (controllerchange). An APK that ships arm64 only refuses to install on
  the 32-bit phones a reader keeps longest, so the Android preset ships
  both ABIs.

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
