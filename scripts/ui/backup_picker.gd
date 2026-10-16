class_name BackupPicker
extends Control
const ThemeScript := preload("res://scripts/ui/theme.gd")
const I18nScript := preload("res://scripts/ui/i18n.gd")

## The backups this machine can see, offered as what they are: one quiet
## card over the settings page, each file named with its own moment and
## size, the app's own backups standing first. A press outside the card,
## the Esc key, or the Cancel button all put it away -- a question asked,
## not a room entered. The file's fitness is judged by the import itself,
## which says so plainly when a zip is not a backup this app made.

signal picked(path: String)

## How many files the page offers: enough for a shelf of days, never a
## file manager's list of everything the folder ever held.
const ROWS := 8

var rows_made := 0

func _ready() -> void:
        set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        mouse_filter = Control.MOUSE_FILTER_STOP
        add_child(ThemeScript.paper_backdrop())
        add_child(ThemeScript.paper_pattern())
        resized.connect(_layout)
        call_deferred("_layout")

        var center := CenterContainer.new()
        center.name = "Centre"
        center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        center.mouse_filter = Control.MOUSE_FILTER_IGNORE
        add_child(center)

        var card := PanelContainer.new()
        card.name = "Card"
        card.add_theme_stylebox_override("panel", ThemeScript.card_stylebox())
        card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        center.add_child(card)

        var pad := MarginContainer.new()
        pad.name = "Pad"
        pad.add_theme_constant_override("margin_left", 26)
        pad.add_theme_constant_override("margin_right", 26)
        pad.add_theme_constant_override("margin_top", 22)
        pad.add_theme_constant_override("margin_bottom", 22)
        card.add_child(pad)

        var box := VBoxContainer.new()
        box.name = "Box"
        box.add_theme_constant_override("separation", 12)
        pad.add_child(box)

        var title := Label.new()
        title.name = "Title"
        title.text = I18nScript.t("Bring a backup back")
        title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        ThemeScript.dress(title, ThemeScript.BODY + 2, ThemeScript.GREEN_DEEP, true)
        box.add_child(title)
        box.add_child(ThemeScript.hairline())

        var rows := VBoxContainer.new()
        rows.name = "Rows"
        rows.add_theme_constant_override("separation", 10)
        box.add_child(rows)
        var found: Array = get_meta("backups", [])
        # The app's own backups stand first -- the name this app gives them
        # is the one thing a reader can recognise a backup by -- and within
        # each company, the newest.
        var ordered := found.duplicate()
        ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
                var mine := str(a["name"]).begins_with("qurantathbit")
                var theirs := str(b["name"]).begins_with("qurantathbit")
                if mine != theirs:
                        return mine
                return float(a["mtime"]) > float(b["mtime"])
        )
        for entry in ordered.slice(0, ROWS):
                rows.add_child(_row(entry))
        if found.is_empty():
                var empty := Label.new()
                empty.name = "Empty"
                empty.text = I18nScript.t(
                        "No backup files found. Backups this app makes land in your Downloads folder — copy one there first."
                )
                empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
                empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
                empty.custom_minimum_size = Vector2(230, 0)
                ThemeScript.dress(empty, ThemeScript.CAPTION, ThemeScript.INK_SOFT)
                rows.add_child(empty)

        var cancel := ThemeScript.ghost_button(I18nScript.t("Cancel"), ThemeScript.INK_SOFT, 44)
        cancel.name = "Cancel"
        cancel.pressed.connect(_close)
        box.add_child(cancel)
        ThemeScript.stagger_in(box, 0.05, 0.22)


## The page answers the window: the card keeps a reader's measure and never
## runs wider than a phone can hold.
func _layout() -> void:
        if size.x <= 0.0:
                return
        var card: PanelContainer = get_node_or_null("Centre/Card")
        if card != null:
                card.custom_minimum_size = Vector2(minf(420.0, size.x - 48.0), 0.0)


## The list travels with the picker as metadata rather than through a
## constructor argument, and setup() is called before the node enters the
## tree: _ready runs at add_child time, so anything handed in afterwards
## would arrive after the page was already built.
func setup(backups: Array) -> void:
        set_meta("backups", backups)


## One file, one row: its name, and beneath it the moment it was made, its
## size, and which shelf it was found on -- a person chooses a backup by
## when it was taken, and the name is the way in.
func _row(entry: Dictionary) -> Button:
        var button := Button.new()
        button.name = "Row" + str(rows_made)
        rows_made += 1
        button.set_meta("path", str(entry["path"]))
        button.custom_minimum_size = Vector2(0, 64)
        var rest := ThemeScript.soft_stylebox(ThemeScript.CARD, 14)
        rest.border_color = Color("#D9CFBB")
        rest.set_border_width_all(1)
        rest.content_margin_left = 14
        rest.content_margin_right = 14
        var wash := rest.duplicate() as StyleBoxFlat
        wash.bg_color = Color(ThemeScript.GREEN.r, ThemeScript.GREEN.g, ThemeScript.GREEN.b, 0.10)
        wash.border_color = ThemeScript.GREEN
        var held := rest.duplicate() as StyleBoxFlat
        held.bg_color = Color(ThemeScript.GREEN.r, ThemeScript.GREEN.g, ThemeScript.GREEN.b, 0.16)
        held.border_color = ThemeScript.GREEN
        button.add_theme_stylebox_override("normal", rest)
        button.add_theme_stylebox_override("hover", wash)
        button.add_theme_stylebox_override("pressed", held)
        button.add_theme_stylebox_override("focus", wash)
        var stack := VBoxContainer.new()
        stack.name = "Stack"
        stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        stack.alignment = BoxContainer.ALIGNMENT_CENTER
        stack.add_theme_constant_override("separation", 3)
        stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
        var name := Label.new()
        name.name = "FileName"
        name.text = str(entry["name"])
        name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        ThemeScript.dress(name, ThemeScript.BODY, ThemeScript.INK, true)
        stack.add_child(name)
        var meta := Label.new()
        meta.name = "Meta"
        meta.text = I18nScript.num("%s · %s" % [_when(float(entry["mtime"])), String.humanize_size(int(entry["bytes"]))])
        meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        ThemeScript.dress(meta, ThemeScript.CAPTION, ThemeScript.INK_SOFT)
        stack.add_child(meta)
        var shelf := Label.new()
        shelf.name = "Shelf"
        shelf.text = I18nScript.t("Downloads") if bool(entry["shared"]) else I18nScript.t("App storage")
        shelf.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        ThemeScript.dress(shelf, ThemeScript.CAPTION, ThemeScript.INK_SOFT)
        stack.add_child(shelf)
        button.add_child(stack)
        ThemeScript.pressable(button)
        button.pressed.connect(func() -> void:
                picked.emit(str(entry["path"]))
                _close()
        )
        return button


## A moment said in numbers a reader reads at a glance -- the day, then the
## hour of that day, so two copies of one day tell each other apart.
static func _when(unix: float) -> String:
        var moment: Dictionary = Time.get_datetime_dict_from_unix_time(int(unix))
        return "%04d-%02d-%02d %02d:%02d" % [
                moment["year"], moment["month"], moment["day"], moment["hour"], moment["minute"],
        ]


## A press on the page around the card is the oldest way a picker is put
## away; the card itself holds its ground.
func _gui_input(event: InputEvent) -> void:
        if event is InputEventMouseButton and event.pressed:
                _close()


## Esc, the app's one way out everywhere else, puts the page away too.
func _unhandled_input(event: InputEvent) -> void:
        if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
                _close()
                get_viewport().set_input_as_handled()


func _close() -> void:
        ThemeScript.vanish(self)
