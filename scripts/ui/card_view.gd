class_name CardView
extends VBoxContainer
const ThemeScript := preload("res://scripts/ui/theme.gd")
const MarkdownScript := preload("res://scripts/ui/markdown.gd")
const I18nScript := preload("res://scripts/ui/i18n.gd")

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
var _fetching := false
var _playing_path := ""
var _playing_button: Button = null
var _body: VBoxContainer

func _init(p_player: AudioStreamPlayer) -> void:
        _player = p_player
        # The recitation's own last word: when the audio runs out by itself
        # the button must hear about it, or it says "Listening…" forever at
        # a verse that has already gone quiet. stop() never emits this -- only
        # a natural finish does -- so a hand that stops the sound still has
        # its own say through _stop_audio().
        _player.finished.connect(_on_audio_finished)
        # The page's two halves: the verses, centred and breathing, and the
        # card's own citation, pinned along the bottom edge -- a footer, the
        # way a book's page names its chapter at its foot.
        _body = VBoxContainer.new()
        _body.name = "Body"
        _body.alignment = BoxContainer.ALIGNMENT_CENTER
        _body.size_flags_vertical = Control.SIZE_EXPAND_FILL
        _body.add_theme_constant_override("separation", ThemeScript.GAP)
        add_child(_body)

## Show one side of a card. `lead` is the question's own heading, set large;
## `ref_line` is that same heading repeated small above an answer, so the
## reader knows which verse they were asked for while they read it;
## `stagger` settles each element in, a beat apart. A paragraph that is a
## lone link is the card's citation: it leaves the verses and takes its
## place at the page's foot, under a gentle rule, bottom-left.
##
## The saying is deferred to the end of the frame on purpose. A card is
## usually built inside containers that have never been laid out yet -- a
## shelf's detail under its row, a preview inside the editor -- and a
## RichTextLabel shaped at the width of a moment that has no width wraps
## one character a line and floods the log with the shaper's own
## complaints (an Arabic verse with its marks is the loudest customer).
## The deferred call lands after this frame's container sort, so the first
## shaping already sees the width the card will actually be read at.
func show_text(text: String, folder: String, lead := false, ref_line := "", stagger := false) -> void:
        _show_text_now.call_deferred(text, folder, lead, ref_line, stagger)


func _show_text_now(text: String, folder: String, lead := false, ref_line := "", stagger := false) -> void:
        _clear()
        _folder = folder
        if not ref_line.is_empty():
                _add_eyebrow(ref_line)
        for block in MarkdownScript.parse(text):
                match block.kind:
                        "media":
                                _add_media(block.media)
                        _:
                                if not block.link.is_empty():
                                        _add_footer(block.text, block.link)
                                else:
                                        _add_text(block.text, block.link, lead)
        if stagger:
                ThemeScript.stagger_in(_body, 0.07, 0.26)
                var footer := get_node_or_null("Footer")
                if footer != null:
                        ThemeScript.settle_in(footer, 0.1, 0.26)

