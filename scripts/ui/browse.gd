class_name BrowseScreen
extends Control
const ThemeScript := preload("res://scripts/ui/theme.gd")
const DeckScript := preload("res://scripts/data/deck.gd")
const CardScript := preload("res://scripts/data/card.gd")
const CardViewScript := preload("res://scripts/ui/card_view.gd")
const CardEditorScript := preload("res://scripts/ui/card_editor.gd")
const MarkdownScript := preload("res://scripts/ui/markdown.gd")
const SchedulerScript := preload("res://scripts/data/scheduler.gd")
const I18nScript := preload("res://scripts/ui/i18n.gd")

## The deck's own library, read as a book: it opens on the shelf of
## surahs -- the book's own table of contents -- where every surah stands
## as one card wearing an arch the way a mushaf heads its chapters, its
## name in the gold of citations, the mushaf's own number beneath it, a
## ring carrying the share of its cards resting in review, and a gold dot
## when the day asks something of it. The questions a reader brings -- the
## search field, the filter pills -- narrow the shelf the same way they
## narrow the pages behind it. A card is touched and its chapter opens:
## every card of that surah in its order, each row a verse set directly
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
## A surah's name stays with its reader: behind a chapter's card the
## page's own title carries the chapter's name, and while its cards
## scroll, the title rides along the top of the page, the way a book's
## running head does -- never lost, never shouting. The way back is the
## way every book backs up: out of the chapter to its shelf, out of the
## library to home.
## Nothing here schedules: reading, listening and the pencil are all it
## does, and the study session keeps its own work to itself.

signal closed
signal volume_changed(value: float)
signal edited(card: CardScript)
## The foot below is the root's own bar -- raised once, above every swap --
## so the page raises no doors of its own; the bar's presses are answered
## by the root directly. What the page still says of the foot is the one
## step only it knows: the library's own door, behind a chapter's page,
## leads back to the shelf (foot_library_door, asked by the root).


var volume := 1.0  # the recitation's loudness here, as the last session left it
var _player: AudioStreamPlayer
var _rig: ThemeScript.VolumeRig  # the popup, its coin and the player, one shared thing
var _open_row: Button = null
var _deck: DeckScript
var _due := 0
var _query := ""
var _filter := "all"  # the shelf's whole story, or one thread of it
var _mode := "shelf"  # the shelf of surahs, or the page behind one of its cards
var _open_surah := ""  # the chapter whose page stands open
var _rebuild_tween: SceneTreeTimer = null
var _sticky: PanelContainer
var _sticky_name: Label
var _sticky_count: Label

# --- the shelf's streaming build ----------------------------------------------------
## A shelf of a hundred-and-fifty cards is a shelf of a hundred-and-fifty
## buttons, fonts and measured inks, and a page that lays them all in one
## breath lays nothing for the seconds that breath takes -- the phone
## meets a frozen opening instead of a library. So the shelf streams: the
## opening breath lays a screenful, and the rest arrive a batch a frame
## while the reader's eye is still settling on the first. A newer
## question (a typed search, a chosen pill) retires the build in flight
## by its generation, and the closing of the shelf -- the last header's
## count, the tail, the sizing pass -- lands only when the last batch
## has.
const SHELF_FIRST := 14     # the opening screenful, laid in one breath
const SHELF_BATCH := 14     # the most a streaming frame may lay
const SHELF_SLICE_MS := 10  # the work a streaming frame may spend on rows
var _build_gen := 0
var _pending: Array = []
var _shelf := {}

func _ready() -> void:
        set_process(false)
        _player = AudioStreamPlayer.new()
        _player.name = "Player"
        add_child(_player)
        _rig = ThemeScript.VolumeRig.new(self, _player)
        _build()
        resized.connect(_layout)
        call_deferred("_layout")

func _exit_tree() -> void:
        _build_gen += 1
        _pending = []
        _shelf = {}
        if _player != null and is_instance_valid(_player):
                _player.queue_free()

## The heartbeat of a streamed shelf: a slice of rows a frame -- as many
## as a slice of milliseconds buys, never more than a batch -- so the
## page keeps its frame rate while the shelf fills, fast machine or slow
## phone alike. A build retired by a newer question (its generation no
## longer the page's) stops here without touching the shelf it no longer
## owns.
func _process(_delta: float) -> void:
        if _shelf.is_empty() or int(_shelf.get("gen", -1)) != _build_gen:
                _shelf = {}
                _pending = []
                set_process(false)
                return
        var started := Time.get_ticks_msec()
        var laid := 0
        while not _pending.is_empty() and laid < SHELF_BATCH:
                _lay_one()
                laid += 1
                if Time.get_ticks_msec() - started >= SHELF_SLICE_MS:
                        break
        # The rows a frame brings are sized that same frame, so the shelf
        # never wobbles beneath the reader's eye (the pad's own signal
        # answers every later change the same way).
        call_deferred("_fit_rows")
        if _pending.is_empty():
                _close_shelf()
                _shelf = {}
                set_process(false)

## The deck arrives with the volume the last session chose, so the first
## recitation heard here already speaks at the remembered loudness.
func setup(deck: DeckScript, p_volume: float) -> void:
        volume = p_volume
        _rig.apply(volume)
        _deck = deck
        _due = SchedulerScript.counts(deck, int(Time.get_unix_time_from_system()))["due"]
        if not is_node_ready():
                await ready
        _query = ""
        _filter = "all"
        _mode = "shelf"
        _open_surah = ""
        (get_node("Margin/Column/Search") as LineEdit).text = ""
        _dress_chrome()
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
        add_child(_rig.popup())
        # The foot below is the root's own bar -- raised once, above every
        # swap -- riding the bottom edge on both of the page's steps, so no
        # door is ever more than a thumb's reach from the shelf or the
        # chapter alike. The page's ground ends a breath above it in
        # _layout.


