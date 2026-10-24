class_name StudyScreen
extends Control
const ThemeScript := preload("res://scripts/ui/theme.gd")
const CardScript := preload("res://scripts/data/card.gd")
const SchedulerScript := preload("res://scripts/data/scheduler.gd")
const CardViewScript := preload("res://scripts/ui/card_view.gd")
const CardEditorScript := preload("res://scripts/ui/card_editor.gd")
const MarkdownScript := preload("res://scripts/ui/markdown.gd")
const I18nScript := preload("res://scripts/ui/i18n.gd")

## A session: one card at a time, question first, then the answer, then how
## well it went. The page keeps the app's one foot bar, the way every page
## does -- the four doors stand at the reader's thumb, and the session's
## own words keep a breath above them. The four answers carry their own
## intervals, so the cost of each choice is plain before you make it, and
## each answer moves the card itself: a card that returns swells and
## fades, a card that moves on recedes, and the next one settles into
## place.
##
## The question rides along on the answer side, small and gold, so the verse
## is never read without knowing which one was asked for.

signal closed
signal answered(card: CardScript, button: String)
## A card taken out of the day and put back in the initial basket: not an
## answer, nothing graded -- the reader is not ready for this ayah now,
## and the card returns with tomorrow's new cards.
signal deferred(card: CardScript)
## A card taken out of the schedule for good: not an answer, nothing graded,
## nothing remembered of what it had learned -- the reader is done being
## asked this ayah, and the queue will never offer it again.
signal suspended(card: CardScript)
signal volume_changed(value: float)
signal edited(card: CardScript)
## The verses' hand, chosen where they are read: main hears it, remembers
## it on the device and stamps it into the deck's own travelling file.
signal ayah_font_chosen(key: String)

const PANEL := "Margin/Column/Surface/Fill/CardPanel"
const AGAIN_COLOR := Color("#B4553F")
const HARD_COLOR := Color("#96762A")
const GOOD_COLOR := Color("#1E6B52")
const EASY_COLOR := Color("#14513D")
## The session's card is a touch wider than the library's page: a verse and
## its translation are read together here, and the extra measure lets the
## pair breathe on one line where the shelf keeps its own economy.
const CARD_MEASURE := 800

var _cards: Array = []
var _index := 0
var _revealed := false
var _answered_count := 0
var _started_ms := 0
var _busy := false
var _player: AudioStreamPlayer
var _view: CardViewScript
var _options: Array = []
var _bar_tween: Tween
var volume := 1.0  # the recitation's own loudness, 0..1, set before the session starts
var _rig: ThemeScript.VolumeRig  # the popup, its coin and the player, one shared thing

func _ready() -> void:
        _player = AudioStreamPlayer.new()
        _player.name = "Player"
        add_child(_player)
        _rig = ThemeScript.VolumeRig.new(self, _player)
        _build()
        resized.connect(_layout)
        call_deferred("_layout")

func _exit_tree() -> void:
        if _player != null and is_instance_valid(_player):
                _player.queue_free()

func start(cards: Array) -> void:
        _cards = cards
        _index = 0
        _answered_count = 0
        _started_ms = Time.get_ticks_msec()
        _busy = false
        if not is_node_ready():
                await ready
        var scroll: ScrollContainer = get_node("Margin/Column/Surface")
        scroll.get_v_scroll_bar().value = 0
        _show_front()

func _build() -> void:
        set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        add_child(ThemeScript.paper_backdrop())
        add_child(ThemeScript.paper_pattern())
        var margin := MarginContainer.new()
        margin.name = "Margin"
        margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        margin.add_theme_constant_override("margin_left", 24)
        margin.add_theme_constant_override("margin_right", 24)
        margin.add_theme_constant_override("margin_top", 24)
        margin.add_theme_constant_override("margin_bottom", 24)
        add_child(margin)

        var column := VBoxContainer.new()
        column.name = "Column"
        column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        column.add_theme_constant_override("separation", 14)
        margin.add_child(column)

        column.add_child(_top_bar())
        column.add_child(_session_bar())
        column.add_child(_surface())
        column.add_child(_answers())
        if not DisplayServer.is_touchscreen_available():
                column.add_child(_key_hints())
        column.add_child(_footer())
        # The small pages float above everything, added last so they draw
        # last, waiting in their corners until the hand asks for them.
        add_child(_rig.popup())
        add_child(_font_popup())

## The session's own quiet progress: a thin bar under the top row that fills
## as cards are answered. The count label above it stays for the exact number;
## the bar is for the feeling of being nearly done -- and it moves to meet
## each answer instead of snapping.
func _session_bar() -> Control:
        var bar := ProgressBar.new()
        bar.name = "SessionBar"
        bar.show_percentage = false
        bar.custom_minimum_size = Vector2(0, 9)
        var track := StyleBoxFlat.new()
        track.bg_color = Color("#CFC1A2")
        track.set_corner_radius_all(4)
        var fill := StyleBoxFlat.new()
        fill.bg_color = ThemeScript.GREEN_DEEP
        fill.set_corner_radius_all(4)
        bar.add_theme_stylebox_override("background", track)
        bar.add_theme_stylebox_override("fill", fill)
        return bar