## The reference the question asked for, small and gold above the answer:
## the thread that ties what is being read to what was asked. On the answer
## side it is the question's own voice returning -- the same Arabic the
## reader was asked to recite from, in the same face the verses wear, a
## breath larger than a caption because here it is the page's one thread
## back to the question, not a footnote.
func _add_eyebrow(ref_line: String) -> void:
        var label := RichTextLabel.new()
        label.name = "Eyebrow"
        label.fit_content = true
        label.scroll_active = false
        label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        label.selection_enabled = true
        var script := ThemeScript.reference_script(ref_line)
        label.text_direction = TextDirection.TEXT_DIRECTION_AUTO
        label.horizontal_alignment = (
                HORIZONTAL_ALIGNMENT_RIGHT if script != "plain" else HORIZONTAL_ALIGNMENT_CENTER
        )
        var face: Font = (
                ThemeScript.ayah_face() if script == "arabic" else ThemeScript.vazir(15, true)
        )
        label.add_theme_font_override("normal_font", face)
        var face_size := ThemeScript.fs(17 if script == "arabic" else 15)
        label.add_theme_font_size_override("normal_font_size", face_size)
        label.add_theme_color_override("default_color", ThemeScript.GOLD_DEEP)
        # The reader's hand rests on the page's own gold, not the engine's blue.
        label.add_theme_color_override("selection_color", ThemeScript.SELECT)
        label.text = ref_line  # bbcode is off here, so brackets can render literally
        # A reference a hand-edited deck vocalised gets its marks the same
        # air the verses get: the whole word, whatever it wears.
        ThemeScript.give_rtl_room(label, ref_line, [face], face_size)
        _body.add_child(label)

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
        # The question side is a reference -- a surah's name and a range,
        # Arabic by construction -- so it reads in the Quranic face whether
        # or not its letters carry a script tell. Everything else (the answer
        # side) classifies line by line: verses are vocalised, translations
        # are not, and that is the tell between them.
        var script: String = (
                ThemeScript.reference_script(MarkdownScript.plain(markdown))
                if lead
                else ThemeScript.script_of(MarkdownScript.plain(markdown))
        )
        # Scripture reads right-to-left. Under an RTL base direction a
        # RichTextLabel mirrors its alignment (LEFT lands on the start edge),
        # so the base stays AUTO and the alignment is set visually instead:
        # scripture from the right edge, anything else from the left.
        label.text_direction = TextDirection.TEXT_DIRECTION_AUTO
        if lead:
                # The question side is a reference, alone on its page: it
                # stands in the middle like a chapter heading, whatever its
                # script -- an RTL line against the right edge of a nearly
                # empty card reads as a smudge, not a heading.
                label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        elif script == "arabic" or script == "persian":
                label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
        else:
                # A plain line in a centred card -- the citation under a verse,
                # usually -- sits centred like the rest of the page, not
                # orphaned against the left edge.
                label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        var face: Font = ThemeScript.verse_face(script)
        label.add_theme_font_override("normal_font", face)
        # A hand-written [i] in a card still leans in the line's own face:
        # the engine's [i] falls back to the upright normal when no italic is
        # given. Nothing the app itself writes leans -- the author's stars are
        # stars -- but a card is plain text a hand may dress any way it likes.
        var bold_face: Font = ThemeScript.verse_face(script, true)
        label.add_theme_font_override("bold_font", bold_face)
        label.add_theme_font_override("italics_font", ThemeScript.leaning(face))
        label.add_theme_font_override("bold_italics_font", ThemeScript.leaning(bold_face))
        # The size rides on all four faces: a run that leans must not also
        # shrink back to the theme's default size.
        var face_size := ThemeScript.fs(_size_for(script, lead))
        label.add_theme_font_size_override("normal_font_size", face_size)
        label.add_theme_font_size_override("bold_font_size", face_size)
        label.add_theme_font_size_override("italics_font_size", face_size)
        label.add_theme_font_size_override("bold_italics_font_size", face_size)
        label.text = _bbcode(markdown, script)
        # The ink's own room: the marks a verse stacks above its tallest
        # letters reach past the box its font declares, and a control that
        # clips at that box draws them nowhere at all -- the damma a reader
        # lost on أُنزِلَ was never the font's fault. The label carries the
        # measured room inside itself, so the whole word is drawn whatever
        # face it wears and however tall it stands.
        var room_faces: Array = [face]
        if "**" in markdown:
                room_faces.append(bold_face)
        ThemeScript.give_rtl_room(label, MarkdownScript.plain(markdown), room_faces, face_size)
        label.add_theme_color_override("default_color", ThemeScript.INK if script != "plain" else ThemeScript.INK_SOFT)
        # Selection, too, wears the page's gold: the verse is the thing a
        # reader is most likely to reach for with the mouse.
        label.add_theme_color_override("selection_color", ThemeScript.SELECT)
        # Scripture breathes between its lines; the lead, most of all.
        if script == "arabic":
                label.add_theme_constant_override("line_separation", 14 if lead else 12)
        elif script == "persian":
                label.add_theme_constant_override("line_separation", 6)
        label.meta_clicked.connect(_open_link)
        # A verse gets the room a verse deserves: a long breath after it,
        # so the translation below reads as the verse's own second voice
        # and never crowds it.
        if script == "arabic" and not lead:
                _body.add_child(_with_bottom_room(label, 22))
        else:
                _body.add_child(label)

