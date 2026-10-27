extends SceneTree
const ThemeScript := preload("res://scripts/ui/theme.gd")
const TouchScrollScript := preload("res://scripts/ui/touch_scroll.gd")
const CopyChipScript := preload("res://scripts/ui/copy_chip.gd")
const SelectHandlesScript := preload("res://scripts/ui/select_handles.gd")

## A phone's finger, replayed event by event through the engine's own
## input path: the page under a shelf of buttons must scroll, a tap must
## still click, a field that owns its drags must keep them, and a scroll
## that ends where it began must not land as a click. Every event is a
## real touch (a device the engine does not reserve for emulation), so
## the mouse echo the engine makes from it -- the echo that clicks
## buttons on a phone -- rides along exactly as it does in a hand.
##
## The ink has manners too, and they are sworn to here: a finger dragging
## on the app's own selectable words is a scroll and chooses nothing (the
## report that began this -- a scroll met a wash of chosen words); a
## finger resting on the words chooses the word under it; the resting
## finger's drag widens the choice while the page holds still; a lift
## leaves the choice standing; a tap on the ink lets it go; and a desk's
## mouse still draws a choice the old way, press and drag.

var _failures := 0

func _init() -> void:
        # The desk's mouse must not breed phantom fingers: these laws push
        # raw touches of their own, and the mouse laws at the end need a
        # mouse that stays a mouse.
        Input.emulate_touch_from_mouse = false
        _fresh_install()
        await _check_own_page()
        await _check_real_shelf()
        await _check_the_ink_answers_a_finger()
        await _check_the_real_session_ink()
        if _failures > 0:
                print("touch-scroll: %d FAILURE(S)" % _failures)
                quit(1)
        else:
                print("touch-scroll: all checks passed")
                quit(0)


# --- a page built like the shelf -------------------------------------------------


