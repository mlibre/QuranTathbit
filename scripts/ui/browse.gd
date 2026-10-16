class_name BrowseScreen
extends Control
const ThemeScript := preload("res://scripts/ui/theme.gd")
const DeckScript := preload("res://scripts/data/deck.gd")
const CardScript := preload("res://scripts/data/card.gd")
const CardViewScript := preload("res://scripts/ui/card_view.gd")
const CardEditorScript := preload("res://scripts/ui/card_editor.gd")
const MarkdownScript := preload("res://scripts/ui/markdown.gd")
const SchedulerScript := preload("res://scripts/data/scheduler.gd")

## The deck's own library, read as a book's index: every card in its
## order, gathered under its surah's name, each row a verse set directly
## on the page's own paper -- the mushaf cut, flush right the way the
## verse itself is read, its address and its standing sharing one quiet
## line beneath it, a hairline between one verse and the next -- because a
## deck of scripture is also a book to read through, not a box of
## questions to be asked. A row opens in place: the verses, the
## translation, the recitations, laid out as the white page they are, set
## on the desk the shelf's edge draws under the page's questions.
##
## The page's own questions are asked in two quiet ways. The search field
## reads the reference, the verses' own words, the surah's name and the
## verse's address (2:1), in the hand's own digits -- Persian and Arabic
## numerals alike. The filter pills beside it answer the other question a
## reader brings to a shelf: what is due today, what has not been started,
## what is resting between reviews.
##
## A surah's name stays with its reader: while the shelf scrolls through a
## long surah's cards, the chapter's own title rides along the top of the
## page, the way a book's running head does -- never lost, never shouting.
## Nothing here schedules: reading, listening and the pencil are all it
## does, and the study session keeps its own work to itself.

signal closed
signal volume_changed(value: float)
signal edited(card: CardScript)

var volume := 1.0  # the recitation's loudness here, as the last session left it
var _player: AudioStreamPlayer
var _open_row: Button = null
var _deck: DeckScript
var _due := 0
var _query := ""
var _filter := "all"  # the shelf's whole story, or one thread of it
var _rebuild_tween: SceneTreeTimer = null
var _sticky: PanelContainer
var _sticky_name: Label
var _sticky_count: Label

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
        _deck = deck
        _due = SchedulerScript.counts(deck, int(Time.get_unix_time_from_system()))["due"]
        if not is_node_ready():
                await ready
        _query = ""
        _filter = "all"
        (get_node("Margin/Column/Search") as LineEdit).text = ""
        _rebuild_filters()
        _rebuild()

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
        column.add_theme_constant_override("separation", 12)
        margin.add_child(column)

        column.add_child(_top_bar())
        column.add_child(_search_field())
        column.add_child(_filters_row())
        column.add_child(_summary_line())
        column.add_child(_shelf_edge())
        column.add_child(_surface())
        # The running head: a surah's title that stays while its cards scroll.
        # It rides above the shelf, a sibling drawn after it, quiet and still.
        add_child(_build_sticky())
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

## It sits pressed into the paper as a line one writes on: no box, no
## fill, no lens -- the placeholder itself says what the line is for, the
## way a ledger's ruled line waits for its entry -- a hairline of ink
## under the words, lifting to gold while it is being written in.
func _search_field() -> Control:
        var field := LineEdit.new()
        field.name = "Search"
        field.placeholder_text = "Search the deck — a surah, a verse, 2:1…"
        field.custom_minimum_size = Vector2(0, 44)
        field.clear_button_enabled = true
        field.text_direction = TextDirection.TEXT_DIRECTION_LTR
        field.add_theme_font_override("font", ThemeScript.vazir(ThemeScript.CAPTION))
        field.add_theme_font_size_override("font_size", ThemeScript.CAPTION)
        field.add_theme_color_override("font_color", ThemeScript.INK)
        field.add_theme_color_override("font_placeholder_color", ThemeScript.INK_SOFT)
        field.add_theme_color_override("caret_color", ThemeScript.GREEN_DEEP)
        field.add_theme_color_override("selection_color", ThemeScript.SELECT)
        var page := ThemeScript.soft_stylebox(Color(0, 0, 0, 0), 0)
        page.set_border_width_all(0)
        page.set_border_width(SIDE_BOTTOM, 1)
        page.border_color = Color(
                ThemeScript.INK.r, ThemeScript.INK.g, ThemeScript.INK.b, 0.30
        )
        page.content_margin_left = 2
        page.content_margin_right = 8
        page.content_margin_top = 6
        page.content_margin_bottom = 7
        field.add_theme_stylebox_override("normal", page)
        var visited := page.duplicate() as StyleBoxFlat
        visited.set_border_width(SIDE_BOTTOM, 2)
        visited.border_color = ThemeScript.GOLD
        field.add_theme_stylebox_override("hover", visited)
        field.add_theme_stylebox_override("focus", visited)
        field.text_changed.connect(_on_search_changed)
        return field

