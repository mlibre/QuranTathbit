class_name CardEditor
extends Control
const ThemeScript := preload("res://scripts/ui/theme.gd")
const CardScript := preload("res://scripts/data/card.gd")
const MarkdownScript := preload("res://scripts/ui/markdown.gd")

## The card's own page, opened over whatever screen was reading it: the
## question and the answer as the markdown their author wrote, editable on
## the spot and saved to the very files the deck is. A typo or a better
## wording is noticed while studying, and the fix belongs there -- not in
## another app on another machine, waiting for a sync to carry it.
##
## The editor owns the page while it is open: the screen beneath does not
## answer the keyboard (its Space and 1-4 would reach into the fields), and
## Esc and Ctrl+Enter are answered here first. Saving writes front.md and
## back.md beside the card's media, updates the card in memory, and leaves
## the rest to the deck's own life: the next sync carries the edit to the
## repo as part of its one commit, exactly as a hand-edited file would.

signal saved(card: CardScript)
signal cancelled

var _card: CardScript
var _front: TextEdit
var _back: TextEdit
var _warn: Label

func _init(p_card: CardScript) -> void:
        _card = p_card

func _ready() -> void:
        set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        # The page beneath dims and stops taking input: the editor is the
        # whole world until it is closed.
        mouse_filter = Control.MOUSE_FILTER_STOP
        var dim := ColorRect.new()
        dim.name = "Dim"
        dim.color = Color(ThemeScript.INK.r, ThemeScript.INK.g, ThemeScript.INK.b, 0.34)
        dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        dim.mouse_filter = Control.MOUSE_FILTER_STOP
        add_child(dim)

        var center := CenterContainer.new()
        center.name = "Centre"
        center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        add_child(center)

        var panel := PanelContainer.new()
        panel.name = "Panel"
        panel.add_theme_stylebox_override("panel", ThemeScript.card_stylebox())
        panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        center.add_child(panel)

        var pad := MarginContainer.new()
        pad.name = "Pad"
        pad.add_theme_constant_override("margin_left", 30)
        pad.add_theme_constant_override("margin_right", 30)
        pad.add_theme_constant_override("margin_top", 26)
        pad.add_theme_constant_override("margin_bottom", 26)
        panel.add_child(pad)

        var column := VBoxContainer.new()
        column.name = "Column"
        column.add_theme_constant_override("separation", 12)
        pad.add_child(column)

        # The page's own heading: the pencil beside the words, the card's
        # reference under them, so the card being edited is never in doubt.
        var heading := HBoxContainer.new()
        heading.name = "Heading"
        heading.add_theme_constant_override("separation", 10)
        var mark := ThemeScript.PencilMark.new(ThemeScript.GOLD_DEEP)
        mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        heading.add_child(mark)
        var title := Label.new()
        title.name = "Title"
        title.text = "Edit card"
        title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        ThemeScript.dress(title, ThemeScript.TITLE, ThemeScript.GREEN_DEEP, true)
        heading.add_child(title)
        column.add_child(heading)

        var reference := Label.new()
        reference.name = "Reference"
        reference.text = _reference_of(_card)
        reference.text_direction = TextDirection.TEXT_DIRECTION_AUTO
        reference.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
        var script := ThemeScript.reference_script(reference.text)
        reference.add_theme_font_override("font", ThemeScript.font_for(script, 14))
        reference.add_theme_font_size_override("font_size", 14)
        reference.add_theme_color_override("font_color", ThemeScript.GOLD_DEEP)
        column.add_child(reference)
        column.add_child(ThemeScript.hairline())

        column.add_child(_caption("QUESTION"))
        _front = _field(_card.front, 78)
        column.add_child(_front)
        column.add_child(_caption("ANSWER"))
        _back = _field(_card.back, 210)
        column.add_child(_back)

        _warn = Label.new()
        _warn.name = "Warn"
        _warn.text = " "
        _warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        ThemeScript.dress(_warn, ThemeScript.CAPTION, ThemeScript.DANGER)
        column.add_child(_warn)

        var actions := HBoxContainer.new()
        actions.name = "Actions"
        actions.alignment = BoxContainer.ALIGNMENT_END
        actions.add_theme_constant_override("separation", 10)
        var quit := ThemeScript.ghost_button("Cancel", ThemeScript.INK_SOFT, 46)
        quit.name = "Cancel"
        quit.custom_minimum_size = Vector2(120, 46)
        quit.pressed.connect(_close)
        actions.add_child(quit)
        var keep := ThemeScript.primary_button("Save", 46)
        keep.name = "Save"
        keep.custom_minimum_size = Vector2(140, 46)
        keep.pressed.connect(_save)
        actions.add_child(keep)
        column.add_child(actions)

        resized.connect(_layout)
        call_deferred("_layout")
        _front.grab_focus()

