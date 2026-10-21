# Input: the field, the finger, and the back key

How QuranTathbit answers hands and keys. The principles live in `AGENTS.md`;
the engine-generic laws (bidi hit-testing, `ScrollContainer`'s touch path,
the back-key notification) live in
`.agents/skills/godot/references/2d-ui-input-i18n.md`. This file describes
how *this app* applies them.

## The writing field: two layers, one font

The RTL field (`scripts/ui/rtl_field.gd`) is an input engine and a visible
mirror. The engine lays a `TextEdit`'s lines flush left while the mirror
shows them flush right, so every width the caret and the clicks are placed
by is read from the font — both layers share one face, always. Scripture is
told from prose not by per-line faces (which would desync the caret from
the ink) but by fallback: the verses' chosen hand as the base, its book
twin behind it for what it does not draw (Amiri Quran writes no پ), and
prose's own face beneath that (`ThemeScript.editor_face()`).

The field is opened on the words, never on the file's trailing newline — a
phantom blank line under every reference is where a reader's eye goes first.

## The field answers the press; the engine answers the key

A raw click on the ink a reader sees is, to the engine, a click past the
line's end — which a right-reading line answers with its very beginning,
wherever the finger pressed. The field therefore takes every left press
itself (`_on_editor_input` accepts it), slides it back onto the engine's
own words (`_hit`, through `get_line_column_at_pos` twice — once for the
row, once for the column at the slid x), and gives the caret to the word
the finger meant: one press places, two take the word, three the line, a
held press chooses.

The slide's row is never read from the column the first hit returns: that
hit is asked at `x=0`, a wrapped row's far end, whose column belongs to the
NEXT row — so every wrapped row but the last was slid by its neighbour's
width and the caret landed a handful of words behind the finger (the
reader's "waaay back" on a long translation). The row is found by its own
band of y on the page instead: the wrap row whose band holds the press,
said by the same rects that draw the caret.

And because `select()` and `set_caret_*` move the caret without saying
`caret_changed`, the field says it for them (`_mirror_follows`) or the
mirror sits a whole hand behind.

## The page scrolls under the finger

The hand's own scroller (`scripts/ui/touch_scroll.gd`, one node standing
above every page from the first) follows each real finger itself: past ten
pixels the page follows the drag one-to-one, a fast release carries on
alone and slows the way paper slows, any new finger catches it, and a
press between rows scrolls like a press on one. Fields that own their own
drags keep them (the writing fields, a rule the thumb slides, the
scrollbar). A tap still clicks, because the touch's mouse echo is never
touched at press-time; and a scroll never lands as a click on the row it
began on: one far-off motion of the finger's own is delivered the moment
the scroll starts, telling that row the hand has left.

## The chosen words are carried by the app itself

Godot draws its own selection, and a phone offers nothing over ink the
app drew: Android's copy toolbar stands only over the system's real text
fields, no keyboard hangs over a drawn verse, and the engine's own label
menu waits for a right-click a finger never makes. So the app offers the
copy itself — one small gold pill (`scripts/ui/copy_chip.gd`, standing on
the window above every page) that appears the moment a selectable
RichTextLabel holds a choice and leaves the moment the choice does. A
label never announces its selection (there is no signal; the tell is
`get_selection_from() < 0`), so the pill looks for itself each frame,
the same quiet polling the page's clipboard half does. A press carries
the chosen words to the clipboard — through the page's own writer on the
web, the engine's everywhere else — says "Copied" for a beat, and then
lets the choice go. A press never takes the focus: focus leaving a label
is what ends its selection, and the words are still wanted through the
beat.

## The back key is a page's way back, not the app's way out

The engine quits on the back key by default; `quit_on_go_back` is off in
the project settings, and the key (`NOTIFICATION_WM_GO_BACK_REQUEST`,
arriving in `main.gd`'s `_notification`) is answered the way every page
answers Esc — whatever stands over the page closes first (the editor over
the library, a popover, the search field's own keys), then the page, and
only from home the app itself leaves. Work under way is not a page: a sync
keeps the key.

Two engine laws shape the answer: the key arrives while the engine walks
the window's children, so the answer is deferred a frame (a page swapped
mid-walk is refused outright); and a page still fading under its successor
must give up its name to the page arriving (`_swap` renames the fading
sibling), because the engine silently renames a clash to `@Control@44` and
every hand that asks for Home would hold nothing.
