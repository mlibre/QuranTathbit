# Text, type, and the page's chrome

How QuranTathbit dresses words. The principles live in `AGENTS.md`; the
engine-generic laws (what Godot itself does with RTL text, ink, and themes)
live in `.agents/skills/godot/references/2d-ui-input-i18n.md`. This file
describes how *this app* applies them.

## One scale, said once

Every size the app shows goes through `theme.gd`'s `fs()`: the font scale
multiplies only the words, so a pill measured from its widest line and the
ink's room are said at the same derivation. A size baked into a control at
build time and a size measured at the same number must never drift apart.
`ThemeScript.set_ui_scale` / `set_font_scale` re-derive everything the pages
measure from.

## The whole word is drawn, whatever its marks reach

A verse's stacked vowels reach past the box its font declares, and every
text control in the engine clips at that box. `ThemeScript.ink_room`
measures the ink itself (from the shaped glyphs) and `give_rtl_room` hands
each surface the room it asks for:

- a `RichTextLabel` via its `"normal"` stylebox's content margins (an empty
  stylebox draws nothing and still grows the control);
- a clipped `Label` via extra height around a centred line;
- the editor's mirror via per-line margins paid back out of the VBox
  separation, so the pitch the `TextEdit` lays never drifts.

Never pad by a guessed constant, never blame the font, never clip a mark.
The same law sizes the boxes a face is offered in: Settings' font segments
and the session's face rows are as tall as the tallest face's measured
sample (`ThemeScript.basmala_sample_height`), so no preview outgrows the
box that offers it — the mushaf cut's line box stands half again its
font's size, and a fixed height once let its basmala draw past the border.

## A page reads from the edge its tongue reads from

When the UI language is right-to-left (`I18n.is_rtl()`), the page's root
turns (`LAYOUT_DIRECTION_RTL`), every title, label, field and line stands at
the right edge, and the way back points right from the right corner; a page
said again in another tongue says its own direction again.

The two most-used controls answer the turn differently (measured, not
guessed): under an RTL layout the engine reads a **Label's** `LEFT` as the
reading's start (the right edge) — so labels say `LEFT` to stand at the
reading's edge — while a **RichTextLabel's** `LEFT` stays the visual left
edge, so its lines must be told `RIGHT` in so many words
(`settings_screen._text`), or every explanation line hangs from the wrong
corner. A page whose root does not turn (the library, a popover) still asks
its questions from the reading's edge: the shelf's entry line is told
`TEXT_DIRECTION_RTL` and `RIGHT`, its pill row `LAYOUT_DIRECTION_RTL` (so
همه stands at the right hand), and a slider inside an RTL container draws
its fill growing from the right.

## Faces

- Scripture wears the reader's chosen Quranic typeface (`ThemeScript`'s
  `AYAH_FACES`); prose wears Vazirmatn. The question side is a reference —
  Arabic by construction — so it reads in the Quranic face whether or not
  its letters carry a script tell.
- A `[b]` run wears `bold_font` and `bold_font_size`; when they are not
  overridden, the run falls to the theme's default face at the theme's
  default size, which carried no Arabic letters at all. Every run the
  bbcode can reach must find a face and a size the app chose (`card_view`
  dresses all four faces and all four sizes; a hand-written `[i]` gets the
  sheared twin of the same face — neither Amiri nor Vazirmatn ships an
  italic). The deck's own single stars are never `[i]`: a star the author
  wrote is a star the reader sees (`**` still means weight).
- The engine's own chrome still wears the app's hand: a tooltip is raised
  by the engine and dressed by the theme alone, so the window's theme
  (`ThemeScript.tooltip_theme()`) carries a Vazirmatn `TooltipLabel` and
  the page's own panel behind it.

## The chrome speaks the reader's tongue; the deck never changes

Every user-visible string of the interface goes through `scripts/ui/i18n.gd`'s
`t()` (English is the key and the fallback), in English, فارسی and العربية.
The verses and their Persian translation are the deck's own content and are
never translated.

Numbers are chrome too: a line carrying them is formatted through `f()` and
a bare number through `num()`, so Persian and Arabic read their own digits
(۱۰ دقیقه, ۱ روز — never "10m", "1d"). Mark-up is never passed through
`num()` wholesale, because a `[color=#B4553F]` tag's own hex digits would be
dressed along with the count it colours. A wait is said in words, and the
language is asked once on first run, afterwards lives in Settings, and
travels with the deck's `progress.json` like every other choice.
