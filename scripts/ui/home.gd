class_name HomeScreen
extends Control
const ThemeScript := preload("res://scripts/ui/theme.gd")
const DeckScript := preload("res://scripts/data/deck.gd")
const SchedulerScript := preload("res://scripts/data/scheduler.gd")
const MarkdownScript := preload("res://scripts/ui/markdown.gd")
const I18nScript := preload("res://scripts/ui/i18n.gd")

## The only front door: the deck's name, what is waiting today, and the one
## button that matters. The page's whole second subject -- the deck's other
## life on GitHub, and the app's own settings -- lives with the library's
## door in a dock at the page's foot: three named places a thumb knows how
## to find, the sync one saying its state in its tone and its own tooltip.
## The page itself is dressed in a still lattice of stars, the way a book's
## margins are.

signal study_pressed
signal sync_pressed
signal settings_pressed
signal update_pressed
signal browse_pressed
## The day's offer is spent, but the reader asked for one more new card
## anyway: a session of exactly one card, opened from the caught-up page.
signal extra_new_pressed

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
## the top margin, the update coin and the dock's own footing ride below
## whatever the display keeps for itself, and the page's ground ends a
## breath above the dock, never flowing under the bar that stands over it.
## The dock itself answers the window's width: whole on a phone, measured
## and centred on a desk. Runs on every resize; reads nothing but the
## window's own width and the display's own safe area.
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
        # The dock rides the page's foot above whatever the display keeps
        # for itself, and the page's own ground ends a breath above it --
        # the column never flows under the bar that stands over it. The
        # bar's height is asked of the bar itself, which knows its words.
        var dock: PanelContainer = get_node("Dock")
        var dock_pad: MarginContainer = get_node("Dock/Pad")
        dock_pad.add_theme_constant_override("margin_bottom", int(8.0 + ThemeScript.bottom_inset()))
        var dock_h := dock.get_combined_minimum_size().y
        var dock_w := minf(520.0, size.x)
        dock.anchor_left = 0.5
        dock.anchor_right = 0.5
        dock.offset_left = -dock_w / 2.0
        dock.offset_right = dock_w / 2.0
        dock.anchor_top = 1.0
        dock.anchor_bottom = 1.0
        dock.offset_top = -dock_h
        dock.offset_bottom = 0.0
        margin.add_theme_constant_override("margin_bottom", int(dock_h + 14.0 + ThemeScript.bottom_inset()))
        # The deck card's own padding leans in with the page: the phone's
        # card gives its words the room the tighter margins took. Its width
        # is said here too, so the middle box keeps a presence on the page
        # whatever its words cost -- never wider than the window holds.
        var deck: PanelContainer = get_node("Margin/Column/DeckCard")
        var pad: MarginContainer = get_node("Margin/Column/DeckCard/Pad")
        pad.add_theme_constant_override("margin_left", 20 if narrow else 30)
        pad.add_theme_constant_override("margin_right", 20 if narrow else 30)
        deck.custom_minimum_size = Vector2(minf(324.0, size.x - 2.0 * side), 138.0)
        # The one coin left -- the gold way a waiting version arrives --
        # keeps the corner's own ride below whatever the display keeps for
        # itself, alone there now that sync and settings are named places
        # in the dock.
        var update_coin: Button = get_node("UpdateCoin")
        update_coin.offset_top = 22.0 + inset
        update_coin.offset_bottom = 70.0 + inset
        var avail := size.x - 2.0 * side  # the margin on each side
        var gap := 12.0
        var pill_w := clampf((avail - 2.0 * gap) / 3.0, 64.0, 116.0)
        for name in ["Due", "New", "Learned"]:
                var pill: PanelContainer = get_node("Margin/Column/Stats/" + name)
                pill.custom_minimum_size = Vector2(pill_w, 74)
        var study: Button = get_node("Margin/Column/Study")
        study.custom_minimum_size = Vector2(minf(340.0, avail), 60.0)
        var extra: Button = get_node("Margin/Column/ExtraNew")
        extra.custom_minimum_size = Vector2(minf(340.0, avail), 50.0)