func _top_bar() -> Control:
        # The bar answers the reading's own direction: under a right-reading
        # tongue the way back points right from the right corner, the way the
        # settings page already reads, so every page answers alike.
        var bar: Dictionary = ThemeScript.top_bar(I18nScript.t("Browse"), I18nScript.is_rtl())
        var row: HBoxContainer = bar["row"]
        var back: Button = bar["back"]
        back.tooltip_text = I18nScript.t("Back to home")
        back.pressed.connect(_go_back)
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
        coin.tooltip_text = I18nScript.t("Recitation volume")
        ThemeScript.pressable(coin)
        coin.pressed.connect(_rig.toggle)
        right.add_child(coin)
        return row

## The page's first question, asked in the box the design draws it in: the
## card's own white, a gold rule standing round it, and the lens waiting at
## the reading's start -- the way a mushaf's frame holds the words it is
## meant to find. While it is being written in, the rule lifts to the full
## gold, the way the page's questions have always lifted; and a page that
## reads from the right keeps its lens and its entry at the reading's own
## start, the clear button at the reading's end.
func _search_field() -> Control:
        var rtl := I18nScript.is_rtl()
        var field := LineEdit.new()
        field.name = "Search"
        field.placeholder_text = I18nScript.t("Search the deck — a surah, a verse, 2:1…")
        field.custom_minimum_size = Vector2(0, 46)
        field.clear_button_enabled = true
        field.text_direction = (
                TextDirection.TEXT_DIRECTION_RTL if rtl
                else TextDirection.TEXT_DIRECTION_LTR
        )
        if rtl:
                field.alignment = HORIZONTAL_ALIGNMENT_RIGHT
        field.add_theme_font_override("font", ThemeScript.vazir(15))
        field.add_theme_font_size_override("font_size", ThemeScript.fs(15))
        field.add_theme_color_override("font_color", ThemeScript.INK)
        field.add_theme_color_override("font_placeholder_color", ThemeScript.INK_SOFT)
        field.add_theme_color_override("caret_color", ThemeScript.GREEN_DEEP)
        field.add_theme_color_override("selection_color", ThemeScript.SELECT)
        # The box itself: the card's white under a gold rule, rounded the
        # way the cards are rounded.
        var box := ThemeScript.soft_stylebox(ThemeScript.CARD, 14)
        box.set_border_width_all(1)
        box.border_color = Color(
                ThemeScript.GOLD.r, ThemeScript.GOLD.g, ThemeScript.GOLD.b, 0.55
        )
        # The lens keeps its own room at the reading's start, so the words
        # written in never run beneath it.
        box.content_margin_left = 12.0 if rtl else 36.0
        box.content_margin_right = 36.0 if rtl else 12.0
        box.content_margin_top = 10
        box.content_margin_bottom = 10
        field.add_theme_stylebox_override("normal", box)
        var lit := box.duplicate() as StyleBoxFlat
        lit.set_border_width_all(2)
        lit.border_color = ThemeScript.GOLD
        field.add_theme_stylebox_override("hover", lit)
        field.add_theme_stylebox_override("focus", lit)
        # The lens itself: a figure on the card, taking no hand and no
        # room but the margin that was kept for it.
        var lens := ThemeScript.SearchMark.new(Color(
                ThemeScript.GOLD_DEEP.r,
                ThemeScript.GOLD_DEEP.g,
                ThemeScript.GOLD_DEEP.b,
                0.85
        ))
        lens.name = "Lens"
        lens.mouse_filter = Control.MOUSE_FILTER_IGNORE
        lens.anchor_left = 1.0 if rtl else 0.0
        lens.anchor_right = 1.0 if rtl else 0.0
        lens.anchor_top = 0.5
        lens.anchor_bottom = 0.5
        lens.offset_left = -30.0 if rtl else 12.0
        lens.offset_right = -14.0 if rtl else 28.0
        lens.offset_top = -8.0
        lens.offset_bottom = 8.0
        field.add_child(lens)
        field.text_changed.connect(_on_search_changed)
        # The hand's own A: a keyboard wearing Persian sends Ctrl+A as
        # Ctrl+ش, and the field's Latin-born shortcuts never recognise it --
        # the field answers the physical keys instead, so the words a reader
        # typed can be taken whole whatever alphabet the keycaps carry.
        ThemeScript.answer_physical_shortcuts(field)
        return field


## The library's own door, behind a chapter's page: one step back to the
## shelf, the library still standing. The root's bar asks it of the page
## the reader stands on; on the shelf itself the door stands still -- the
## page they are on is the place the door names.
func foot_library_door() -> void:
        if _mode == "surah":
                _back_to_shelf()


## The shelf's other question, asked in pills: the whole story, or one
## thread of it -- what the day is asking for, what has never been started,
## what is resting between reviews. A pill knows its count, so the answer
## is read before it is chosen. The pills are asked in the reading's own
## order: a page that reads from the right begins its shelf with همه at
## the right hand, the way the question occurs to the reader.
func _filters_row() -> Control:
        var flow := HFlowContainer.new()
        flow.name = "Filters"
        flow.add_theme_constant_override("h_separation", 8)
        flow.add_theme_constant_override("v_separation", 6)
        flow.mouse_filter = Control.MOUSE_FILTER_PASS
        if I18nScript.is_rtl():
                flow.layout_direction = Control.LAYOUT_DIRECTION_RTL
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
                                # The counts agree with the home page's pills: a
                                # card taken out of the schedule for good is not
                                # waiting to be learned -- it is a page in the
                                # book, and only the whole shelf counts it.
                                if not SchedulerScript.is_suspended(card.state):
                                        new_count += 1
                        "review":
                                learned += 1
        counts["due"] = _due
        counts["new"] = new_count
        counts["learned"] = learned
        for key in ["all", "due", "new", "learned"]:
                var pill := Button.new()
                pill.name = "Pill" + key.capitalize()
                pill.text = I18nScript.num("%s %d" % [_pill_word(key), counts[key]])
                pill.custom_minimum_size = Vector2(0, 36)
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
                        return I18nScript.t("Due")
                "new":
                        return I18nScript.t("New")
                "learned":
                        return I18nScript.t("In review")
        return I18nScript.t("All")

