class_name CardEditor
extends Control
const ThemeScript := preload("res://scripts/ui/theme.gd")
const CardScript := preload("res://scripts/data/card.gd")
const CardViewScript := preload("res://scripts/ui/card_view.gd")
const MarkdownScript := preload("res://scripts/ui/markdown.gd")
const RtlFieldScript := preload("res://scripts/ui/rtl_field.gd")
const I18nScript := preload("res://scripts/ui/i18n.gd")

## The card's own page, opened over whatever screen was reading it: not a
## small window over a dimmed room but a whole page of the app, arriving the
## way deeper pages arrive, because a fix to scripture is not an aside -- it
## is the work of the moment.
##
## The page has two ways of standing. In WRITE, the question and the answer
## are written in the app's own right-to-left fields: every line flush
## against the right edge the way Arabic and Persian are read, the caret and
## the chosen words following the hand, markup lines wearing the gold of the
## app's citations so a file's name never masquerades as a sentence. In
## READ, the very card the deck will show is laid out whole -- the verses in
## the mushaf cut, the translations, the recitations, the citation at the
## foot -- so a wording is judged as it will be read, not as it is typed.
##
## Leaving with words unwritten is answered, not assumed: the footer asks
## once, quietly, and either keeps the page or closes it. Saving writes
## front.md and back.md beside the card's media, updates the card in memory,
## and leaves the rest to the deck's own life: the next sync carries the
## edit to the repo as part of its one commit, exactly as a hand-edited
## file would.

signal saved(card: CardScript)
signal cancelled

var _card: CardScript
var _volume := 1.0
var _player: AudioStreamPlayer
var _front: RtlFieldScript
var _back: RtlFieldScript
var _reference: Label
var _write_column: VBoxContainer
var _read_column: VBoxContainer
var _scroll: ScrollContainer
var _footer: VBoxContainer
var _actions: HBoxContainer
var _guard: HBoxContainer
var _warn: Label
var _mode := "write"  # the page's two ways of standing
var _closing := false

func _init(p_card: CardScript, p_volume := 1.0) -> void:
        _card = p_card
        _volume = p_volume

func _ready() -> void:
        set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        mouse_filter = Control.MOUSE_FILTER_STOP

        _player = AudioStreamPlayer.new()
        _player.name = "Player"
        _player.volume_db = linear_to_db(maxf(clampf(_volume, 0.0, 1.0), 0.0001))
        add_child(_player)

        add_child(ThemeScript.paper_backdrop())
        add_child(ThemeScript.paper_pattern())

        var margin := MarginContainer.new()
        margin.name = "Margin"
        margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        margin.add_theme_constant_override("margin_left", 24)
        margin.add_theme_constant_override("margin_right", 24)
        margin.add_theme_constant_override("margin_top", 22)
        margin.add_theme_constant_override("margin_bottom", 24)
        add_child(margin)

        var column := VBoxContainer.new()
        column.name = "Column"
        column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        column.add_theme_constant_override("separation", 12)
        margin.add_child(column)

        column.add_child(_build_top_bar())
        column.add_child(_build_reference())
        column.add_child(_build_scroll())
        column.add_child(_build_footer())

        resized.connect(_layout)
        call_deferred("_layout")
        ThemeScript.appear(self, 0.0, 26.0)
        _front.take_focus()
        _front.set_caret_at_end()

func _build_top_bar() -> Control:
        # The bar answers the reading's own direction: under a right-reading
        # tongue the way back points right from the right corner, the way the
        # settings page already reads, so every page answers alike.
        var bar: Dictionary = ThemeScript.top_bar(I18nScript.t("Edit card"), I18nScript.is_rtl())
        var row: HBoxContainer = bar["row"]
        var back: Button = bar["back"]
        back.tooltip_text = I18nScript.t("Back without saving")
        back.pressed.connect(_request_close)
        return row