## The shelf's other question, asked in pills: the whole story, or one
## thread of it -- what the day is asking for, what has never been started,
## what is resting between reviews. A pill knows its count, so the answer
## is read before it is chosen.
func _filters_row() -> Control:
        var flow := HFlowContainer.new()
        flow.name = "Filters"
        flow.add_theme_constant_override("h_separation", 8)
        flow.add_theme_constant_override("v_separation", 6)
        flow.mouse_filter = Control.MOUSE_FILTER_PASS
        return flow

func _rebuild_filters() -> void:
        var flow: HFlowContainer = get_node_or_null("Margin/Column/Filters")
        if flow == null or _deck == null:
                return
        for child in flow.get_children():
                flow.remove_child(child)
                child.queue_free()
        var counts := {"all": _deck.cards.size()}
        var new_count := 0
        var learned := 0
        var now := int(Time.get_unix_time_from_system())
        for card in _deck.cards:
                match card.state["status"]:
                        "new":
                                new_count += 1
                        "review":
                                learned += 1
        counts["due"] = _due
        counts["new"] = new_count
        counts["learned"] = learned
        for key in ["all", "due", "new", "learned"]:
                var pill := Button.new()
                pill.name = "Pill" + key.capitalize()
                pill.text = "%s %d" % [_pill_word(key), counts[key]]
                pill.custom_minimum_size = Vector2(0, 34)
                pill.tooltip_text = _pill_tooltip(key)
                ThemeScript.pressable(pill, 0.97, 1.0)
                _dress_pill(pill, key == _filter)
                pill.pressed.connect(func() -> void:
                        _filter = key if _filter != key else "all"
                        _rebuild_filters()
                        _rebuild()
                )
                flow.add_child(pill)

func _pill_word(key: String) -> String:
        match key:
                "due":
                        return "Due"
                "new":
                        return "New"
                "learned":
                        return "In review"
        return "All"

func _pill_tooltip(key: String) -> String:
        match key:
                "due":
                        return "What the day is asking for"
                "new":
                        return "Cards never yet studied"
                "learned":
                        return "Cards resting between reviews"
        return "The whole shelf"

## A pill at rest is nothing at all -- words on the paper; the pill that
## is chosen takes the page's own green wash, the colour of the deck's
## progress, with no outline anywhere: the way a book's folios are marked,
## not the way a web form's checkboxes are.
func _dress_pill(pill: Button, on: bool) -> void:
        var rest := ThemeScript.soft_stylebox(Color(0, 0, 0, 0), 18)
        if on:
                rest.bg_color = ThemeScript.GREEN_SOFT
        var wash := rest.duplicate() as StyleBoxFlat
        if not on:
                wash.bg_color = Color(ThemeScript.INK.r, ThemeScript.INK.g, ThemeScript.INK.b, 0.05)
        pill.add_theme_stylebox_override("normal", rest)
        pill.add_theme_stylebox_override("hover", wash)
        pill.add_theme_stylebox_override("pressed", wash)
        pill.add_theme_stylebox_override("focus", wash)
        pill.add_theme_stylebox_override("disabled", rest)
        pill.add_theme_font_override("font", ThemeScript.vazir(12, on))
        pill.add_theme_font_size_override("font_size", 12)
        var tone := ThemeScript.GREEN_DEEP if on else ThemeScript.INK_SOFT
        pill.add_theme_color_override("font_color", tone)
        pill.add_theme_color_override("font_hover_color", ThemeScript.GREEN_DEEP if on else ThemeScript.INK)
        pill.add_theme_color_override("font_pressed_color", tone)
        pill.add_theme_color_override("font_focus_color", tone)
        pill.add_theme_color_override("font_disabled_color", tone)

## The shelf's own account of itself: how many cards it holds, how many the
## day is asking for -- and, while a search or a filter stands, how many
## answer it.
func _summary_line() -> Control:
        var label := Label.new()
        label.name = "Summary"
        label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        ThemeScript.dress(label, ThemeScript.CAPTION, ThemeScript.INK_SOFT)
        return label

## The line where the page's questions end and the book itself begins: one
## hairline under the search, the pills and the count -- the edge of the
## desk the verses lie on, so the shelf below reads as one continuous
## page rather than a stack of boxes.
func _shelf_edge() -> Control:
        var edge := PanelContainer.new()
        edge.name = "Edge"
        edge.custom_minimum_size = Vector2(0, 1)
        edge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
        edge.add_theme_stylebox_override("panel", ThemeScript.soft_stylebox(ThemeScript.LINE, 0))
        return edge

func _surface() -> Control:
        var scroll := ScrollContainer.new()
        scroll.name = "Scroll"
        scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
        scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
        ThemeScript.style_scroll(scroll)
        scroll.get_v_scroll_bar().value_changed.connect(func(_v: float) -> void: _update_sticky())
        var wrap := CenterContainer.new()
        wrap.name = "Wrap"
        wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        scroll.add_child(wrap)
        var column := VBoxContainer.new()
        column.name = "Column"
        column.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        # The page's rhythm is set by the rows themselves -- their padding,
        # their hairlines, their chapters' opening air -- not by a blanket
        # gap between every child.
        column.add_theme_constant_override("separation", 0)
        wrap.add_child(column)
        return scroll