func _pill_tooltip(key: String) -> String:
        match key:
                "due":
                        return I18nScript.t("What the day is asking for")
                "new":
                        return I18nScript.t("Cards never yet studied")
                "learned":
                        return I18nScript.t("Cards resting between reviews")
        return I18nScript.t("The whole shelf")

## A pill at rest is nothing at all -- words on the paper; the pill that
## is chosen takes the page's own green wash, the colour of the deck's
## progress, with no outline anywhere: the way a book's folios are marked,
## not the way a web form's checkboxes are. A pill sizes itself by its own
## words, so the words must bring their own air with them: without a
## margin of their own they stand on the very edge of the shape, and the
## count reads as though it were escaping the pill it belongs to.
func _dress_pill(pill: Button, on: bool) -> void:
        var rest := ThemeScript.soft_stylebox(Color(0, 0, 0, 0), 18)
        rest.content_margin_left = 14
        rest.content_margin_right = 14
        rest.content_margin_top = 7
        rest.content_margin_bottom = 7
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
        pill.add_theme_font_override("font", ThemeScript.vazir(14, on))
        pill.add_theme_font_size_override("font_size", ThemeScript.fs(14))
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
        ThemeScript.dress(label, 15, ThemeScript.INK_SOFT)
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
        # The scrollbar answers a jump once, not frame after frame the way a
        # drag does, and its one call lands before the container has carried
        # the shelf to its new place -- the running head would read the
        # positions the scroll just left and stay silent about a chapter the
        # eye has already entered. Answer one frame later, when the shelf
        # stands where the scroll put it; a drag asks every frame and is
        # answered every frame.
        scroll.get_v_scroll_bar().value_changed.connect(
                func(_v: float) -> void: call_deferred("_update_sticky")
        )
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
        _sticky_name.add_theme_font_override("font", ThemeScript.font_for("arabic", 17, true))
        _sticky_name.add_theme_font_size_override("font_size", ThemeScript.fs(17))
        _sticky_name.add_theme_color_override("font_color", ThemeScript.GOLD_DEEP)
        row.add_child(_sticky_name)
        _sticky_count = Label.new()
        _sticky_count.name = "Count"
        _sticky_count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
        ThemeScript.dress(_sticky_count, 13, ThemeScript.INK_SOFT)
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
## between reviews. A card taken out of the schedule for good is none of
## the last three -- it stands only on the whole shelf, the way it stands
## only in the book.
func _filter_matches(card: CardScript) -> bool:
        if _filter == "all":
                return true
        if SchedulerScript.is_suspended(card.state):
                return false
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

## The shelf itself, rebuilt whole, after the page's two steps: on the
## shelf of surahs the cards that answer gather by their chapters, and
## behind a chapter's card the chapter's own rows stand in their order.
## The column's own separation is nothing -- the rhythm of the page lives
## in the rows and the hairlines between them, each element carrying its
## own air, the way a book's typesetting does.
func _rebuild() -> void:
        _rebuild_tween = null
        # A new question retires any build still streaming: its batches
        # must not lay another row onto a shelf this pass has already
        # cleared.
        _build_gen += 1
        var column: VBoxContainer = get_node("Margin/Column/Scroll/Wrap/Column")
        for child in column.get_children():
                column.remove_child(child)
                child.queue_free()
        _open_row = null
        if _mode == "shelf":
                _rebuild_shelf(column)
        else:
                _rebuild_pages(column)

## The shelf of surahs: the deck's cards gathered by their chapters, each
## chapter one card on the shelf -- its name, the mushaf's number, its
## ring, its gold dot when the day asks something of it. The shelf answers
## the same questions the pages answer: a chapter stands here when any of
## its cards answers the search and the filter, so a verse's own words
## lead to the chapter that holds it. The ring and the count are the
## chapter's own facts, gathered from the whole chapter -- a chapter's
## standing does not change because the shelf was narrowed to reach it.
func _rebuild_shelf(column: VBoxContainer) -> void:
        var stats := _surah_stats()
        var groups: Array = []
        var seen := {}
        var shown := 0
        for card in _deck.cards:
                if not _matches(card):
                        continue
                shown += 1
                var surah := _surah_of(_reference_of(card))
                if not seen.has(surah):
                        seen[surah] = true
                        groups.append(surah)
        var summary: Label = get_node("Margin/Column/Summary")
        var asking := not _query.strip_edges().is_empty() or _filter != "all"
        # The shelf's account of itself is spoken only while a question
        # stands: at rest the pills already carry their counts, and a line
        # that repeats them is a dashboard, not a book.
        summary.visible = asking
        if asking:
                summary.text = I18nScript.f("%d of %d cards", [shown, _deck.cards.size()])
        if groups.is_empty():
                _pending = []
                _shelf = {}
                column.add_child(_empty_state())
                _update_sticky()
                return
        var grid := GridContainer.new()
        grid.name = "Shelf"
        grid.columns = 2
        grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        grid.add_theme_constant_override("h_separation", 14)
        grid.add_theme_constant_override("v_separation", 14)
        grid.mouse_filter = Control.MOUSE_FILTER_PASS
        column.add_child(grid)
        _shelf = {"gen": _build_gen, "mode": "shelf", "stats": stats, "laid": 0}
        _pending = groups
        # The opening breath: a screenful laid at once, so the page opens
        # on a shelf and not on a promise -- then the rest stream in.
        _lay_batch(SHELF_FIRST)
        call_deferred("_fit_rows")
        if not asking:
                ThemeScript.stagger_in(grid, minf(0.03, 0.55 / maxf(grid.get_child_count(), 1.0)), 0.18)
        if _pending.is_empty():
                _close_shelf()
        else:
                set_process(true)
        _update_sticky()

