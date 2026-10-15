class_name HomeScreen
extends Control
const ThemeScript := preload("res://scripts/ui/theme.gd")
const DeckScript := preload("res://scripts/data/deck.gd")
const SchedulerScript := preload("res://scripts/data/scheduler.gd")
const MarkdownScript := preload("res://scripts/ui/markdown.gd")

## The only front door: the deck's name, what is waiting today, and the one
## button that matters. Settings lives in the corner, out of the way; sync
## waits at the bottom, small and unhurried; the page itself is dressed in a
## still lattice of stars, the way a book's margins are.

signal study_pressed
signal sync_pressed
signal settings_pressed

var _counts := {"due": 0, "new": 0, "learned": 0}
var _deck_of_last_setup: DeckScript

func _ready() -> void:
        _build()
        resized.connect(_layout)
        call_deferred("_layout")

## The page answers the window: pills, study and sync grow to fill a phone
## and stop at their own measure on a desktop, so nothing ever overflows
## and nothing ever floats narrower than the content it holds. Runs on
## every resize; reads nothing but the window's own width.
func _layout() -> void:
        if size.x <= 0.0:
                return
        var avail := size.x - 56.0  # the margin's 28 on each side
        var gap := 12.0
        var pill_w := clampf((avail - 2.0 * gap) / 3.0, 64.0, 116.0)
        for name in ["Due", "New", "Learned"]:
                var pill: PanelContainer = get_node("Margin/Column/Stats/" + name)
                pill.custom_minimum_size = Vector2(pill_w, 74)
        var study: Button = get_node("Margin/Column/Study")
        study.custom_minimum_size = Vector2(minf(340.0, avail), 60.0)
        var sync: Button = get_node("Margin/Column/Bottom/Buttons/Sync")
        sync.custom_minimum_size = Vector2(minf(180.0, avail), 48.0)

func setup(deck: DeckScript, counts: Dictionary, sync_line: String, connected: bool, sync_state := "off") -> void:
        if not is_node_ready():
                await ready
        _counts = counts
        _deck_of_last_setup = deck
        var title: Label = get_node("Margin/Column/DeckCard/Pad/Box/Title")
        var caption: Label = get_node("Margin/Column/DeckCard/Pad/Box/Caption")
        title.text = deck.name
        var waiting: int = counts["due"] + counts["new"]
        caption.text = (
                "%d cards · %d learned · nothing waiting" % [deck.cards.size(), counts["learned"]]
                if waiting == 0
                else "%d cards · %d learned · %d waiting" % [deck.cards.size(), counts["learned"], waiting]
        )

        var due_pill: Label = get_node("Margin/Column/Stats/Due/Box/Value")
        var new_pill: Label = get_node("Margin/Column/Stats/New/Box/Value")
        var learned_pill: Label = get_node("Margin/Column/Stats/Learned/Box/Value")
        # The numbers arrive rather than appear: 0 to their value over half a
        # second, easing out. A page that counts its own inventory in is a
        # page that was just thought about, not stamped.
        ThemeScript.count_up(due_pill, int(counts["due"]))
        ThemeScript.count_up(new_pill, int(counts["new"]))
        ThemeScript.count_up(learned_pill, int(counts["learned"]))

        var study: Button = get_node("Margin/Column/Study")
        if waiting == 0:
                study.text = "All caught up"
                study.disabled = true
        else:
                study.text = "Study" if counts["due"] > 0 else "Learn new cards"
                study.disabled = false

        var sync_label: Label = get_node("Margin/Column/Bottom/Buttons/Sync/SyncBox/Label")
        sync_label.text = "Sync" if connected else "Connect GitHub"
        _set_sync_line(sync_line, sync_state)

        # The one line that answers "what am I about to study?": the next
        # card's own heading, read from its front, dressed for its script.
        var next_up: Label = get_node("Margin/Column/DeckCard/Pad/Box/NextUp")
        var eyebrow: Label = get_node("Margin/Column/DeckCard/Pad/Box/Eyebrow")
        var reference := _next_reference()
        next_up.visible = not reference.is_empty()
        eyebrow.visible = not reference.is_empty()
        if not reference.is_empty():
                next_up.text = reference
                var script := ThemeScript.reference_script(reference)
                next_up.add_theme_font_override("font", ThemeScript.font_for(script, ThemeScript.BODY))
                next_up.add_theme_font_size_override("font_size", _size_for(script))
                next_up.add_theme_color_override("font_color", ThemeScript.GREEN_DEEP)