## The running head itself: a small page carrying the surah's name and its
## count, pinned under the search while the shelf scrolls through its cards.
## It says nothing the shelf has not already said; it only says it where the
## eye currently is.
func _build_sticky() -> Control:
        _sticky = PanelContainer.new()
        _sticky.name = "Sticky"
        _sticky.visible = false
        _sticky.mouse_filter = Control.MOUSE_FILTER_IGNORE
        var head := ThemeScript.card_stylebox()
        head.shadow_size = 14
        head.shadow_offset = Vector2(0, 6)
        head.set_corner_radius_all(12)
        head.content_margin_left = 16
        head.content_margin_right = 16
        head.content_margin_top = 8
        head.content_margin_bottom = 8
        _sticky.add_theme_stylebox_override("panel", head)
        var row := HBoxContainer.new()
        row.name = "Row"
        row.add_theme_constant_override("separation", 10)
        row.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _sticky.add_child(row)
        var star := ThemeScript.StarMark.new(ThemeScript.GOLD)
        star.name = "Star"
        star.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        row.add_child(star)
        _sticky_name = Label.new()
        _sticky_name.name = "Name"
        _sticky_name.text_direction = TextDirection.TEXT_DIRECTION_AUTO
        _sticky_name.add_theme_font_override("font", ThemeScript.font_for("arabic", 16, true))
        _sticky_name.add_theme_font_size_override("font_size", 16)
        _sticky_name.add_theme_color_override("font_color", ThemeScript.GOLD_DEEP)
        row.add_child(_sticky_name)
        _sticky_count = Label.new()
        _sticky_count.name = "Count"
        _sticky_count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
        ThemeScript.dress(_sticky_count, 12, ThemeScript.INK_SOFT)
        row.add_child(_sticky_count)
        return _sticky

## While the shelf scrolls, the chapter that owns the cards under the eye
## names itself at the top of the page -- from the moment its own title
## scrolls away until the moment it comes back.
func _update_sticky() -> void:
        if _sticky == null or not is_instance_valid(_sticky):
                return
        var column: VBoxContainer = get_node_or_null("Margin/Column/Scroll/Wrap/Column")
        var scroll: ScrollContainer = get_node_or_null("Margin/Column/Scroll")
        if column == null or scroll == null:
                return
        var top := scroll.get_global_rect().position.y
        var current: VBoxContainer = null
        for child in column.get_children():
                if child.name.begins_with("Header") and child.get_global_rect().end.y <= top + 0.5:
                        current = child
        if current == null:
                if _sticky.visible:
                        _sticky.visible = false
                return
        var name_label: Label = current.get_node("Line/Name")
        var count_label: Label = current.get_node("Line/Count")
        if _sticky_name.text != name_label.text:
                _sticky_name.text = name_label.text
                _sticky_count.text = count_label.text
                if not _sticky.visible:
                        _sticky.visible = true
                        ThemeScript.settle_in(_sticky, 0.0, 0.16)
        elif not _sticky.visible:
                _sticky.visible = true
                ThemeScript.settle_in(_sticky, 0.0, 0.16)

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

# --- the search ----------------------------------------------------------------------

## The hand types; the shelf follows a breath behind, once, when the hand
## pauses -- not once a letter, which would rebuild the page under a fast
## typist's fingers.
func _on_search_changed(text: String) -> void:
        _query = text
        if _rebuild_tween != null:
                _rebuild_tween.timeout.disconnect(_rebuild)
        _rebuild_tween = get_tree().create_timer(0.22)
        _rebuild_tween.timeout.connect(_rebuild)

## A card answers when the search's words and the standing filter both say
## so: the reference it asks with, the verses and translations it answers
## with, its surah's name, or its verse's address. Digits read as digits
## whatever hand wrote them -- ۲:۱ and 2:1 are the same question.
func _matches(card: CardScript) -> bool:
        if not _filter_matches(card):
                return false
        var q := _normalize_digits(_query).to_lower().strip_edges()
        if q.is_empty():
                return true
        var parts := PackedStringArray([
                _reference_of(card), card.front, card.back, card.id,
        ])
        for address in _addresses_of(card):
                parts.append(address)
        return _normalize_digits("\n".join(parts)).to_lower().contains(q)

## The thread of the shelf a pill keeps: the whole story, or only the cards
## the day is asking for, the ones never yet studied, or the ones resting
## between reviews.
func _filter_matches(card: CardScript) -> bool:
        if _filter == "all":
                return true
        if _filter == "due":
                return _is_due(card)
        var status := str(card.state["status"])
        if _filter == "new":
                return status == "new"
        return status == "review"