## Every chapter's own facts, gathered in one pass: how many cards it
## holds, how many rest in review, whether the day asks anything of it,
## and the mushaf's own number for it -- said by the first of its cards
## that carries an address (2:1), the way the book numbers its chapters.
## A chapter whose cards name no address stands unnumbered; the shelf
## never invents what the deck does not say.
func _surah_stats() -> Dictionary:
        var stats := {}
        var now := int(Time.get_unix_time_from_system())
        for card in _deck.cards:
                var surah := _surah_of(_reference_of(card))
                if not stats.has(surah):
                        stats[surah] = {"total": 0, "learned": 0, "due": 0, "number": 0}
                var one: Dictionary = stats[surah]
                one["total"] = int(one["total"]) + 1
                if str(card.state["status"]) == "review":
                        one["learned"] = int(one["learned"]) + 1
                if _is_due(card):
                        one["due"] = int(one["due"]) + 1
                if int(one["number"]) == 0:
                        for address in _addresses_of(card):
                                var colon := address.find(":")
                                if colon > 0:
                                        var head := address.substr(0, colon)
                                        if head.is_valid_int():
                                                one["number"] = int(head)
                                                break
        return stats

## One chapter's own page: the cards of the surah whose card the reader
## touched, under the chapter's own header, in the deck's order -- the
## rows the library has always read, answering the same search and the
## same filter the shelf answered.
func _rebuild_pages(column: VBoxContainer) -> void:
        var shown: Array = []
        for card in _deck.cards:
                if _matches(card) and _surah_of(_reference_of(card)) == _open_surah:
                        shown.append(card)
        var summary: Label = get_node("Margin/Column/Summary")
        var asking := not _query.strip_edges().is_empty() or _filter != "all"
        summary.visible = asking
        if asking:
                summary.text = I18nScript.f("%d of %d cards", [shown.size(), _deck.cards.size()])
        if shown.is_empty():
                _pending = []
                _shelf = {}
                column.add_child(_empty_state())
                _update_sticky()
                return
        _shelf = {"gen": _build_gen, "surah": "", "in_surah": 0, "resting": 0}
        _pending = shown
        # The opening breath: a screenful laid at once, so the page opens
        # on a shelf and not on a promise -- then the rest stream in.
        _lay_batch(SHELF_FIRST)
        call_deferred("_fit_rows")
        if not asking:
                ThemeScript.stagger_in(column, minf(0.015, 0.55 / maxf(column.get_child_count(), 1.0)), 0.18)
        if _pending.is_empty():
                _close_shelf()
        else:
                set_process(true)
        _update_sticky()

## The opening breath, or any whole batch asked for at once: as many
## cards as count says, budget or no budget.
func _lay_batch(count: int) -> void:
        for _i in count:
                if _pending.is_empty():
                        return
                _lay_one()

## One card onto the shelf, one step at a time: on the shelf of surahs a
## chapter's card onto the grid, and behind a chapter's card the surah's
## header when the rows cross into it, the card's row after, and the
## counts the header will stand by. The walk is the page's own -- only
## its reach is a slice's.
func _lay_one() -> void:
        var column: VBoxContainer = get_node("Margin/Column/Scroll/Wrap/Column")
        var item: Variant = _pending.pop_front()
        if _mode == "shelf":
                column.get_node("Shelf").add_child(
                        _surah_card(str(item), _shelf["stats"])
                )
                return
        var card: CardScript = item
        var reference := _reference_of(card)
        var card_surah := _surah_of(reference)
        if card_surah != str(_shelf["surah"]):
                if not str(_shelf["surah"]).is_empty():
                        _set_header_count(column, int(_shelf["in_surah"]), int(_shelf["resting"]))
                _shelf["surah"] = card_surah
                _shelf["in_surah"] = 0
                _shelf["resting"] = 0
                column.add_child(_surah_header(card_surah, card.id))
        _shelf["in_surah"] = int(_shelf["in_surah"]) + 1
        if str(card.state["status"]) == "review":
                _shelf["resting"] = int(_shelf["resting"]) + 1
        column.add_child(_entry(card, reference))

## The shelf's last word: the final header's count where headers stand,
## the breathing room under the last row or the last card, and the
## running head's own account of the page.
func _close_shelf() -> void:
        var column: VBoxContainer = get_node("Margin/Column/Scroll/Wrap/Column")
        if _mode != "shelf":
                _set_header_count(column, int(_shelf["in_surah"]), int(_shelf["resting"]))
        var tail := Control.new()
        tail.name = "Tail"
        tail.custom_minimum_size = Vector2(0, 18)
        tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
        column.add_child(tail)
        call_deferred("_fit_rows")
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
        ThemeScript.dress(lead, ThemeScript.BODY + 1, ThemeScript.INK)
        lead.text = _empty_lead()
        box.add_child(lead)
        var under := Label.new()
        under.name = "Under"
        under.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        ThemeScript.dress(under, 15, ThemeScript.INK_SOFT)
        under.text = _empty_under()
        box.add_child(under)
        return box

func _empty_lead() -> String:
        if not _query.strip_edges().is_empty():
                return I18nScript.t("No cards answer")
        match _filter:
                "due":
                        return I18nScript.t("Nothing is due today")
                "new":
                        return I18nScript.t("Every card has been started")
                "learned":
                        return I18nScript.t("Nothing rests between reviews yet")
        return I18nScript.t("The shelf is empty")