func _key_hints() -> Control:
        var row := HBoxContainer.new()
        row.name = "Keys"
        row.alignment = BoxContainer.ALIGNMENT_CENTER
        row.add_theme_constant_override("separation", 8)
        var hint := func(chip: String, what: String) -> void:
                row.add_child(ThemeScript.key_chip(chip))
                var label := Label.new()
                label.text = what
                ThemeScript.dress(label, ThemeScript.CAPTION, ThemeScript.INK_SOFT)
                row.add_child(label)
        hint.call("Space", I18nScript.t("reveal"))
        hint.call("1–4", I18nScript.t("answer"))
        hint.call("S", I18nScript.t("Not today"))
        hint.call("Esc", I18nScript.t("close"))
        return row

## Back the way the user came, the count in the middle, room on the right:
## the same bones every screen's header shares. The right corner carries
## three coins -- the pencil that opens the card for editing, the alif that
## asks which hand the verses are written in, and the speaker that asks
## how loud -- with a spacer of the same width beside the way back, so the
## count in the middle stays the middle.
func _top_bar() -> Control:
        # The bar answers the reading's own direction: under a right-reading
        # tongue the way back points right from the right corner, the way the
        # settings page already reads, so every page answers alike.
        var bar: Dictionary = ThemeScript.top_bar("", I18nScript.is_rtl())
        var row: HBoxContainer = bar["row"]
        var back: Button = bar["back"]
        back.tooltip_text = I18nScript.t("Back to home")
        back.pressed.connect(func() -> void: closed.emit())
        # The corner's coins move the centre left by their extra width; a
        # quiet spacer of the same width after the way back keeps the
        # count where every other screen keeps it.
        var spacer := Control.new()
        spacer.name = "Spacer"
        spacer.custom_minimum_size = Vector2(108, 0)
        spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
        row.add_child(spacer)
        row.move_child(spacer, 1)
        # The header's middle is this screen's count, not its name: the user
        # knows where they are; what they want to know is how far is left.
        var progress: Label = bar["title"]
        progress.name = "Progress"
        progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        progress.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        ThemeScript.dress(progress, 15, ThemeScript.INK_SOFT, true)
        # The corner every screen leaves empty gets this screen's own three
        # questions: the card's own words, the hand they are written in, and
        # how loud they are spoken.
        var right: Control = bar["right"]
        right.custom_minimum_size = Vector2(156, 48)
        var pair := HBoxContainer.new()
        pair.name = "Pair"
        pair.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        pair.add_theme_constant_override("separation", 6)
        right.add_child(pair)

        var edit := Button.new()
        edit.name = "Edit"
        edit.custom_minimum_size = Vector2(48, 48)
        edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        edit.tooltip_text = I18nScript.t("Edit this card")
        ThemeScript.apply_mark_styles(edit, ThemeScript.mark_button_styles(ThemeScript.GOLD, true))
        var pencil := ThemeScript.PencilMark.new(ThemeScript.GOLD_DEEP)
        pencil.name = "PencilMark"
        var edit_center := CenterContainer.new()
        edit_center.name = "Mark"
        edit_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        edit_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
        pencil.mouse_filter = Control.MOUSE_FILTER_IGNORE
        edit_center.add_child(pencil)
        edit.add_child(edit_center)
        ThemeScript.pressable(edit)
        edit.pressed.connect(_open_editor)
        pair.add_child(edit)

        var face := Button.new()
        face.name = "Font"
        face.custom_minimum_size = Vector2(48, 48)
        face.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        face.tooltip_text = I18nScript.t("Ayah font")
        ThemeScript.apply_mark_styles(face, ThemeScript.mark_button_styles(ThemeScript.GREEN, true))
        var alif := ThemeScript.TypeMark.new(ThemeScript.GREEN_DEEP)
        alif.name = "TypeMark"
        var face_center := CenterContainer.new()
        face_center.name = "Mark"
        face_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        face_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
        alif.mouse_filter = Control.MOUSE_FILTER_IGNORE
        face_center.add_child(alif)
        face.add_child(face_center)
        ThemeScript.pressable(face)
        face.pressed.connect(_toggle_font_popup)
        pair.add_child(face)

        var coin := Button.new()
        coin.name = "Volume"
        coin.custom_minimum_size = Vector2(48, 48)
        coin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        ThemeScript.apply_mark_styles(coin, ThemeScript.mark_button_styles(ThemeScript.GREEN, true))
        var mark := ThemeScript.VolumeMark.new(ThemeScript.GREEN_DEEP)
        mark.name = "VolumeMark"
        var center := CenterContainer.new()
        center.name = "Mark"
        center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        center.mouse_filter = Control.MOUSE_FILTER_IGNORE
        mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
        center.add_child(mark)
        coin.add_child(center)
        coin.tooltip_text = I18nScript.t("Recitation volume")
        ThemeScript.pressable(coin)
        coin.pressed.connect(_toggle_volume)
        pair.add_child(coin)
        return row