## The page's two ways of standing, said in one quiet pill: Write, the words
## as their author wrote them; Read, the card as its reader will see it. It
## lives at the foot beside the saving, where a hand resting from the
## keyboard already is.
func _build_mode_switch() -> Control:
        var track := PanelContainer.new()
        track.name = "Mode"
        track.add_theme_stylebox_override("panel", ThemeScript.soft_stylebox(
                Color(ThemeScript.INK.r, ThemeScript.INK.g, ThemeScript.INK.b, 0.06), 21
        ))
        var row := HBoxContainer.new()
        row.name = "Row"
        row.add_theme_constant_override("separation", 2)
        track.add_child(row)
        for mode in ["write", "read"]:
                var button := Button.new()
                button.name = mode.capitalize()
                button.custom_minimum_size = Vector2(78, 42)
                button.text = I18nScript.t(mode.capitalize())
                button.tooltip_text = (
                        I18nScript.t("The words as their author wrote them") if mode == "write"
                        else I18nScript.t("The card as its reader will see it")
                )
                ThemeScript.pressable(button)
                button.pressed.connect(_set_mode.bind(mode))
                row.add_child(button)
        return track

func _dress_mode_buttons() -> void:
        var row: HBoxContainer = get_node_or_null("Margin/Column/Footer/Actions/Mode/Row")
        if row == null:
                return
        for mode in ["write", "read"]:
                var button := row.get_node(str(mode).capitalize()) as Button
                var on: bool = str(mode) == _mode
                var rest := ThemeScript.soft_stylebox(ThemeScript.GOLD_SOFT if on else Color(0, 0, 0, 0), 18)
                button.add_theme_stylebox_override("normal", rest)
                button.add_theme_stylebox_override("hover", rest)
                button.add_theme_stylebox_override("pressed", rest)
                button.add_theme_stylebox_override("focus", rest)
                button.add_theme_stylebox_override("disabled", rest)
                button.add_theme_font_override("font", ThemeScript.vazir(ThemeScript.CAPTION, on))
                button.add_theme_font_size_override("font_size", ThemeScript.fs(ThemeScript.CAPTION))
                button.add_theme_color_override("font_color", ThemeScript.GOLD_DEEP if on else ThemeScript.INK_SOFT)
                button.add_theme_color_override("font_hover_color", ThemeScript.GOLD_DEEP if on else ThemeScript.INK)
                button.add_theme_color_override("font_pressed_color", ThemeScript.GOLD_DEEP if on else ThemeScript.INK)
                button.add_theme_color_override("font_focus_color", ThemeScript.GOLD_DEEP if on else ThemeScript.INK_SOFT)

func _set_mode(mode: String) -> void:
        if mode == _mode:
                return
        _mode = mode
        _dress_mode_buttons()
        var writing := mode == "write"
        _write_column.visible = writing
        _read_column.visible = not writing
        _scroll.scroll_vertical = 0
        if writing:
                _front.take_focus()
        if not writing:
                _fill_read_column()
        ThemeScript.settle_in(_write_column if writing else _read_column, 0.0, 0.2)

## The thread that ties the page to its card: the question's first line, in
## the gold of every eyebrow, following the words as they are written.
func _build_reference() -> Control:
        _reference = Label.new()
        _reference.name = "Reference"
        _reference.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        _reference.text = _reference_of(_card)
        _reference.text_direction = TextDirection.TEXT_DIRECTION_AUTO
        var script := ThemeScript.reference_script(_reference.text)
        _reference.add_theme_font_override("font", ThemeScript.font_for(script, 14))
        _reference.add_theme_font_size_override("font_size", ThemeScript.fs(14))
        _reference.add_theme_color_override("font_color", ThemeScript.GOLD_DEEP)
        return _reference

