class_name HomeScreen
extends Control
const ThemeScript := preload("res://scripts/ui/theme.gd")
const DeckScript := preload("res://scripts/data/deck.gd")
const SchedulerScript := preload("res://scripts/data/scheduler.gd")
const MarkdownScript := preload("res://scripts/ui/markdown.gd")

## The only front door: the deck's name, what is waiting today, and the one
## button that matters. The page's whole second subject -- the deck's other
## life on GitHub -- sits with settings in the top corners, as two coins;
## the page itself is dressed in a still lattice of stars, the way a book's
## margins are.

signal study_pressed
signal sync_pressed
signal settings_pressed

var _counts := {"due": 0, "new": 0, "learned": 0}
var _deck_of_last_setup: DeckScript

func _ready() -> void:
        _build()
        resized.connect(_layout)
        call_deferred("_layout")

## The page answers the window: pills and the study button grow to fill a
## phone and stop at their own measure on a desktop, so nothing ever
## overflows and nothing ever floats narrower than the content it holds.
## The margins answer it too -- a phone's page sits closer to its edges and
## gives its card more of what is left -- and everything answers the notch:
## the top margin and the corner coins ride below whatever the display
## keeps for itself. Runs on every resize; reads nothing but the window's
## own width and the display's own safe area.
func _layout() -> void:
        if size.x <= 0.0:
                return
        var inset := ThemeScript.top_inset()
        var narrow := size.x < ThemeScript.NARROW
        var side := 20.0 if narrow else 28.0
        var margin: MarginContainer = get_node("Margin")
        margin.add_theme_constant_override("margin_left", int(side))
        margin.add_theme_constant_override("margin_right", int(side))
        margin.add_theme_constant_override("margin_top", int(36.0 + inset))
        margin.add_theme_constant_override("margin_bottom", int(30.0 + ThemeScript.bottom_inset()))
        # The deck card's own padding leans in with the page: the phone's
        # card gives its words the room the tighter margins took.
        var pad: MarginContainer = get_node("Margin/Column/DeckCard/Pad")
        pad.add_theme_constant_override("margin_left", 20 if narrow else 30)
        pad.add_theme_constant_override("margin_right", 20 if narrow else 30)
        for coin_name in ["SyncCoin", "SettingsCorner"]:
                var coin: Button = get_node(coin_name)
                coin.offset_top = 22.0 + inset
                coin.offset_bottom = 70.0 + inset
        var avail := size.x - 2.0 * side  # the margin on each side
        var gap := 12.0
        var pill_w := clampf((avail - 2.0 * gap) / 3.0, 64.0, 116.0)
        for name in ["Due", "New", "Learned"]:
                var pill: PanelContainer = get_node("Margin/Column/Stats/" + name)
                pill.custom_minimum_size = Vector2(pill_w, 74)
        var study: Button = get_node("Margin/Column/Study")
        study.custom_minimum_size = Vector2(minf(340.0, avail), 60.0)

func setup(deck: DeckScript, counts: Dictionary, sync_line: String, sync_state := "off") -> void:
        if not is_node_ready():
                await ready
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

        _apply_counts(counts)
        _set_sync_state(sync_line, sync_state)

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

## The three numbers and the one button, said once: setup() and refresh()
## both end here, so the page can never disagree with itself between the
## two doors it is reached through.
func _apply_counts(counts: Dictionary) -> void:
        _counts = counts
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
        if counts["due"] + counts["new"] == 0:
                study.text = "All caught up"
                study.disabled = true
        else:
                study.text = "Study" if counts["due"] > 0 else "Learn new cards"
                study.disabled = false

## The sync coin says the state before any words do: a green coin when the
## deck and the repo last agreed, a gold coin while the promise is still
## unkept, a quiet ink one when there is no connection at all. The words
## ride in the tooltip, where the person who wants them will find them.
func _set_sync_state(text: String, state: String) -> void:
        var coin: Button = get_node("SyncCoin")
        var mark: ThemeScript.SyncMark = coin.get_node("Mark/SyncMark")
        var tone := ThemeScript.INK
        var mark_tone := ThemeScript.INK_SOFT
        match state:
                "synced":
                        tone = ThemeScript.GREEN
                        mark_tone = ThemeScript.GREEN_DEEP
                "pending":
                        tone = ThemeScript.GOLD
                        mark_tone = ThemeScript.GOLD_DEEP
        ThemeScript.apply_mark_styles(coin, ThemeScript.mark_button_styles(tone, true))
        mark.color = mark_tone
        mark.queue_redraw()
        coin.tooltip_text = text
        var line: Label = get_node_or_null("Margin/Column/SyncLine")
        if line != null:
                line.text = text


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
        column.add_child(_sync_line())

        # The corner coins go on last, not first: children added later sit
        # above earlier ones in both drawing and hit-testing, and a full-rect
        # container added after them was covering the corner, so the click
        # that opened a coin landed on the page instead. On top is where a
        # floating control belongs.
        add_child(_corner_coin(
                "SyncCoin",
                Vector2(-136.0, -88.0),
                ThemeScript.SyncMark.new(ThemeScript.INK_SOFT),
                "Not connected",
                func() -> void: sync_pressed.emit()
        ))
        add_child(_corner_coin(
                "SettingsCorner",
                Vector2(-76.0, -28.0),
                ThemeScript.SlidersMark.new(ThemeScript.GREEN_DEEP),
                "Settings",
                func() -> void: settings_pressed.emit()
        ))

