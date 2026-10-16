class_name StudyScreen
extends Control
const ThemeScript := preload("res://scripts/ui/theme.gd")
const CardScript := preload("res://scripts/data/card.gd")
const SchedulerScript := preload("res://scripts/data/scheduler.gd")
const CardViewScript := preload("res://scripts/ui/card_view.gd")
const MarkdownScript := preload("res://scripts/ui/markdown.gd")

## A session: one card at a time, question first, then the answer, then how
## well it went. Nothing else is on screen while you study -- no counters
## arguing for attention, no menus to wander into. The four answers carry
## their own intervals, so the cost of each choice is plain before you make
## it, and each answer moves the card itself: a card that returns swells and
## fades, a card that moves on recedes, and the next one settles into place.
##
## The question rides along on the answer side, small and gold, so the verse
## is never read without knowing which one was asked for.

signal closed
signal answered(card: CardScript, button: String)

const PANEL := "Margin/Column/Surface/Fill/CardPanel"
const AGAIN_COLOR := Color("#B4553F")
const HARD_COLOR := Color("#96762A")
const GOOD_COLOR := Color("#1E6B52")
const EASY_COLOR := Color("#14513D")

var _cards: Array = []
var _index := 0
var _revealed := false
var _answered_count := 0
var _grade_counts := {}
var _started_ms := 0
var _busy := false
var _player: AudioStreamPlayer
var _view: CardViewScript
var _options: Array = []
var _bar_tween: Tween

func _ready() -> void:
        _player = AudioStreamPlayer.new()
        _player.name = "Player"
        add_child(_player)
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
        _grade_counts = {}
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
        hint.call("Space", "reveal")
        hint.call("1–4", "answer")
        hint.call("Esc", "close")
        return row

## Back the way the user came, the count in the middle, room on the right:
## the same bones every screen's header shares.
func _top_bar() -> Control:
        var bar: Dictionary = ThemeScript.top_bar("")
        var row: HBoxContainer = bar["row"]
        var back: Button = bar["back"]
        back.tooltip_text = "Back to home"
        back.pressed.connect(func() -> void: closed.emit())
        # The header's middle is this screen's count, not its name: the user
        # knows where they are; what they want to know is how far is left.
        var progress: Label = bar["title"]
        progress.name = "Progress"
        progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        progress.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        ThemeScript.dress(progress, 15, ThemeScript.INK_SOFT, true)
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

func _footer() -> Control:
        var row := CenterContainer.new()
        row.name = "Footer"

        var show := ThemeScript.primary_button("Show answer", 58)
        show.name = "ShowAnswer"
        show.custom_minimum_size = Vector2(320, 58)
        show.pressed.connect(_reveal)
        row.add_child(show)

        var done := ThemeScript.ghost_button("Done", ThemeScript.GREEN, 58)
        done.name = "Done"
        done.custom_minimum_size = Vector2(320, 58)
        done.visible = false
        done.pressed.connect(func() -> void: closed.emit())
        row.add_child(done)
        return row

func _layout() -> void:
        if size.x <= 0.0:
                return
        _layout_answers()
        # The card is a page, not a banner: it never runs wider than a
        # comfortable measure, whatever the window does with itself. Narrow
        # windows still get everything they can hold. The height is a floor,
        # not a fixed size -- a short reference gets a modest card, and a long
        # verse grows the page as far as the words need.
        var surface: ScrollContainer = get_node("Margin/Column/Surface")
        var fill: VBoxContainer = get_node("Margin/Column/Surface/Fill")
        var card: PanelContainer = get_node(PANEL)
        var width: float = minf(size.x - 48.0, ThemeScript.MEASURE)
        card.custom_minimum_size = Vector2(maxf(width, 280.0), 260.0)
        # The centre the question side needs: the filler is never shorter than
        # the surface, so a short card floats in the middle of the page.
        fill.custom_minimum_size.y = surface.size.y
        # The footer's two buttons share one width: capped at their own
        # measure, never wider than the window, so a phone holds them whole.
        var avail := minf(320.0, size.x - 48.0)
        (get_node("Margin/Column/Footer/ShowAnswer") as Button).custom_minimum_size = Vector2(avail, 58.0)
        (get_node("Margin/Column/Footer/Done") as Button).custom_minimum_size = Vector2(avail, 58.0)

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
        progress.text = "%d of %d" % [_index + 1, _cards.size()]
        _tween_bar(100.0 * float(_index) / float(_cards.size()))
        _view.show_text(card.front, card.folder, true)
        get_node("Margin/Column/Footer/ShowAnswer").visible = true
        get_node("Margin/Column/Footer/Done").visible = false
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
        get_node("Margin/Column/Footer/ShowAnswer").visible = false

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
## asked to recite from.
func _reference_of(card: CardScript) -> String:
        for line in card.front.split("\n"):
                var plain := MarkdownScript.plain(line).strip_edges()
                if not plain.is_empty():
                        return plain
        return ""

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
        word.text = str(option.button).capitalize()
        ThemeScript.dress(word, 14, grade, true)
        stack.add_child(word)
        var wait := Label.new()
        wait.name = "Wait"
        wait.text = str(option.interval)
        ThemeScript.dress(wait, 22, ThemeScript.INK, true)
        stack.add_child(wait)
        return button