func _empty_under() -> String:
        if not _query.strip_edges().is_empty():
                return I18nScript.t("Try fewer words, or the verse's address — 2:1.")
        match _filter:
                "due":
                        return I18nScript.t("The deck rests, and so can its reader.")
                "new":
                        return I18nScript.t("The whole deck is under way.")
                "learned":
                        return I18nScript.t("Cards land here once reviews carry them.")
        return I18nScript.t("A deck of folders and files, read from its own shelf.")

## The count and the rest a surah's title carries, written into the header
## that waits for them at the top of its own run of cards. How many rest in
## review is said in words beside the count -- a thread under the name
## says it only as a line that looks broken until it is full, and a
## chapter's opening should never look like a mistake.
func _set_header_count(column: VBoxContainer, count: int, resting: int) -> void:
        var header: VBoxContainer = null
        for child in column.get_children():
                if child.name.begins_with("Header"):
                        header = child
        if header != null:
                var cards := (
                        I18nScript.f("%d card", [count])
                        if count == 1
                        else I18nScript.f("%d cards", [count])
                )
                var line := cards
                if resting > 0:
                        line += " · " + I18nScript.f("%d in review", [resting])
                (header.get_node("Line/Count") as Label).text = line

## A surah's own opening: its name in the gold of citations at a
## chapter's own size, a small star before it the way a mushaf marks its
## surahs, its count at the far end saying in words how many of its cards
## rest in review. A chapter opens with the air of a page break, not with
## a banner: the name must be able to stand beside the verses it governs
## without shouting over them.
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
                ThemeScript.reference_script(surah), 23, true
        ))
        label.add_theme_font_size_override("font_size", ThemeScript.fs(23))
        label.add_theme_color_override("font_color", ThemeScript.GOLD_DEEP)
        line.add_child(label)
        var count := Label.new()
        count.name = "Count"
        count.text = ""
        count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
        # A folio number: small, quiet, ink -- the way a book numbers its
        # leaves at a chapter's opening.
        ThemeScript.dress(count, 12, ThemeScript.INK_SOFT)
        line.add_child(count)
        box.add_child(line)
        return box

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
        # mushaf cut at a size its vowels keep every curl -- and with the
        # room the ink asks for, so a mark stacked past its font's own box
        # is drawn whole, never cut into the row above.
        var preview_text := _preview_of(card)
        if not preview_text.is_empty():
                var preview := Label.new()
                preview.name = "Preview"
                preview.text = preview_text
                preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
                preview.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
                preview.text_direction = TextDirection.TEXT_DIRECTION_AUTO
                preview.clip_text = true
                preview.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
                var preview_script := ThemeScript.script_of(preview_text)
                var preview_face: Font = ThemeScript.verse_face(preview_script)
                var preview_size := ThemeScript.fs(27 if preview_script == "arabic" else 15)
                preview.add_theme_font_override("font", preview_face)
                preview.add_theme_font_size_override("font_size", preview_size)
                preview.add_theme_color_override("font_color", ThemeScript.INK)
                ThemeScript.give_label_room(preview, preview_text, preview_face, preview_size)
                words.add_child(preview)

        # The verse's other half: its Persian, one quiet line under the Arabic,
        # so a reader hunting a card by what it means finds it as surely as a
        # reader hunting by what it says. It is the shelf's own voice at a
        # whisper -- ink soft, one line, its tail trimmed with an ellipsis
        # rather than cut mid-letter -- and it stands flush right, the edge
        # the translation itself is read from.
        var translation_text := _translation_of(card)
        if not translation_text.is_empty():
                var translation := Label.new()
                translation.name = "Translation"
                translation.text = translation_text
                translation.size_flags_horizontal = Control.SIZE_EXPAND_FILL
                translation.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
                translation.text_direction = TextDirection.TEXT_DIRECTION_AUTO
                translation.clip_text = true
                translation.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
                var t_size := ThemeScript.fs(14)
                translation.add_theme_font_override("font", ThemeScript.font_for("persian", 14))
                translation.add_theme_font_size_override("font_size", t_size)
                translation.add_theme_color_override("font_color", ThemeScript.INK_SOFT)
                words.add_child(translation)

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
                ThemeScript.dress(status, 13, standing["color"], true)
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
        var script := ThemeScript.reference_script(reference)
        ref_label.add_theme_font_override("font", ThemeScript.font_for(script, 15, true))
        ref_label.add_theme_font_size_override("font_size", ThemeScript.fs(15 if script == "arabic" else 13))
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
        # the padding that lets the verse breathe. The number is spoken
        # twice: this first word is only a guess, because a Label keeps
        # its first account of itself -- the default face at its own size
        # -- until a layout asks for better, so a shelf sized by this call
        # alone stands shorter than its own words and the row's box cuts
        # its meta line out under its floor. _fit_row says the number the
        # pad stands by once the page has been laid out, and the pad's own
        # signal covers every later change the same way.
        pad.minimum_size_changed.connect(_fit_row.bind(row, pad))
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

## The height of every row on the shelf, said once the page has been laid
## out. The call that builds a row measures its pad before anything has
## arranged it, and a Label holds its first account of itself -- the
## default face at its own size -- until a layout asks for better, so a
## shelf sized only at its building stands shorter than its own words: the
## row's rounded box cuts the meta line out under its floor, and the
## standing and the pointer hang outside the box they belong to. This
## pass -- deferred to the end of the frame in which the shelf was built --
## says the number the pad now stands by; the pad's own signal answers
## every later change the same way. The grid's cards answer the same law
## and are fitted the same way.
func _fit_rows() -> void:
        var column: VBoxContainer = get_node_or_null("Margin/Column/Scroll/Wrap/Column")
        if column == null:
                return
        for entry in column.get_children():
                if entry.name.begins_with("Entry"):
                        var row: Button = entry.get_node_or_null("Row")
                        var row_pad: MarginContainer = entry.get_node_or_null("Row/Pad")
                        if row != null and row_pad != null:
                                _fit_row(row, row_pad)
                elif entry.name.begins_with("Shelf"):
                        for card in entry.get_children():
                                if not card.name.begins_with("SurahCard"):
                                        continue
                                var card_pad: MarginContainer = card.get_node_or_null("Pad")
                                if card_pad != null:
                                        _fit_card(card, card_pad)

