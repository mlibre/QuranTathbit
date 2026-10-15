class_name CardView
extends VBoxContainer
const ThemeScript := preload("res://scripts/ui/theme.gd")
const MarkdownScript := preload("res://scripts/ui/markdown.gd")

## Draws a card side: the markdown turned into calm, centered paragraphs.
## Arabic verses take the Quranic typeface at a size you can read across the
## room; Persian translations sit under them in Vazirmatn; an audio reference
## becomes a small gold button that plays the recitation sitting beside the
## markdown. Links open in the browser, quietly.
##
## The answer side is dressed as a page of scripture: the reference asked for
## rides above as a small gold eyebrow, each verse gets the room a verse
## deserves, its translation follows a step behind, and the whole side
## arrives one element after another -- a reveal, not a swap.

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
var _playing_path := ""
var _playing_button: Button = null

func _init(p_player: AudioStreamPlayer) -> void:
        _player = p_player
        add_theme_constant_override("separation", ThemeScript.GAP)

## Show one side of a card. `lead` is the question's own heading, set large;
## `ref_line` is that same heading repeated small above an answer, so the
## reader knows which verse they were asked for while they read it;
## `stagger` settles each element in, a beat apart.
func show_text(text: String, folder: String, lead := false, ref_line := "", stagger := false) -> void:
        _clear()
        _folder = folder
        if not ref_line.is_empty():
                _add_eyebrow(ref_line)
        for block in MarkdownScript.parse(text):
                match block.kind:
                        "media":
                                _add_media(block.media)
                        _:
                                _add_text(block.text, block.link, lead)
        if stagger:
                ThemeScript.stagger_in(self, 0.07, 0.26)

## The reference the question asked for, small and gold above the answer:
## the thread that ties what is being read to what was asked.
func _add_eyebrow(ref_line: String) -> void:
        var label := RichTextLabel.new()
        label.name = "Eyebrow"
        label.fit_content = true
        label.scroll_active = false
        label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        label.selection_enabled = true
        var script := ThemeScript.script_of(ref_line)
        label.text_direction = TextDirection.TEXT_DIRECTION_AUTO
        label.horizontal_alignment = (
                HORIZONTAL_ALIGNMENT_RIGHT if script != "plain" else HORIZONTAL_ALIGNMENT_CENTER
        )
        label.add_theme_font_override("normal_font", (
                ThemeScript.amiri(15) if script == "arabic" else ThemeScript.vazir(13, true)
        ))
        label.add_theme_font_size_override("normal_font_size", 15 if script == "arabic" else 13)
        label.add_theme_color_override("default_color", ThemeScript.GOLD_DEEP)
        label.text = ref_line  # bbcode is off here, so brackets can render literally
        add_child(label)

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
                # A plain line in a centred card -- the citation under a verse,
                # usually -- sits centred like the rest of the page, not
                # orphaned against the left edge.
                label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        label.add_theme_font_override("normal_font", ThemeScript.font_for(script, ThemeScript.BODY))
        label.add_theme_font_size_override("normal_font_size", _size_for(script, lead))
        label.text = _bbcode(markdown)
        label.add_theme_color_override("default_color", ThemeScript.INK if script != "plain" else ThemeScript.INK_SOFT)
        # Scripture breathes between its lines; the lead, most of all.
        if script == "arabic":
                label.add_theme_constant_override("line_separation", 14 if lead else 10)
        elif script == "persian":
                label.add_theme_constant_override("line_separation", 6)
        label.meta_clicked.connect(_open_link)
        # A verse gets the room a verse deserves: extra breath after it, so the
        # translation below reads as the verse's own second voice.
        if script == "arabic" and not lead:
                add_child(_with_bottom_room(label, 12))
        else:
                add_child(label)

## A margin wrapper for the few places that need spacing the uniform column
## cannot express: the pause between a verse and what follows it.
func _with_bottom_room(control: Control, room: int) -> MarginContainer:
        var wrap := MarginContainer.new()
        wrap.name = "Room"
        wrap.add_theme_constant_override("margin_bottom", room)
        wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        wrap.add_child(control)
        return wrap