func _answer(button: String) -> void:
        if _busy or _index >= _cards.size():
                return
        var card: CardScript = _cards[_index]
        answered.emit(card, button)
        _answered_count += 1
        _grade_counts[button] = int(_grade_counts.get(button, 0)) + 1
        _advance(str(button) == "again")

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
                ThemeScript.settle_in(get_node("Margin/Column/Footer/ShowAnswer"), 0.06)
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
                return "under a minute"
        if minutes == 1:
                return "1 minute"
        return "%d minutes" % minutes

## The grades of this session, one line, in their own colours -- a look back
## at how it went, in the order the buttons stand.
func _grades_line() -> String:
        var parts := PackedStringArray()
        var tones := {
                "again": "#B4553F",
                "hard": "#96762A",
                "good": "#1E6B52",
                "easy": "#14513D",
        }
        for key in ["again", "hard", "good", "easy"]:
                var count := int(_grade_counts.get(key, 0))
                if count > 0:
                        parts.append("[color=%s]%d %s[/color]" % [tones[key], count, key])
        if parts.is_empty():
                return ""
        return " · ".join(parts)

func _show_done() -> void:
        _tween_bar(100.0)
        var progress: Label = get_node("Margin/Column/TopBar/Progress")
        progress.text = "complete"
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
        title.text = "Session complete"
        title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        ThemeScript.dress(title, ThemeScript.TITLE, ThemeScript.GREEN_DEEP, true)
        summary.add_child(title)

        var body := Label.new()
        body.name = "Body"
        body.text = "You answered %d cards in %s. Everything is saved." % [_answered_count, _duration()]
        body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        ThemeScript.dress(body, ThemeScript.BODY, ThemeScript.INK)
        summary.add_child(body)

        var grades_line := _grades_line()
        if not grades_line.is_empty():
                var grades := RichTextLabel.new()
                grades.name = "Grades"
                grades.bbcode_enabled = true
                grades.fit_content = true
                grades.scroll_active = false
                # Fill the column and centre by alignment, the pattern every other
                # RichTextLabel in this app uses: a shrink-centred fit-content label
                # wraps itself to a column one character wide (RichTextLabel wraps by
                # default, unlike Label).
                grades.size_flags_horizontal = Control.SIZE_EXPAND_FILL
                grades.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
                grades.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
                grades.add_theme_font_override("normal_font", ThemeScript.vazir(ThemeScript.CAPTION))
                grades.add_theme_font_size_override("normal_font_size", ThemeScript.CAPTION)
                grades.text = "[center]" + grades_line + "[/center]"
                summary.add_child(grades)

        summary.add_child(ThemeScript.hairline())

        var rest := Label.new()
        rest.name = "Rest"
        rest.text = "Rest is part of learning."
        rest.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        ThemeScript.dress(rest, ThemeScript.CAPTION, ThemeScript.INK_SOFT)
        summary.add_child(rest)

        ThemeScript.stagger_in(summary, 0.09, 0.3)
        get_node("Margin/Column/Footer/ShowAnswer").visible = false
        get_node("Margin/Column/Footer/Done").visible = true

func _input(event: InputEvent) -> void:
        if not visible:
                return
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