## A margin wrapper for the few places that need spacing the uniform column
## cannot express: the pause between a verse and what follows it.
func _with_bottom_room(control: Control, room: int) -> MarginContainer:
        var wrap := MarginContainer.new()
        wrap.name = "Room"
        wrap.add_theme_constant_override("margin_bottom", room)
        wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        wrap.add_child(control)
        return wrap

## The card's citation, as a page's own footer: a breath of space, then a
## gentle rule, then the source at the bottom-left, quiet and clickable --
## the place a book puts the page's provenance, so the verses never have to
## share their room with an address. The breath above the rule is what
## keeps the last of the verses -- and the recitation's button, which
## follows them -- from standing on the footer's own line.
func _add_footer(markdown: String, url: String) -> void:
        var label_text := MarkdownScript.plain(markdown)
        var box := VBoxContainer.new()
        box.name = "Footer"
        box.size_flags_vertical = Control.SIZE_SHRINK_END
        box.add_theme_constant_override("separation", 8)
        box.mouse_filter = Control.MOUSE_FILTER_PASS
        add_child(box)
        var breath := Control.new()
        breath.name = "Breath"
        breath.custom_minimum_size = Vector2(0, 20)
        breath.mouse_filter = Control.MOUSE_FILTER_IGNORE
        box.add_child(breath)
        box.add_child(ThemeScript.hairline())
        var line := RichTextLabel.new()
        line.name = "Citation"
        line.fit_content = true
        line.scroll_active = false
        line.selection_enabled = true
        line.bbcode_enabled = true
        var font := ThemeScript.vazir(12)
        line.add_theme_font_override("normal_font", font)
        line.add_theme_font_size_override("normal_font_size", ThemeScript.fs(12))
        line.add_theme_color_override("default_color", ThemeScript.INK_SOFT)
        line.add_theme_color_override("selection_color", ThemeScript.SELECT)
        line.text = "[color=#8D6E24][url=%s]%s[/url][/color]" % [url, label_text]
        line.meta_clicked.connect(_open_link)
        box.add_child(line)

func _add_media(name: String) -> void:
        var path := _folder.path_join(name)
        var extension := name.get_extension().to_lower()
        if extension in AUDIO_EXTENSIONS:
                _add_verse_voices(name, path)
        elif extension in IMAGE_EXTENSIONS:
                _add_image(path)
        else:
                push_warning("CardView: unknown media type %s" % name)

## The verse's two voices, side by side: its own recitation and its Persian
## translation, one flow that sits them together on a desk's width and
## lets them stack on a phone's -- a verse's voices belong to the verse,
## not to a column of pills that never ends.
func _add_verse_voices(name: String, path: String) -> void:
        var flow := HFlowContainer.new()
        flow.name = "Voices:" + name
        flow.alignment = FlowContainer.ALIGNMENT_CENTER
        flow.add_theme_constant_override("h_separation", 10)
        flow.add_theme_constant_override("v_separation", 10)
        # FILL, not SHRINK: a flow only wraps when its width is actually
        # constrained, and a shrink-centred flow is never narrower than its
        # single line. Filling the page lets the pair sit together on a desk
        # and stack on a phone, each line centred as the alignment says.
        flow.size_flags_horizontal = Control.SIZE_FILL
        flow.mouse_filter = Control.MOUSE_FILTER_PASS
        flow.add_child(_make_audio_button(name, path, false))
        var translation := _translation_path(name)
        if not translation.is_empty():
                flow.add_child(_make_audio_button(name, translation, true))
        _body.add_child(flow)