## The law is measured on the app's own shapes: a scroller full of
## button rows, a field that owns its drags, a rule the thumb slides --
## and the same scroller again through the real library, rows and all.
func _check_own_page() -> void:
        var page := Control.new()
        page.name = "Page"
        page.set_anchors_preset(Control.PRESET_FULL_RECT)
        root.add_child(page)

        var scroll := ScrollContainer.new()
        scroll.name = "Scroll"
        scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
        scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
        ThemeScript.style_scroll(scroll)
        page.add_child(scroll)

        var column := VBoxContainer.new()
        column.name = "Column"
        column.add_theme_constant_override("separation", 6)
        column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        scroll.add_child(column)

        var clicks := {}
        for row in 30:
                var button := Button.new()
                button.name = "Row%d" % row
                button.text = "Row %d" % row
                button.custom_minimum_size = Vector2(0, 64)
                button.pressed.connect(func() -> void: clicks[row] = true)
                column.add_child(button)
        var field := LineEdit.new()
        field.name = "Field"
        field.custom_minimum_size = Vector2(0, 48)
        column.add_child(field)
        var rule := HSlider.new()
        rule.name = "Rule"
        rule.custom_minimum_size = Vector2(320, 44)
        column.add_child(rule)

        var touch := TouchScrollScript.new()
        touch.name = "TouchScroll"
        page.add_child(touch)

        await process_frame
        await process_frame
        _ok(scroll.get_v_scroll_bar().max_value > 100.0, "the page is long enough to scroll")

        # A tap still clicks: the echo the engine makes from the touch is
        # the hand's click, and it is never shown out.
        var row5: Button = page.get_node("Scroll/Column/Row5")
        await _tap(row5.get_global_rect().get_center())
        await process_frame
        _ok(clicks.has(5), "a tap on a row still clicks it")

        # A finger that travels less than the slop is a tap, not a scroll:
        # the click lands and the page has not moved.
        var row6: Button = page.get_node("Scroll/Column/Row6")
        await _tap_with_jitter(row6.get_global_rect().get_center())
        await process_frame
        _ok(clicks.has(6), "a jittery tap still clicks")
        _ok(is_equal_approx(scroll.scroll_vertical, 0.0), "a jittery tap does not scroll")

        # The page follows the finger over the buttons: down drags the
        # content down (the scroll's own number falls), up raises it. Both
        # are measured from the page's middle, where neither edge can
        # clamp the answer.
        var row10: Button = page.get_node("Scroll/Column/Row10")
        var travel := 80.0
        scroll.scroll_vertical = 300.0
        await process_frame
        await _drag_finger(row10.get_global_rect().get_center(), Vector2(0, travel), 4)
        await process_frame
        _ok(
                absf(scroll.scroll_vertical - 220.0) < 6.0,
                "a finger dragging down scrolls the content down (%.1f)" % scroll.scroll_vertical
        )
        await _drag_finger(Vector2(210, 400), Vector2(0, -travel), 4)
        await process_frame
        _ok(absf(scroll.scroll_vertical - 300.0) < 6.0, "a finger dragging up scrolls the content back up")

        # A field that owns its drags keeps them: dragging inside the
        # line does not move the page behind it. The field and the rule
        # sit at the page's far end, so the shelf is scrolled to them
        # first -- a press off the page tests nothing.
        scroll.scroll_vertical = 1400.0
        await process_frame
        _ok(
                field.get_global_rect().position.y > 0.0 and field.get_global_rect().position.y < 760.0,
                "the field is on the page where a finger can reach it"
        )
        await _drag_finger(field.get_global_rect().get_center(), Vector2(0, travel), 4)
        await process_frame
        _ok(absf(scroll.scroll_vertical - 1400.0) < 6.0, "a drag in the field does not scroll the page")
        var rule_before := rule.value
        await _drag_finger(rule.get_global_rect().get_center(), Vector2(60, 0), 4)
        await process_frame
        _ok(absf(scroll.scroll_vertical - 1400.0) < 6.0, "a drag on the rule does not scroll the page")
        _ok(not is_equal_approx(rule.value, rule_before), "the rule's own drag still moves the rule")

        # A scroll that begins and ends inside one row must not land as a
        # click on that row: the hand left it when the page began to move.
        # The drag stays inside the row's own height, so only the scroller's
        # word to the row -- the hand has left -- stands between the
        # release and a click. The page is settled below its top first: a
        # scroll's content moves on the next frame, and a rect read before
        # that names a place the row has already left -- and a page dragged
        # down at its very top has nowhere to go.
        scroll.scroll_vertical = 100.0
        await process_frame
        var row3: Button = page.get_node("Scroll/Column/Row3")
        var at := row3.get_global_rect().get_center()
        _press(at)
        var walked_from := at
        for step in 4:
                walked_from = at + Vector2(0, 6.0 * (step + 1))
                _drag_by(at + Vector2(0, 6.0 * step), walked_from)
                await process_frame
        _release(walked_from)
        await process_frame
        await process_frame
        _ok(not clicks.has(3), "a scroll that ends inside its own row does not click it")
        _ok(absf(scroll.scroll_vertical - 82.0) < 6.0, "that same drag did scroll the page (%.1f)" % scroll.scroll_vertical)

        # Let go with speed and the page carries on alone, slowing as
        # paper slows -- and any new finger catches it. The drags are
        # spaced by real time, not frames: the engine reads a finger's
        # speed only from a run of drags at least a tenth of a second
        # long, and a headless frame costs no clock at all.
        scroll.scroll_vertical = 0.0
        await process_frame
        var start := Vector2(210, 300)
        var walked := start
        _press(start)
        for step in 8:
                var to := start + Vector2(0, -40.0 * (step + 1))
                _drag_by(walked, to)
                walked = to
                await create_timer(0.02).timeout
        _release(walked)
        var at_release := scroll.scroll_vertical
        await create_timer(0.25).timeout
        var coasted := scroll.scroll_vertical
        _ok(coasted > at_release + 30.0, "a fast release carries the page on (%.1f past %.1f)" % [coasted, at_release])
        _ok(coasted < at_release + 540.0, "the coast is bounded, not a flight")
        var catch_at := Vector2(210, 200)
        _press(catch_at)
        await process_frame
        var caught := scroll.scroll_vertical
        await create_timer(0.4).timeout
        _ok(
                absf(scroll.scroll_vertical - caught) < 2.0,
                "a new finger catches the coasting page at once"
        )
        _release(catch_at)
        await process_frame

        # A press between the rows scrolls the same page: the gap belongs
        # to the shelf as surely as a row does. The page sits at its top
        # and the finger drags up, the one direction with room to move.
        scroll.scroll_vertical = 0.0
        await process_frame
        var row0: Button = page.get_node("Scroll/Column/Row0")
        var row1: Button = page.get_node("Scroll/Column/Row1")
        var gap := Vector2(
                (row0.get_global_rect().get_center().x + row1.get_global_rect().get_center().x) / 2.0,
                (row0.get_global_rect().end.y + row1.get_global_rect().position.y) / 2.0
        )
        await _drag_finger(gap, Vector2(0, -travel), 4)
        await process_frame
        _ok(absf(scroll.scroll_vertical - travel) < 6.0, "a press between rows scrolls like a press on one")

        page.queue_free()
        await process_frame