## The page answers the window: the panel keeps a reader's measure on a
## desk and a phone's whole width in a hand, and the answer's field grows
## with the room -- capped, so a small window scrolls inside the field
## instead of the panel running past the screen.
func _layout() -> void:
        if size.x <= 0.0:
                return
        var panel: PanelContainer = get_node("Centre/Panel")
        var width: float = minf(size.x - 36.0, 560.0)
        panel.custom_minimum_size = Vector2(maxf(width, 280.0), 0.0)
        if _back != null:
                var room: float = size.y - 320.0
                _back.custom_minimum_size.y = clampf(room, 150.0, 330.0)

## The editor answers the keyboard before the page beneath it can: Esc
## leaves without touching anything, and Ctrl+Enter saves without leaving
## the fields for the mouse.
func _input(event: InputEvent) -> void:
        if event is InputEventKey and event.pressed and not event.echo:
                if event.keycode == KEY_ESCAPE:
                        _close()
                        get_viewport().set_input_as_handled()
                elif (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER) and (
                        event.ctrl_pressed or event.meta_pressed
                ):
                        _save()
                        get_viewport().set_input_as_handled()

func _caption(text: String) -> Label:
        var label := Label.new()
        label.text = text
        label.add_theme_color_override("font_color", ThemeScript.INK_SOFT)
        ThemeScript.dress(label, 12, ThemeScript.INK_SOFT, true)
        return label

## A field dressed like the app, not like a source editor: the page's own
## white, the page's own type, the verse's own direction left to the text.
func _field(text: String, min_height: int) -> TextEdit:
        var field := TextEdit.new()
        field.text = text
        field.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
        field.custom_minimum_size = Vector2(0, min_height)
        field.size_flags_vertical = Control.SIZE_EXPAND_FILL
        field.text_direction = TextDirection.TEXT_DIRECTION_AUTO
        field.add_theme_font_override("font", ThemeScript.vazir(15))
        field.add_theme_font_size_override("font_size", 15)
        field.add_theme_color_override("font_color", ThemeScript.INK)
        field.add_theme_color_override("caret_color", ThemeScript.GREEN_DEEP)
        var page := ThemeScript.soft_stylebox(ThemeScript.CARD, 12)
        page.border_color = ThemeScript.LINE
        page.set_border_width_all(1)
        page.content_margin_left = 12
        page.content_margin_right = 12
        page.content_margin_top = 10
        page.content_margin_bottom = 10
        field.add_theme_stylebox_override("normal", page)
        var focus := page.duplicate() as StyleBoxFlat
        focus.border_color = ThemeScript.GOLD
        focus.set_border_width_all(2)
        field.add_theme_stylebox_override("focus", focus)
        return field

func _close() -> void:
        cancelled.emit()
        queue_free()

func _save() -> void:
        var front := _front.text.strip_edges()
        var back := _back.text.strip_edges()
        if front.is_empty() or back.is_empty():
                _warn.text = "A card needs both a question and an answer."
                return
        if not _write(_card.folder.path_join("front.md"), front + "\n"):
                _warn.text = "The question could not be saved."
                return
        if not _write(_card.folder.path_join("back.md"), back + "\n"):
                _warn.text = "The answer could not be saved."
                return
        _card.front = front
        _card.back = back
        saved.emit(_card)
        queue_free()

static func _write(path: String, text: String) -> bool:
        var file := FileAccess.open(path, FileAccess.WRITE)
        if file == null:
                push_error("CardEditor: cannot write %s" % path)
                return false
        file.store_string(text)
        file.close()
        return true

## The first plain line of the card's question: the name of what is being
## edited, said the way the study page says it.
static func _reference_of(card: CardScript) -> String:
        for line in card.front.split("\n"):
                var plain := MarkdownScript.plain(line).strip_edges()
                if not plain.is_empty():
                        return plain
        return card.id