func _build_scroll() -> Control:
        _scroll = ScrollContainer.new()
        _scroll.name = "Scroll"
        _scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
        _scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
        ThemeScript.style_scroll(_scroll)
        var wrap := CenterContainer.new()
        wrap.name = "Wrap"
        wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        _scroll.add_child(wrap)
        var content := VBoxContainer.new()
        content.name = "Content"
        content.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        content.add_theme_constant_override("separation", 14)
        wrap.add_child(content)

        _write_column = VBoxContainer.new()
        _write_column.name = "Write"
        _write_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        _write_column.add_theme_constant_override("separation", 6)
        content.add_child(_write_column)

        _write_column.add_child(_caption(I18nScript.t("QUESTION"), "QuestionCaption"))
        _front = RtlFieldScript.new()
        _front.name = "Front"
        _front.one_line = true
        _front.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        _front.text_changed.connect(_on_front_changed)
        _front.advance_requested.connect(func() -> void: _back.take_focus())
        _write_column.add_child(_front)
        # The file on disk ends with the newline every text file carries; the
        # field's words do not. Reading it in whole painted a phantom blank
        # line under every reference, so the page is opened on the words
        # themselves and the newline goes back on only when the file is
        # written again. Saving compares stripped to stripped either way, so
        # opening a card and closing it is still not an edit.
        _front.set_text(_card.front.strip_edges())
        # The question is a reference, and a reference is Arabic by
        # construction: the field writes in the verses' own hand.
        _front.set_face(ThemeScript.editor_face_for(
                ThemeScript.reference_script(_reference_of_text(_card.front))
        ))

        _write_column.add_child(_spacer(8))
        _write_column.add_child(_caption(I18nScript.t("ANSWER"), "AnswerCaption"))
        _back = RtlFieldScript.new()
        _back.name = "Back"
        _back.custom_minimum_size = Vector2(0, 180)
        _back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        _back.text_changed.connect(func() -> void: _clear_warning())
        _back.caret_moved.connect(_follow_caret)
        _front.caret_moved.connect(_follow_caret)
        _write_column.add_child(_back)
        _back.set_text(_card.back.strip_edges())
        # The answer is scripture first: the verses are written in the hand
        # the reader chose for them, and whatever that hand does not draw --
        # Amiri Quran writes no پ -- falls to its book twin behind it. One
        # face for the whole field keeps the caret and the clicks honest:
        # the mirror and the engine beneath it measure the same widths.
        _back.set_face(ThemeScript.editor_face())

        _write_column.add_child(_spacer(10))
        _write_column.add_child(_hint_row())

        _read_column = VBoxContainer.new()
        _read_column.name = "Read"
        _read_column.visible = false
        _read_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        _read_column.add_theme_constant_override("separation", 16)
        content.add_child(_read_column)
        return _scroll

func _spacer(height: int) -> Control:
        var room := Control.new()
        room.custom_minimum_size = Vector2(0, height)
        room.mouse_filter = Control.MOUSE_FILTER_IGNORE
        return room

func _caption(text: String, node_name := "Caption") -> Label:
        var label := Label.new()
        label.name = node_name
        label.text = text
        label.add_theme_color_override("font_color", ThemeScript.INK_SOFT)
        # A page read from the right names its boxes at the right edge; this
        # page's own layout stays left-to-right, so RIGHT is simply the right
        # edge here (under an RTL layout the meaning flips -- see the
        # settings page's _card_header for that law).
        if I18nScript.is_rtl():
                label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
        ThemeScript.dress(label, 12, ThemeScript.INK_SOFT, true)
        return label

## What the keyboard already knows, said once for the eye: leaving, saving,
## and the clipboard every hand already knows -- on the web the page carries
## it, on a desktop the engine does, and to the reader it is one thing.
func _hint_row() -> Control:
        var row := HBoxContainer.new()
        row.name = "Hints"
        row.alignment = BoxContainer.ALIGNMENT_CENTER
        row.add_theme_constant_override("separation", 8)
        row.mouse_filter = Control.MOUSE_FILTER_IGNORE
        row.add_child(ThemeScript.key_chip("Esc"))
        row.add_child(_hint_word(I18nScript.t("leave")))
        row.add_child(ThemeScript.key_chip("Ctrl + Enter"))
        row.add_child(_hint_word(I18nScript.t("save")))
        row.add_child(ThemeScript.key_chip("Ctrl + C / V"))
        row.add_child(_hint_word(I18nScript.t("copy & paste")))
        return row

func _hint_word(text: String) -> Label:
        var label := Label.new()
        label.text = text
        ThemeScript.dress(label, 12, ThemeScript.INK_SOFT)
        label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        return label