func setup(deck: DeckScript, counts: Dictionary, sync_line: String, sync_state := "off") -> void:
        if not is_node_ready():
                await ready
        _deck_of_last_setup = deck
        var title: Label = get_node("Margin/Column/DeckCard/Pad/Box/Title")
        title.text = deck.name

        _apply_counts(counts)
        _set_sync_state(sync_line, sync_state)
        _say_next_reference()

## The three numbers and the one button, said once: setup() and refresh()
## both end here, so the page can never disagree with itself between the
## two doors it is reached through. The whole holding is no longer said here
## at all: the pills below own the day's numbers, and the card between owns
## the day's one news -- the next card -- so nothing is said twice and the
## box the reader once found lonely is gone with the figure that filled it.
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
        var extra: Button = get_node("Margin/Column/ExtraNew")
        if counts["due"] + counts["new"] == 0:
                study.text = I18nScript.t("All caught up")
                study.disabled = true
                # A day with nothing waiting is an answer, not an absence: the
                # button rests in the day's own green, warm and settled,
                # instead of the engine's grey that reads as broken.
                var rest := ThemeScript.button_stylebox(ThemeScript.GREEN_SOFT)
                rest.border_color = Color(ThemeScript.GREEN.r, ThemeScript.GREEN.g, ThemeScript.GREEN.b, 0.35)
                rest.set_border_width_all(2)
                study.add_theme_stylebox_override("disabled", rest)
                study.add_theme_color_override("font_disabled_color", ThemeScript.GREEN_DEEP)
                # But a day with nothing waiting is not necessarily a deck
                # with nothing left: while an unseen card remains, one more
                # can be taken into a session now, and the offer stands
                # between the day's rest and the library's door.
                extra.visible = _next_fresh_card() != null
        else:
                study.text = I18nScript.t("Study") if counts["due"] > 0 else I18nScript.t("Learn new cards")
                study.disabled = false
                extra.visible = false

## The dock's sync door says the state before any words do: green when the
## deck and the repo last agreed, gold while answers still wait to travel
## or the promise is unkept, a turning green mark while the exchange is
## actually happening, red when it could not finish, and a quiet ink one
## when there is no connection at all. The state is worn twice at once --
## the wash the item's own tone gives the door, and the tint the mark and
## its word share -- and the words live in the item's own tooltip: the
## dock tells the whole story, and the page above it belongs to the day,
## not to the plumbing. The mark alone is the door's one figure; nothing
## else stands beside it.
func _set_sync_state(text: String, state: String) -> void:
        var item: Button = get_node("Dock/Pad/Row/Sync")
        var mark: ThemeScript.SyncMark = item.get_node("Stack/Icon/Mark/SyncMark")
        var label: Label = item.get_node("Stack/Text")
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
        ThemeScript.apply_mark_styles(item, ThemeScript.dock_button_styles(tone))
        mark.color = mark_tone
        mark.set_working(state == "syncing")
        mark.queue_redraw()
        label.add_theme_color_override("font_color", mark_tone)
        item.tooltip_text = text


## The coin turns while a sync runs quietly under the page: the one honest
## thing between "you answered" and "it is safe on GitHub".
func set_syncing() -> void:
        _set_sync_state(I18nScript.t("Syncing…"), "syncing")


## The one line that answers "what am I about to study?": the next card's
## own heading, read from its front, dressed for its script. Said at setup
## and said again whenever the numbers move, because the card the numbers
## name moves with them -- a card that comes due while the page is already
## open changes the day's own news.
func _say_next_reference() -> void:
        var next_up: Label = get_node("Margin/Column/DeckCard/Pad/Box/NextUp")
        var eyebrow: Label = get_node("Margin/Column/DeckCard/Pad/Box/Eyebrow")
        var reference := _next_reference()
        next_up.visible = not reference.is_empty()
        eyebrow.visible = not reference.is_empty()
        if not reference.is_empty():
                next_up.text = reference
                var script := ThemeScript.reference_script(reference)
                next_up.add_theme_font_override("font", ThemeScript.font_for(script, ThemeScript.BODY))
                next_up.add_theme_font_size_override("font_size", ThemeScript.fs(_size_for(script)))
                next_up.add_theme_color_override("font_color", ThemeScript.GREEN_DEEP)


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
        return MarkdownScript.first_plain_line(queue[0].front)