## The real library, the page the reader reported: rows of buttons in a
## scroller, driven by the app's own boot, scrolled by a finger.
func _check_real_shelf() -> void:
        var main = (load("res://scripts/main.gd") as GDScript).new()
        main.set_anchors_preset(Control.PRESET_FULL_RECT)
        root.add_child(main)
        # After the tree has run frames, _ready fires inside add_child itself,
        # and awaiting a signal that already fired would stand still forever.
        if not main.is_node_ready():
                await main.ready
        await create_timer(0.9).timeout
        # The first question stands over the page; answer it, as a reader
        # does, so the page beneath is the one the finger meets.
        var asking: Node = main.get_node_or_null("LanguagePicker")
        if asking != null:
                main._on_language_chosen("en")
                await process_frame
        main._on_browse_pressed()
        await create_timer(0.6).timeout
        var browse: Control = main.get_node_or_null("Browse")
        if browse == null:
                _ok(false, "the library opens")
                return
        var scroll: ScrollContainer = browse.get_node_or_null("Margin/Column/Scroll")
        if scroll == null:
                _ok(false, "the library carries its scroller")
                return
        # The library opens on the shelf of surahs now; a finger's drag is
        # judged on a chapter's own page, the way the reader reported it --
        # so the test opens the deck's first chapter and waits for its rows.
        var grid: GridContainer = browse.get_node_or_null(
                "Margin/Column/Scroll/Wrap/Column/Shelf"
        )
        if grid == null:
                _ok(false, "the library opens on the shelf of surahs")
                return
        var first: Button = null
        for child in grid.get_children():
                if child.name.begins_with("SurahCard"):
                        first = child
                        break
        if first == null:
                _ok(false, "the shelf carries a chapter's card")
                return
        browse._open_surah_view((first.get_node("Pad/Words/Name") as Label).text)
        var waited := 0.0
        while _entries_on(browse) < 1 and waited < 10.0:
                await create_timer(0.2).timeout
                waited += 0.2
        await create_timer(0.6).timeout
        _ok(scroll.get_v_scroll_bar().max_value > 300.0, "the chapter's page is long enough to scroll")
        scroll.scroll_vertical = 200.0
        var row: Button = null
        for child in browse.get_node("Margin/Column/Scroll/Wrap/Column").get_children():
                if child.name.begins_with("Entry") and child.has_node("Row"):
                        var candidate: Button = child.get_node("Row")
                        var top := candidate.get_global_rect().position.y
                        if top > 60.0 and top < 600.0:
                                row = candidate
                                break
        if row == null:
                _ok(false, "the shelf carries a row under the eye")
                return
        await _drag_finger(row.get_global_rect().get_center(), Vector2(0, 80.0), 4, 0.25)
        await process_frame
        _ok(
                scroll.scroll_vertical < 150.0 and scroll.scroll_vertical > 60.0,
                "a finger on a real row scrolls the real shelf (%.1f from 200)" % scroll.scroll_vertical
        )


