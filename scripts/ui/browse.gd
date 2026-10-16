class_name BrowseScreen
extends Control
const ThemeScript := preload("res://scripts/ui/theme.gd")
const DeckScript := preload("res://scripts/data/deck.gd")
const CardScript := preload("res://scripts/data/card.gd")
const CardViewScript := preload("res://scripts/ui/card_view.gd")
const MarkdownScript := preload("res://scripts/ui/markdown.gd")
const SchedulerScript := preload("res://scripts/data/scheduler.gd")

## The deck's own library: every card in its order, grouped by surah, each
## row a verse-reference with its standing beside it. A row opens in place --
## the verses, the translation, the recitation -- because a deck of scripture
## is also a book to read through, not only a box of questions to be asked.
## Nothing here schedules or edits: reading and listening are all it does,
## and the study session keeps its own work to itself.

signal closed
signal volume_changed(value: float)

var volume := 1.0  # the recitation's loudness here, as the last session left it
var _player: AudioStreamPlayer
var _open_row: Button = null

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

## The deck arrives with the volume the last session chose, so the first
## recitation heard here already speaks at the remembered loudness.
func setup(deck: DeckScript, p_volume: float) -> void:
        volume = p_volume
        _apply_volume(volume)
        if not is_node_ready():
                await ready
        var column: VBoxContainer = get_node("Margin/Column/Scroll/Wrap/Column")
        for child in column.get_children():
                column.remove_child(child)
                child.queue_free()
        _open_row = null
        var surah := ""
        for card in deck.cards:
                var reference := _reference_of(card)
                var card_surah := _surah_of(reference)
                if card_surah != surah:
                        surah = card_surah
                        column.add_child(_surah_header(surah, card.id))
                column.add_child(_entry(card, reference))
        var tail := Control.new()
        tail.name = "Tail"
        tail.custom_minimum_size = Vector2(0, 18)
        column.add_child(tail)
        ThemeScript.stagger_in(column, 0.02, 0.2)

func _build() -> void:
        set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        add_child(ThemeScript.paper_backdrop())
        add_child(ThemeScript.paper_pattern())
        var margin := MarginContainer.new()
        margin.name = "Margin"
        margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        margin.add_theme_constant_override("margin_left", 24)
        margin.add_theme_constant_override("margin_right", 24)
        margin.add_theme_constant_override("margin_top", 22)
        margin.add_theme_constant_override("margin_bottom", 26)
        add_child(margin)

        var column := VBoxContainer.new()
        column.name = "Column"
        column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        column.add_theme_constant_override("separation", 14)
        margin.add_child(column)

        column.add_child(_top_bar())
        column.add_child(_surface())
        add_child(_volume_popup())

func _top_bar() -> Control:
        var bar: Dictionary = ThemeScript.top_bar("Browse")
        var row: HBoxContainer = bar["row"]
        var back: Button = bar["back"]
        back.tooltip_text = "Back to home"
        back.pressed.connect(func() -> void: closed.emit())
        # The same corner every playing screen leaves for the question of
        # loudness: one quiet coin, the same page under it.
        var right: Control = bar["right"]
        var coin := Button.new()
        coin.name = "Volume"
        coin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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
        coin.tooltip_text = "Recitation volume"
        ThemeScript.pressable(coin)
        coin.pressed.connect(_toggle_volume_popup)
        right.add_child(coin)
        return row

func _surface() -> Control:
        var scroll := ScrollContainer.new()
        scroll.name = "Scroll"
        scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
        scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
        ThemeScript.style_scroll(scroll)
        var wrap := CenterContainer.new()
        wrap.name = "Wrap"
        wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        scroll.add_child(wrap)
        var column := VBoxContainer.new()
        column.name = "Column"
        column.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        column.add_theme_constant_override("separation", 8)
        wrap.add_child(column)
        return scroll

# --- the volume, the same page everywhere a recitation can be heard ------------------

func _volume_popup() -> Control:
        var popup := ThemeScript.VolumePopover.new()
        popup.changed.connect(_apply_volume)
        popup.committed.connect(func(v: float) -> void: volume_changed.emit(v))
        return popup


func _toggle_volume_popup() -> void:
        var popup: ThemeScript.VolumePopover = get_node_or_null("VolumePopup")
        if popup == null:
                return
        popup.visible = not popup.visible
        if popup.visible:
                popup.set_volume(volume)
                ThemeScript.settle_in(popup, 0.0, 0.16)


func _apply_volume(v: float) -> void:
        volume = clampf(v, 0.0, 1.0)
        _player.volume_db = linear_to_db(maxf(volume, 0.0001))
        var mark: ThemeScript.VolumeMark = get_node_or_null(
                "Margin/Column/TopBar/Right/Volume/Mark/VolumeMark"
        )
        if mark != null:
                mark.muted = volume <= 0.005
                mark.queue_redraw()