func _build_footer() -> Control:
        _footer = VBoxContainer.new()
        _footer.name = "Footer"
        _footer.add_theme_constant_override("separation", 8)

        _warn = Label.new()
        _warn.name = "Warn"
        _warn.text = " "
        _warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        ThemeScript.dress(_warn, ThemeScript.CAPTION, ThemeScript.DANGER)
        _footer.add_child(_warn)

        _actions = HBoxContainer.new()
        _actions.name = "Actions"
        _actions.alignment = BoxContainer.ALIGNMENT_END
        _actions.add_theme_constant_override("separation", 10)
        _actions.add_child(_build_mode_switch())
        var stretch := Control.new()
        stretch.name = "Stretch"
        stretch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        stretch.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _actions.add_child(stretch)
        var quit := ThemeScript.ghost_button(I18nScript.t("Cancel"), ThemeScript.INK_SOFT, 46)
        quit.name = "Cancel"
        quit.custom_minimum_size = Vector2(110, 46)
        quit.pressed.connect(_request_close)
        _actions.add_child(quit)
        var keep := ThemeScript.primary_button(I18nScript.t("Save"), 46)
        keep.name = "Save"
        keep.custom_minimum_size = Vector2(130, 46)
        keep.pressed.connect(_save)
        _actions.add_child(keep)
        _footer.add_child(_actions)
        call_deferred("_dress_mode_buttons")

        # The question the page asks before it lets the work go: nothing is
        # discarded on a stray press, and nothing is kept by accident either.
        _guard = HBoxContainer.new()
        _guard.name = "Guard"
        _guard.visible = false
        _guard.alignment = BoxContainer.ALIGNMENT_END
        _guard.add_theme_constant_override("separation", 10)
        var asking := Label.new()
        asking.name = "Asking"
        asking.text = I18nScript.t("The edits are not saved.")
        asking.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        asking.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        asking.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
        ThemeScript.dress(asking, ThemeScript.CAPTION, ThemeScript.DANGER)
        _guard.add_child(asking)
        var stay := ThemeScript.ghost_button(I18nScript.t("Keep editing"), ThemeScript.GREEN_DEEP, 46, 21)
        stay.name = "Stay"
        stay.pressed.connect(_dismiss_guard)
        _guard.add_child(stay)
        var discard := ThemeScript.ghost_button(I18nScript.t("Discard"), ThemeScript.DANGER, 46, 21)
        discard.name = "Discard"
        discard.pressed.connect(_close)
        _guard.add_child(discard)
        _footer.add_child(_guard)
        return _footer

func _dismiss_guard() -> void:
        _guard.visible = false
        _actions.visible = true

# --- the page's two ways of standing --------------------------------------------------

## The card as its reader will see it: both sides, dressed exactly as the
## session dresses them, so a wording is judged where it will be read.
func _fill_read_column() -> void:
        for child in _read_column.get_children():
                _read_column.remove_child(child)
                child.queue_free()
        _read_column.add_child(_preview_card(
                _front.get_text(), "", true
        ))
        _read_column.add_child(_preview_card(
                _back.get_text(), _reference_of_front(), false
        ))

func _preview_card(text: String, ref_line: String, lead: bool) -> Control:
        var panel := PanelContainer.new()
        panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        panel.add_theme_stylebox_override("panel", ThemeScript.card_stylebox())
        var pad := MarginContainer.new()
        pad.add_theme_constant_override("margin_left", 24)
        pad.add_theme_constant_override("margin_right", 24)
        pad.add_theme_constant_override("margin_top", 22)
        pad.add_theme_constant_override("margin_bottom", 22)
        panel.add_child(pad)
        var view := CardViewScript.new(_player)
        view.show_text(text, _card.folder, lead, ref_line, true)
        pad.add_child(view)
        return panel

func _on_front_changed() -> void:
        _reference.text = _reference_of_front()
        _clear_warning()
        # A hand follows the words: a reference rewritten in another script
        # is rewritten in that script's own face, and only then -- the face
        # is not re-said on every keystroke, just when its reason changes.
        var wanted := ThemeScript.editor_face_for(
                ThemeScript.reference_script(_reference_of_front())
        )
        if _front.face() != wanted:
                _front.set_face(wanted)

func _reference_of_front() -> String:
        return _reference_of_text(_front.get_text())

func _clear_warning() -> void:
        _warn.text = " "

