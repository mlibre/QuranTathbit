class_name RtlField
extends Container
const ThemeScript := preload("res://scripts/ui/theme.gd")

## A writing field that writes the way its words are read: right to left.
##
## Godot's TextEdit cannot align its lines at all -- not in a setting, not in
## a theme item; `text_direction` only sets the BiDi base and the caret's
## logic, and the lines stay flush against the left edge no matter what (the
## engine's own proposal queue has carried the gap for years). A reader
## editing an Arabic verse or a Persian translation was handed a paragraph
## pinned to the wrong edge of the page, which reads as a mistake in a
## scripture app if it reads as anything at all.
##
## So the field is two layers with one truth between them. Underneath, a
## RichTextLabel per visual line shows the words the way this app shows all
## its words: each line flush right, its own base direction read from its own
## first strong letter (a verse runs right to left, an audio file's name runs
## left to right inside the same right-flush block). Above it, a TextEdit
## with fully transparent ink, caret and selection -- the real input engine,
## taking every key, every drag, every long-press, doing every BiDi
## resolution per line exactly as the mirror does. The two agree on the
## layout because they share one font at one size and one line pitch, and the
## field asks the engine where the caret stands (`get_rect_at_line_column`)
## and where each laid-out line ends (`get_line_width`) to place its own
## drawn caret beside the mirror's ink. Selection rides in the mirror as a
## gold wash behind the chosen words, the same gold every selection in this
## app wears.
##
## The field grows to fit what is written (the page beneath scrolls; the
## field never scrolls inside itself), and when the words are Arabic the
## reader who asked "why is it not RTL in editing" sees, at last, why not:
## because it is.

signal text_changed
signal caret_moved
signal advance_requested  # Enter in a one-line field: the next field is waiting

const SIZE := 15
const PITCH := 4  # the engine's line spacing and the mirror's, kept equal

## The size both layers wear, said once: the input engine's invisible lines,
## the mirror's visible words and the room they ask for all read this one
## number, and it goes through fs() (theme.gd) so the text scale reaches the
## field without ever letting the two layers disagree -- a caret placed by
## one size over ink drawn at another is the lie this field exists to stop.
var _size := SIZE

var one_line := false  # a reference is one line; Enter hands the keyboard on

# The hand the field writes in. Both layers must wear the same one -- the
# input engine's invisible lines and the mirror's visible words -- or every
# width the caret and the clicks are placed by drifts away from the ink.
# The editor hands each field its own face (the verses' hand for the
# reference, the verses' hand with a book twin behind it for the answer),
# and the default is the page's own prose face.
var _face: Font = null

# The room the mirror's ink needs above and below each line: marks stacked
# past the font's own box would be drawn nowhere (a RichTextLabel clips at
# its rect), so every line label carries this much margin inside itself.
# The same amount comes back off the VBox's separation, keeping the pitch
# the TextEdit lays its own invisible lines at -- the mirror and the engine
# never drift apart, however many lines a verse wraps into.
var _room := 0

var _editor: TextEdit
var _lines: VBoxContainer
var _pending_text := ""
var _caret: CaretMark
var _field_look: StyleBoxFlat
var _focus_look: StyleBoxFlat
var _wash: String  # the selection's gold, as bbcode
var _part_counts: PackedInt32Array = PackedInt32Array()  # visual lines per logical line
var _wrapped_at := -1.0  # the width the current mirror was wrapped at
var _rebuilding := false
var _rebuild_pending := false  # one rebuild a frame, however many reasons

func _init() -> void:
        custom_minimum_size = Vector2(0, 58)
        clip_contents = true

## The hand the field writes in, said once for both layers. Changing it
## lays the words out again in the new hand, because the mirror's widths
## and the engine's must be the same widths or the caret lies.
func set_face(face: Font) -> void:
        _face = face
        if _editor == null:
                return
        _editor.add_theme_font_override("font", face)
        _rebuild()

func face() -> Font:
        return _face if _face != null else ThemeScript.vazir(SIZE)