# --- the list ------------------------------------------------------------------------

## A surah's own running title: the name alone, gold, over a hairline -- the
## book's way of saying a new chapter has begun without a banner.
func _surah_header(surah: String, of_card: String) -> Control:
        var box := VBoxContainer.new()
        # One name per node: the engine renames a second "Header" into an
        # anonymous @VBoxContainer, and a test (or a finger) looking for the
        # chapter marks finds only the first.
        box.name = "Header" + of_card
        box.add_theme_constant_override("separation", 6)
        box.mouse_filter = Control.MOUSE_FILTER_IGNORE
        var label := Label.new()
        label.name = "Name"
        label.text = surah
        label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
        label.text_direction = TextDirection.TEXT_DIRECTION_AUTO
        label.add_theme_font_override("font", ThemeScript.font_for(
                ThemeScript.reference_script(surah), 15, true
        ))
        label.add_theme_font_size_override("font_size", 15)
        label.add_theme_color_override("font_color", ThemeScript.GOLD_DEEP)
        box.add_child(label)
        box.add_child(ThemeScript.hairline())
        return box

## One card in the library: its row, and the page that opens under it. The
## row says the reference and the card's standing; the page beneath carries
## the verses, the translation and the recitation, exactly as a session
## would show them.
func _entry(card: CardScript, reference: String) -> Control:
        var entry := VBoxContainer.new()
        entry.name = "Entry" + card.id
        entry.add_theme_constant_override("separation", 6)

        var row := Button.new()
        row.name = "Row"
        row.toggle_mode = false
        row.custom_minimum_size = Vector2(0, 56)
        row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        var rest := ThemeScript.soft_stylebox(ThemeScript.CARD, 14)
        rest.border_color = ThemeScript.LINE
        rest.set_border_width_all(1)
        rest.content_margin_left = 16
        rest.content_margin_right = 16
        rest.content_margin_top = 8
        rest.content_margin_bottom = 8
        var hover := rest.duplicate() as StyleBoxFlat
        hover.bg_color = Color(
                ThemeScript.GREEN.r, ThemeScript.GREEN.g, ThemeScript.GREEN.b, 0.05
        )
        hover.border_color = Color(
                ThemeScript.GREEN.r, ThemeScript.GREEN.g, ThemeScript.GREEN.b, 0.35
        )
        row.add_theme_stylebox_override("normal", rest)
        row.add_theme_stylebox_override("hover", hover)
        row.add_theme_stylebox_override("pressed", hover)
        row.add_theme_stylebox_override("focus", hover)
        row.add_theme_stylebox_override("disabled", rest)
        ThemeScript.pressable(row)
        row.pressed.connect(_toggle_row.bind(row, card, entry))

        var line := HBoxContainer.new()
        line.name = "Line"
        line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        line.mouse_filter = Control.MOUSE_FILTER_IGNORE
        line.add_theme_constant_override("separation", 12)
        row.add_child(line)

        var disclose := ThemeScript.DisclosureMark.new(ThemeScript.INK_SOFT)
        disclose.name = "Disclose"
        disclose.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        line.add_child(disclose)

        var ref_label := Label.new()
        ref_label.name = "Ref"
        ref_label.text = reference
        ref_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        ref_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        ref_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
        ref_label.text_direction = TextDirection.TEXT_DIRECTION_AUTO
        ref_label.clip_text = true
        var script := ThemeScript.reference_script(reference)
        ref_label.add_theme_font_override("font", ThemeScript.font_for(script, 18))
        ref_label.add_theme_font_size_override("font_size", 18)
        ref_label.add_theme_color_override("font_color", ThemeScript.INK)
        line.add_child(ref_label)

        var standing := _standing_of(card)
        var status := Label.new()
        status.name = "Status"
        status.text = str(standing["text"])
        status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
        ThemeScript.dress(status, 12, standing["color"], true)
        line.add_child(status)

        entry.add_child(row)

        var detail := VBoxContainer.new()
        detail.name = "Detail"
        detail.visible = false
        detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        var pad := MarginContainer.new()
        pad.name = "Pad"
        pad.add_theme_constant_override("margin_left", 14)
        pad.add_theme_constant_override("margin_right", 14)
        pad.add_theme_constant_override("margin_bottom", 10)
        detail.add_child(pad)
        entry.add_child(detail)
        return entry