func _surface() -> Control:
        var scroll := ScrollContainer.new()
        scroll.name = "Surface"
        scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
        scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
        ThemeScript.style_scroll(scroll)

        # The card is a page, not a banner: a short one stands in the middle of
        # the surface instead of clinging to its top, and a long one scrolls.
        # The filler is pinned to the surface's height from below -- a plain
        # centre would leave the card hugging the top edge whenever the words
        # run short, which is most of the time on the question side.
        var fill := VBoxContainer.new()
        fill.name = "Fill"
        fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        fill.alignment = BoxContainer.ALIGNMENT_CENTER
        fill.add_theme_constant_override("separation", 0)
        scroll.add_child(fill)

        var card := PanelContainer.new()
        card.name = "CardPanel"
        card.custom_minimum_size = Vector2(640, 260)
        card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        card.add_theme_stylebox_override("panel", ThemeScript.card_stylebox())
        card.resized.connect(func() -> void:
                if card.size.x > 0.0:
                        card.pivot_offset = card.size / 2.0
        )
        fill.add_child(card)

        var pad := MarginContainer.new()
        pad.name = "Padding"
        pad.add_theme_constant_override("margin_left", 40)
        pad.add_theme_constant_override("margin_right", 40)
        pad.add_theme_constant_override("margin_top", 44)
        pad.add_theme_constant_override("margin_bottom", 44)
        card.add_child(pad)

        var view: CardViewScript = CardViewScript.new(_player)
        view.name = "View"
        view.alignment = BoxContainer.ALIGNMENT_CENTER
        pad.add_child(view)
        _view = view
        return scroll

func _answers() -> Control:
        var grid := GridContainer.new()
        grid.name = "Answers"
        grid.columns = 2
        grid.add_theme_constant_override("h_separation", 10)
        grid.add_theme_constant_override("v_separation", 10)
        grid.custom_minimum_size = Vector2(0, 72)
        return grid

## The footer's own column: the way forward and the two ways out, one above
## the other. The way forward -- "Show answer" -- is the page's one loud
## word, standing at the column's full width; the ways out are quiet ghosts
## beneath it, centred and a breath shorter, because they must be found
## when they are wanted and never stumbled into. "Not today" puts the card
## back in its basket until tomorrow; "Not at all", a breath shorter still,
## takes it out of the schedule for good -- as though it was never started.
## Both stand only on the question side: once the answer is seen, the card
## is answered, not put back. At the end the column carries one word only.
func _footer() -> Control:
        var row := CenterContainer.new()
        row.name = "Footer"

        var stack := VBoxContainer.new()
        stack.name = "Stack"
        stack.add_theme_constant_override("separation", 10)
        row.add_child(stack)

        var show := ThemeScript.primary_button(I18nScript.t("Show answer"), 58)
        show.name = "ShowAnswer"
        show.custom_minimum_size = Vector2(320, 58)
        show.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        show.pressed.connect(_reveal)
        stack.add_child(show)

        var put_back := ThemeScript.ghost_button(I18nScript.t("Not today"), ThemeScript.INK_SOFT, 48, 24)
        put_back.name = "PutBack"
        put_back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        put_back.tooltip_text = I18nScript.t(
                "Put this card back — it returns with tomorrow's new cards."
        )
        put_back.pressed.connect(_put_back)
        stack.add_child(put_back)

        # The quietest way out stands last and smallest: one deliberate reach
        # further than "Not today", for the card the reader wants never to be
        # asked again. It carries its own words, and the tooltip says exactly
        # what it does -- there is no way back from it inside the app.
        var take_out := ThemeScript.ghost_button(I18nScript.t("Not at all"), ThemeScript.INK_SOFT, 40, 20)
        take_out.name = "TakeOut"
        take_out.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        take_out.tooltip_text = I18nScript.t(
                "Take this card out of the schedule for good — as if never studied."
        )
        take_out.pressed.connect(_take_out)
        stack.add_child(take_out)

        var done := ThemeScript.ghost_button(I18nScript.t("Done"), ThemeScript.GREEN, 58)
        done.name = "Done"
        done.custom_minimum_size = Vector2(320, 58)
        done.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        done.visible = false
        done.pressed.connect(func() -> void: closed.emit())
        stack.add_child(done)
        return row