func _is_due(card: CardScript) -> bool:
        var now := int(Time.get_unix_time_from_system())
        var state: Dictionary = card.state
        match state["status"]:
                "learning":
                        return int(state["due_ts"]) <= now
                "review":
                        return int(state["due_day"]) <= SchedulerScript.today(now)
        return false

## The verse addresses a card carries, from the media its markdown names:
## 002001.mp3 is surah 2, verse 1, said the way a search asks for it.
func _addresses_of(card: CardScript) -> PackedStringArray:
        var out := PackedStringArray()
        var finder := RegEx.create_from_string("\\b(\\d{6})\\.(?:mp3|ogg|wav|m4a)\\b")
        for found in finder.search_all(card.front + "\n" + card.back):
                var stem := str(found.get_string(1))
                if stem.is_valid_int():
                        out.append("%d:%d" % [int(stem.substr(0, 3)), int(stem.substr(3, 3))])
        return out

## Persian ۰-۹ and Arabic ٠-٩ become the digits a search can compare.
static func _normalize_digits(text: String) -> String:
        var out := text
        for i in 10:
                out = out.replace(String.chr(0x06F0 + i), str(i))
                out = out.replace(String.chr(0x0660 + i), str(i))
        return out

# --- the list ------------------------------------------------------------------------

## The shelf itself, rebuilt whole: the cards that answer the search and the
## filter, under their surahs' names, with the page's account of them above.
## The column's own separation is nothing -- the rhythm of the page lives in
## the rows and the hairlines between them, each element carrying its own
## air, the way a book's typesetting does.
func _rebuild() -> void:
        _rebuild_tween = null
        var column: VBoxContainer = get_node("Margin/Column/Scroll/Wrap/Column")
        for child in column.get_children():
                column.remove_child(child)
                child.queue_free()
        _open_row = null
        var shown: Array = []
        for card in _deck.cards:
                if _matches(card):
                        shown.append(card)
        var summary: Label = get_node("Margin/Column/Summary")
        var asking := not _query.strip_edges().is_empty() or _filter != "all"
        # The shelf's account of itself is spoken only while a question
        # stands: at rest the pills already carry their counts, and a line
        # that repeats them is a dashboard, not a book.
        summary.visible = asking
        if asking:
                summary.text = "%d of %d cards" % [shown.size(), _deck.cards.size()]
        if shown.is_empty():
                column.add_child(_empty_state())
                _update_sticky()
                return
        var surah := ""
        var in_surah := 0
        var resting := 0
        for i in shown.size():
                var card: CardScript = shown[i]
                var reference := _reference_of(card)
                var card_surah := _surah_of(reference)
                if card_surah != surah:
                        if not surah.is_empty():
                                _set_header_count(column, in_surah, resting)
                        surah = card_surah
                        in_surah = 0
                        resting = 0
                        column.add_child(_surah_header(surah, card.id))
                in_surah += 1
                if str(card.state["status"]) == "review":
                        resting += 1
                column.add_child(_entry(card, reference))
        _set_header_count(column, in_surah, resting)
        var tail := Control.new()
        tail.name = "Tail"
        tail.custom_minimum_size = Vector2(0, 18)
        tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
        column.add_child(tail)
        # The reveal is a breath, whatever the shelf's length: a hundred cards
        # stepping a fixed beat apart would keep arriving long after the eye
        # has moved on, and a shelf half-arrived reads as a shelf half-broken.
        if not asking:
                ThemeScript.stagger_in(column, minf(0.015, 0.55 / maxf(column.get_child_count(), 1.0)), 0.18)
        _update_sticky()

## The shelf with nothing to say says it warmly: what was asked, why the
## answer is empty, and -- when it was a filter -- that the emptiness is
## itself good news.
func _empty_state() -> Control:
        var box := VBoxContainer.new()
        box.name = "Empty"
        box.alignment = BoxContainer.ALIGNMENT_CENTER
        box.custom_minimum_size = Vector2(0, 220)
        box.mouse_filter = Control.MOUSE_FILTER_IGNORE
        var mark := ThemeScript.OrnamentMark.new()
        mark.name = "Ornament"
        mark.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        box.add_child(mark)
        var lead := Label.new()
        lead.name = "Lead"
        lead.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        ThemeScript.dress(lead, ThemeScript.BODY, ThemeScript.INK)
        lead.text = _empty_lead()
        box.add_child(lead)
        var under := Label.new()
        under.name = "Under"
        under.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        ThemeScript.dress(under, ThemeScript.CAPTION, ThemeScript.INK_SOFT)
        under.text = _empty_under()
        box.add_child(under)
        return box

func _empty_lead() -> String:
        if not _query.strip_edges().is_empty():
                return "No cards answer"
        match _filter:
                "due":
                        return "Nothing is due today"
                "new":
                        return "Every card has been started"
                "learned":
                        return "Nothing rests between reviews yet"
        return "The shelf is empty"

