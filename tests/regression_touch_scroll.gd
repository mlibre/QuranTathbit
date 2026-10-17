extends SceneTree
const ThemeScript := preload("res://scripts/ui/theme.gd")
const TouchScrollScript := preload("res://scripts/ui/touch_scroll.gd")

## A phone's finger, replayed event by event through the engine's own
## input path: the page under a shelf of buttons must scroll, a tap must
## still click, a field that owns its drags must keep them, and a scroll
## that ends where it began must not land as a click. Every event is a
## real touch (a device the engine does not reserve for emulation), so
## the mouse echo the engine makes from it -- the echo that clicks
## buttons on a phone -- rides along exactly as it does in a hand.

var _failures := 0

func _init() -> void:
        _fresh_install()
        await _check_own_page()
        await _check_real_shelf()
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
        _ok(scroll.get_v_scroll_bar().max_value > 300.0, "the shelf is long enough to scroll")
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
        await _drag_finger(row.get_global_rect().get_center(), Vector2(0, 80.0), 4)
        await process_frame
        _ok(
                scroll.scroll_vertical < 150.0 and scroll.scroll_vertical > 60.0,
                "a finger on a real row scrolls the real shelf (%.1f from 200)" % scroll.scroll_vertical
        )


# --- the finger, said in events ----------------------------------------------------


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
## pixels, the way a finger reports them), a release at the end.
func _drag_finger(canvas_pos: Vector2, travel: Vector2, steps: int) -> void:
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
