class_name HomeScreen
extends Control
const ThemeScript := preload("res://scripts/ui/theme.gd")
const DeckScript := preload("res://scripts/data/deck.gd")
const SchedulerScript := preload("res://scripts/data/scheduler.gd")
const MarkdownScript := preload("res://scripts/ui/markdown.gd")

## The only front door: the deck's name, what is waiting today, and the one
## button that matters. Everything else on this screen is a quiet second
## thought -- sync and settings wait at the bottom, small and unhurried.

signal study_pressed
signal sync_pressed
signal settings_pressed

var _counts := {"due": 0, "new": 0, "learned": 0}
var _deck_of_last_setup: DeckScript

func _ready() -> void:
        _build()
        ThemeScript.appear(self)

func setup(deck: DeckScript, counts: Dictionary, sync_line: String, connected: bool) -> void:
        if not is_node_ready():
                await ready
        _counts = counts
        _deck_of_last_setup = deck
        var title: Label = get_node("Margin/Column/DeckCard/Box/Title")
        var caption: Label = get_node("Margin/Column/DeckCard/Box/Caption")
        title.text = deck.name
        caption.text = "%d cards · %d learned · %d waiting" % [deck.cards.size(), counts["learned"], counts["due"] + counts["new"]]

        var due_pill: Label = get_node("Margin/Column/Stats/Due/Box/Value")
        var new_pill: Label = get_node("Margin/Column/Stats/New/Box/Value")
        var learned_pill: Label = get_node("Margin/Column/Stats/Learned/Box/Value")
        due_pill.text = str(counts["due"])
        new_pill.text = str(counts["new"])
        learned_pill.text = str(counts["learned"])

        var study: Button = get_node("Margin/Column/Study")
        if counts["due"] + counts["new"] == 0:
                study.text = "Nothing due — come back tomorrow"
                study.disabled = true
        else:
                study.text = "Study" if counts["due"] > 0 else "Learn new cards"
                study.disabled = false

        var sync_label: Label = get_node("Margin/Column/Buttons/Sync/SyncBox/Label")
        sync_label.text = "Sync" if connected else "Connect GitHub"
        var sync_caption: Label = get_node("Margin/Column/SyncLine")
        sync_caption.text = sync_line

        # The one line that answers "what am I about to study?": the next
        # card's own heading, read from its front, dressed for its script.
        var next_up: Label = get_node("Margin/Column/DeckCard/Box/NextUp")
        var reference := _next_reference()
        next_up.visible = not reference.is_empty()
        if not reference.is_empty():
                next_up.text = "Next up · %s" % reference
                var script := ThemeScript.script_of(reference)
                next_up.add_theme_font_override("font", ThemeScript.font_for(script, ThemeScript.BODY))
                next_up.add_theme_font_size_override("font_size", _size_for(script))
                next_up.add_theme_color_override("font_color", ThemeScript.GREEN_DEEP)

## The next card's heading: the first line of its front, plain text. The
## scheduler's queue already knows which card is truly next -- due before new --
## so this is read from the queue, not guessed from the deck's order.
func _next_reference() -> String:
        if _counts["due"] + _counts["new"] == 0:
                return ""
        var queue: Array = SchedulerScript.queue(_deck_of_last_setup, int(Time.get_unix_time_from_system()))
        if queue.is_empty():
                return ""
        var front: String = queue[0].front
        for line in front.split("\n"):
                var plain := MarkdownScript.plain(line).strip_edges()
                if not plain.is_empty():
                        return plain
        return ""

func _size_for(script: String) -> int:
        if script == "arabic":
                return 24
        if script == "persian":
                return 19
        return ThemeScript.BODY

func _build() -> void:
        set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        add_child(_backdrop())
        var margin := MarginContainer.new()
        margin.name = "Margin"
        margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        margin.add_theme_constant_override("margin_left", 28)
        margin.add_theme_constant_override("margin_right", 28)
        margin.add_theme_constant_override("margin_top", 40)
        margin.add_theme_constant_override("margin_bottom", 32)
        add_child(margin)

        var column := VBoxContainer.new()
        column.name = "Column"
        column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        column.alignment = BoxContainer.ALIGNMENT_CENTER
        column.add_theme_constant_override("separation", 18)
        margin.add_child(column)

        var wordmark := _wordmark()
        column.add_child(wordmark)

        var deck_card := _deck_card()
        column.add_child(deck_card)

        var stats := _stats()
        column.add_child(stats)

        var study := _study_button()
        column.add_child(study)

        var buttons := _bottom_buttons()
        column.add_child(buttons)

        var sync_line := Label.new()
        sync_line.name = "SyncLine"
        sync_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        sync_line.add_theme_font_override("font", ThemeScript.vazir(ThemeScript.CAPTION))
        sync_line.add_theme_font_size_override("font_size", ThemeScript.CAPTION)
        sync_line.add_theme_color_override("font_color", ThemeScript.INK_SOFT)
        column.add_child(sync_line)