func _empty_under() -> String:
        if not _query.strip_edges().is_empty():
                return "Try fewer words, or the verse's address — 2:1."
        match _filter:
                "due":
                        return "The deck rests, and so can its reader."
                "new":
                        return "The whole deck is under way."
                "learned":
                        return "Cards land here once reviews carry them."
        return "A deck of folders and files, read from its own shelf."

## The count and the rest a surah's title carries, written into the header
## that waits for them at the top of its own run of cards -- and drawn as a
## thin green rule beneath the name, the fraction of the surah now resting
## between reviews.
func _set_header_count(column: VBoxContainer, count: int, resting: int) -> void:
        var header: VBoxContainer = null
        for child in column.get_children():
                if child.name.begins_with("Header"):
                        header = child
        if header != null:
                (header.get_node("Line/Count") as Label).text = "%d card%s" % [
                        count, "" if count == 1 else "s"
                ]
                var done := clampf(resting / float(count) if count > 0 else 0.0, 0.0, 1.0)
                (header.get_node("Rule/Fill") as Control).size_flags_stretch_ratio = maxf(done, 0.02)
                (header.get_node("Rule/Grow") as Control).size_flags_stretch_ratio = maxf(1.0 - done, 0.02)

## A surah's own opening: its name in the gold of citations at a
## chapter's own size, a small star before it the way a mushaf marks its
## surahs, its count at the far end -- and beneath, a thin green rule of
## how much of the chapter rests between reviews. A chapter opens with
## the air of a page break, not with a banner: the name must be able to
## stand beside the verses it governs without shouting over them.
func _surah_header(surah: String, of_card: String) -> Control:
        var box := VBoxContainer.new()
        # One name per node: the engine renames a second "Header" into an
        # anonymous @VBoxContainer, and a test (or a finger) looking for the
        # chapter marks finds only the first.
        box.name = "Header" + of_card
        box.add_theme_constant_override("separation", 6)
        box.mouse_filter = Control.MOUSE_FILTER_IGNORE
        var air := Control.new()
        air.name = "Air"
        air.custom_minimum_size = Vector2(0, 22)
        air.mouse_filter = Control.MOUSE_FILTER_IGNORE
        box.add_child(air)
        var line := HBoxContainer.new()
        line.name = "Line"
        line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        line.add_theme_constant_override("separation", 10)
        var star := ThemeScript.StarMark.new(ThemeScript.GOLD)
        star.name = "Star"
        star.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        line.add_child(star)
        var label := Label.new()
        label.name = "Name"
        label.text = surah
        label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
        label.text_direction = TextDirection.TEXT_DIRECTION_AUTO
        label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        label.add_theme_font_override("font", ThemeScript.font_for(
                ThemeScript.reference_script(surah), 22, true
        ))
        label.add_theme_font_size_override("font_size", 22)
        label.add_theme_color_override("font_color", ThemeScript.GOLD_DEEP)
        line.add_child(label)
        var count := Label.new()
        count.name = "Count"
        count.text = ""
        count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
        # A folio number: small, quiet, ink -- the way a book numbers its
        # leaves at a chapter's opening.
        ThemeScript.dress(count, 11, ThemeScript.INK_SOFT)
        line.add_child(count)
        box.add_child(line)
        box.add_child(_progress_rule())
        return box

## The chapter's own progress: a track the colour of the page's edges, with
## as much of it green as the surah has cards resting between reviews --
## thin as a sewing thread, far enough beneath the name to read as the
## chapter's progress and not as a correction under a word.
func _progress_rule() -> Control:
        var rule := HBoxContainer.new()
        rule.name = "Rule"
        rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        rule.custom_minimum_size = Vector2(0, 2)
        rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
        rule.add_theme_constant_override("separation", 0)
        rule.add_child(_rule_panel("Fill", ThemeScript.GREEN))
        rule.add_child(_rule_panel("Grow", ThemeScript.LINE))
        return rule

func _rule_panel(panel_name: String, tone: Color) -> PanelContainer:
        var panel := PanelContainer.new()
        panel.name = panel_name
        panel.custom_minimum_size = Vector2(6, 2)
        panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        panel.size_flags_stretch_ratio = 0.5
        panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
        var box := ThemeScript.soft_stylebox(tone, 2)
        box.content_margin_left = 0
        box.content_margin_right = 0
        box.content_margin_top = 0
        box.content_margin_bottom = 0
        panel.add_theme_stylebox_override("panel", box)
        return panel