func _ready() -> void:
        _size = ThemeScript.fs(SIZE)
        var wash := ThemeScript.SELECT
        _wash = "%02X%02X%02X%02X" % [
                int(round(wash.r * 255.0)), int(round(wash.g * 255.0)),
                int(round(wash.b * 255.0)), int(round(wash.a * 255.0)),
        ]

        # The look of the field itself, drawn here rather than styled: the
        # page's own white, the page's own edge, gold while it is being
        # written in -- the same dress the old editor's fields wore.
        _field_look = ThemeScript.soft_stylebox(ThemeScript.CARD, 12)
        _field_look.border_color = ThemeScript.LINE
        _field_look.set_border_width_all(1)
        _field_look.content_margin_left = 14
        _field_look.content_margin_right = 14
        _field_look.content_margin_top = 12
        _field_look.content_margin_bottom = 12
        _focus_look = _field_look.duplicate() as StyleBoxFlat
        _focus_look.border_color = ThemeScript.GOLD
        _focus_look.set_border_width_all(2)

        _lines = VBoxContainer.new()
        _lines.name = "Lines"
        _lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        _lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _lines.add_theme_constant_override("separation", PITCH)
        add_child(_lines)
        _editor = TextEdit.new()
        _editor.name = "Source"
        _editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
        _editor.text_direction = Control.TEXT_DIRECTION_AUTO
        _editor.scroll_fit_content_height = true
        _editor.add_theme_font_override("font", face())
        _editor.add_theme_font_size_override("font_size", _size)
        _editor.add_theme_color_override("font_color", Color(0, 0, 0, 0))
        _editor.add_theme_color_override("caret_color", Color(0, 0, 0, 0))
        _editor.add_theme_color_override("selection_color", Color(0, 0, 0, 0))
        _editor.add_theme_constant_override("line_spacing", PITCH)
        var empty := StyleBoxEmpty.new()
        _editor.add_theme_stylebox_override("normal", empty)
        _editor.add_theme_stylebox_override("focus", empty)
        _editor.add_theme_stylebox_override("read_only", empty)
        _editor.text_changed.connect(_on_text_changed)
        _editor.caret_changed.connect(_on_caret_changed)
        _editor.gui_input.connect(_on_editor_input)
        add_child(_editor)

        _caret = CaretMark.new()
        _caret.name = "Caret"
        _caret.mouse_filter = Control.MOUSE_FILTER_IGNORE
        add_child(_caret)

        # The engine's own way to lay out a container's children: the signal
        # fires whenever the children must be fitted (a size changed, a child
        # arrived, the minimum moved), and the fitting is done there.
        sort_children.connect(_sort_now)

        _editor.focus_entered.connect(_on_focus_changed)
        _editor.focus_exited.connect(_on_focus_changed)
        if not _pending_text.is_empty():
                _editor.text = _pending_text
                _pending_text = ""
        _rebuild()

func _on_focus_changed() -> void:
        queue_redraw()
        _reposition_caret()

## What the field holds. Setting it lays the words out anew -- even in the
## breath before the field has entered the tree, the words are kept waiting.
func set_text(value: String) -> void:
        if _editor == null:
                _pending_text = value
                return
        _editor.text = value
        _rebuild()

func get_text() -> String:
        return _editor.text

func take_focus() -> void:
        _editor.grab_focus()

func holds_focus() -> bool:
        return _editor.has_focus()

func set_caret_at_start() -> void:
        _editor.set_caret_line(0, false)
        _editor.set_caret_column(0, false)

func set_caret_at_end() -> void:
        var last := _editor.get_line_count() - 1
        _editor.set_caret_line(maxi(last, 0), false)
        _editor.set_caret_column(_editor.get_line(maxi(last, 0)).length(), false)

## The caret's own place in the field, for a page that scrolls it into view.
func caret_control() -> Control:
        return _caret

func _on_editor_input(event: InputEvent) -> void:
        if one_line and event is InputEventKey and event.pressed and not event.echo:
                if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
                        advance_requested.emit()
                        _editor.accept_event()

func _on_text_changed() -> void:
        if _rebuilding:
                return
        _rebuild_soon()
        text_changed.emit()

func _on_caret_changed() -> void:
        # The caret's move is also the selection's story: a drag choosing
        # words moves the caret and the choosing together, and the wash must
        # follow both.
        _rebuild_soon()
        caret_moved.emit()

