class_name HomeScreen
extends Control
const ThemeScript := preload("res://scripts/ui/theme.gd")
const DeckScript := preload("res://scripts/data/deck.gd")

## The only front door: the deck's name, what is waiting today, and the one
## button that matters. Everything else on this screen is a quiet second
## thought -- sync and settings wait at the bottom, small and unhurried.

signal study_pressed
signal sync_pressed
signal settings_pressed

var _counts := {"due": 0, "new": 0, "learned": 0}

func _ready() -> void:
	_build()
	ThemeScript.appear(self)

func setup(deck: DeckScript, counts: Dictionary, sync_line: String, connected: bool) -> void:
	if not is_node_ready():
		await ready
	_counts = counts
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

func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 32)
	add_child(margin)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
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

func _wordmark() -> Control:
	var row := CenterContainer.new()
	row.name = "Wordmark"
	row.custom_minimum_size = Vector2(0, 64)
	var label := Label.new()
	label.text = "QuranTathbit"
	label.add_theme_font_override("font", ThemeScript.vazir(ThemeScript.TITLE, true))
	label.add_theme_font_size_override("font_size", ThemeScript.TITLE)
	label.add_theme_color_override("font_color", ThemeScript.GREEN_DEEP)
	row.add_child(label)
	return row

func _deck_card() -> Control:
	var card := PanelContainer.new()
	card.name = "DeckCard"
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.custom_minimum_size = Vector2(0, 92)
	card.add_theme_stylebox_override("panel", ThemeScript.card_stylebox())
	var box := VBoxContainer.new()
	box.name = "Box"
	box.alignment = BoxContainer.ALIGNMENT_CENTER
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
	pill.add_theme_stylebox_override("panel", ThemeScript.soft_stylebox(ThemeScript.GREEN_SOFT))
	var box := VBoxContainer.new()
	box.name = "Box"
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	pill.add_child(box)

	var value := Label.new()
	value.name = "Value"
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.add_theme_font_override("font", ThemeScript.vazir(26, true))
	value.add_theme_font_size_override("font_size", 26)
	value.add_theme_color_override("font_color", ThemeScript.GREEN_DEEP)
	box.add_child(value)

	var name := Label.new()
	name.text = title
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.add_theme_font_override("font", ThemeScript.vazir(ThemeScript.CAPTION))
	name.add_theme_font_size_override("font_size", ThemeScript.CAPTION)
	name.add_theme_color_override("font_color", ThemeScript.INK_SOFT)
	box.add_child(name)
	return pill

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