## One corner coin: a roundel in its own tone, a drawn mark centred in it,
## the same press the whole app knows. Settings and sync differ only in
## their mark, their place and their message, so one hand builds both.
func _corner_coin(coin_name: String, x_range: Vector2, mark: Control, tooltip: String, on_press: Callable) -> Button:
        var coin := Button.new()
        coin.name = coin_name
        coin.anchor_left = 1.0
        coin.anchor_right = 1.0
        coin.anchor_top = 0.0
        coin.anchor_bottom = 0.0
        coin.offset_left = x_range.x
        coin.offset_right = x_range.y
        coin.offset_top = 22.0
        coin.offset_bottom = 70.0
        if coin_name == "SyncCoin":
                mark.name = "SyncMark"
        var center := CenterContainer.new()
        center.name = "Mark"
        center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        center.mouse_filter = Control.MOUSE_FILTER_IGNORE
        mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
        center.add_child(mark)
        coin.add_child(center)
        coin.tooltip_text = tooltip
        # Every coin starts dressed in the app's green; the sync coin's state
        # re-dresses it at setup().
        ThemeScript.apply_mark_styles(coin, ThemeScript.mark_button_styles(ThemeScript.GREEN, true))
        ThemeScript.pressable(coin)
        coin.pressed.connect(on_press)
        return coin

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
        ThemeScript.dress(label, 20, ThemeScript.GREEN_DEEP, true)
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
        ThemeScript.dress(title, 30, ThemeScript.INK, true)
        box.add_child(title)

        var caption := Label.new()
        caption.name = "Caption"
        caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        ThemeScript.dress(caption, ThemeScript.CAPTION, ThemeScript.INK_SOFT)
        box.add_child(caption)

        # The card's lower half is an editor's block: a hairline, an eyebrow
        # that says what is coming, and the reference itself in its own script.
        box.add_child(ThemeScript.hairline())

        var eyebrow := Label.new()
        eyebrow.name = "Eyebrow"
        eyebrow.text = "NEXT UP"
        eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        ThemeScript.dress(eyebrow, 12, ThemeScript.GOLD_DEEP, true)
        box.add_child(eyebrow)

        var next_up := Label.new()
        next_up.name = "NextUp"
        # The reference centres like the card's own title and caption: an
        # RTL line left-aligned inside a centred card reads as a smudge, not
        # a heading.
        next_up.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        next_up.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        ThemeScript.dress(next_up, ThemeScript.BODY, ThemeScript.GREEN_DEEP)
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
        ThemeScript.dress(value, 26, _pill_fg(key), true)
        box.add_child(value)

        var name := Label.new()
        name.text = title
        name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        ThemeScript.dress(name, 13, ThemeScript.INK, true)
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

## The sync coin's state in words, under the day's button: a tooltip says
## it to a mouse, but a fingertip has no hover to carry one, so the line
## stands on the page itself -- quiet, small, and there for whichever kind
## of hand asks.
func _sync_line() -> Control:
        var line := Label.new()
        line.name = "SyncLine"
        line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        ThemeScript.dress(line, ThemeScript.CAPTION, ThemeScript.INK_SOFT)
        line.text = ""
        return line

func _study_button() -> Control:
        var button := ThemeScript.primary_button("Study", 60)
        button.name = "Study"
        button.custom_minimum_size = Vector2(340, 60)
        button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        button.pressed.connect(func() -> void: study_pressed.emit())
        return button

func refresh(counts: Dictionary) -> void:
        _apply_counts(counts)

## A browser session can outlive the version it is running. When the engine
## reports a newer one waiting outside, Home offers it here -- under the day's
## own button, never inside a study session -- as one quiet line and the way
## to take it. The page does the swapping; the button only asks.
func offer_update(on_update: Callable) -> void:
        if get_node_or_null("Margin/Column/Update") != null:
                return
        var column: VBoxContainer = get_node("Margin/Column")
        var row := VBoxContainer.new()
        row.name = "Update"
        row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        row.add_theme_constant_override("separation", 8)
        var line := Label.new()
        line.name = "Line"
        line.text = "A new version is ready."
        line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        ThemeScript.dress(line, ThemeScript.CAPTION, ThemeScript.INK_SOFT)
        row.add_child(line)
        var take := ThemeScript.ghost_button("Update", ThemeScript.GREEN_DEEP, 44)
        take.name = "Take"
        take.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        take.pressed.connect(on_update)
        row.add_child(take)
        column.add_child(row)
        # One arrival, one settle: the row fades in where it stands, the way
        # a container's own children arrive, never fighting the layout.
        ThemeScript.settle_in(row, 0.12)

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