## The quiet row under everything: a dot that says the state before the words
## do -- filled green when the deck and the repo last agreed, gold when the
## promise is still unkept, hollow when there is no connection at all.
func _set_sync_line(text: String, state: String) -> void:
        var row: HBoxContainer = get_node("Margin/Column/Bottom/SyncLine")
        var label: Label = row.get_node("Text")
        label.text = text
        var dot: ThemeScript.StatusDot = row.get_node("Dot")
        match state:
                "synced":
                        dot.color = ThemeScript.GREEN
                        dot.filled = true
                "pending":
                        dot.color = ThemeScript.GOLD
                        dot.filled = true
                _:
                        dot.color = ThemeScript.INK
                        dot.filled = false
        dot.queue_redraw()
        # The line fades in where it stands: a fresh state is news, and news
        # arrives, it does not pop.
        ThemeScript.settle_in(row, 0.0, 0.2)


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
                return 30
        if script == "persian":
                return 21
        return ThemeScript.BODY

func _build() -> void:
        set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        add_child(ThemeScript.paper_backdrop())
        add_child(ThemeScript.paper_pattern())

        var margin := MarginContainer.new()
        margin.name = "Margin"
        margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        margin.add_theme_constant_override("margin_left", 28)
        margin.add_theme_constant_override("margin_right", 28)
        margin.add_theme_constant_override("margin_top", 36)
        margin.add_theme_constant_override("margin_bottom", 30)
        add_child(margin)

        var column := VBoxContainer.new()
        column.name = "Column"
        column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        column.alignment = BoxContainer.ALIGNMENT_CENTER
        column.add_theme_constant_override("separation", 18)
        margin.add_child(column)

        column.add_child(_wordmark())
        column.add_child(_deck_card())
        column.add_child(_stats())
        column.add_child(_study_button())
        column.add_child(_bottom_group())

        # The corner button goes on last, not first: children added later sit
        # above earlier ones in both drawing and hit-testing, and a full-rect
        # container added after it was covering the corner, so the click that
        # opened settings landed on the page instead. On top is where a
        # floating control belongs.
        add_child(_settings_corner())

## The deck's other life, gathered at the page's foot: the sync button and
## its state line belong to each other, so they stand together, a breath
## below the study flow they sit under -- close enough to read as one
## subject, far enough that no thumb finds them by accident.
func _bottom_group() -> Control:
        var group := VBoxContainer.new()
        group.name = "Bottom"
        group.alignment = BoxContainer.ALIGNMENT_CENTER
        group.add_theme_constant_override("separation", 8)
        group.add_child(_bottom_buttons())
        group.add_child(_sync_line_row())
        return group

## Settings in the corner, where a whole machine keeps it. The mark sits
## on a soft green coin at rest -- a button that is only three thin lines
## on bare paper reads as debris, and was missed by every first-time
## reader -- and the coin deepens when visited.
func _settings_corner() -> Button:
        var corner := Button.new()
        corner.name = "SettingsCorner"
        corner.anchor_left = 1.0
        corner.anchor_right = 1.0
        corner.anchor_top = 0.0
        corner.anchor_bottom = 0.0
        corner.offset_left = -76.0
        corner.offset_right = -28.0
        corner.offset_top = 22.0
        corner.offset_bottom = 70.0
        var rest := StyleBoxFlat.new()
        rest.bg_color = Color(ThemeScript.GREEN.r, ThemeScript.GREEN.g, ThemeScript.GREEN.b, 0.08)
        rest.set_corner_radius_all(24)
        var hover := StyleBoxFlat.new()
        hover.bg_color = Color(ThemeScript.GREEN.r, ThemeScript.GREEN.g, ThemeScript.GREEN.b, 0.16)
        hover.set_corner_radius_all(24)
        var focus := StyleBoxFlat.new()
        focus.bg_color = Color(ThemeScript.GREEN.r, ThemeScript.GREEN.g, ThemeScript.GREEN.b, 0.10)
        focus.border_color = Color(ThemeScript.GREEN.r, ThemeScript.GREEN.g, ThemeScript.GREEN.b, 0.55)
        focus.set_border_width_all(2)
        focus.set_corner_radius_all(24)
        corner.add_theme_stylebox_override("normal", rest)
        corner.add_theme_stylebox_override("hover", hover)
        corner.add_theme_stylebox_override("pressed", hover)
        corner.add_theme_stylebox_override("focus", focus)
        var center := CenterContainer.new()
        center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        center.mouse_filter = Control.MOUSE_FILTER_IGNORE
        var mark := ThemeScript.SlidersMark.new(ThemeScript.GREEN_DEEP)
        mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
        center.add_child(mark)
        corner.add_child(center)
        corner.tooltip_text = "Settings"
        ThemeScript.pressable(corner)
        corner.pressed.connect(func() -> void: settings_pressed.emit())
        return corner