func _size_for(script: String) -> int:
        # The reference is the card's hero now, the figure the eye is brought
        # to the middle box to read: the mushaf cut keeps its own generous
        # measure, and the other scripts stand a breath above the body they
        # left, so the day's news outweighs the name above it whatever
        # script the reference is written in.
        if script == "arabic":
                return 30
        if script == "persian":
                return 22
        return 16

## The first card a larger offer would bring, read past the day's cap by
## the scheduler's own rule: new, not suspended, not waiting out a defer.
## Null when the deck holds nothing more to take -- the offer then has
## nothing to stand on and the button that asks for it stays away.
func _next_fresh_card():
        if _deck_of_last_setup == null:
                return null
        return SchedulerScript.first_fresh(
                _deck_of_last_setup, int(Time.get_unix_time_from_system())
        )

func _build() -> void:
        set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        # A page whose tongue reads from the right is laid out from the
        # right: the pills run the way the words do, and the dock's doors
        # stand in the reading's own order -- the library first at the
        # reading's start. The root says it once and every container below
        # inherits it, the way every other page in the app does; a page
        # said again in another tongue says its own direction again.
        layout_direction = (
                Control.LAYOUT_DIRECTION_RTL if I18nScript.is_rtl()
                else Control.LAYOUT_DIRECTION_LTR
        )
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
        column.add_child(_extra_new_button())

        # The dock and the sleeping coin go on last, not first: children
        # added later sit above earlier ones in both drawing and
        # hit-testing, and a full-rect container added after them was
        # covering the corner, so the click that opened a coin landed on
        # the page instead. On top is where floating controls belong.
        add_child(_dock())
        # The one coin sleeps until the page hears that a newer version
        # waits outside; then it is the gold way to take it, alone in the
        # corner where the app's gold has always arrived.
        var update := _corner_coin(
                "UpdateCoin",
                Vector2(-76.0, -28.0),
                ThemeScript.UpdateMark.new(),
                I18nScript.t("Install the new version"),
                func() -> void: update_pressed.emit()
        )
        update.visible = false
        add_child(update)

## One corner coin: a roundel in its own tone, a drawn mark centred in it,
## the same press the whole app knows. The corner's one remaining tenant
## is the update coin; sync and settings live in the dock, named in words.
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
        if coin_name == "UpdateCoin":
                mark.name = "UpdateMark"
        var center := CenterContainer.new()
        center.name = "Mark"
        center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        center.mouse_filter = Control.MOUSE_FILTER_IGNORE
        mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
        center.add_child(mark)
        coin.add_child(center)
        coin.tooltip_text = tooltip
        # The coin starts dressed in the app's green; a waiting version wakes
        # it gold-breathing from its own mark.
        ThemeScript.apply_mark_styles(coin, ThemeScript.mark_button_styles(ThemeScript.GREEN, true))
        ThemeScript.pressable(coin)
        coin.pressed.connect(on_press)
        return coin

## The app's name in the script it was given, and under it the ornament
## a title page wears: the Arabic reads as the name it was given, and the
## gold star between two short rules keeps the wordmark from floating off
## the page.
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
        arabic.add_theme_font_size_override("font_size", ThemeScript.fs(17))
        arabic.add_theme_color_override("font_color", ThemeScript.GOLD_DEEP)
        stack.add_child(arabic)
        var ornament := ThemeScript.OrnamentMark.new()
        ornament.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        stack.add_child(ornament)
        row.add_child(stack)
        return row