## One card in the library: its row, and the page that opens under it. The
## row is ink on the page's own paper -- no box, no border, the way a book's
## index is set. The verse itself is the row's primary voice, flush right
## in the mushaf cut the way the verse is read; beneath it, on one quiet
## line, the card's standing at the left and its address in gold at the
## right, with the row's own small chevron at the far edge. The page that
## opens below is the white card a session shows -- the desk's page against
## the shelf's paper, verses, recitations and the pencil at hand.
func _entry(card: CardScript, reference: String) -> Control:
        var entry := VBoxContainer.new()
        entry.name = "Entry" + card.id
        entry.add_theme_constant_override("separation", 13)

        var row := Button.new()
        row.name = "Row"
        row.toggle_mode = false
        row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        # The row is not a card on a desk but a line in a book: transparent
        # at rest, a breath of the deck's green under the hand or while its
        # page stands open. Its padding is carried by the MarginContainer
        # below, not by the stylebox: a Button is no Container, and a
        # stylebox's content margins place ink, not children -- a child
        # anchored full-rect spans the button's raw edge and the verse
        # would run to the very rim of its row.
        var rest := ThemeScript.soft_stylebox(Color(0, 0, 0, 0), 12)
        var hover := rest.duplicate() as StyleBoxFlat
        hover.bg_color = Color(
                ThemeScript.GREEN.r, ThemeScript.GREEN.g, ThemeScript.GREEN.b, 0.07
        )
        row.add_theme_stylebox_override("normal", rest)
        row.add_theme_stylebox_override("hover", hover)
        row.add_theme_stylebox_override("pressed", hover)
        row.add_theme_stylebox_override("focus", hover)
        row.add_theme_stylebox_override("disabled", rest)
        ThemeScript.pressable(row)
        row.pressed.connect(_toggle_row.bind(row, card, entry))

        var pad := MarginContainer.new()
        pad.name = "Pad"
        pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        pad.add_theme_constant_override("margin_left", 20)
        pad.add_theme_constant_override("margin_right", 20)
        pad.add_theme_constant_override("margin_top", 16)
        pad.add_theme_constant_override("margin_bottom", 16)
        row.add_child(pad)

        var line := HBoxContainer.new()
        line.name = "Line"
        line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        line.mouse_filter = Control.MOUSE_FILTER_IGNORE
        line.add_theme_constant_override("separation", 12)
        pad.add_child(line)

        var words := VBoxContainer.new()
        words.name = "Words"
        words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        words.mouse_filter = Control.MOUSE_FILTER_IGNORE
        words.add_theme_constant_override("separation", 8)
        line.add_child(words)

        # The verse itself, the shelf's primary voice: a reader finds the
        # line they half-remember by its words, not its number. It stands
        # flush right, the edge the verse itself is read from, in the
        # mushaf cut at a size its vowels keep every curl.
        var preview_text := _preview_of(card)
        if not preview_text.is_empty():
                var preview := Label.new()
                preview.name = "Preview"
                preview.text = preview_text
                preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
                preview.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
                preview.text_direction = TextDirection.TEXT_DIRECTION_AUTO
                preview.clip_text = true
                var preview_script := ThemeScript.script_of(preview_text)
                preview.add_theme_font_override("font", ThemeScript.verse_face(preview_script))
                var preview_size := 26 if preview_script == "arabic" else 14
                preview.add_theme_font_size_override("font_size", preview_size)
                preview.add_theme_color_override("font_color", ThemeScript.INK)
                words.add_child(preview)

        # The row's second line: the card's standing written small in the
        # left margin when there is a standing to write -- a card never yet
        # studied says nothing at all, because ninety-nine "new" badges on
        # ninety-nine new cards are wallpaper, not information -- and its
        # address in the gold of citations at the right, both on one quiet
        # baseline beneath the verse.
        var meta := HBoxContainer.new()
        meta.name = "Meta"
        meta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        meta.add_theme_constant_override("separation", 8)
        meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
        words.add_child(meta)

        var standing := _standing_of(card)
        if not str(standing["text"]).is_empty():
                var chip := HBoxContainer.new()
                chip.name = "Chip"
                chip.add_theme_constant_override("separation", 6)
                chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
                var dot := ThemeScript.StatusDot.new(standing["color"], standing["hollow"])
                dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
                chip.add_child(dot)
                var status := Label.new()
                status.name = "Status"
                status.text = str(standing["text"])
                status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
                ThemeScript.dress(status, 12, standing["color"], true)
                chip.add_child(status)
                meta.add_child(chip)

        var stretch := Control.new()
        stretch.name = "Stretch"
        stretch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        stretch.mouse_filter = Control.MOUSE_FILTER_IGNORE
        meta.add_child(stretch)

        var ref_label := Label.new()
        ref_label.name = "Ref"
        ref_label.text = reference
        ref_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        ref_label.text_direction = TextDirection.TEXT_DIRECTION_AUTO
        ref_label.clip_text = true
        var script := ThemeScript.reference_script(reference)
        ref_label.add_theme_font_override("font", ThemeScript.font_for(script, 14, true))
        ref_label.add_theme_font_size_override("font_size", 14 if script == "arabic" else 12)
        ref_label.add_theme_color_override("font_color", ThemeScript.GOLD_DEEP)
        meta.add_child(ref_label)

        var disclose := ThemeScript.DisclosureMark.new(ThemeScript.INK_SOFT)
        disclose.name = "Disclose"
        disclose.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        meta.add_child(disclose)

        # A Button is not a Container: its anchored children never size it,
        # and a row left to the button's own account of itself would stand
        # shorter than its own verse -- the verse's vowels clipped into the
        # row above, the meta line buried under the card below. The row
        # says its own height instead: what its line of words needs, plus
        # the padding that lets the verse breathe.
        row.custom_minimum_size = Vector2(
                0,
                maxf(pad.get_combined_minimum_size().y, 92.0),
        )

        entry.add_child(row)

        var detail := VBoxContainer.new()
        detail.name = "Detail"
        detail.visible = false
        detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        detail.add_theme_constant_override("separation", 12)
        entry.add_child(detail)
        entry.add_child(_divider())
        return entry