## Whatever moved -- a letter, the caret, a choosing hand -- the mirror is
## rebuilt once for the frame, not once per cause.
func _rebuild_soon() -> void:
        if _rebuild_pending:
                return
        _rebuild_pending = true
        _rebuild.call_deferred()

func _get_minimum_size() -> Vector2:
        if _lines == null:
                return custom_minimum_size
        return _lines.get_combined_minimum_size() + Vector2(
                _field_look.content_margin_left + _field_look.content_margin_right,
                _field_look.content_margin_top + _field_look.content_margin_bottom,
        )

func _sort_now() -> void:
        if _lines == null or _editor == null:
                return
        var pad := Vector2(_field_look.content_margin_left, _field_look.content_margin_top)
        var inner := Vector2(
                maxf(size.x - pad.x * 2.0, 1.0),
                maxf(size.y - _field_look.content_margin_top - _field_look.content_margin_bottom, 1.0),
        )
        fit_child_in_rect(_lines, Rect2(pad, Vector2(inner.x, _lines.get_combined_minimum_size().y)))
        # The engine's own lines sit the room's distance below the mirror's
        # label tops -- where the words themselves stand -- so a click beside
        # a word lands on the very word it meant.
        fit_child_in_rect(
                _editor,
                Rect2(pad + Vector2(0, _room), Vector2(inner.x, maxf(inner.y - _room, 1.0)))
        )
        # The mirror's lines are the engine's own wraps; the engine wraps at
        # the width it is given, which is only honest once the field has been
        # laid out. A width that moved means the wraps move with it -- and the
        # engine needs the frame between to lay its own lines at that width.
        if absf(_editor.size.x - _wrapped_at) > 0.5:
                _rebuild_soon()
                return
        _reposition_caret()

func _draw() -> void:
        var look := _focus_look if _editor != null and _editor.has_focus() else _field_look
        draw_style_box(look, Rect2(Vector2.ZERO, size))

## Lay the mirror out again from the engine's own account of the text: every
## logical line becomes the visual lines the engine wrapped it into, each one
## a label flush right, wearing the gold where a hand has chosen words.
func _rebuild() -> void:
        if _lines == null or _editor == null:
                return
        _rebuild_pending = false
        for child in _lines.get_children():
                _lines.remove_child(child)
                child.queue_free()
        _part_counts = PackedInt32Array()
        var from_line := -1
        var from_col := -1
        var to_line := -1
        var to_col := -1
        if _editor.has_selection():
                from_line = _editor.get_selection_from_line()
                from_col = _editor.get_selection_from_column()
                to_line = _editor.get_selection_to_line()
                to_col = _editor.get_selection_to_column()
        var line_count := _editor.get_line_count()
        # The room the words on this page ask for, said once for them all: a
        # verse's tall stacks need it, a plain line needs none of it, and the
        # pitch gives back whatever the margins take -- so the mirror never
        # drifts from the engine that takes its keys.
        _room = 0
        for line in maxi(line_count, 1):
                if line >= line_count:
                        continue
                for part in _editor.get_line_wrapped_text(line):
                        var part_room := ThemeScript.ink_room(part, face(), _size)
                        _room = maxi(_room, maxi(part_room.x, part_room.y))
        _lines.add_theme_constant_override("separation", PITCH - 2 * _room)
        for line in maxi(line_count, 1):
                var source := _editor.get_line(line) if line < line_count else ""
                var parts := _editor.get_line_wrapped_text(line) if line < line_count else PackedStringArray([""])
                if parts.is_empty():
                        parts = PackedStringArray([""])
                var offset := 0
                for part in parts:
                        var start := source.find(part, offset)
                        if start < 0:
                                start = offset
                        _lines.add_child(_line_label(part, start, line, from_line, from_col, to_line, to_col))
                        offset = start + part.length()
                _part_counts.append(parts.size())
        _wrapped_at = _editor.size.x
        _reposition_caret()
        update_minimum_size()
        queue_sort()