func _deck_card() -> Control:
        var card := PanelContainer.new()
        card.name = "DeckCard"
        card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        # The page's own margins: every other card in the app pads its
        # content; this one was letting its widest line touch the frame.
        # Its height answers its words (never below this breath), and its
        # width is said by the page's own layout, which knows the window.
        card.custom_minimum_size = Vector2(0, 138)
        card.add_theme_stylebox_override("panel", ThemeScript.card_stylebox())
        var pad := MarginContainer.new()
        pad.name = "Pad"
        pad.add_theme_constant_override("margin_left", 30)
        pad.add_theme_constant_override("margin_right", 30)
        pad.add_theme_constant_override("margin_top", 18)
        pad.add_theme_constant_override("margin_bottom", 18)
        card.add_child(pad)
        var box := VBoxContainer.new()
        box.name = "Box"
        box.alignment = BoxContainer.ALIGNMENT_CENTER
        box.add_theme_constant_override("separation", 9)
        pad.add_child(box)

        # The deck's name opens the card, calm rather than shouting: the
        # name is the page's own furniture, read daily and rarely hunted for,
        # so it stands at one quiet measure while the card's hero -- the
        # day's own news -- takes the weight below it.
        var title := Label.new()
        title.name = "Title"
        title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        ThemeScript.dress(title, 22, ThemeScript.INK, true)
        box.add_child(title)

        # The deck's own figure, where another card would hang a hairline:
        # the wordmark's star between its rules, standing as the card's
        # own ornament between the name and the day's news.
        var ornament := ThemeScript.OrnamentMark.new()
        ornament.name = "Ornament"
        ornament.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        box.add_child(ornament)

        # The card's lower half is the day's: an eyebrow that says what is
        # coming, and the reference itself in its own script, the figure the
        # eye is brought to the card to read.
        var eyebrow := Label.new()
        eyebrow.name = "Eyebrow"
        eyebrow.text = I18nScript.t("NEXT UP")
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
        name.text = I18nScript.t(title)
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

func _study_button() -> Control:
        var button := ThemeScript.primary_button(I18nScript.t("Study"), 60)
        button.name = "Study"
        button.custom_minimum_size = Vector2(340, 60)
        button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        button.pressed.connect(func() -> void: study_pressed.emit())
        return button

## The page's own foot: a bar of the card's white riding the bottom edge,
## carrying the app's three standing doors -- the library, the sync, the
## settings -- each a mark above its own word, so no door is ever a
## mystery icon again. The dock is furniture rather than a button: one
## surface, three places on it, a thumb's reach from everywhere the page's
## own work happens.
func _dock() -> Control:
        var dock := PanelContainer.new()
        dock.name = "Dock"
        dock.add_theme_stylebox_override("panel", ThemeScript.dock_stylebox())
        var pad := MarginContainer.new()
        pad.name = "Pad"
        pad.add_theme_constant_override("margin_left", 10)
        pad.add_theme_constant_override("margin_right", 10)
        pad.add_theme_constant_override("margin_top", 8)
        pad.add_theme_constant_override("margin_bottom", 8)
        dock.add_child(pad)
        var row := HBoxContainer.new()
        row.name = "Row"
        row.add_theme_constant_override("separation", 4)
        pad.add_child(row)
        # The reading's own order: the library at the reading's start, then
        # the sync, then the settings -- and in a right-reading tongue the
        # row inherits its page's turned-around direction, so the library
        # still stands first where the reading begins.
        row.add_child(_dock_item(
                "Browse",
                ThemeScript.BookMark.new(ThemeScript.INK_SOFT),
                I18nScript.t("Library"),
                I18nScript.t("Read the whole deck, card by card"),
                ThemeScript.INK_SOFT,
                func() -> void: browse_pressed.emit()
        ))
        row.add_child(_dock_item(
                "Sync",
                ThemeScript.SyncMark.new(ThemeScript.INK_SOFT),
                I18nScript.t("Sync"),
                I18nScript.t("Not connected"),
                ThemeScript.INK,
                func() -> void: sync_pressed.emit()
        ))
        row.add_child(_dock_item(
                "Settings",
                ThemeScript.SlidersMark.new(ThemeScript.GOLD_DEEP),
                I18nScript.t("Settings"),
                I18nScript.t("Settings"),
                ThemeScript.GOLD,
                func() -> void: settings_pressed.emit()
        ))
        return dock