## One card on the shelf says its own height: never below the least a
## card can breathe (168 -- the arch's own measure), and never other than
## what its words cost, the same law a row keeps.
func _fit_card(card: Button, pad: MarginContainer) -> void:
        var needed := maxf(pad.get_combined_minimum_size().y, 168.0)
        if absf(card.custom_minimum_size.y - needed) < 0.5:
                return
        card.custom_minimum_size = Vector2(0, needed)

## One row says its own height: never below the least a row can breathe
## (92), and never other than what its words cost -- a row taller than its
## own line only pads the shelf with air.
func _fit_row(row: Button, pad: MarginContainer) -> void:
        var needed := maxf(pad.get_combined_minimum_size().y, 92.0)
        if absf(row.custom_minimum_size.y - needed) < 0.5:
                return
        row.custom_minimum_size = Vector2(0, needed)

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

## One surah's card on the shelf: a white page wearing its arch -- the
## outline a mushaf sets above its chapter's heading -- with the name in
## the gold of citations inside it, the mushaf's own number beneath it
## when the deck says one, the chapter's ring, and the share the ring
## carries said again in words under it; the gold dot at the reading's
## far corner when the day asks something of the chapter. The whole card
## is one button: its press opens the chapter's own page. A Button is no
## Container, so the card says its own height from the pad's account of
## its words, the same law a row keeps.
func _surah_card(surah: String, stats: Dictionary) -> Button:
        var one: Dictionary = stats.get(
                surah, {"total": 0, "learned": 0, "due": 0, "number": 0}
        )
        var card := Button.new()
        card.name = "SurahCard" + str(int(_shelf.get("laid", 0)) + 1)
        _shelf["laid"] = int(_shelf.get("laid", 0)) + 1
        card.toggle_mode = false
        card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        card.size_flags_vertical = Control.SIZE_EXPAND_FILL
        var rest := ThemeScript.card_stylebox()
        var visited := rest.duplicate() as StyleBoxFlat
        visited.bg_color = ThemeScript.GREEN_SOFT
        card.add_theme_stylebox_override("normal", rest)
        card.add_theme_stylebox_override("hover", visited)
        card.add_theme_stylebox_override("pressed", visited)
        card.add_theme_stylebox_override("focus", visited)
        card.add_theme_stylebox_override("disabled", rest)
        ThemeScript.pressable(card)
        card.pressed.connect(_open_surah_view.bind(surah))

        # The arch: a hairline of gold with no floor, drawn where the
        # mushaf draws its chapter's heading. It anchors itself to the
        # card's own height -- the upper half, down to where the ring
        # begins -- and asks for no input, the way an outline drawn on the
        # page asks for nothing but the eye.
        var arch := Panel.new()
        arch.name = "Arch"
        arch.mouse_filter = Control.MOUSE_FILTER_IGNORE
        arch.set_anchors_preset(Control.PRESET_FULL_RECT)
        arch.anchor_bottom = 0.54
        arch.offset_left = 14.0
        arch.offset_right = -14.0
        arch.offset_top = 8.0
        arch.offset_bottom = 0.0
        var outline := ThemeScript.soft_stylebox(Color(0, 0, 0, 0), 0)
        outline.border_color = Color(
                ThemeScript.GOLD.r, ThemeScript.GOLD.g, ThemeScript.GOLD.b, 0.5
        )
        outline.set_border_width_all(1)
        outline.set_border_width(SIDE_BOTTOM, 0)
        outline.set_corner_radius_all(0)
        outline.corner_radius_top_left = 120
        outline.corner_radius_top_right = 120
        arch.add_theme_stylebox_override("panel", outline)
        card.add_child(arch)

        # The day's gold dot at the reading's far corner: where the eye's
        # sweep across the shelf lands last, the way a book's own margin
        # carries its marks.
        if int(one["due"]) > 0:
                var dot := ThemeScript.StatusDot.new(ThemeScript.GOLD_DEEP)
                dot.name = "Due"
                if I18nScript.is_rtl():
                        dot.anchor_left = 0.0
                        dot.anchor_right = 0.0
                        dot.offset_left = 14.0
                        dot.offset_right = 23.0
                else:
                        dot.anchor_left = 1.0
                        dot.anchor_right = 1.0
                        dot.offset_left = -23.0
                        dot.offset_right = -14.0
                dot.anchor_top = 0.0
                dot.anchor_bottom = 0.0
                dot.offset_top = 14.0
                dot.offset_bottom = 23.0
                card.add_child(dot)

        var pad := MarginContainer.new()
        pad.name = "Pad"
        pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
        pad.add_theme_constant_override("margin_left", 12)
        pad.add_theme_constant_override("margin_right", 12)
        pad.add_theme_constant_override("margin_top", 26)
        pad.add_theme_constant_override("margin_bottom", 14)
        card.add_child(pad)

        var words := VBoxContainer.new()
        words.name = "Words"
        words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        words.add_theme_constant_override("separation", 5)
        words.mouse_filter = Control.MOUSE_FILTER_IGNORE
        pad.add_child(words)

        # The chapter's name, inside its arch: the gold of citations at the
        # size a chapter's own heading wears in a book's index -- present,
        # never shouting -- centred the way a mushaf centres its headings.
        var face := ThemeScript.font_for(
                ThemeScript.reference_script(surah), 17, true
        )
        var fsize := ThemeScript.fs(17)
        var name_label := Label.new()
        name_label.name = "Name"
        name_label.text = surah
        name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        name_label.text_direction = TextDirection.TEXT_DIRECTION_AUTO
        name_label.clip_text = true
        name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
        name_label.add_theme_font_override("font", face)
        name_label.add_theme_font_size_override("font_size", fsize)
        name_label.add_theme_color_override("font_color", ThemeScript.GOLD_DEEP)
        ThemeScript.give_label_room(name_label, surah, face, fsize)
        words.add_child(name_label)

        # The mushaf's own number for the chapter, said small beneath the
        # name -- a folio's whisper, not a figure's shout. A chapter the
        # deck numbers nowhere stands here with its name alone.
        if int(one["number"]) > 0:
                var number_label := Label.new()
                number_label.name = "Number"
                number_label.text = I18nScript.f("Surah %d", [int(one["number"])])
                number_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
                number_label.clip_text = true
                number_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
                ThemeScript.dress(number_label, 12, ThemeScript.INK_SOFT)
                words.add_child(number_label)

        # The chapter's ring: the share of its cards resting in review,
        # drawn around the share itself in the reader's own digits.
        var share := 0
        if int(one["total"]) > 0:
                share = int(round(100.0 * int(one["learned"]) / int(one["total"])))
        var ring := ThemeScript.ProgressRing.new(share)
        ring.name = "Ring"
        ring.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        words.add_child(ring)

        # The ring's fraction in words: what rests and what the chapter
        # holds -- the same numbers the ring is drawn from, named the way
        # the headers name a chapter's count.
        var count_label := Label.new()
        count_label.name = "Count"
        count_label.text = I18nScript.f(
                "%d of %d cards", [int(one["learned"]), int(one["total"])]
        )
        count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        count_label.clip_text = true
        count_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
        ThemeScript.dress(count_label, 12, ThemeScript.INK_SOFT)
        words.add_child(count_label)

        pad.minimum_size_changed.connect(_fit_card.bind(card, pad))
        card.custom_minimum_size = Vector2(
                0,
                maxf(pad.get_combined_minimum_size().y, 168.0),
        )
        return card

