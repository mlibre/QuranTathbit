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
signal update_pressed
signal browse_pressed

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
        for coin_name in ["SyncCoin", "SettingsCorner", "UpdateCoin"]:
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
        var browse: Button = get_node("Margin/Column/Browse")
        browse.custom_minimum_size = Vector2(minf(340.0, avail), 50.0)
        _fit_sync_line()

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
                # A day with nothing waiting is an answer, not an absence: the
                # button rests in the day's own green, warm and settled,
                # instead of the engine's grey that reads as broken.
                var rest := ThemeScript.button_stylebox(ThemeScript.GREEN_SOFT)
                rest.border_color = Color(ThemeScript.GREEN.r, ThemeScript.GREEN.g, ThemeScript.GREEN.b, 0.35)
                rest.set_border_width_all(2)
                study.add_theme_stylebox_override("disabled", rest)
                study.add_theme_color_override("font_disabled_color", ThemeScript.GREEN_DEEP)
        else:
                study.text = "Study" if counts["due"] > 0 else "Learn new cards"
                study.disabled = false

## The sync coin says the state before any words do: a green coin when the
## deck and the repo last agreed, a gold coin while answers still wait to
## travel or the promise is unkept, a turning green one while the exchange
## is actually happening, a red one when it could not finish, and a quiet
## ink one when there is no connection at all. The words ride under the
## day's button with a dot of the same tone, where a fingertip finds them
## as surely as a cursor finds a tooltip.
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
                "syncing":
                        tone = ThemeScript.GREEN
                        mark_tone = ThemeScript.GREEN_DEEP
                "error":
                        tone = ThemeScript.DANGER
                        mark_tone = ThemeScript.DANGER
        ThemeScript.apply_mark_styles(coin, ThemeScript.mark_button_styles(tone, true))
        mark.color = mark_tone
        mark.set_working(state == "syncing")
        mark.queue_redraw()
        coin.tooltip_text = text
        var row: HBoxContainer = get_node_or_null("Margin/Column/SyncLine/Row")
        if row != null:
                (row.get_node("Text") as Label).text = text
                (row.get_node("Dot") as ThemeScript.StatusDot).color = mark_tone
                _fit_sync_line()


## The coin turns and the line says so, while a sync runs quietly under
## the page: the one honest thing between "you answered" and "it is safe
## on GitHub".
func set_syncing() -> void:
        _set_sync_state("Syncing…", "syncing")


## The next card's heading: the first line of its front, plain text. The
## scheduler's queue already knows which card is truly next -- due before new --
## so this is read from the queue, not guessed from the deck's order.
func _next_reference() -> String:
        if _counts["due"] + _counts["new"] == 0:
                return ""
        # The queue is filled with the day's own offer of new cards -- the
        # same number the counts carried in -- so the next card shown is the
        # next card a session would actually bring.
        var queue: Array = SchedulerScript.queue(
                _deck_of_last_setup,
                int(Time.get_unix_time_from_system()),
                int(_counts.get("new_per_day", SchedulerScript.NEW_PER_DAY))
        )
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
        column.add_child(_browse_button())
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
        # The third coin sleeps until the page hears that a newer version
        # waits outside; then it is the gold way to take it, beside its kin,
        # where the eye already knows the app's corners live.
        var update := _corner_coin(
                "UpdateCoin",
                Vector2(-196.0, -148.0),
                ThemeScript.UpdateMark.new(),
                "Install the new version",
                func() -> void: update_pressed.emit()
        )
        update.visible = false
        add_child(update)

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
        elif coin_name == "UpdateCoin":
                mark.name = "UpdateMark"
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
        pill.add_theme_stylebox_override("panel", ThemeScript.pill_stylebox(_pill_bg(key), _pill_fg(key)))
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
## stands on the page itself -- a dot of the state's own tone, the words
## beside it, quiet, small, and there for whichever kind of hand asks.
## The dot and the words are one centered figure: the row they share
## shrinks to what it holds and the page centers the pair, so the dot
## stands beside its own sentence instead of stranded at the margin.
func _sync_line() -> Control:
        var wrap := VBoxContainer.new()
        wrap.name = "SyncLine"
        var row := HBoxContainer.new()
        row.name = "Row"
        row.alignment = BoxContainer.ALIGNMENT_CENTER
        row.add_theme_constant_override("separation", 8)
        row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        var dot := ThemeScript.StatusDot.new(ThemeScript.INK_SOFT)
        dot.name = "Dot"
        dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        row.add_child(dot)
        var line := Label.new()
        line.name = "Text"
        line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        ThemeScript.dress(line, ThemeScript.CAPTION, ThemeScript.INK_SOFT)
        line.text = ""
        row.add_child(line)
        wrap.add_child(row)
        return wrap


## The sentence takes the width its words need, and no more than the page
## can hold: a long line wraps at the measure of the window rather than
## pushing its dot off the edge, and a short one keeps the pair centred.
func _fit_sync_line() -> void:
        var label: Label = get_node_or_null("Margin/Column/SyncLine/Row/Text")
        if label == null:
                return
        var font := ThemeScript.vazir(ThemeScript.CAPTION)
        var widest := 0.0
        for text_line in label.text.split("\n"):
                widest = maxf(
                        widest,
                        font.get_string_size(
                                text_line, HORIZONTAL_ALIGNMENT_LEFT, -1, ThemeScript.CAPTION
                        ).x
                )
        var avail := maxf(size.x - 120.0, 140.0)
        label.custom_minimum_size = Vector2(minf(widest, avail), 0.0)

func _study_button() -> Control:
        var button := ThemeScript.primary_button("Study", 60)
        button.name = "Study"
        button.custom_minimum_size = Vector2(340, 60)
        button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        button.pressed.connect(func() -> void: study_pressed.emit())
        return button

## The library's own door, under the day's work: the same width as the
## session it sits under, a thought rather than an errand -- the outline
## that says the deck is a book as well as a queue.
func _browse_button() -> Control:
        var button := ThemeScript.ghost_button("Browse the cards", ThemeScript.GREEN, 50)
        button.name = "Browse"
        button.custom_minimum_size = Vector2(340, 50)
        button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        button.tooltip_text = "Read the whole deck, card by card"
        button.pressed.connect(func() -> void: browse_pressed.emit())
        return button

func refresh(counts: Dictionary) -> void:
        _apply_counts(counts)

## A browser session can outlive the version it is running. When the engine
## reports a newer one waiting outside, Home offers it twice over: a gold
## coin in the corner beside its kin, breathing until it is taken, and a
## quiet line under the day's own button that says what the coin is for --
## never inside a study session. The page does the swapping; the buttons
## only ask.
func offer_update() -> void:
        var coin := get_node_or_null("UpdateCoin")
        if coin != null:
                coin.visible = true
                (coin.get_node("Mark/UpdateMark") as ThemeScript.UpdateMark).set_waiting(true)
        if get_node_or_null("Margin/Column/Update") != null:
                return
        var column: VBoxContainer = get_node("Margin/Column")
        var line := Label.new()
        line.name = "Update"
        line.text = "A new version is ready — the gold button up top installs it."
        line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        ThemeScript.dress(line, ThemeScript.CAPTION, ThemeScript.GOLD_DEEP)
        column.add_child(line)
        # One arrival, one settle: the line fades in where it stands, the way
        # a container's own children arrive, never fighting the layout.
        ThemeScript.settle_in(line, 0.12)

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