## One visual line of the mirror: the words as written, flush right, markup
## lines in the gold of the app's citations, chosen words washed in gold.
func _line_label(part: String, start: int, line: int, from_line: int, from_col: int, to_line: int, to_col: int) -> RichTextLabel:
        var label := RichTextLabel.new()
        label.name = "Line"
        label.bbcode_enabled = true
        label.fit_content = true
        label.scroll_active = false
        label.autowrap_mode = TextServer.AUTOWRAP_OFF
        label.text_direction = Control.TEXT_DIRECTION_AUTO
        label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
        label.mouse_filter = Control.MOUSE_FILTER_IGNORE
        label.add_theme_font_override("normal_font", face())
        label.add_theme_font_size_override("normal_font_size", _size)
        # The room each line carries inside itself, so the marks that stand
        # past the font's box are drawn -- and the separation above gives it
        # back, so the lines stay on the engine's own pitch.
        var box := StyleBoxEmpty.new()
        box.content_margin_top = _room
        box.content_margin_bottom = _room
        label.add_theme_stylebox_override("normal", box)
        label.add_theme_constant_override("line_separation", 0)
        var plain := ThemeScript.script_of(part)
        var color := ThemeScript.INK if plain != "plain" else ThemeScript.GOLD_DEEP
        label.add_theme_color_override("default_color", color)
        # The words a hand has chosen, washed where the choosing ran through
        # this visual line. A line is washed when the selection runs through
        # its logical line at all: the range clamped to this line's columns.
        var body := ""
        if from_line >= 0 and from_line <= line and line <= to_line:
                var a := start
                var b := start + part.length()
                if line == from_line:
                        a = maxi(a, from_col)
                if line == to_line:
                        b = mini(b, to_col)
                if b > a:
                        body = (
                                _escape(part.substr(0, a - start))
                                + "[bgcolor=#" + _wash + "]" + _escape(part.substr(a - start, b - a)) + "[/bgcolor]"
                                + _escape(part.substr(b - start))
                        )
        if body.is_empty():
                body = _escape(part)
        label.text = "[color=#" + color.to_html(false) + "]" + body + "[/color]"
        return label

func _escape(text: String) -> String:
        # The brackets themselves must not be escaped twice: "[lb]" carries its
        # own "]", so each mark steps aside for a moment while the other passes.
        return (
                text.replace("[", "\u0001").replace("]", "\u0002")
                .replace("\u0001", "[lb]").replace("\u0002", "[rb]")
        )

## Where the field's own caret stands: the engine says where the caret lies
## within its flush-left line, and how wide that laid-out line is; the field
## slides both by the distance the line travels to reach the right edge.
func _reposition_caret() -> void:
        if _caret == null or _editor == null or _lines == null or not is_node_ready():
                return
        if not _editor.has_focus():
                _caret.visible = false
                return
        var line := _editor.get_caret_line()
        var column := _editor.get_caret_column()
        var wrap := _editor.get_line_wrap_index_at_column(line, column)
        var rect := _editor.get_rect_at_line_column(line, column)
        var width := _editor.get_line_width(line, wrap)
        var inner_w := maxf(size.x - _field_look.content_margin_left - _field_look.content_margin_right, 1.0)
        var visual := 0
        for i in mini(line, _part_counts.size()):
                visual += _part_counts[i]
        visual += wrap
        var y := _field_look.content_margin_top
        if visual < _lines.get_child_count():
                # The line's own words begin the room's distance inside its
                # label, and the caret stands where the words stand.
                y += _lines.get_child(visual).position.y + _room
        else:
                _caret.visible = false
                return
        _caret.position = Vector2(
                _field_look.content_margin_left + (inner_w - width) + rect.position.x,
                y + 1.0,
        )
        _caret.line_height = maxf(rect.size.y - 2.0, 12.0)
        _caret.queue_redraw()
        _caret.visible = true

## The caret the field draws itself: a slim gold rule beside the mirror's
## ink, standing where the engine's caret stands, seen only while the field
## holds the keyboard. Still while the hand rests, like the engine's own.
class CaretMark extends Control:
        var color := ThemeScript.GOLD_DEEP
        var line_height := 28.0

        func _init() -> void:
                custom_minimum_size = Vector2(2, 2)
                mouse_filter = Control.MOUSE_FILTER_IGNORE

        func _draw() -> void:
                draw_rect(Rect2(0, 0, 2, line_height), color)