func _add_media(name: String) -> void:
        var path := _folder.path_join(name)
        var extension := name.get_extension().to_lower()
        if extension in AUDIO_EXTENSIONS:
                _add_audio_button(name, path)
        elif extension in IMAGE_EXTENSIONS:
                _add_image(path)
        else:
                push_warning("CardView: unknown media type %s" % name)

## The recitation, as a gold oval that speaks: a drawn triangle at rest, a
## breathing column of bars while the voice runs -- the one motion the app
## allows itself, because it is the sound's own feedback.
func _add_audio_button(name: String, path: String) -> void:
        var button := Button.new()
        button.name = "Audio:" + name
        # The words the button carries: the verse's own address when the file
        # name carries one, so two recitations on one card are never mistaken
        # for each other.
        var verse := _verse_label(name)
        var idle_text := "Listen" if verse.is_empty() else "Listen · %s" % verse
        # A Button measures its own text, and this button's words live in
        # children it cannot see: the width is set by hand from the widest
        # line the button will ever carry, so the pill is a pill on arrival
        # and never jumps between states.
        var font := ThemeScript.vazir(ThemeScript.CAPTION)
        var widest := maxf(
                font.get_string_size("Listening…", HORIZONTAL_ALIGNMENT_LEFT, -1, ThemeScript.CAPTION).x,
                font.get_string_size(idle_text, HORIZONTAL_ALIGNMENT_LEFT, -1, ThemeScript.CAPTION).x
        )
        button.custom_minimum_size = Vector2(ceil(widest) + 15 + 9 + 42, 46)
        button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        button.add_theme_font_override("font", ThemeScript.vazir(ThemeScript.CAPTION))
        button.add_theme_font_size_override("font_size", ThemeScript.CAPTION)
        button.add_theme_color_override("font_color", ThemeScript.GREEN_DEEP)
        button.add_theme_color_override("font_hover_color", ThemeScript.GREEN_DEEP)
        button.add_theme_color_override("font_focus_color", ThemeScript.GREEN_DEEP)
        # A gold pill with a real edge: the recitation is an action, and an
        # action on this page wears a fill deep enough to see against the card
        # and an edge crisp enough to read as something that gives.
        var rest := ThemeScript.button_stylebox(Color("#F2E3BC"), 23)
        rest.border_color = ThemeScript.GOLD
        rest.set_border_width_all(2)
        var hover := ThemeScript.button_stylebox(Color("#EAD9AC"), 23)
        hover.border_color = ThemeScript.GOLD_DEEP
        hover.set_border_width_all(2)
        button.add_theme_stylebox_override("normal", rest)
        button.add_theme_stylebox_override("hover", hover)
        button.add_theme_stylebox_override("pressed", hover)
        var speaking := ThemeScript.button_stylebox(ThemeScript.GREEN_SOFT, 23)
        speaking.border_color = ThemeScript.GOLD
        speaking.set_border_width_all(1)
        button.add_theme_stylebox_override("focus", speaking)
        button.set_meta("idle_text", idle_text)
        ThemeScript.pressable(button)
        button.pressed.connect(_toggle_audio.bind(path, button))
        # The marks are drawn, not typed: no font in this app carries the
        # glyphs, and a tofu box where a play mark should be is worse than none.
        var center := CenterContainer.new()
        center.name = "Center"
        center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        center.mouse_filter = Control.MOUSE_FILTER_IGNORE
        button.add_child(center)
        var row := HBoxContainer.new()
        row.name = "Row"
        row.add_theme_constant_override("separation", 9)
        row.mouse_filter = Control.MOUSE_FILTER_IGNORE
        center.add_child(row)
        var icon := ThemeScript.SoundMark.new(ThemeScript.GREEN_DEEP)
        icon.name = "Icon"
        icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
        row.add_child(icon)
        var label := Label.new()
        label.name = "Label"
        label.text = idle_text
        label.add_theme_font_override("font", ThemeScript.vazir(ThemeScript.CAPTION))
        label.add_theme_font_size_override("font_size", ThemeScript.CAPTION)
        label.add_theme_color_override("font_color", ThemeScript.GREEN_DEEP)
        row.add_child(label)
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