## A slow paper gradient behind everything: the screen breathes top-to-bottom
## instead of sitting on one flat colour.
func _backdrop() -> Control:
        var rect := ColorRect.new()
        rect.name = "Backdrop"
        rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        var gradient := Gradient.new()
        gradient.colors = PackedColorArray([Color("#FBF8F0"), Color("#F0E8D5")])
        var texture := GradientTexture2D.new()
        texture.gradient = gradient
        texture.fill_from = Vector2(0, 0)
        texture.fill_to = Vector2(0, 1)
        rect.color = Color.WHITE
        rect.texture = texture
        return rect

func _wordmark() -> Control:
        var row := CenterContainer.new()
        row.name = "Wordmark"
        row.custom_minimum_size = Vector2(0, 72)
        var stack := VBoxContainer.new()
        stack.alignment = BoxContainer.ALIGNMENT_CENTER
        stack.add_theme_constant_override("separation", 8)
        var label := Label.new()
        label.text = "QuranTathbit"
        label.add_theme_font_override("font", ThemeScript.vazir(ThemeScript.TITLE, true))
        label.add_theme_font_size_override("font_size", ThemeScript.TITLE)
        label.add_theme_color_override("font_color", ThemeScript.GREEN_DEEP)
        stack.add_child(label)
        var rule := PanelContainer.new()
        rule.custom_minimum_size = Vector2(46, 3)
        rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        rule.add_theme_stylebox_override("panel", ThemeScript.soft_stylebox(ThemeScript.GOLD, 2))
        stack.add_child(rule)
        row.add_child(stack)
        return row

func _deck_card() -> Control:
        var card := PanelContainer.new()
        card.name = "DeckCard"
        card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        card.custom_minimum_size = Vector2(0, 112)
        card.add_theme_stylebox_override("panel", ThemeScript.card_stylebox())
        var box := VBoxContainer.new()
        box.name = "Box"
        box.alignment = BoxContainer.ALIGNMENT_CENTER
        box.add_theme_constant_override("separation", 6)
        card.add_child(box)

        var title := Label.new()
        title.name = "Title"
        title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        title.add_theme_font_override("font", ThemeScript.vazir(ThemeScript.DISPLAY, true))
        title.add_theme_font_size_override("font_size", ThemeScript.DISPLAY)
        title.add_theme_color_override("font_color", ThemeScript.INK)
        box.add_child(title)

        var caption := Label.new()
        caption.name = "Caption"
        caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        caption.add_theme_font_override("font", ThemeScript.vazir(ThemeScript.BODY))
        caption.add_theme_font_size_override("font_size", ThemeScript.CAPTION)
        caption.add_theme_color_override("font_color", ThemeScript.INK_SOFT)
        box.add_child(caption)

        var next_up := Label.new()
        next_up.name = "NextUp"
        next_up.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        next_up.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        next_up.add_theme_font_override("font", ThemeScript.vazir(ThemeScript.BODY))
        next_up.add_theme_font_size_override("font_size", ThemeScript.BODY)
        next_up.add_theme_color_override("font_color", ThemeScript.GREEN_DEEP)
        box.add_child(next_up)
        return card

func _stats() -> Control:
        var row := HBoxContainer.new()
        row.name = "Stats"
        row.alignment = BoxContainer.ALIGNMENT_CENTER
        row.add_theme_constant_override("separation", 12)
        row.set_meta("_pills", {})
        for pair in [["Due", "due"], ["New", "new"], ["Learned", "learned"]]:
                row.add_child(_pill(pair[0], pair[1]))
        return row

func _pill(title: String, key: String) -> Control:
        var pill := PanelContainer.new()
        pill.name = title
        pill.custom_minimum_size = Vector2(104, 74)
        pill.add_theme_stylebox_override("panel", ThemeScript.soft_stylebox(_pill_bg(key)))
        var box := VBoxContainer.new()
        box.name = "Box"
        box.alignment = BoxContainer.ALIGNMENT_CENTER
        pill.add_child(box)

        var value := Label.new()
        value.name = "Value"
        value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        value.add_theme_font_override("font", ThemeScript.vazir(26, true))
        value.add_theme_font_size_override("font_size", 26)
        value.add_theme_color_override("font_color", _pill_fg(key))
        box.add_child(value)

        var name := Label.new()
        name.text = title
        name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        name.add_theme_font_override("font", ThemeScript.vazir(ThemeScript.CAPTION))
        name.add_theme_font_size_override("font_size", ThemeScript.CAPTION)
        name.add_theme_color_override("font_color", ThemeScript.INK_SOFT)
        box.add_child(name)
        return pill

## Waiting wears gold, new wears green, learned rests on paper: the three
## numbers a glance can tell apart before they are read.
func _pill_bg(key: String) -> Color:
        match key:
                "due":
                        return ThemeScript.GOLD_SOFT
                "new":
                        return ThemeScript.GREEN_SOFT
                _:
                        return Color(0.96, 0.95, 0.92)

