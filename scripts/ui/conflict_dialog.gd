class_name ConflictDialog
extends ColorRect
const ThemeScript := preload("res://scripts/ui/theme.gd")
const I18nScript := preload("res://scripts/ui/i18n.gd")

## The question sync asks when it cannot answer itself: a file changed here
## and changed in the repo, each unseen by the other, and which copy stands
## is not the engine's to decide. The dialog names what changed, asks which
## copy should win, and hard-forces the other away by the reader's word --
## or stands down entirely ("Decide later", the back key) and replaces
## nothing at all, leaving both sides as they stood for the next sync to
## ask again. It stands over whatever else is on the page, the sync overlay
## included, because a question that replaces someone's work is the work of
## the moment.

## How many paths are named before the list falls quiet with a count.
const LISTED := 4

signal answered(verdict: String)

var _paths: Array = []
var _panel: PanelContainer


func _init(p_paths: Array) -> void:
        _paths = p_paths


func _ready() -> void:
        color = Color(0.10, 0.14, 0.11, 0.0)
        mouse_filter = Control.MOUSE_FILTER_STOP
        set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        resized.connect(_layout)
        call_deferred("_layout")
        # The dim arrives with the card on it, not before it: a screen that
        # darkens before it has anything to say reads as a freeze.
        var dim := create_tween()
        dim.tween_property(self, "color:a", 0.55, 0.18)

        var center := CenterContainer.new()
        center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        center.mouse_filter = Control.MOUSE_FILTER_IGNORE
        add_child(center)

        var panel := PanelContainer.new()
        panel.name = "Panel"
        panel.add_theme_stylebox_override("panel", ThemeScript.card_stylebox())
        center.add_child(panel)
        _panel = panel

        var pad := MarginContainer.new()
        for side in ["left", "right"]:
                pad.add_theme_constant_override("margin_" + side, 26)
        for side in ["top", "bottom"]:
                pad.add_theme_constant_override("margin_" + side, 24)
        panel.add_child(pad)

        var box := VBoxContainer.new()
        box.add_theme_constant_override("separation", 12)
        pad.add_child(box)

        var title := Label.new()
        title.text = I18nScript.t("Some cards changed in two places")
        title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        ThemeScript.dress(title, ThemeScript.TITLE, ThemeScript.GREEN_DEEP, true)
        box.add_child(title)

        var body := Label.new()
        body.text = I18nScript.t(
                "Both this device and your GitHub repo changed these since the last sync:"
        )
        body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        ThemeScript.dress(body, ThemeScript.BODY, ThemeScript.INK)
        box.add_child(body)

        # The names of what changed, said once and whole: a few paths, then a
        # count. Paths are file names and stay as written, whatever tongue the
        # page speaks.
        var listed := Label.new()
        listed.text = _paths_text()
        listed.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        listed.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        ThemeScript.dress(listed, ThemeScript.CAPTION, ThemeScript.INK_SOFT)
        box.add_child(listed)

        var question := Label.new()
        question.text = I18nScript.t("Which copy should win? The other is replaced.")
        question.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        question.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        ThemeScript.dress(question, ThemeScript.BODY, ThemeScript.INK, true)
        box.add_child(question)

        # The two answers, each a whole half of the row: the device in hand
        # wears the filled green of "go", the repo the quiet outline of a
        # second thought.
        var answers := HBoxContainer.new()
        answers.add_theme_constant_override("separation", 10)
        box.add_child(answers)

        var mine := ThemeScript.primary_button(I18nScript.t("This device's copy"), 46)
        mine.name = "Mine"
        mine.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        mine.pressed.connect(func() -> void: _answer("local"))
        answers.add_child(mine)

        var theirs := ThemeScript.ghost_button(I18nScript.t("The GitHub copy"), ThemeScript.GREEN, 46)
        theirs.name = "Theirs"
        theirs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        theirs.pressed.connect(func() -> void: _answer("remote"))
        answers.add_child(theirs)

        # The quiet third way: no winner named, nothing replaced, the next
        # sync asks again.
        var later := ThemeScript.ghost_button(I18nScript.t("Decide later"), ThemeScript.INK_SOFT, 42)
        later.name = "Later"
        later.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        later.pressed.connect(func() -> void: _answer(""))
        box.add_child(later)

        ThemeScript.settle_in(panel, 0.0, 0.3)
        later.grab_focus()


## Ask, and wait for the word: "local" (this device's copy stands), "remote"
## (the repo's copy stands) or "" (the question stood down, nothing replaced).
func ask() -> String:
        var verdict: String = await answered
        return verdict


func _paths_text() -> String:
        if _paths.is_empty():
                return ""
        var names: PackedStringArray = PackedStringArray()
        for i in mini(_paths.size(), LISTED):
                names.append(str(_paths[i]))
        var text := " · ".join(names)
        if _paths.size() > LISTED:
                text += "\n" + I18nScript.f("+ %d more", [_paths.size() - LISTED])
        return text


func _answer(verdict: String) -> void:
        answered.emit(verdict)


## The back key is the quiet third way too: nothing named, nothing replaced.
func _input(event: InputEvent) -> void:
        if event is InputEventKey and event.pressed and not event.echo:
                if event.keycode == KEY_ESCAPE:
                        _answer("")
                        get_viewport().set_input_as_handled()


## The card answers the window: capped at its own measure, never wider than
## what a phone can hold.
func _layout() -> void:
        if size.x <= 0.0 or _panel == null:
                return
        var avail := minf(420.0, size.x - 48.0)
        _panel.custom_minimum_size = Vector2(avail, 0)