## The hairline after every verse, the last of a chapter included: a rule
## that appears and disappears reads as a rendering mistake, not a rhythm --
## the index's own rule, the weight and colour of the page's edges, and the
## chapter's opening air is the only break a book needs.
func _divider() -> Control:
        var rule := PanelContainer.new()
        rule.name = "Divider"
        rule.custom_minimum_size = Vector2(0, 1)
        rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
        rule.add_theme_stylebox_override("panel", ThemeScript.soft_stylebox(ThemeScript.LINE, 0))
        return rule

## A row opens its card, and only one card is open at a time: the page it
## opens is read, then folded away by the next one a finger asks for. An
## open row keeps the wash of a visited one, so the shelf itself says which
## page stands open.
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
        _fill_detail(detail, card)
        detail.visible = true
        ThemeScript.settle_in(detail, 0.0, 0.24)
        _open_row = row

## The card's page under its row: the same card a session shows -- verses,
## translations, recitations, citation at the foot -- dressed as the page it
## is, on the app's own card, with the pencil at hand for the fix a reader
## notices mid-read.
func _fill_detail(detail: VBoxContainer, card: CardScript) -> void:
        for child in detail.get_children():
                detail.remove_child(child)
                child.queue_free()
        var panel := PanelContainer.new()
        panel.name = "Card"
        panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        panel.add_theme_stylebox_override("panel", ThemeScript.card_stylebox())
        detail.add_child(panel)
        var pad := MarginContainer.new()
        pad.name = "Pad"
        pad.add_theme_constant_override("margin_left", 24)
        pad.add_theme_constant_override("margin_right", 24)
        pad.add_theme_constant_override("margin_top", 22)
        pad.add_theme_constant_override("margin_bottom", 22)
        panel.add_child(pad)
        var view := CardViewScript.new(_player)
        view.name = "View"
        view.show_text(card.back, card.folder)
        pad.add_child(view)
        var edit := ThemeScript.ghost_button("Edit card", ThemeScript.GOLD_DEEP, 44, 21)
        edit.name = "Edit"
        edit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        edit.pressed.connect(_open_editor.bind(card))
        detail.add_child(edit)

func _set_row_open(row: Button, open: bool) -> void:
        var mark: ThemeScript.DisclosureMark = row.get_node("Line/Words/Meta/Disclose")
        mark.open = open
        mark.color = ThemeScript.GREEN_DEEP if open else ThemeScript.INK_SOFT
        mark.queue_redraw()
        # An open row carries the visiting wash at rest, not only under the
        # hand: the shelf itself says which page stands open.
        var wash := row.get_theme_stylebox("hover")
        if open:
                row.add_theme_stylebox_override("normal", wash)
        else:
                var rest := (wash as StyleBoxFlat).duplicate()
                rest.bg_color = Color(0, 0, 0, 0)
                row.add_theme_stylebox_override("normal", rest)

func _close_detail(detail: VBoxContainer) -> void:
        for child in detail.get_children():
                detail.remove_child(child)
                child.queue_free()
        detail.visible = false

# --- the pencil ----------------------------------------------------------------------

## The pencil opens the card's own page over the library, the same page a
## session opens: the words as the author wrote them, saved to the very
## files the deck is.
func _open_editor(card: CardScript) -> void:
        if get_node_or_null("Editor") != null:
                return
        var editor := CardEditorScript.new(card, volume)
        editor.name = "Editor"
        add_child(editor)
        editor.saved.connect(_on_editor_saved)

## A saved edit re-opens the row's page with the words as they now are, and
## the row's own reference follows its question's first line.
func _on_editor_saved(card: CardScript) -> void:
        edited.emit(card)
        var entry: VBoxContainer = get_node_or_null("Margin/Column/Scroll/Wrap/Column/Entry" + card.id)
        if entry == null:
                return
        (entry.get_node("Row/Line/Words/Meta/Ref") as Label).text = _reference_of(card)
        var detail: VBoxContainer = entry.get_node("Detail")
        if detail.visible:
                _fill_detail(detail, card)
                ThemeScript.settle_in(detail, 0.0, 0.24)

# --- the card's own words ------------------------------------------------------------

## The reference the card asks for: the first plain line of its front.
func _reference_of(card: CardScript) -> String:
        for line in card.front.split("\n"):
                var plain := MarkdownScript.plain(line).strip_edges()
                if not plain.is_empty():
                        return plain
        return card.id