# --- the ink answers a finger ------------------------------------------------------


## A page of the app's own selectable words in a scroller, the shapes the
## manners live on: a finger dragging on the ink scrolls and chooses
## nothing, a resting finger chooses the word under it, the resting
## finger's drag widens the choice while the page holds still, a lift
## leaves the choice standing, a tap lets it go, and a desk's mouse keeps
## its own press-and-drag manners.
func _check_the_ink_answers_a_finger() -> void:
        # The library's own hand goes home first: the manners are judged on
        # a page of their own, and a second TouchScroll alive behind this
        # one would answer the same finger twice.
        for child in root.get_children():
                if child.get_script() == load("res://scripts/main.gd"):
                        child.free()
        await process_frame
        var page := Control.new()
        page.name = "InkPage"
        page.set_anchors_preset(Control.PRESET_FULL_RECT)
        root.add_child(page)

        var scroll := ScrollContainer.new()
        scroll.name = "Scroll"
        scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
        scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
        ThemeScript.style_scroll(scroll)
        page.add_child(scroll)

        var column := VBoxContainer.new()
        column.name = "Column"
        column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        scroll.add_child(column)

        var ink := RichTextLabel.new()
        ink.name = "Ink"
        ink.fit_content = true
        ink.scroll_active = false
        ink.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        ink.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        ink.selection_enabled = true
        CopyChipScript.watch(ink)
        ink.text = "The words a reader may want to carry away live here. ".repeat(80)
        column.add_child(ink)

        var more := RichTextLabel.new()
        more.name = "More"
        more.fit_content = true
        more.scroll_active = false
        more.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        more.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        more.selection_enabled = true
        CopyChipScript.watch(more)
        more.text = "A second page of words, far below the first, where a tap can land. ".repeat(30)
        column.add_child(more)

        var touch := TouchScrollScript.new()
        touch.name = "TouchScroll"
        page.add_child(touch)

        # The choice's own caretaker, on the window where the real one
        # lives, so the finger's steering after a rest has its edge math.
        var handles: Control = SelectHandlesScript.new()
        handles.name = "SelectHandles"
        root.add_child(handles)

        await process_frame
        await process_frame
        _ok(scroll.get_v_scroll_bar().max_value > 500.0, "the ink's page is long enough to scroll")

        # A finger dragging on the words is a scroll, and chooses nothing:
        # the report that began the manners. The scroll is moved first, so
        # the drag has room either way.
        scroll.scroll_vertical = 120.0
        await process_frame
        await _drag_finger(ink.get_global_rect().get_center(), Vector2(0, 80.0), 4, 0.25)
        await process_frame
        _ok(_no_choice_anywhere(), "a finger dragging on the ink chose no words")
        _ok(
                scroll.scroll_vertical < 70.0 and scroll.scroll_vertical > 20.0,
                "that same finger scrolled the page (%.1f from 120)" % scroll.scroll_vertical
        )

        # A finger that rests on the words means to choose: the word under
        # it is chosen, by the engine's own word-breaks. The page is settled
        # back to its top first (the drag above moved it), and the band
        # stands on a line the window can actually see -- a band above the
        # page's own top edge answers nothing, and that is the engine being
        # honest about a finger that is not on the page either.
        scroll.scroll_vertical = 0.0
        await process_frame
        var band := _on_the_line(ink, 1, 0.3)
        _press(band)
        await create_timer(0.7).timeout
        var from_i := ink.get_selection_from()
        var to_i := ink.get_selection_to()
        _ok(
                from_i >= 0 and to_i > from_i and not ink.get_selected_text().strip_edges().is_empty(),
                "a resting finger chose the word under it (from=%d to=%d)" % [from_i, to_i]
        )
        _ok(handles.visible, "the choice made, the pins are standing")

        # The resting finger now travels: the choice follows it and the
        # page holds still.
        var scroll_at_rest := scroll.scroll_vertical
        await _drag_by(band, band + Vector2(-24.0, 56.0))
        await _drag_by(band + Vector2(-24.0, 56.0), band + Vector2(-40.0, 120.0))
        await create_timer(0.2).timeout
        var grown_from := ink.get_selection_from()
        var grown_to := ink.get_selection_to()
        _ok(
                grown_from >= 0 and grown_to > grown_from
                        and (grown_from != from_i or grown_to != to_i),
                "the finger's drag widened the choice (from=%d to=%d)" % [grown_from, grown_to]
        )
        _ok(
                absf(scroll.scroll_vertical - scroll_at_rest) < 3.0,
                "the steering finger held the page still (%.1f at %.1f)" % [scroll.scroll_vertical, scroll_at_rest]
        )

        # The lift leaves the choice standing; a tap on the ink lets it go
        # -- a tap on a line the window sees, a little below the choice.
        _release(band + Vector2(-40.0, 120.0))
        await process_frame
        _ok(ink.get_selection_from() >= 0, "the lift leaves the choice standing")
        var tap_at := _on_the_line(ink, 5, 0.6)
        _press(tap_at)
        await process_frame
        _release(tap_at)
        await process_frame
        await process_frame
        _ok(_no_choice_anywhere(), "a tap on the ink let the choice go")
        _ok(not handles.visible, "the choice gone, the pins left with it")

        # The desk's mouse keeps its own manners: press and drag still
        # draws a choice, character by character, the way it always has --
        # and a mouse drag never scrolls the page (the wheel's work).
        var mouse_at := _on_the_line(ink, 2, 0.4)
        _mouse_press(mouse_at)
        var last := mouse_at
        for step in 5:
                last = mouse_at + Vector2(90.0 * (step + 1) / 5.0, 12.0 * (step + 1))
                _mouse_drag(last)
                await create_timer(0.07).timeout
        await create_timer(0.15).timeout
        _mouse_release(last)
        await process_frame
        _ok(ink.get_selection_from() >= 0, "a desk's mouse press-and-drag still chooses words")
        _ok(
                absf(scroll.scroll_vertical - scroll_at_rest) < 3.0,
                "a mouse drag never scrolls the page"
        )

        page.queue_free()
        handles.queue_free()
        await process_frame