func _layout() -> void:
        if size.x <= 0.0:
                return
        _layout_answers()
        # The page answers the notch: the top margin rides below whatever the
        # display keeps for itself, so the way back is never under a camera.
        var margin: MarginContainer = get_node("Margin")
        margin.add_theme_constant_override("margin_top", int(24.0 + ThemeScript.top_inset()))
        # The app's own foot stands here, the way it stands under every page:
        # the session's answers and footer end a breath above its doors, and
        # whatever the display keeps for itself rides below them both.
        margin.add_theme_constant_override("margin_bottom", int(ThemeScript.foot_height() + 12.0))
        # A phone's card breathes with smaller margins: the words keep the
        # room the desktop's generous padding would have taken.
        var narrow := size.x < ThemeScript.NARROW
        var pad: MarginContainer = get_node(PANEL + "/Padding")
        pad.add_theme_constant_override("margin_left", 24 if narrow else 40)
        pad.add_theme_constant_override("margin_right", 24 if narrow else 40)
        pad.add_theme_constant_override("margin_top", 30 if narrow else 44)
        pad.add_theme_constant_override("margin_bottom", 30 if narrow else 44)
        # The card is a page, not a banner: it never runs wider than a
        # comfortable measure, whatever the window does with itself. Narrow
        # windows still get everything they can hold. The height is a floor,
        # not a fixed size -- a short reference gets a modest card, and a long
        # verse grows the page as far as the words need.
        var surface: ScrollContainer = get_node("Margin/Column/Surface")
        var fill: VBoxContainer = get_node("Margin/Column/Surface/Fill")
        var card: PanelContainer = get_node(PANEL)
        var width: float = minf(size.x - 48.0, CARD_MEASURE)
        card.custom_minimum_size = Vector2(maxf(width, 280.0), 260.0)
        # The centre the question side needs: the filler is never shorter than
        # the surface, so a short card floats in the middle of the page.
        fill.custom_minimum_size.y = surface.size.y
        # The footer's stack: one measure, shared. The stack never runs
        # past the window's own margins and never past the measure the
        # primary word deserves; the way forward takes the whole measure
        # and the quiet escape a centred breath of it beneath -- a phone
        # trims both, so neither button is ever asked to hold more words
        # than its width can carry.
        var stack: VBoxContainer = get_node("Margin/Column/Footer/Stack")
        var room := maxf(minf(size.x - 48.0, 470.0), 240.0)
        stack.custom_minimum_size = Vector2(room, 0)
        var escape_w := 150.0 if size.x >= 470.0 else 126.0
        (stack.get_node("PutBack") as Button).custom_minimum_size = Vector2(escape_w, 48.0)
        (stack.get_node("TakeOut") as Button).custom_minimum_size = Vector2(escape_w, 40.0)
        (stack.get_node("ShowAnswer") as Button).custom_minimum_size = Vector2(room, 58.0)
        (stack.get_node("Done") as Button).custom_minimum_size = Vector2(room, 58.0)
        # The small pages that hang from the header's coins stay hung: the
        # window may move under them, and the pages follow the coins the
        # bar keeps in its corner.
        var volume_page: Control = get_node_or_null("VolumePopup")
        if volume_page != null:
                ThemeScript.place_popover(
                        volume_page, get_node("Margin/Column/TopBar/Right/Pair/Volume")
                )
        var font_page: Control = get_node_or_null("FontPopup")
        if font_page != null:
                ThemeScript.place_popover(
                        font_page, get_node("Margin/Column/TopBar/Right/Pair/Font")
                )

func _layout_answers() -> void:
        var grid: GridContainer = get_node("Margin/Column/Answers")
        grid.columns = 4 if size.x >= 620 else 2

func _show_front(incoming := false) -> void:
        _revealed = false
        if _index >= _cards.size():
                _show_done()
                return
        # A finished session leaves its summary behind; a new one takes the
        # card's own view back.
        var summary := get_node_or_null(PANEL + "/Padding/Summary")
        if summary != null:
                summary.queue_free()
        _view.visible = true
        var card: CardScript = _cards[_index]
        var progress: Label = get_node("Margin/Column/TopBar/Progress")
        progress.text = I18nScript.f("%d of %d", [_index + 1, _cards.size()])
        _tween_bar(100.0 * float(_index) / float(_cards.size()))
        _view.show_text(card.front, card.folder, true)
        get_node("Margin/Column/Footer/Stack/ShowAnswer").visible = true
        get_node("Margin/Column/Footer/Stack/PutBack").visible = true
        get_node("Margin/Column/Footer/Stack/TakeOut").visible = true
        get_node("Margin/Column/Footer/Stack/Done").visible = false
        _clear_answers()
        _settle_card(incoming)