## The verse's first words, for the row's primary line: the first plain line
## of the card's answer that carries words a reader would recognise.
func _preview_of(card: CardScript) -> String:
        for block in MarkdownScript.parse(card.back):
                if block.kind != "text":
                        continue
                var plain := MarkdownScript.plain(block.text).strip_edges()
                if not plain.is_empty():
                        return plain
        return ""

## The surah a reference belongs to: its own words before the dash.
func _surah_of(reference: String) -> String:
        var at := reference.find(" - ")
        if at > 0:
                return reference.substr(0, at).strip_edges()
        return reference

## Where a card stands, in the day's own words: waiting a learning step,
## due today, or resting between reviews -- the same facts the home page
## counts, said for one card at a time. A card never yet studied says
## nothing at all: on a shelf of new cards the silence is the information,
## and the first gold "in 10m" lands as the event it is.
func _standing_of(card: CardScript) -> Dictionary:
        var now := int(Time.get_unix_time_from_system())
        var state: Dictionary = card.state
        match state["status"]:
                "new":
                        return {"text": "", "color": ThemeScript.INK_SOFT, "hollow": false}
                "learning":
                        var due := int(state["due_ts"]) - now
                        if due <= 0:
                                return {"text": "due now", "color": ThemeScript.GOLD_DEEP, "hollow": false}
                        return {
                                "text": "in " + SchedulerScript.humanize(due),
                                "color": ThemeScript.GOLD_DEEP,
                                "hollow": false,
                        }
                "review":
                        var today_idx := SchedulerScript.today(now)
                        if int(state["due_day"]) <= today_idx:
                                return {"text": "due today", "color": ThemeScript.GOLD_DEEP, "hollow": false}
                        return {
                                "text": "in %dd" % (int(state["due_day"]) - today_idx),
                                "color": ThemeScript.GREEN_DEEP,
                                "hollow": false,
                        }
        return {"text": "", "color": ThemeScript.INK_SOFT, "hollow": false}

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
        # A landscape window is a reading desk: the shelf takes a reader's
        # measure, the same one a session's card takes.
        var measure := minf(ThemeScript.MEASURE, size.x - 32.0)
        column.custom_minimum_size = Vector2(measure, 0.0)
        # The running head sits over the shelf, the width of the shelf
        # itself, wherever the shelf is.
        if _sticky != null:
                var scroll: ScrollContainer = get_node("Margin/Column/Scroll")
                var left := (size.x - measure) / 2.0
                _sticky.position = Vector2(
                        maxf(left, 8.0),
                        scroll.get_global_rect().position.y - get_global_rect().position.y
                )
                _sticky.custom_minimum_size = Vector2(measure, 0.0)
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

## The shelf answers the keyboard as a shelf: the arrows walk the rows, one
## card at a time, and Enter opens what stands under the hand.
func _row_buttons() -> Array:
        var rows := []
        var column: VBoxContainer = get_node_or_null("Margin/Column/Scroll/Wrap/Column")
        if column == null:
                return rows
        for entry in column.get_children():
                if entry.name.begins_with("Entry"):
                        rows.append(entry.get_node("Row"))
        return rows

func _input(event: InputEvent) -> void:
        if not visible:
                return
        # The editor owns the page while it is open; Esc belongs to it.
        if get_node_or_null("Editor") != null:
                return
        var popup: Control = get_node_or_null("VolumePopup")
        if popup != null and popup.visible and event is InputEventMouseButton and event.pressed:
                var press := event as InputEventMouseButton
                var coin: Button = get_node_or_null("Margin/Column/TopBar/Right/Volume")
                var inside_coin := coin != null and coin.get_global_rect().has_point(press.position)
                if not inside_coin and not popup.get_global_rect().has_point(press.position):
                        popup.visible = false
        # While the search field is being written in, the page's keys are
        # the field's own; Esc leaves the field first, and only a second
        # Esc leaves the library.
        var search: LineEdit = get_node_or_null("Margin/Column/Search")
        var writing := search != null and search.has_focus()
        if event is InputEventKey and event.pressed and not event.echo:
                if event.keycode == KEY_ESCAPE:
                        if writing:
                                search.release_focus()
                        else:
                                closed.emit()
                        get_viewport().set_input_as_handled()
                elif not writing and (event.keycode == KEY_UP or event.keycode == KEY_DOWN):
                        var rows := _row_buttons()
                        if rows.is_empty():
                                return
                        var at := -1
                        for i in rows.size():
                                if (rows[i] as Button).has_focus():
                                        at = i
                        var step := 1 if event.keycode == KEY_DOWN else -1
                        var next := at
                        if at < 0:
                                next = 0 if step > 0 else rows.size() - 1
                        else:
                                next = clampi(at + step, 0, rows.size() - 1)
                        (rows[next] as Button).grab_focus()
                        get_viewport().set_input_as_handled()