## The real session, the room the report came from: a finger dragged
## across the verse card must scroll or rest -- never choose -- and a
## finger resting on the verse must choose its word.
func _check_the_real_session_ink() -> void:
        var main = (load("res://scripts/main.gd") as GDScript).new()
        main.set_anchors_preset(Control.PRESET_FULL_RECT)
        root.add_child(main)
        if not main.is_node_ready():
                await main.ready
        await create_timer(0.9).timeout
        var asking: Node = main.get_node_or_null("LanguagePicker")
        if asking != null:
                main._on_language_chosen("en")
                await process_frame
        main._start_session()
        await create_timer(0.6).timeout
        var study: Control = main.get_node_or_null("Study")
        if study == null:
                _ok(false, "the session opens for the ink's manners")
                return
        study._reveal()
        await create_timer(1.0).timeout
        var view: Control = study.get_node("Margin/Column/Surface/Fill/CardPanel/Padding/View")
        var verse: RichTextLabel = null
        for found in view.find_children("*", "RichTextLabel", true, false):
                if found.selection_enabled and found.is_visible_in_tree():
                        if verse == null or found.get_parsed_text().length() > verse.get_parsed_text().length():
                                verse = found
        if verse == null:
                _ok(false, "the answer side carries the ink the finger meets")
                study.closed.emit()
                await create_timer(0.3).timeout
                return

        # The report itself: a finger dragged down the verse card is a
        # scroll, and no wash of chosen words appears under it.
        await _drag_finger(verse.get_global_rect().get_center(), Vector2(0, 70.0), 4, 0.25)
        await process_frame
        _ok(_no_choice_anywhere(), "a finger dragged down the real verse card chose no words")

        # The resting finger: the word under it is chosen, the pins stand.
        var band := _on_the_line(verse, 0, 0.5)
        _press(band)
        await create_timer(0.7).timeout
        _ok(
                verse.get_selection_from() >= 0
                        and not verse.get_selected_text().strip_edges().is_empty(),
                "a finger resting on the verse chose the word under it"
        )
        var handles: Control = root.get_node_or_null("SelectHandles")
        _ok(handles != null and handles.visible, "the pins stand over the real verse's choice")
        _release(band)
        await process_frame

        study.closed.emit()
        await create_timer(0.3).timeout