func _pill_fg(key: String) -> Color:
        match key:
                "due":
                        return Color("#9C7A28")
                "new":
                        return ThemeScript.GREEN_DEEP
                _:
                        return ThemeScript.INK_SOFT

func _study_button() -> Control:
        var button := Button.new()
        button.name = "Study"
        button.custom_minimum_size = Vector2(320, 62)
        button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        button.add_theme_font_override("font", ThemeScript.vazir(21, true))
        button.add_theme_font_size_override("font_size", 21)
        button.add_theme_color_override("font_color", Color.WHITE)
        button.add_theme_color_override("font_hover_color", Color.WHITE)
        button.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.75))
        button.add_theme_stylebox_override("normal", ThemeScript.button_stylebox(ThemeScript.GREEN))
        button.add_theme_stylebox_override("hover", ThemeScript.button_stylebox(ThemeScript.GREEN_DEEP))
        button.add_theme_stylebox_override("pressed", ThemeScript.button_stylebox(ThemeScript.GREEN_DEEP))
        button.add_theme_stylebox_override("disabled", ThemeScript.button_stylebox(ThemeScript.INK_SOFT))
        button.add_theme_stylebox_override("focus", ThemeScript.button_stylebox(ThemeScript.GREEN_DEEP))
        button.pressed.connect(func() -> void: study_pressed.emit())
        return button

func _bottom_buttons() -> Control:
        var row := HBoxContainer.new()
        row.name = "Buttons"
        row.alignment = BoxContainer.ALIGNMENT_CENTER
        row.add_theme_constant_override("separation", 12)

        var sync := Button.new()
        sync.name = "Sync"
        sync.custom_minimum_size = Vector2(150, 46)
        sync.add_theme_font_override("font", ThemeScript.vazir(ThemeScript.BODY))
        sync.add_theme_font_size_override("font_size", ThemeScript.BODY)
        sync.add_theme_color_override("font_color", ThemeScript.GREEN_DEEP)
        sync.add_theme_color_override("font_hover_color", ThemeScript.GREEN_DEEP)
        sync.add_theme_stylebox_override("normal", ThemeScript.outline_stylebox(ThemeScript.GREEN))
        sync.add_theme_stylebox_override("hover", ThemeScript.soft_stylebox(ThemeScript.GREEN_SOFT, 23))
        sync.add_theme_stylebox_override("pressed", ThemeScript.soft_stylebox(ThemeScript.GREEN_SOFT, 23))
        sync.add_theme_stylebox_override("focus", ThemeScript.outline_stylebox(ThemeScript.GREEN))
        var sync_box := VBoxContainer.new()
        sync_box.name = "SyncBox"
        sync_box.alignment = BoxContainer.ALIGNMENT_CENTER
        var sync_label := Label.new()
        sync_label.name = "Label"
        sync_label.text = "Sync"
        sync_label.add_theme_font_override("font", ThemeScript.vazir(ThemeScript.BODY))
        sync_label.add_theme_font_size_override("font_size", ThemeScript.BODY)
        sync_label.add_theme_color_override("font_color", ThemeScript.GREEN_DEEP)
        sync_box.add_child(sync_label)
        sync.add_child(sync_box)
        sync.pressed.connect(func() -> void: sync_pressed.emit())
        row.add_child(sync)

        var settings := Button.new()
        settings.name = "Settings"
        settings.custom_minimum_size = Vector2(150, 46)
        settings.add_theme_font_override("font", ThemeScript.vazir(ThemeScript.BODY))
        settings.add_theme_font_size_override("font_size", ThemeScript.BODY)
        settings.add_theme_color_override("font_color", ThemeScript.INK_SOFT)
        settings.add_theme_color_override("font_hover_color", ThemeScript.INK)
        settings.add_theme_stylebox_override("normal", ThemeScript.outline_stylebox(ThemeScript.LINE))
        settings.add_theme_stylebox_override("hover", ThemeScript.soft_stylebox(Color(0.96, 0.95, 0.92), 23))
        settings.add_theme_stylebox_override("pressed", ThemeScript.soft_stylebox(Color(0.96, 0.95, 0.92), 23))
        settings.add_theme_stylebox_override("focus", ThemeScript.outline_stylebox(ThemeScript.LINE))
        settings.text = "Settings"
        settings.pressed.connect(func() -> void: settings_pressed.emit())
        row.add_child(settings)
        return row

func refresh(counts: Dictionary) -> void:
        _counts = counts
        var due_pill: Label = get_node("Margin/Column/Stats/Due/Box/Value")
        var new_pill: Label = get_node("Margin/Column/Stats/New/Box/Value")
        var learned_pill: Label = get_node("Margin/Column/Stats/Learned/Box/Value")
        due_pill.text = str(counts["due"])
        new_pill.text = str(counts["new"])
        learned_pill.text = str(counts["learned"])
        var study: Button = get_node("Margin/Column/Study")
        study.disabled = counts["due"] + counts["new"] == 0
        study.text = "Study" if counts["due"] > 0 else ("Learn new cards" if counts["new"] > 0 else "Nothing due — come back tomorrow")