## A row opens its card, and only one card is open at a time: the page it
## opens is read, then folded away by the next one a finger asks for.
func _toggle_row(row: Button, card: CardScript, entry: VBoxContainer) -> void:
        var detail: VBoxContainer = entry.get_node("Detail")
        if _open_row == row:
                _close_detail(detail)
                _set_row_open(row, false)
                _open_row = null
                return
        if _open_row != null and is_instance_valid(_open_row):
                _set_row_open(_open_row, false)
                var old: VBoxContainer = _open_row.get_parent().get_node("Detail")
                _close_detail(old)
        _set_row_open(row, true)
        for child in detail.get_child(0).get_children():
                detail.get_child(0).remove_child(child)
                child.queue_free()
        var view := CardViewScript.new(_player)
        view.name = "View"
        view.show_text(card.back, card.folder)
        detail.get_child(0).add_child(view)
        detail.visible = true
        ThemeScript.settle_in(detail, 0.0, 0.24)
        _open_row = row

func _set_row_open(row: Button, open: bool) -> void:
        var mark: ThemeScript.DisclosureMark = row.get_node("Line/Disclose")
        mark.open = open
        mark.color = ThemeScript.GREEN_DEEP if open else ThemeScript.INK_SOFT
        mark.queue_redraw()

func _close_detail(detail: VBoxContainer) -> void:
        for child in detail.get_child(0).get_children():
                detail.get_child(0).remove_child(child)
                child.queue_free()
        detail.visible = false

## The reference the card asks for: the first plain line of its front.
func _reference_of(card: CardScript) -> String:
        for line in card.front.split("\n"):
                var plain := MarkdownScript.plain(line).strip_edges()
                if not plain.is_empty():
                        return plain
        return card.id

## The surah a reference belongs to: its own words before the dash.
func _surah_of(reference: String) -> String:
        var at := reference.find(" - ")
        if at > 0:
                return reference.substr(0, at).strip_edges()
        return reference

## Where a card stands, in the day's own words: new, waiting a learning
## step, due today, or resting between reviews -- the same facts the home
## page counts, said for one card at a time.
func _standing_of(card: CardScript) -> Dictionary:
        var now := int(Time.get_unix_time_from_system())
        var state: Dictionary = card.state
        match state["status"]:
                "new":
                        return {"text": "not started", "color": ThemeScript.INK_SOFT}
                "learning":
                        var due := int(state["due_ts"]) - now
                        if due <= 0:
                                return {"text": "due now", "color": ThemeScript.GOLD_DEEP}
                        return {
                                "text": "in " + SchedulerScript.humanize(due),
                                "color": ThemeScript.GOLD_DEEP,
                        }
                "review":
                        var today_idx := SchedulerScript.today(now)
                        if int(state["due_day"]) <= today_idx:
                                return {"text": "due today", "color": ThemeScript.GOLD_DEEP}
                        return {
                                "text": "in %dd" % (int(state["due_day"]) - today_idx),
                                "color": ThemeScript.GREEN_DEEP,
                        }
        return {"text": "", "color": ThemeScript.INK_SOFT}

# --- the page answers the window ------------------------------------------------------

func _layout() -> void:
        if size.x <= 0.0:
                return
        var margin: MarginContainer = get_node("Margin")
        margin.add_theme_constant_override("margin_top", int(22.0 + ThemeScript.top_inset()))
        margin.add_theme_constant_override("margin_bottom", int(26.0 + ThemeScript.bottom_inset()))
        var narrow := size.x < ThemeScript.NARROW
        margin.add_theme_constant_override("margin_left", 16 if narrow else 24)
        margin.add_theme_constant_override("margin_right", 16 if narrow else 24)
        var column: VBoxContainer = get_node("Margin/Column/Scroll/Wrap/Column")
        column.custom_minimum_size = Vector2(minf(600.0, size.x - 32.0), 0.0)
        # The volume's page hangs from its own corner, under the coin.
        var popup: Control = get_node_or_null("VolumePopup")
        if popup != null:
                var popup_w := popup.get_combined_minimum_size().x
                var inset := ThemeScript.top_inset()
                popup.anchor_left = 0.0
                popup.anchor_right = 0.0
                popup.anchor_top = 0.0
                popup.offset_left = maxf(size.x - popup_w - 24.0, 16.0)
                popup.offset_top = 22.0 + inset + 48.0 + 12.0

func _input(event: InputEvent) -> void:
        if not visible:
                return
        var popup: Control = get_node_or_null("VolumePopup")
        if popup != null and popup.visible and event is InputEventMouseButton and event.pressed:
                var press := event as InputEventMouseButton
                var coin: Button = get_node_or_null("Margin/Column/TopBar/Right/Volume")
                var inside_coin := coin != null and coin.get_global_rect().has_point(press.position)
                if not inside_coin and not popup.get_global_rect().has_point(press.position):
                        popup.visible = false
        if event is InputEventKey and event.pressed and not event.echo:
                if event.keycode == KEY_ESCAPE:
                        closed.emit()
                        get_viewport().set_input_as_handled()