## A point on a label's laid-out line `line`, at `frac` of the line's own
## inked width: the line's offset and height, its shaped width and the
## label's one alignment say where its words actually stand -- the box's
## own top sliver is nobody's guess to make.
func _on_the_line(label: RichTextLabel, line: int, frac: float) -> Vector2:
        var rect := label.get_global_rect()
        var line_w := label.get_line_width(line)
        var line_h := float(label.get_line_height(line))
        var origin := 0.0
        match label.horizontal_alignment:
                HORIZONTAL_ALIGNMENT_CENTER:
                        origin = (label.size.x - line_w) * 0.5
                HORIZONTAL_ALIGNMENT_RIGHT:
                        origin = label.size.x - line_w
        return Vector2(
                rect.position.x + origin + line_w * frac,
                rect.position.y + label.get_line_offset(line) + line_h * 0.5)


## No watched label anywhere holds a choice: the wash the report was
## made of can never quietly stand again.
func _no_choice_anywhere() -> bool:
        for entry in CopyChipScript._watched:
                if not is_instance_valid(entry):
                        continue
                var label := entry as RichTextLabel
                if label.get_selection_from() >= 0 \
                        and not label.get_selected_text().strip_edges().is_empty():
                        return false
        return true


# --- the finger, said in events ----------------------------------------------------

## The chapter's own account of how many of its rows stand.
func _entries_on(browse: Control) -> int:
        var column := browse.get_node_or_null("Margin/Column/Scroll/Wrap/Column")
        if column == null:
                return 0
        var count := 0
        for child in column.get_children():
                if child.name.begins_with("Entry"):
                        count += 1
        return count


## A position on the page, said the way the engine says it to a window:
## the transform is read from the window itself, never assumed.
func _win(pos: Vector2) -> Vector2:
        return root.get_final_transform() * pos


func _flush() -> void:
        Input.flush_buffered_events()


func _press(canvas_pos: Vector2) -> void:
        var ev := InputEventScreenTouch.new()
        ev.pressed = true
        ev.position = _win(canvas_pos)
        ev.index = 0
        ev.device = 0
        Input.parse_input_event(ev)
        _flush()


func _move(canvas_pos: Vector2) -> void:
        _drag_by(canvas_pos, canvas_pos)


## A drag whose finger moved from one page point to another: the position
## and the relative both said the way the engine says them, a window's own
## numbers.
func _drag_by(from: Vector2, to: Vector2) -> void:
        var ev := InputEventScreenDrag.new()
        ev.position = _win(to)
        ev.relative = _win(to) - _win(from)
        ev.index = 0
        ev.device = 0
        Input.parse_input_event(ev)
        _flush()


func _release(canvas_pos: Vector2) -> void:
        var ev := InputEventScreenTouch.new()
        ev.pressed = false
        ev.position = _win(canvas_pos)
        ev.index = 0
        ev.device = 0
        Input.parse_input_event(ev)
        _flush()