## One place on the dock: a mark above its own word, both in the door's
## own tone, a wash of the same tone while visited. The word is half the
## door -- a mark alone was a riddle in the corner, and the dock's whole
## reason is that no door asks to be guessed again.
func _dock_item(item_name: String, mark: Control, label_text: String, tooltip: String, tone: Color, on_press: Callable) -> Button:
        var item := Button.new()
        item.name = item_name
        item.custom_minimum_size = Vector2(0, 52)
        item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        item.tooltip_text = tooltip
        ThemeScript.apply_mark_styles(item, ThemeScript.dock_button_styles(tone))
        ThemeScript.pressable(item)
        item.pressed.connect(on_press)
        var stack := VBoxContainer.new()
        stack.name = "Stack"
        stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
        stack.alignment = BoxContainer.ALIGNMENT_CENTER
        stack.add_theme_constant_override("separation", 5)
        item.add_child(stack)
        stack.add_child(_dock_icon(item_name, mark))
        var label := Label.new()
        label.name = "Text"
        label.text = label_text
        label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        ThemeScript.dress(label, ThemeScript.CAPTION, mark.get("color"), true)
        stack.add_child(label)
        return item

## The mark's own ground: a quiet square the mark stands centred in, the
## same height for all three doors so their marks share one line.
func _dock_icon(item_name: String, mark: Control) -> Control:
        var icon := Control.new()
        icon.name = "Icon"
        icon.custom_minimum_size = Vector2(26, 26)
        icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
        var center := CenterContainer.new()
        center.name = "Mark"
        center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        center.mouse_filter = Control.MOUSE_FILTER_IGNORE
        mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
        mark.name = item_name + "Mark"
        center.add_child(mark)
        icon.add_child(center)
        return icon

## The day is done and the deck is not: one more new card, offered where
## the day's own button rests, the page's last word before the dock. A
## reader whose pace is spent -- or set to reviews alone -- can still take
## one fresh card into a session; the offer stands only while an unseen
## card remains, and never offers back a card the reader deferred or
## suspended today.
func _extra_new_button() -> Control:
        var button := ThemeScript.ghost_button(
                I18nScript.t("Learn one more card"), ThemeScript.GREEN, 50
        )
        button.name = "ExtraNew"
        button.custom_minimum_size = Vector2(340, 50)
        button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        button.tooltip_text = I18nScript.t("One more new card, beyond the day's own offer")
        button.visible = false
        button.pressed.connect(func() -> void: extra_new_pressed.emit())
        return button

## The three numbers and the day's news, said again without the page being
## rebuilt: a card that came due while the reader sat on the page, a
## session that ended, a sync that merged another device's study -- the
## numbers moved, and the card they name moves with them.
func refresh(counts: Dictionary) -> void:
        _apply_counts(counts)
        _say_next_reference()


## The counts the page is saying right now -- the due watch's own
## comparison, so the page is only re-said when its numbers truly moved.
func current_counts() -> Dictionary:
        return _counts.duplicate()

## A browser session can outlive the version it is running. When the engine
## reports a newer one waiting outside, Home offers it twice over: a gold
## coin alone in the corner, breathing until it is taken, and a quiet line
## under the day's own button that says what the coin is for -- never
## inside a study session. The page does the swapping; the buttons only
## ask.
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
        line.text = I18nScript.t("A new version is ready — the gold button up top installs it.")
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
## from anywhere. When the day is done, the same key takes the one card
## still on offer -- the page's answer to itself, not a dead key.
func _unhandled_input(event: InputEvent) -> void:
        if not visible:
                return
        if event is InputEventKey and event.pressed and not event.echo:
                if event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
                        var study: Button = get_node("Margin/Column/Study")
                        if not study.disabled:
                                study_pressed.emit()
                                get_viewport().set_input_as_handled()
                        else:
                                var extra: Button = get_node("Margin/Column/ExtraNew")
                                if extra.visible:
                                        extra_new_pressed.emit()
                                        get_viewport().set_input_as_handled()
