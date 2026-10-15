class_name CardView
extends VBoxContainer
const ThemeScript := preload("res://scripts/ui/theme.gd")
const MarkdownScript := preload("res://scripts/ui/markdown.gd")

## Draws a card side: the markdown turned into calm, centered paragraphs.
## Arabic verses take the Quranic typeface at a size you can read across the
## room; Persian translations sit under them in Vazirmatn; an audio reference
## becomes a small gold button that plays the recitation sitting beside the
## markdown. Links open in the browser, quietly.

const AUDIO_EXTENSIONS := ["mp3", "ogg", "wav", "m4a"]
const IMAGE_EXTENSIONS := ["png", "jpg", "jpeg", "webp", "svg"]

var _player: AudioStreamPlayer
var _folder := ""
var _buttons: Array = []

func _init(p_player: AudioStreamPlayer) -> void:
	_player = p_player
	add_theme_constant_override("separation", ThemeScript.GAP)

func show_text(text: String, folder: String) -> void:
	_clear()
	_folder = folder
	for block in MarkdownScript.parse(text):
		match block.kind:
			"media":
				_add_media(block.media)
			_:
				_add_text(block.text, block.link)

func _add_text(markdown: String, link: String) -> void:
	if markdown.strip_edges().is_empty():
		return
	var label := RichTextLabel.new()
	label.name = "Paragraph"
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var script := ThemeScript.script_of(MarkdownScript.plain(markdown))
	label.add_theme_font_override("normal_font", ThemeScript.font_for(script, ThemeScript.BODY))
	label.add_theme_font_size_override("normal_font_size", _size_for(script))
	label.text = _bbcode(markdown)
	label.add_theme_color_override("default_color", ThemeScript.INK if script != "plain" else ThemeScript.INK_SOFT)
	if not link.is_empty():
		label.meta_clicked.connect(_open_link)
	add_child(label)

func _add_media(name: String) -> void:
	var path := _folder.path_join(name)
	var extension := name.get_extension().to_lower()
	if extension in AUDIO_EXTENSIONS:
		_add_audio_button(name, path)
	elif extension in IMAGE_EXTENSIONS:
		_add_image(path)
	else:
		push_warning("CardView: unknown media type %s" % name)

func _add_audio_button(name: String, path: String) -> void:
	var button := Button.new()
	button.name = "Audio:" + name
	button.text = "▶  " + name
	button.custom_minimum_size = Vector2(0, 44)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_override("font", ThemeScript.vazir(ThemeScript.CAPTION))
	button.add_theme_font_size_override("font_size", ThemeScript.CAPTION)
	button.add_theme_color_override("font_color", ThemeScript.GREEN_DEEP)
	button.add_theme_color_override("font_hover_color", ThemeScript.GREEN_DEEP)
	button.add_theme_stylebox_override("normal", ThemeScript.button_stylebox(ThemeScript.GOLD_SOFT, 22))
	button.add_theme_stylebox_override("hover", ThemeScript.button_stylebox(ThemeScript.GREEN_SOFT, 22))
	button.add_theme_stylebox_override("pressed", ThemeScript.button_stylebox(ThemeScript.GREEN_SOFT, 22))
	button.add_theme_stylebox_override("focus", ThemeScript.button_stylebox(ThemeScript.GOLD_SOFT, 22))
	button.pressed.connect(_play_audio.bind(path, button))
	add_child(button)
	_buttons.append(button)

func _add_image(path: String) -> void:
	var image := Image.new()
	if image.load(path) != OK:
		push_warning("CardView: cannot load image %s" % path)
		return
	var texture := ImageTexture.create_from_image(image)
	var rect := TextureRect.new()
	rect.name = "Image"
	rect.texture = texture
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = Vector2(0, 180)
	rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(rect)

func _play_audio(path: String, button: Button) -> void:
	if not FileAccess.file_exists(path):
		push_warning("CardView: audio missing %s" % path)
		return
	var stream := AudioStreamMP3.new()
	stream.data = FileAccess.get_file_as_bytes(path)
	_player.stream = stream
	_player.play()
	_highlight(button)

func _highlight(button: Button) -> void:
	for other in _buttons:
		other.add_theme_color_override("font_color", ThemeScript.GREEN_DEEP)
	button.add_theme_color_override("font_color", ThemeScript.GOLD)
	var tween := create_tween()
	tween.tween_interval(1.2)
	tween.tween_callback(func() -> void:
		if is_instance_valid(button):
			button.add_theme_color_override("font_color", ThemeScript.GREEN_DEEP)
	)

func _open_link(meta: Variant) -> void:
	OS.shell_open(str(meta))

func _size_for(script: String) -> int:
	match script:
		"arabic":
			return 30
		"persian":
			return 19
		_:
			return ThemeScript.CAPTION

static func _bbcode(markdown: String) -> String:
	var text := markdown
	text = _bold(text)
	text = _italic(text)
	return text

static func _bold(text: String) -> String:
	var re := RegEx.create_from_string("\\*\\*(?P<inner>[^*]+)\\*\\*")
	return re.sub(text, "[b]$1[/b]", true)

static func _italic(text: String) -> String:
	var re := RegEx.create_from_string("(?<!\\*)\\*(?P<inner>[^*]+)\\*(?!\\*)")
	return re.sub(text, "[i]$1[/i]", true)

func _clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_buttons.clear()
	if _player.playing:
		_player.stop()