## A desk mouse, said in events: a press, motions carrying the held
## button, a release -- device zero, the device a real mouse holds. With
## the touch emulation hushed for this suite, a mouse event breeds no
## phantom finger, so these speak for the desk alone.
func _mouse_press(canvas_pos: Vector2) -> void:
        var ev := InputEventMouseButton.new()
        ev.button_index = MOUSE_BUTTON_LEFT
        ev.pressed = true
        ev.button_mask = MOUSE_BUTTON_MASK_LEFT
        ev.position = _win(canvas_pos)
        ev.global_position = _win(canvas_pos)
        ev.device = 0
        Input.parse_input_event(ev)
        _flush()


func _mouse_drag(canvas_pos: Vector2) -> void:
        var ev := InputEventMouseMotion.new()
        ev.position = _win(canvas_pos)
        ev.global_position = _win(canvas_pos)
        ev.button_mask = MOUSE_BUTTON_MASK_LEFT
        ev.device = 0
        Input.parse_input_event(ev)
        _flush()


func _mouse_release(canvas_pos: Vector2) -> void:
        var ev := InputEventMouseButton.new()
        ev.button_index = MOUSE_BUTTON_LEFT
        ev.pressed = false
        ev.position = _win(canvas_pos)
        ev.global_position = _win(canvas_pos)
        ev.device = 0
        Input.parse_input_event(ev)
        _flush()


## A press, one holding move, a release: the shape of a tap.
func _tap(canvas_pos: Vector2) -> void:
        _press(canvas_pos)
        await process_frame
        _release(canvas_pos)
        await process_frame


## A tap whose hand trembles a little: three moves of two pixels, well
## under the slop a press must travel before it becomes a scroll.
func _tap_with_jitter(canvas_pos: Vector2) -> void:
        _press(canvas_pos)
        for step in 3:
                _move(canvas_pos + Vector2(0, 2.0 * (step + 1)))
                await process_frame
        _release(canvas_pos + Vector2(0, 6.0))
        await process_frame


## A whole drag, one press and `steps` even moves of `travel` (window
## pixels, the way a finger reports them), a release at the end. The
## release may be asked to wait first: a hand still for a breath before
## it lifts is not a flick, and the page honors that with its own grace
## rule -- a release that comes later than it never carries the page on.
## The wait matters because the engine may hand these drags a speed they
## never earned: a velocity the input path stamps on events the test
## wrote at rest, one the shelf's coast would happily spend. A check that
## asks for the drag, not the coast, lifts after the pause; a check that
## asks for the coast passes no pause and keeps its fast lift.
func _drag_finger(canvas_pos: Vector2, travel: Vector2, steps: int, pause_before_lift: float = 0.0) -> void:
        _press(canvas_pos)
        var last := canvas_pos
        for step in steps:
                var to := canvas_pos + travel * (float(step + 1) / float(steps))
                var ev := InputEventScreenDrag.new()
                ev.position = _win(to)
                ev.relative = _win(to) - _win(last)
                ev.index = 0
                ev.device = 0
                Input.parse_input_event(ev)
                _flush()
                last = to
                await process_frame
        if pause_before_lift > 0.0:
                await create_timer(pause_before_lift).timeout
        _release(last)
        await process_frame


func _fresh_install() -> void:
        _remove_tree("user://decks")
        _remove_tree("user://settings.json")


func _remove_tree(path: String) -> void:
        if FileAccess.file_exists(path):
                DirAccess.remove_absolute(path)
                return
        if DirAccess.dir_exists_absolute(path):
                for entry in DirAccess.get_files_at(path):
                        DirAccess.remove_absolute(path.path_join(entry))
                for entry in DirAccess.get_directories_at(path):
                        _remove_tree(path.path_join(entry))
                DirAccess.remove_absolute(path)


func _ok(what: bool, saying: String) -> void:
        if what:
                print("  ok  %s" % saying)
        else:
                _failures += 1
                print("  FAIL  %s" % saying)