## The caret never leaves the page's sight: wherever it stands, the page
## scrolls to keep it, the way every editor a hand already knows behaves.
func _follow_caret() -> void:
        var field := _back if _back.holds_focus() else _front
        if field == null or not field.holds_focus():
                return
        _scroll.ensure_control_visible(field.caret_control())

# --- leaving, saving -------------------------------------------------------------------

func _dirty() -> bool:
        # The card's files carry the trailing newline every text file carries
        # on disk; the field's words do not. Both sides are read the same way
        # before they are compared, so a page that was only opened and only
        # closed is not "edited" -- the guard is asked only when words truly
        # moved.
        return (
                _front.get_text().strip_edges() != _card.front.strip_edges()
                or _back.get_text().strip_edges() != _card.back.strip_edges()
        )

func _request_close() -> void:
        if _dirty():
                _guard.visible = true
                _actions.visible = false
                ThemeScript.settle_in(_guard, 0.0, 0.16)
                return
        _close()

func _close() -> void:
        if _closing:
                return
        _closing = true
        cancelled.emit()
        ThemeScript.vanish(self)

func _save() -> void:
        if _closing:
                return
        var front := _front.get_text().strip_edges()
        var back := _back.get_text().strip_edges()
        if front.is_empty() or back.is_empty():
                _warn.text = I18nScript.t("A card needs both a question and an answer.")
                return
        if front == _card.front.strip_edges() and back == _card.back.strip_edges():
                _close()
                return
        if not _write(_card.folder.path_join("front.md"), front + "\n"):
                _warn.text = I18nScript.t("The question could not be saved.")
                return
        if not _write(_card.folder.path_join("back.md"), back + "\n"):
                _warn.text = I18nScript.t("The answer could not be saved.")
                return
        _card.front = front
        _card.back = back
        _closing = true
        saved.emit(_card)
        ThemeScript.vanish(self)

static func _write(path: String, text: String) -> bool:
        var file := FileAccess.open(path, FileAccess.WRITE)
        if file == null:
                push_error("CardEditor: cannot write %s" % path)
                return false
        file.store_string(text)
        file.close()
        return true

## The editor answers the keyboard before the page beneath it can: Esc
## leaves without touching anything (once the guard is satisfied), and
## Ctrl+Enter saves without leaving the fields for the mouse.
func _input(event: InputEvent) -> void:
        if event is InputEventKey and event.pressed and not event.echo:
                if event.keycode == KEY_ESCAPE:
                        if _guard.visible:
                                _dismiss_guard()
                        else:
                                _request_close()
                        get_viewport().set_input_as_handled()
                elif (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER) and (
                        event.ctrl_pressed or event.meta_pressed
                ):
                        if _guard.visible:
                                _dismiss_guard()
                        else:
                                _save()
                        get_viewport().set_input_as_handled()


## The phone's back key is Esc's sibling: it dismisses the guard first,
## and only a second press leaves, through the same guarded door.
func request_back() -> bool:
        if _guard.visible:
                _dismiss_guard()
        else:
                _request_close()
        return true

## The first plain line of the card's question: the name of what is being
## edited, said the way the study page says it.
static func _reference_of(card: CardScript) -> String:
        return _reference_of_text(card.front)

static func _reference_of_text(source: String) -> String:
        for line in source.split("\n"):
                var plain := MarkdownScript.plain(line).strip_edges()
                if not plain.is_empty():
                        return plain
        return ""

# --- the page answers the window -------------------------------------------------------

func _layout() -> void:
        if size.x <= 0.0:
                return
        var margin: MarginContainer = get_node("Margin")
        margin.add_theme_constant_override("margin_top", int(22.0 + ThemeScript.top_inset()))
        margin.add_theme_constant_override("margin_bottom", int(24.0 + ThemeScript.bottom_inset()))
        var narrow := size.x < ThemeScript.NARROW
        margin.add_theme_constant_override("margin_left", 16 if narrow else 24)
        margin.add_theme_constant_override("margin_right", 16 if narrow else 24)
        var content: VBoxContainer = get_node("Margin/Column/Scroll/Wrap/Content")
        content.custom_minimum_size = Vector2(minf(ThemeScript.MEASURE, size.x - 32.0), 0.0)