## The Persian translation's own address, when the deck carries it: a
## sibling file named after the verse -- 002001-fa.mp3 beside 002001.mp3,
## fetched once from quran.makarem.ir's CDN and shipped with the deck ever
## since. A browser cannot look at the disk, so there the translation is
## offered on the site's promise -- the same promise the verse's own
## recitation already rides -- and a deck without it says so honestly if
## the translation is asked for anyway.
func _translation_path(name: String) -> String:
        if _verse_label(name).is_empty():
                return ""
        var file := "%s-fa.%s" % [name.get_basename(), name.get_extension()]
        var path := _folder.path_join(file)
        if OS.has_feature("web") or FileAccess.file_exists(path):
                return path
        return ""

## The recitation, as a gold oval that speaks: a drawn triangle at rest, a
## breathing column of bars while the voice runs -- the one motion the app
## allows itself, because it is the sound's own feedback. The translation's
## button wears the same shape in the page's own white with gold lettering,
## so the two voices of one verse stand together without competing.
func _make_audio_button(name: String, path: String, persian := false) -> Button:
        var button := Button.new()
        button.name = ("Translation:" if persian else "Audio:") + name
        # The words the button carries: what will speak, and nothing more. A
        # verse's own address stood here once, but the page already says it
        # twice over -- the question asked for it and the eyebrow repeats it
        # -- so a third telling on the button was only noise on the pill.
        var word := I18nScript.t("Persian") if persian else I18nScript.t("Listen")
        var idle_text := word
        # A Button measures its own text, and this button's words live in
        # children it cannot see: the width is set by hand from the widest
        # line the button will ever carry, so the pill is a pill on arrival
        # and never jumps between states. The widest line is measured in the
        # tongue the app is speaking, not the last one it spoke -- and at the
        # size the label will wear it, which fs() says for both the words and
        # the measure, so the pill grows with the text scale.
        var caption := ThemeScript.fs(ThemeScript.CAPTION)
        var font := ThemeScript.vazir(ThemeScript.CAPTION)
        var widest := maxf(
                font.get_string_size(I18nScript.t("Listening…"), HORIZONTAL_ALIGNMENT_LEFT, -1, caption).x,
                font.get_string_size(idle_text, HORIZONTAL_ALIGNMENT_LEFT, -1, caption).x
        )
        # 48 tall, not 46: a fingertip deserves the whole guideline, and on a
        # phone's canvas this is the button a verse is heard by.
        button.custom_minimum_size = Vector2(ceil(widest) + 15 + 9 + 42, 48)
        button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        button.add_theme_font_override("font", ThemeScript.vazir(ThemeScript.CAPTION))
        button.add_theme_font_size_override("font_size", caption)
        var ink := ThemeScript.GOLD_DEEP if persian else ThemeScript.GREEN_DEEP
        button.add_theme_color_override("font_color", ink)
        button.add_theme_color_override("font_hover_color", ink)
        button.add_theme_color_override("font_focus_color", ink)
        # A gold pill with a real edge: the recitation is an action, and an
        # action on this page wears a fill deep enough to see against the card
        # and an edge crisp enough to read as something that gives. The
        # translation keeps the same coin in white, so a reader can tell the
        # two voices apart at a glance.
        var rest_fill := Color("#FFFFFF") if persian else Color("#F2E3BC")
        var rest := ThemeScript.button_stylebox(rest_fill, 23)
        rest.border_color = ThemeScript.GOLD
        rest.set_border_width_all(2)
        var hover_fill := ThemeScript.GOLD_SOFT if persian else Color("#EAD9AC")
        var hover := ThemeScript.button_stylebox(hover_fill, 23)
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
        button.set_meta("persian", persian)
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
        var icon := ThemeScript.SoundMark.new(ink)
        icon.name = "Icon"
        icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
        row.add_child(icon)
        var label := Label.new()
        label.name = "Label"
        label.text = idle_text
        ThemeScript.dress(label, ThemeScript.CAPTION, ink)
        row.add_child(label)
        return button

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
        _body.add_child(rect)

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