## The bar moves to meet each answer; it never snaps.
func _tween_bar(to: float) -> void:
        if _bar_tween != null and _bar_tween.is_valid():
                _bar_tween.kill()
        var bar := get_node("Margin/Column/SessionBar") as ProgressBar
        _bar_tween = create_tween()
        _bar_tween.tween_property(bar, "value", to, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _clear_answers() -> void:
        var grid: GridContainer = get_node("Margin/Column/Answers")
        for child in grid.get_children():
                grid.remove_child(child)
                child.queue_free()

func _reveal() -> void:
        if _revealed or _index >= _cards.size():
                return
        _revealed = true
        var card: CardScript = _cards[_index]
        # The question rides along, small and gold, above its own answer.
        _view.show_text(card.back, card.folder, false, _reference_of(card), true)
        var scroll: ScrollContainer = get_node("Margin/Column/Surface")
        scroll.scroll_vertical = 0
        get_node("Margin/Column/Footer/Stack/ShowAnswer").visible = false
        # The escapes belong to the question alone: once the answer is seen,
        # the card is answered, not put back and not taken out.
        get_node("Margin/Column/Footer/Stack/PutBack").visible = false
        get_node("Margin/Column/Footer/Stack/TakeOut").visible = false

        _clear_answers()
        _options = SchedulerScript.options(SchedulerScript.id_seed(card.id), card.state, int(Time.get_unix_time_from_system()))
        for i in _options.size():
                var button := _answer_button(_options[i], i)
                get_node("Margin/Column/Answers").add_child(button)
                ThemeScript.settle_in(button, 0.05 * i, 0.2)
        _layout_answers()
        var grid: GridContainer = get_node("Margin/Column/Answers")
        if grid.get_child_count() > 0:
                grid.get_child(0).grab_focus()

## The first plain line of a card's question: the reference the reader was
## asked to recite from -- one law with home and the library
## (MarkdownScript.first_plain_line).
func _reference_of(card: CardScript) -> String:
        return MarkdownScript.first_plain_line(card.front)

## One answer, one button. The button says three things at once: what it
## means (the word, in the grade's colour), what it costs (the interval --
## the biggest thing on the button, because it is the decision), and, where a
## keyboard is attached, which key presses it (a chip, because the hints line
## below already promised 1-4 would work).
func _answer_button(option: Dictionary, index: int) -> Control:
        var button := Button.new()
        button.name = str(option.button).capitalize()
        button.custom_minimum_size = Vector2(0, 72)
        button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        var grade: Color = ThemeScript.INK
        match str(option.button):
                "again":
                        grade = AGAIN_COLOR
                "hard":
                        grade = HARD_COLOR
                "good":
                        grade = GOOD_COLOR
                "easy":
                        grade = EASY_COLOR
        # A wash fill at rest -- an empty outline reads as disabled -- a
        # hairline of the grade's own colour so the pill has an edge even
        # before it is visited (a bare wash was reading as inactive), with
        # the full border arriving on hover and staying while pressed.
        var rest := StyleBoxFlat.new()
        rest.bg_color = Color(grade.r, grade.g, grade.b, 0.12)
        rest.border_color = Color(grade.r, grade.g, grade.b, 0.38)
        rest.set_border_width_all(2)
        rest.set_corner_radius_all(16)
        var held := StyleBoxFlat.new()
        held.bg_color = Color(grade.r, grade.g, grade.b, 0.20)
        held.border_color = grade
        held.set_border_width_all(2)
        held.set_corner_radius_all(16)
        button.add_theme_stylebox_override("normal", rest)
        button.add_theme_stylebox_override("hover", held)
        button.add_theme_stylebox_override("pressed", held)
        button.add_theme_stylebox_override("focus", held)
        ThemeScript.pressable(button)
        button.pressed.connect(_answer.bind(str(option.button)))

        var center := CenterContainer.new()
        center.name = "Center"
        center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        center.mouse_filter = Control.MOUSE_FILTER_IGNORE
        button.add_child(center)
        var row := HBoxContainer.new()
        row.name = "Row"
        row.alignment = BoxContainer.ALIGNMENT_CENTER
        row.add_theme_constant_override("separation", 12)
        row.mouse_filter = Control.MOUSE_FILTER_IGNORE
        center.add_child(row)

        if not DisplayServer.is_touchscreen_available():
                var chip := PanelContainer.new()
                chip.name = "Key"
                chip.custom_minimum_size = Vector2(32, 32)
                chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
                chip.add_theme_stylebox_override("panel", ThemeScript.soft_stylebox(Color(grade.r, grade.g, grade.b, 0.10), 9))
                var digit := Label.new()
                digit.text = str(index + 1)
                digit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
                digit.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
                digit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
                digit.size_flags_vertical = Control.SIZE_EXPAND_FILL
                ThemeScript.dress(digit, 15, grade, true)
                chip.add_child(digit)
                row.add_child(chip)

        var stack := VBoxContainer.new()
        stack.name = "Stack"
        stack.alignment = BoxContainer.ALIGNMENT_CENTER
        stack.add_theme_constant_override("separation", 2)
        row.add_child(stack)
        var word := Label.new()
        word.name = "Word"
        word.text = I18nScript.t(str(option.button).capitalize())
        # The word and its wait stand on one axis, the pair of them centred
        # together: a left-flush word inside a stack as wide as its bigger
        # neighbour reads as a dent, not a decision.
        word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        ThemeScript.dress(word, 14, grade, true)
        stack.add_child(word)
        var wait := Label.new()
        wait.name = "Wait"
        wait.text = I18nScript.wait(int(option.interval_secs))
        wait.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        ThemeScript.dress(wait, 22, ThemeScript.INK, true)
        stack.add_child(wait)
        return button

func _answer(button: String) -> void:
        if _busy or _index >= _cards.size():
                return
        var card: CardScript = _cards[_index]
        answered.emit(card, button)
        _answered_count += 1
        _advance(str(button) == "again")


## The card leaves without being answered: it goes back in the initial
## basket and waits out the day, and the page hands itself to whatever
## comes next the way a finished card does -- it is leaving, not staying
## to return. The session's own count never hears of it: nothing was
## answered, and tomorrow's fresh cards will say the card again.
func _put_back() -> void:
        if _busy or _index >= _cards.size() or _revealed:
                return
        var card: CardScript = _cards[_index]
        deferred.emit(card)
        _advance(false)


## The card leaves the schedule altogether: whatever it had learned is
## given back, the door closes, and the page hands itself to whatever comes
## next the way a finished card does. Like a defer, the session's own count
## never hears of it -- but unlike a defer, no tomorrow brings it back.
func _take_out() -> void:
        if _busy or _index >= _cards.size() or _revealed:
                return
        var card: CardScript = _cards[_index]
        suspended.emit(card)
        _advance(false)


## The card itself answers too: one that returns swells and fades in place --
## it is not going anywhere -- and one that is finished with recedes, handing
## the page to whatever comes next. Then the next card settles into place,
## arriving as a page does, once.
func _advance(returns: bool) -> void:
        _busy = true
        var panel := get_node(PANEL) as PanelContainer
        if panel.pivot_offset == Vector2.ZERO:
                panel.pivot_offset = panel.size / 2.0
        var to := Vector2(1.05, 1.05) if returns else Vector2(0.955, 0.955)
        var tween := create_tween()
        tween.set_parallel(true)
        tween.tween_property(panel, "modulate:a", 0.0, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
        tween.tween_property(panel, "scale", to, 0.17).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
        tween.chain().tween_callback(func() -> void:
                _index += 1
                _show_front(true)
        )

## A new card arrives: it fades in where it stands, gathering from a breath
## larger than itself down to its own size -- the settling of a page, not the
## sliding of a widget.
func _settle_card(incoming: bool) -> void:
        var panel := get_node(PANEL) as PanelContainer
        if panel.pivot_offset == Vector2.ZERO:
                panel.pivot_offset = panel.size / 2.0
        if not incoming:
                ThemeScript.settle_in(_view)
                ThemeScript.settle_in(get_node("Margin/Column/Footer/Stack/ShowAnswer"), 0.06)
                _busy = false
                return
        panel.modulate.a = 0.0
        panel.scale = Vector2(1.03, 1.03)
        var tween := create_tween()
        tween.set_parallel(true)
        tween.tween_property(panel, "modulate:a", 1.0, 0.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
        tween.tween_property(panel, "scale", Vector2.ONE, 0.30).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
        tween.chain().tween_callback(func() -> void: _busy = false)

## How long the session took, said plainly: the app keeps no timer a user
## could feel watched by; this is a count after the fact, never a clock
## running during.
func _duration() -> String:
        var minutes := int(round((Time.get_ticks_msec() - _started_ms) / 60000.0))
        if minutes < 1:
                return I18nScript.t("under a minute")
        if minutes == 1:
                return I18nScript.t("1 minute")
        return I18nScript.f("%d minutes", [minutes])

func _show_done() -> void:
        _tween_bar(100.0)
        var progress: Label = get_node("Margin/Column/TopBar/Progress")
        progress.text = I18nScript.t("complete")
        _view.visible = false
        _clear_answers()
        # The page the last answer faded out is the page the summary stands on:
        # back to full presence, and the summary's own children arrive in turn.
        var page := get_node(PANEL) as PanelContainer
        page.modulate.a = 1.0
        page.scale = Vector2.ONE
        var pad: MarginContainer = get_node(PANEL + "/Padding")
        var summary := VBoxContainer.new()
        summary.name = "Summary"
        summary.alignment = BoxContainer.ALIGNMENT_CENTER
        summary.add_theme_constant_override("separation", 12)
        pad.add_child(summary)

        # The medal must sit in the middle of the page, not at the left edge of
        # a control the column stretched: shrink-centre it, the way its drawn
        # circle always meant to stand.
        var medal := ThemeScript.CheckMark.new()
        medal.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        summary.add_child(medal)

        var title := Label.new()
        title.name = "Title"
        title.text = I18nScript.t("Session complete")
        title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        ThemeScript.dress(title, ThemeScript.TITLE, ThemeScript.GREEN_DEEP, true)
        summary.add_child(title)

        var body := Label.new()
        body.name = "Body"
        body.text = I18nScript.f(
                "You answered %d cards in %s. Everything is saved.",
                [_answered_count, _duration()]
        )
        body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        ThemeScript.dress(body, ThemeScript.BODY, ThemeScript.INK)
        summary.add_child(body)

        summary.add_child(ThemeScript.hairline())

        var rest := Label.new()
        rest.name = "Rest"
        rest.text = I18nScript.t("Rest is part of learning.")
        rest.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        ThemeScript.dress(rest, ThemeScript.CAPTION, ThemeScript.INK_SOFT)
        summary.add_child(rest)

        ThemeScript.stagger_in(summary, 0.09, 0.3)
        get_node("Margin/Column/Footer/Stack/ShowAnswer").visible = false
        get_node("Margin/Column/Footer/Stack/PutBack").visible = false
        get_node("Margin/Column/Footer/Stack/TakeOut").visible = false
        get_node("Margin/Column/Footer/Stack/Done").visible = true

# --- the card, editable on the spot --------------------------------------------------

## The pencil opens the card's own page over the session: the words as the
## author wrote them, ready for the fix a reader notices while studying.
## Added after everything else, the editor stands above the page and is
## offered the keyboard first; the screen beneath goes quiet until it
## closes.
func _open_editor() -> void:
        if _index >= _cards.size():
                return
        if get_node_or_null("Editor") != null:
                return
        var editor := CardEditorScript.new(_cards[_index], volume)
        editor.name = "Editor"
        add_child(editor)
        editor.saved.connect(_on_editor_saved)

## A saved edit is the same card, re-read: the page shows the words as they
## now are, on whichever side was standing when the pencil was pressed.
func _on_editor_saved(card: CardScript) -> void:
        edited.emit(card)
        if _revealed:
                _view.show_text(card.back, card.folder, false, _reference_of(card))
        else:
                _view.show_text(card.front, card.folder, true)

# --- the verses' own hand, chosen where they are read ----------------------------

## The verses' own hand, chosen mid-session: the same faces Settings
## offers, each row named and sampled in the face itself, hung from the
## alif coin in the header's corner. The choice is applied to the card on
## the spot -- the reader watches the verse change hands without leaving
## the session -- and travels with the deck the way every choice does.
func _font_popup() -> Control:
        var popup := ThemeScript.Popover.new(268.0)
        popup.name = "FontPopup"
        var pad := popup.content(14, 12, 14, 14)
        var column := VBoxContainer.new()
        column.name = "Column"
        column.add_theme_constant_override("separation", 8)
        pad.add_child(column)
        var title := Label.new()
        title.name = "Title"
        title.text = I18nScript.t("Ayah font")
        ThemeScript.dress(title, ThemeScript.CAPTION, ThemeScript.INK_SOFT)
        column.add_child(title)
        var rows := VBoxContainer.new()
        rows.name = "Faces"
        rows.add_theme_constant_override("separation", 6)
        column.add_child(rows)
        var current := ThemeScript.ayah_face_key()
        for face in ThemeScript.AYAH_FACES:
                rows.add_child(_face_row(str(face["key"]), str(face["key"]) == current))
        return popup

## One face, one row: its name at the reading end, the basmala in the face
## itself at the other -- the choice is judged on what it chooses, not on a
## description of it, exactly as the Settings page judges the same choice.
## The row's height is said by the faces themselves, so no sample can
## outgrow the box that offers it.
func _face_row(key: String, on: bool) -> Button:
        var button := Button.new()
        button.name = "Face" + key.capitalize()
        button.set_meta("choice", key)
        button.custom_minimum_size = Vector2(0, _face_row_height())
        button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        _dress_face_row(button, on)
        var pad := MarginContainer.new()
        pad.name = "Pad"
        pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
        pad.add_theme_constant_override("margin_left", 12)
        pad.add_theme_constant_override("margin_right", 12)
        pad.add_theme_constant_override("margin_top", 6)
        pad.add_theme_constant_override("margin_bottom", 6)
        button.add_child(pad)
        var row := HBoxContainer.new()
        row.name = "Row"
        row.mouse_filter = Control.MOUSE_FILTER_IGNORE
        row.add_theme_constant_override("separation", 10)
        pad.add_child(row)
        var name := Label.new()
        name.name = "Name"
        name.text = ThemeScript.ayah_face_label(key)
        name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        ThemeScript.dress(name, 13, ThemeScript.GREEN_DEEP if on else ThemeScript.INK, on)
        row.add_child(name)
        var sample := Label.new()
        sample.name = "Sample"
        sample.text = ThemeScript.BASMALA_SAMPLE
        sample.text_direction = TextDirection.TEXT_DIRECTION_AUTO
        var face: Font = ThemeScript.ayah_face_for(key)
        var sample_size := ThemeScript.fs(19)
        sample.add_theme_font_override("font", face)
        sample.add_theme_font_size_override("font_size", sample_size)
        sample.add_theme_color_override("font_color", ThemeScript.INK)
        # The sample's ink is measured, not guessed: a face whose marks
        # stand past its font's box is given the room they ask for -- the
        # same law every verse on every page is drawn by.
        ThemeScript.give_label_room(sample, sample.text, face, sample_size)
        row.add_child(sample)
        ThemeScript.pressable(button)
        button.pressed.connect(_choose_face.bind(key))
        return button

## The height every face row shares: the tallest face's measured sample,
## with the padding the row carries inside. The faces themselves say the
## number, the same way Settings' segments are sized.
static func _face_row_height() -> float:
        var name_h := ceili(ThemeScript.vazir(13).get_height(ThemeScript.fs(13)))
        return 12.0 + maxf(name_h, ThemeScript.basmala_sample_height())

## A face row at rest is quiet paper; the face being worn carries the
## page's own green wash -- the way a book's folios are marked.
func _dress_face_row(button: Button, on: bool) -> void:
        var rest := ThemeScript.soft_stylebox(Color(0, 0, 0, 0), 12)
        rest.border_color = Color(
                ThemeScript.GREEN.r, ThemeScript.GREEN.g, ThemeScript.GREEN.b, 0.42 if on else 0.16
        )
        rest.set_border_width_all(1)
        var wash := rest.duplicate() as StyleBoxFlat
        wash.bg_color = Color(ThemeScript.GREEN.r, ThemeScript.GREEN.g, ThemeScript.GREEN.b, 0.10)
        var held := wash.duplicate() as StyleBoxFlat
        held.bg_color = Color(ThemeScript.GREEN.r, ThemeScript.GREEN.g, ThemeScript.GREEN.b, 0.16)
        if on:
                rest.bg_color = wash.bg_color
        button.add_theme_stylebox_override("normal", rest)
        button.add_theme_stylebox_override("hover", held if not on else wash)
        button.add_theme_stylebox_override("pressed", held)
        button.add_theme_stylebox_override("focus", wash)

## The face, chosen where it is read: the card re-says its words in the new
## hand at once, the deck is stamped so every device the deck reaches reads
## the same hand, and the page folds itself away -- the choice is made, and
## there is nothing more to ask.
func _choose_face(key: String) -> void:
        if key != ThemeScript.ayah_face_key():
                ThemeScript.set_ayah_face(key)
                _resay_card()
                ayah_font_chosen.emit(key)
        var popup := get_node_or_null("FontPopup")
        if popup != null:
                popup.visible = false
        _redress_face_rows(key)

## The standing face said again on the rows, without rebuilding the page.
func _redress_face_rows(chosen: String) -> void:
        var rows: VBoxContainer = get_node_or_null("FontPopup/Sheet/Pad/Column/Faces")
        if rows == null:
                return
        for child in rows.get_children():
                var button := child as Button
                if button == null:
                        continue
                var key := str(button.get_meta("choice", ""))
                _dress_face_row(button, key == chosen)
                var name: Label = button.get_node_or_null("Pad/Row/Name")
                if name != null:
                        ThemeScript.dress(name, 13, ThemeScript.GREEN_DEEP if key == chosen else ThemeScript.INK, key == chosen)

## The card says its words again, in whatever hand it now wears -- on
## whichever side was standing when the hand was changed. A finished
## session's summary has no words to re-say and keeps its place.
func _resay_card() -> void:
        if _index >= _cards.size():
                return
        if get_node_or_null(PANEL + "/Padding/Summary") != null:
                return
        var card: CardScript = _cards[_index]
        if _revealed:
                _view.show_text(card.back, card.folder, false, _reference_of(card), true)
        else:
                _view.show_text(card.front, card.folder, true)

## The two pages of the header's corner take turns: opening one closes the
## other, the way one question at a time is asked.
func _toggle_font_popup() -> void:
        var popup := get_node_or_null("FontPopup")
        if popup == null:
                return
        var volume_page := get_node_or_null("VolumePopup")
        if volume_page != null:
                volume_page.visible = false
        popup.visible = not popup.visible
        if popup.visible:
                _redress_face_rows(ThemeScript.ayah_face_key())
                ThemeScript.place_popover(popup, get_node("Margin/Column/TopBar/Right/Pair/Font"))
                ThemeScript.settle_in(popup, 0.0, 0.16)

func _toggle_volume() -> void:
        var font_page := get_node_or_null("FontPopup")
        if font_page != null:
                font_page.visible = false
        _rig.toggle()

func _input(event: InputEvent) -> void:
        if not visible:
                return
        # The editor owns the page while it is open: the session's own keys
        # (Space to reveal, 1-4 to answer) would otherwise reach into its
        # fields, and a reader typing a space would answer a card instead.
        if get_node_or_null("Editor") != null:
                return
        # A popover closes the way popovers do: any press outside it. The
        # coin that opened it is outside it too -- its own press will close
        # it, so the press is left alone here rather than closed and reopened
        # in the same breath.
        if event is InputEventMouseButton and event.pressed:
                var press := event as InputEventMouseButton
                for page_name in ["VolumePopup", "FontPopup"]:
                        var page: Control = get_node_or_null(page_name)
                        if page == null or not page.visible:
                                continue
                        var coin_name := "Volume" if page_name == "VolumePopup" else "Font"
                        var coin: Button = get_node_or_null(
                                "Margin/Column/TopBar/Right/Pair/" + coin_name
                        )
                        var inside_coin := coin != null and coin.get_global_rect().has_point(press.position)
                        if not inside_coin and not page.get_global_rect().has_point(press.position):
                                page.visible = false
        if event is InputEventKey and event.pressed and not event.echo:
                match event.keycode:
                        KEY_ESCAPE:
                                closed.emit()
                                get_viewport().set_input_as_handled()
                        KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
                                # Consume the key here: the focused answer button
                                # must not also fire on the same press.
                                if not _revealed:
                                        _reveal()
                                        get_viewport().set_input_as_handled()
                                elif _options.size() >= 3 and not _busy:
                                        _answer("good")
                                        get_viewport().set_input_as_handled()
                        KEY_S:
                                # The quiet way out, on the question side only.
                                if not _revealed and not _busy:
                                        _put_back()
                                        get_viewport().set_input_as_handled()
                        KEY_1:
                                if _revealed and not _busy:
                                        _answer("again")
                                        get_viewport().set_input_as_handled()
                        KEY_2:
                                if _revealed and not _busy:
                                        _answer("hard")
                                        get_viewport().set_input_as_handled()
                        KEY_3:
                                if _revealed and not _busy:
                                        _answer("good")
                                        get_viewport().set_input_as_handled()
                        KEY_4:
                                if _revealed and not _busy:
                                        _answer("easy")
                                        get_viewport().set_input_as_handled()


## The phone's back key closes what stands over the page before it closes
## the page: the editor first, then a popover the coin raised, and only
## then the session itself, the same order the keys above leave in.
func request_back() -> bool:
        var editor := get_node_or_null("Editor") as CardEditorScript
        if editor != null:
                return editor.request_back()
        for page_name in ["VolumePopup", "FontPopup"]:
                var popup := get_node_or_null(page_name)
                if popup != null and popup.visible:
                        popup.visible = false
                        return true
        closed.emit()
        return true