## The chapter's door: its card was touched, so the page behind it opens.
## The page's own furniture follows -- the title carries the chapter's
## name, and the way back at the reading's start points to the shelf.
func _open_surah_view(surah: String) -> void:
        _mode = "surah"
        _open_surah = surah
        _dress_chrome()
        _rebuild()

## The way back out of a chapter: the shelf again, the page's furniture
## saying the library's own name once more.
func _back_to_shelf() -> void:
        _mode = "shelf"
        _open_surah = ""
        _dress_chrome()
        _rebuild()

## The back button's own door: on the shelf it leaves the library; behind
## a chapter's card it returns to the shelf first. One button, the step
## the page stands on.
func _go_back() -> void:
        if _mode == "surah":
                _back_to_shelf()
        else:
                closed.emit()

## The page's furniture follows its two steps: on the shelf the title is
## the library's and the way back leads home; behind a chapter's card the
## title is the chapter, in the face the chapter's own name is read in.
## The running head needs no telling -- it rides only where chapters'
## headers stand, and the shelf has none.
func _dress_chrome() -> void:
        var title: Label = get_node_or_null("Margin/Column/TopBar/Title")
        var back: Button = get_node_or_null("Margin/Column/TopBar/Back")
        if title == null or back == null:
                return
        if _mode == "surah":
                title.text = _open_surah
                title.add_theme_font_override(
                        "font",
                        ThemeScript.font_for(
                                ThemeScript.reference_script(_open_surah),
                                ThemeScript.TITLE,
                                true,
                        )
                )
                back.tooltip_text = I18nScript.t("Back to the shelf")
        else:
                title.text = I18nScript.t("Browse")
                title.add_theme_font_override(
                        "font", ThemeScript.vazir(ThemeScript.TITLE, true)
                )
                back.tooltip_text = I18nScript.t("Back to home")

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
        pad.add_theme_constant_override("margin_bottom", 20)
        panel.add_child(pad)
        var page := VBoxContainer.new()
        page.name = "Page"
        page.add_theme_constant_override("separation", 14)
        pad.add_child(page)
        var view := CardViewScript.new(_player)
        view.name = "View"
        view.show_text(card.back, card.folder)
        page.add_child(view)
        page.add_child(_pencil_row(card))