## The sound ran to its own end: the button that spoke for it goes back to
## rest, if the card it lived on still exists to hear it.
func _on_audio_finished() -> void:
        _playing_path = ""
        var button := _playing_button
        _playing_button = null
        if button != null and is_instance_valid(button):
                _set_button_state(button, "idle")

## What a button says while it works, speaks, or cannot: one place, so every
## state dresses the same on every button.
func _set_button_state(button: Button, state: String) -> void:
        var icon: ThemeScript.SoundMark = button.get_node("Center/Row/Icon")
        var label: Label = button.get_node("Center/Row/Label")
        var ink: Color = ThemeScript.GOLD_DEEP if bool(button.get_meta("persian", false)) else ThemeScript.GREEN_DEEP
        match state:
                "playing":
                        icon.color = ThemeScript.GOLD
                        icon.speaking = true
                        label.text = I18nScript.t("Listening…")
                "loading":
                        label.text = I18nScript.t("Fetching…")
                "missing":
                        icon.color = ThemeScript.INK_SOFT
                        label.text = I18nScript.t("Unavailable")
                _:
                        icon.color = ink
                        icon.speaking = false
                        label.text = str(button.get_meta("idle_text", I18nScript.t("Listen")))
        icon.queue_redraw()

func _stream_from_site(path: String, button: Button) -> void:
        if _fetching:
                return
        if _web_cache.has(path):
                _speak(path, button, _web_cache[path])
                return
        _fetching = true
        _set_button_state(button, "loading")
        # The button is not disabled while it fetches: a disabled button
        # wears the engine's grey, and a pill that flashes grey for a moment
        # reads as broken. The fetch guard above already keeps a second
        # press from starting a second fetch.
        var fetcher := HTTPRequest.new()
        add_child(fetcher)
        var err := fetcher.request(_site_url(path))
        var bytes := PackedByteArray()
        if err == OK:
                var outcome: Array = await fetcher.request_completed
                if int(outcome[1]) == 200:
                        bytes = outcome[3]
        fetcher.queue_free()
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
                # The address the button carries is chrome, not content: it
                # is written in the reader's own digits, like every number
                # the app says about itself.
                return I18nScript.num("%d:%d" % [int(stem.substr(0, 3)), int(stem.substr(3, 3))])
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
                                return 56
                        "persian":
                                return 30
                        _:
                                return 24
        match script:
                "arabic":
                        return 40
                "persian":
                        return 20
                _:
                        return ThemeScript.CAPTION

static func _bbcode(markdown: String, _script := "plain") -> String:
        var text := markdown
        text = _links(text)
        text = _bold(text)
        # The author's asterisks are the author's asterisks: a star written
        # on either side of a word is shown on either side of the word, a
        # character like any other. The deck's author wrapped the bismillah
        # in stars to see them, not to lean the words between them -- the
        # emphasis reading was the app's own, and the author asked for it
        # to stop.
        return text


## Markdown links become clickable BBCode. Images are skipped -- the view's
## media pass owns those, and their brackets must not be touched here.
static func _links(text: String) -> String:
        var re := RegEx.create_from_string("(?<!!)\\[([^\\]]+)\\]\\(([^)]+)\\)")
        return re.sub(text, "[url=$2][color=#1E6B52]$1[/color][/url]", true)

static func _bold(text: String) -> String:
        var re := RegEx.create_from_string("\\*\\*(?P<inner>[^*]+)\\*\\*")
        return re.sub(text, "[b]$1[/b]", true)

func _clear() -> void:
        _stop_audio()
        for child in _body.get_children():
                _body.remove_child(child)
                child.queue_free()
        var footer := get_node_or_null("Footer")
        if footer != null:
                remove_child(footer)
                footer.queue_free()
        _playing_button = null
        _playing_path = ""