## The app's name in both of its languages, and under it the ornament a
## title page wears: the Arabic reads as the name it was given, the Latin
## as the name it types, and the gold star between two short rules keeps
## the wordmark from floating off the page.
func _wordmark() -> Control:
        var row := CenterContainer.new()
        row.name = "Wordmark"
        row.custom_minimum_size = Vector2(0, 64)
        var stack := VBoxContainer.new()
        stack.alignment = BoxContainer.ALIGNMENT_CENTER
        stack.add_theme_constant_override("separation", 7)
        var arabic := Label.new()
        arabic.name = "Arabic"
        arabic.text = "تثبيت القرآن"
        arabic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        arabic.add_theme_font_override("font", ThemeScript.amiri(17))
        arabic.add_theme_font_size_override("font_size", 17)
        arabic.add_theme_color_override("font_color", ThemeScript.GOLD_DEEP)
        stack.add_child(arabic)
        var label := Label.new()
        label.name = "Latin"
        label.text = "QuranTathbit"
        label.add_theme_font_override("font", ThemeScript.vazir(20, true))
        label.add_theme_font_size_override("font_size", 20)
        label.add_theme_color_override("font_color", ThemeScript.GREEN_DEEP)
        stack.add_child(label)
        var ornament := ThemeScript.OrnamentMark.new()
        ornament.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        stack.add_child(ornament)
        row.add_child(stack)
        return row

func _deck_card() -> Control:
        var card := PanelContainer.new()
        card.name = "DeckCard"
        card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        card.custom_minimum_size = Vector2(0, 112)
        card.add_theme_stylebox_override("panel", ThemeScript.card_stylebox())
        # The page's own margins: every other card in the app pads its
        # content; this one was letting its widest line touch the frame.
        var pad := MarginContainer.new()
        pad.name = "Pad"
        pad.add_theme_constant_override("margin_left", 30)
        pad.add_theme_constant_override("margin_right", 30)
        pad.add_theme_constant_override("margin_top", 16)
        pad.add_theme_constant_override("margin_bottom", 16)
        card.add_child(pad)
        var box := VBoxContainer.new()
        box.name = "Box"
        box.alignment = BoxContainer.ALIGNMENT_CENTER
        box.add_theme_constant_override("separation", 6)
        pad.add_child(box)

        var title := Label.new()
        title.name = "Title"
        title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        # The deck's name is the hero of this card, but not of the screen:
        # one size below the app's own wordmark weight class.
        title.add_theme_font_override("font", ThemeScript.vazir(30, true))
        title.add_theme_font_size_override("font_size", 30)
        title.add_theme_color_override("font_color", ThemeScript.INK)
        box.add_child(title)

        var caption := Label.new()
        caption.name = "Caption"
        caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        caption.add_theme_font_override("font", ThemeScript.vazir(ThemeScript.BODY))
        caption.add_theme_font_size_override("font_size", ThemeScript.CAPTION)
        caption.add_theme_color_override("font_color", ThemeScript.INK_SOFT)
        box.add_child(caption)

        # The card's lower half is an editor's block: a hairline, an eyebrow
        # that says what is coming, and the reference itself in its own script.
        box.add_child(ThemeScript.hairline())

        var eyebrow := Label.new()
        eyebrow.name = "Eyebrow"
        eyebrow.text = "NEXT UP"
        eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        eyebrow.add_theme_font_override("font", ThemeScript.vazir(12, true))
        eyebrow.add_theme_font_size_override("font_size", 12)
        eyebrow.add_theme_color_override("font_color", ThemeScript.GOLD_DEEP)
        box.add_child(eyebrow)

        var next_up := Label.new()
        next_up.name = "NextUp"
        # The reference centres like the card's own title and caption: an
        # RTL line left-aligned inside a centred card reads as a smudge, not
        # a heading.
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
        name.add_theme_font_override("font", ThemeScript.vazir(13, true))
        name.add_theme_font_size_override("font_size", 13)
        name.add_theme_color_override("font_color", ThemeScript.INK)
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
                        return ThemeScript.GOLD_DEEP
                "new":
                        return ThemeScript.GREEN_DEEP
                _:
                        return ThemeScript.INK_SOFT

func _study_button() -> Control:
        var button := ThemeScript.primary_button("Study", 60)
        button.name = "Study"
        button.custom_minimum_size = Vector2(340, 60)
        button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        button.pressed.connect(func() -> void: study_pressed.emit())
        return button