## One press speaks; a second press on the same button takes it back. The
## button that is speaking wears green, and only that one.
func _toggle_audio(path: String, button: Button) -> void:
        if _player.playing and _playing_path == path:
                _stop_audio()
                return
        if FileAccess.file_exists(path):
                _speak(path, button, FileAccess.get_file_as_bytes(path))
                return
        # A browser build carries the deck's text but streams its audio from
        # the site it was served from, next to index.html under decks/.
        if OS.has_feature("web"):
                _stream_from_site(path, button)
                return
        _set_button_state(button, "missing")

func _speak(path: String, button: Button, bytes: PackedByteArray) -> void:
        if bytes.is_empty():
                _set_button_state(button, "missing")
                return
        var stream := AudioStreamMP3.new()
        stream.data = bytes
        _player.stream = stream
        _player.play()
        if _playing_button != null and is_instance_valid(_playing_button):
                _set_button_state(_playing_button, "idle")
        _playing_path = path
        _playing_button = button
        _set_button_state(button, "playing")

func _stop_audio() -> void:
        if _player.playing:
                _player.stop()
        if _playing_button != null and is_instance_valid(_playing_button):
                _set_button_state(_playing_button, "idle")
        _playing_path = ""
        _playing_button = null

## What a button says while it works, speaks, or cannot: one place, so every
## state dresses the same on every button.
func _set_button_state(button: Button, state: String) -> void:
        var icon: ThemeScript.SoundMark = button.get_node("Center/Row/Icon")
        var label: Label = button.get_node("Center/Row/Label")
        match state:
                "playing":
                        icon.color = ThemeScript.GOLD
                        icon.speaking = true
                        label.text = "Listening…"
                "loading":
                        label.text = "Fetching…"
                "missing":
                        icon.color = ThemeScript.INK_SOFT
                        label.text = "Unavailable"
                _:
                        icon.color = ThemeScript.GREEN_DEEP
                        icon.speaking = false
                        label.text = str(button.get_meta("idle_text", "Listen"))
        icon.queue_redraw()

func _stream_from_site(path: String, button: Button) -> void:
        if _fetching:
                return
        if _web_cache.has(path):
                _speak(path, button, _web_cache[path])
                return
        _fetching = true
        _set_button_state(button, "loading")
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
                _set_button_state(button, "missing")
        else:
                _web_cache[path] = bytes
                _speak(path, button, bytes)
        _fetching = false


## The recitation's own address, when the file name carries one: 001001.mp3
## is surah 1, verse 1, and the button says which verse will speak.
static func _verse_label(name: String) -> String:
        var stem := name.get_basename()
        if stem.is_valid_int() and stem.length() == 6:
                return "%d:%d" % [int(stem.substr(0, 3)), int(stem.substr(3, 3))]
        return ""


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

func _open_link(meta: Variant) -> void:
        OS.shell_open(str(meta))

## The question's heading is set to be read across the room; a verse on the
## answer side is the largest thing on the page; a translation follows at
## reading size; everything else is a caption.
func _size_for(script: String, lead := false) -> int:
        if lead:
                match script:
                        "arabic":
                                return 54
                        "persian":
                                return 30
                        _:
                                return 24
        match script:
                "arabic":
                        return 38
                "persian":
                        return 20
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
        return re.sub(text, "[url=$2][color=#1E6B52]$1[/color][/url]", true)

static func _bold(text: String) -> String:
        var re := RegEx.create_from_string("\\*\\*(?P<inner>[^*]+)\\*\\*")
        return re.sub(text, "[b]$1[/b]", true)

static func _italic(text: String) -> String:
        var re := RegEx.create_from_string("(?<!\\*)\\*(?P<inner>[^*]+)\\*(?!\\*)")
        return re.sub(text, "[i]$1[/i]", true)

func _clear() -> void:
        _stop_audio()
        for child in get_children():
                remove_child(child)
                child.queue_free()
        _buttons.clear()
        _playing_button = null
        _playing_path = ""
