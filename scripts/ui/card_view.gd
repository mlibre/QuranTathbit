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

## Where a deck folder sits under the site that served the web build, so a
## browser can stream the recitations that a desktop build carries inside.
const WEB_DECK_MARKER := "decks/"

## Recitations fetched from the site, kept for the session: a browser build
## has no deck audio on disk, and each file is heard many times.
static var _web_cache := {}

var _player: AudioStreamPlayer
var _folder := ""
var _buttons: Array = []
var _fetching := false

func _init(p_player: AudioStreamPlayer) -> void:
        _player = p_player
        add_theme_constant_override("separation", ThemeScript.GAP)

func show_text(text: String, folder: String, lead := false) -> void:
        _clear()
        _folder = folder
        for block in MarkdownScript.parse(text):
                match block.kind:
                        "media":
                                _add_media(block.media)
                        _:
                                _add_text(block.text, block.link, lead)

func _add_text(markdown: String, link: String, lead := false) -> void:
        if markdown.strip_edges().is_empty():
                return
        var label := RichTextLabel.new()
        label.name = "Paragraph"
        label.bbcode_enabled = true
        label.fit_content = true
        label.scroll_active = false
        label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        # A verse or translation is something a person will want to copy:
        # hold the mouse and drag, the way every other reader works.
        label.selection_enabled = true
        var script := ThemeScript.script_of(MarkdownScript.plain(markdown))
        # Scripture reads right-to-left. Under an RTL base direction a
        # RichTextLabel mirrors its alignment (LEFT lands on the start edge),
        # so the base stays AUTO and the alignment is set visually instead:
        # scripture from the right edge, anything else from the left.
        label.text_direction = TextDirection.TEXT_DIRECTION_AUTO
        if script == "arabic" or script == "persian":
                label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
        else:
                label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
        label.add_theme_font_override("normal_font", ThemeScript.font_for(script, ThemeScript.BODY))
        label.add_theme_font_size_override("normal_font_size", _size_for(script, lead))
        label.text = _bbcode(markdown)
        label.add_theme_color_override("default_color", ThemeScript.INK if script != "plain" else ThemeScript.INK_SOFT)
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
        button.text = "▶  " + name.get_basename()
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
        if FileAccess.file_exists(path):
                _start_stream(FileAccess.get_file_as_bytes(path), button)
                return
        # A browser build carries the deck's text but streams its audio from
        # the site it was served from, next to index.html under decks/.
        if OS.has_feature("web"):
                _stream_from_site(path, button)
                return
        push_warning("CardView: audio missing %s" % path)


func _start_stream(bytes: PackedByteArray, button: Button) -> void:
        if bytes.is_empty():
                button.text = "audio unavailable"
                return
        var stream := AudioStreamMP3.new()
        stream.data = bytes
        _player.stream = stream
        _player.play()
        _highlight(button)


func _stream_from_site(path: String, button: Button) -> void:
        if _fetching:
                return
        if _web_cache.has(path):
                _start_stream(_web_cache[path], button)
                return
        _fetching = true
        var label := button.text
        button.text = "…  " + label.get_basename()
        button.disabled = true
        var fetcher := HTTPRequest.new()
        add_child(fetcher)
        var err := fetcher.request(_site_url(path))
        var bytes := PackedByteArray()
        if err == OK:
                var outcome: Array = await fetcher.request_completed
                if int(outcome[1]) == 200:
                        bytes = outcome[3]
        fetcher.queue_free()
        button.disabled = false
        if bytes.is_empty():
                button.text = "audio unavailable"
        else:
                button.text = label
                _web_cache[path] = bytes
                _start_stream(bytes, button)
        _fetching = false


## The deck path under user:// mapped onto the site that served this build:
## user://decks/quran/001/verse.mp3 -> <site>/decks/quran/001/verse.mp3.
static func _site_url(path: String) -> String:
        var base := ""
        if OS.has_feature("web"):
                base = str(JavaScriptBridge.eval("location.href.split('#')[0].split('?')[0]", true))
        var slash := base.rfind("/")
        if slash >= 0:
                base = base.substr(0, slash + 1)
        var rel := path
        var at := path.find(WEB_DECK_MARKER)
        if at >= 0:
                rel = path.substr(at)
        var encoded := PackedStringArray()
        for part in rel.split("/"):
                encoded.append(part.uri_encode())
        return base + "/".join(encoded)

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

func _size_for(script: String, lead := false) -> int:
        # The lead is the question side's heading: the reference the reader
        # recites from, set large enough to read across the room.
        if lead:
                match script:
                        "arabic":
                                return 46
                        "persian":
                                return 28
                        _:
                                return 22
        match script:
                "arabic":
                        return 30
                "persian":
                        return 19
                _:
                        return ThemeScript.CAPTION

static func _bbcode(markdown: String) -> String:
        var text := markdown
        text = _links(text)
        text = _bold(text)
        text = _italic(text)
        return text

## Markdown links become clickable BBCode. Images are skipped -- the view's
## media pass owns those, and their brackets must not be touched here.
static func _links(text: String) -> String:
        var re := RegEx.create_from_string("(?<!!)\\[([^\\]]+)\\]\\(([^)]+)\\)")
        return re.sub(text, "[url=$2]$1[/url]", true)

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