## Sync on its own, with its own mark: the deck's other life, on GitHub,
## one small decision below the day's study.
func _bottom_buttons() -> Control:
        var row := HBoxContainer.new()
        row.name = "Buttons"
        row.alignment = BoxContainer.ALIGNMENT_CENTER
        row.add_theme_constant_override("separation", 12)

        var sync := Button.new()
        sync.name = "Sync"
        sync.custom_minimum_size = Vector2(170, 48)
        sync.add_theme_font_override("font", ThemeScript.vazir(ThemeScript.BODY))
        sync.add_theme_font_size_override("font_size", ThemeScript.BODY)
        sync.add_theme_color_override("font_color", ThemeScript.GREEN_DEEP)
        sync.add_theme_color_override("font_hover_color", ThemeScript.GREEN_DEEP)
        sync.add_theme_color_override("font_focus_color", ThemeScript.GREEN_DEEP)
        sync.add_theme_stylebox_override("normal", ThemeScript.outline_stylebox(ThemeScript.GREEN, 2, 24))
        var held := ThemeScript.outline_stylebox(ThemeScript.GREEN, 2, 24)
        held.bg_color = Color(ThemeScript.GREEN.r, ThemeScript.GREEN.g, ThemeScript.GREEN.b, 0.10)
        sync.add_theme_stylebox_override("hover", held)
        sync.add_theme_stylebox_override("pressed", held)
        sync.add_theme_stylebox_override("focus", ThemeScript.outline_stylebox(Color(ThemeScript.GREEN.r, ThemeScript.GREEN.g, ThemeScript.GREEN.b, 0.55)))
        ThemeScript.pressable(sync)
        var sync_box := HBoxContainer.new()
        sync_box.name = "SyncBox"
        sync_box.alignment = BoxContainer.ALIGNMENT_CENTER
        sync_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        sync_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
        sync_box.add_theme_constant_override("separation", 9)
        var mark := ThemeScript.SyncMark.new(ThemeScript.GREEN_DEEP)
        mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
        sync_box.add_child(mark)
        var sync_label := Label.new()
        sync_label.name = "Label"
        sync_label.text = "Sync"
        sync_label.add_theme_font_override("font", ThemeScript.vazir(ThemeScript.BODY))
        sync_label.add_theme_font_size_override("font_size", ThemeScript.BODY)
        sync_label.add_theme_color_override("font_color", ThemeScript.GREEN_DEEP)
        sync_box.add_child(sync_label)
        sync.add_child(sync_box)
        sync.tooltip_text = "Sync with GitHub"
        sync.pressed.connect(func() -> void: sync_pressed.emit())
        row.add_child(sync)
        return row

## The row itself: a drawn dot, a breath of space, the words. Built once;
## setup() only ever changes what they say and which of the three states the
## dot is in.
func _sync_line_row() -> Control:
        var row := HBoxContainer.new()
        row.name = "SyncLine"
        row.alignment = BoxContainer.ALIGNMENT_CENTER
        row.add_theme_constant_override("separation", 8)
        row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        var dot := ThemeScript.StatusDot.new(ThemeScript.INK_SOFT, false)
        dot.name = "Dot"
        row.add_child(dot)
        var text := Label.new()
        text.name = "Text"
        text.add_theme_font_override("font", ThemeScript.vazir(ThemeScript.CAPTION))
        text.add_theme_font_size_override("font_size", ThemeScript.CAPTION)
        text.add_theme_color_override("font_color", ThemeScript.INK_SOFT)
        row.add_child(text)
        return row

func refresh(counts: Dictionary) -> void:
        _counts = counts
        var due_pill: Label = get_node("Margin/Column/Stats/Due/Box/Value")
        var new_pill: Label = get_node("Margin/Column/Stats/New/Box/Value")
        var learned_pill: Label = get_node("Margin/Column/Stats/Learned/Box/Value")
        ThemeScript.count_up(due_pill, int(counts["due"]))
        ThemeScript.count_up(new_pill, int(counts["new"]))
        ThemeScript.count_up(learned_pill, int(counts["learned"]))
        var study: Button = get_node("Margin/Column/Study")
        study.disabled = counts["due"] + counts["new"] == 0
        study.text = "Study" if counts["due"] > 0 else ("Learn new cards" if counts["new"] > 0 else "Nothing due — come back tomorrow")

## Enter begins the day's study, the way Space reveals an answer: the home
## screen's one button is the whole screen, so the keyboard may press it
## from anywhere.
func _unhandled_input(event: InputEvent) -> void:
        if not visible:
                return
        if event is InputEventKey and event.pressed and not event.echo:
                if event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
                        var study: Button = get_node("Margin/Column/Study")
                        if not study.disabled:
                                study_pressed.emit()
                                get_viewport().set_input_as_handled()