## The pencil at the page's foot, inside the card the way a margin note is
## kept inside its leaf -- not a pill cast on the desk below the page,
## where it reads as a button that belongs to no card. One quiet line in
## the gold of the citation above it: the drawn pencil, its words, and a
## breath of gold while the hand is over them.
func _pencil_row(card: CardScript) -> Control:
        var edit := Button.new()
        edit.name = "Edit"
        edit.tooltip_text = I18nScript.t("Edit this card")
        edit.custom_minimum_size = Vector2(148, 44)
        # The pencil sits at the edge its page reads from -- the left edge in
        # a left-reading tongue, the right edge in a right-reading one -- so
        # the card's own tool answers from the corner its reader starts at.
        edit.size_flags_horizontal = (
                Control.SIZE_SHRINK_END if I18nScript.is_rtl() else Control.SIZE_SHRINK_BEGIN
        )
        var rest := ThemeScript.soft_stylebox(Color(0, 0, 0, 0), 10)
        var held := ThemeScript.soft_stylebox(
                Color(ThemeScript.GOLD.r, ThemeScript.GOLD.g, ThemeScript.GOLD.b, 0.10), 10
        )
        edit.add_theme_stylebox_override("normal", rest)
        edit.add_theme_stylebox_override("hover", held)
        edit.add_theme_stylebox_override("pressed", held)
        var ring := ThemeScript.soft_stylebox(Color(0, 0, 0, 0), 10)
        ring.border_color = Color(ThemeScript.GOLD.r, ThemeScript.GOLD.g, ThemeScript.GOLD.b, 0.55)
        ring.set_border_width_all(2)
        edit.add_theme_stylebox_override("focus", ring)
        ThemeScript.pressable(edit)
        edit.pressed.connect(_open_editor.bind(card))
        var inside := MarginContainer.new()
        inside.name = "Pad"
        inside.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        inside.mouse_filter = Control.MOUSE_FILTER_IGNORE
        inside.add_theme_constant_override("margin_left", 14)
        inside.add_theme_constant_override("margin_right", 20)
        var words := HBoxContainer.new()
        words.name = "Row"
        words.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
        words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        words.add_theme_constant_override("separation", 10)
        words.mouse_filter = Control.MOUSE_FILTER_IGNORE
        # The mark leads the words from the reading's own end: a right-reading
        # row mirrors, so the pencil stands where the eye starts.
        if I18nScript.is_rtl():
                words.layout_direction = Control.LAYOUT_DIRECTION_RTL
        inside.add_child(words)
        var pencil := ThemeScript.PencilMark.new(ThemeScript.GOLD_DEEP)
        pencil.name = "Pencil"
        pencil.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        words.add_child(pencil)
        var label := Label.new()
        label.name = "Words"
        label.text = I18nScript.t("Edit card")
        label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        ThemeScript.dress(label, 14, ThemeScript.GOLD_DEEP, true)
        words.add_child(label)
        edit.add_child(inside)
        return edit

func _set_row_open(row: Button, open: bool) -> void:
        var mark: ThemeScript.DisclosureMark = row.get_node("Pad/Line/Words/Meta/Disclose")
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
        (entry.get_node("Row/Pad/Line/Words/Meta/Ref") as Label).text = _reference_of(card)
        var detail: VBoxContainer = entry.get_node("Detail")
        if detail.visible:
                _fill_detail(detail, card)
                ThemeScript.settle_in(detail, 0.0, 0.24)

# --- the card's own words ------------------------------------------------------------

## The reference the card asks for: the first plain line of its front, or
## its id when the front says nothing -- one law with home and the editor
## (MarkdownScript.first_plain_line), so a card is called the same thing
## everywhere it is named.
func _reference_of(card: CardScript) -> String:
        var reference := MarkdownScript.first_plain_line(card.front)
        return reference if not reference.is_empty() else card.id

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

## The verse's Persian, for the row's second line: the first text block that
## reads in Persian -- the deck's own translation, the half the Arabic above
## it is speaking to. A deck without a Persian half falls back to its second
## text block, so the shelf still says what the card answers with.
func _translation_of(card: CardScript) -> String:
        var blocks: Array[String] = []
        for block in MarkdownScript.parse(card.back):
                if block.kind != "text":
                        continue
                var plain := MarkdownScript.plain(block.text).strip_edges()
                if plain.is_empty():
                        continue
                if ThemeScript.script_of(plain) == "persian":
                        return plain
                blocks.append(plain)
        # No Persian half: the verse itself stood first; the next text
        # block is the best remaining witness to what the card means.
        return blocks[1] if blocks.size() > 1 else ""

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
                                return {"text": I18nScript.t("due now"), "color": ThemeScript.GOLD_DEEP, "hollow": false}
                        return {
                                "text": I18nScript.f("in %s", [I18nScript.wait(due)]),
                                "color": ThemeScript.GOLD_DEEP,
                                "hollow": false,
                        }
                "review":
                        var today_idx := SchedulerScript.today(now)
                        if int(state["due_day"]) <= today_idx:
                                return {"text": I18nScript.t("due today"), "color": ThemeScript.GOLD_DEEP, "hollow": false}
                        return {
                                "text": I18nScript.f(
                                        "in %s",
                                        [I18nScript.wait((int(state["due_day"]) - today_idx) * 86400)]
                                ),
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
        # The page's ground ends a breath above the doors at its foot: the
        # height the theme says the root's bar takes, and nothing of the
        # shelf beneath it.
        margin.add_theme_constant_override("margin_bottom", int(ThemeScript.foot_height() + 12.0))
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
        # The volume's page hangs from its own coin, wherever the bar put
        # it -- centred under the coin, its roof pointing up at it.
        var popup: Control = get_node_or_null("VolumePopup")
        if popup != null:
                ThemeScript.place_popover(popup, get_node("Margin/Column/TopBar/Right/Volume"))

## The shelf answers the keyboard as a shelf: the arrows walk the rows or
## the grid's cards, one at a time, and Enter opens what stands under the
## hand.
func _row_buttons() -> Array:
        var rows := []
        var column: VBoxContainer = get_node_or_null("Margin/Column/Scroll/Wrap/Column")
        if column == null:
                return rows
        if _mode == "shelf":
                var grid: GridContainer = column.get_node_or_null("Shelf")
                if grid == null:
                        return rows
                for card in grid.get_children():
                        if card.name.begins_with("SurahCard"):
                                rows.append(card)
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
                        elif _mode == "surah":
                                _back_to_shelf()
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


## The phone's back key asks the same question Esc asks, in the same
## order: the editor over the page first, then the volume's popover, then
## the search field's own keys, then the way back out of a chapter to its
## shelf, and only then the page itself.
func request_back() -> bool:
        var editor := get_node_or_null("Editor") as CardEditorScript
        if editor != null:
                return editor.request_back()
        var popup := get_node_or_null("VolumePopup")
        if popup != null and popup.visible:
                popup.visible = false
                return true
        var search: LineEdit = get_node_or_null("Margin/Column/Search")
        if search != null and search.has_focus():
                search.release_focus()
                return true
        if _mode == "surah":
                _back_to_shelf()
                return true
        closed.emit()
        return true
