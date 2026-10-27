extends Node
const RtlFieldScript := preload("res://scripts/ui/rtl_field.gd")
const CopyChipScript := preload("res://scripts/ui/copy_chip.gd")

## The shelf answers a finger the way every list on a phone does.
##
## The engine's own touch scrolling lives inside ScrollContainer's mouse
## path, and a mouse drag only reaches it when the press landed on the
## container itself -- but a shelf is rows of buttons, a button takes the
## press, and the drag dies on the row it started from. So on a phone the
## page behind the buttons never moved. This node is the hand's own
## scroller, standing above the whole GUI: every real finger it follows,
## and the ScrollContainer under that finger scrolls, whatever the finger
## pressed to begin with.
##
## A finger and its mouse echo. On a touchscreen every touch also becomes
## a mouse press (that echo is what clicks buttons), and that echo is what
## arms the engine's native drag. While a scroll is being made here, the
## echo is shown out: its motions are consumed so the native scroller and
## the hover states never wake, and one motion of the finger's own -- sent
## far off the page the moment the scroll begins -- tells the control the
## press began on that the hand has left, the same news a real drag past a
## row's edge would carry. The releases are never touched: a tap still
## clicks, and a scroll that ends still lets go cleanly, because the
## button was told the hand left before the release could be read as a
## click on it.
##
## The ink has manners of its own. The app's own selectable words (the
## labels the copy pill watches) are not a desk: a finger that lands on
## them and travels means to move the page, and the press the engine
## echoes from the touch is shown out with the rest -- that press is what
## arms the engine's selection clock, and left armed it answers a scroll
## with a wash of chosen words nobody chose. A choice is made the way
## every phone makes one: the finger rests on the words and this node
## speaks one double-click in its place, the engine's own word-breaks
## picking the word under it; from there a drag is the choice growing
## under the finger -- one press is spoken at the choice's far edge (the
## pins' own trick, the engine's own clock doing the choosing) while the
## page itself holds still; a tap on the ink lets a standing choice go,
## the way a tap has always dismissed it; and the pins stand at the two
## ends for the mending a thumb wants after. None of this touches a
## desk's mouse: real mouse events never pass through a finger's path.
##
## What the hand is doing is decided by where it lands. A press on a field
## that owns its own drags -- the writing fields, a rule the thumb slides,
## the scrollbar itself -- belongs to that field, and nothing here moves.
## A press over no scroller belongs to the page beneath. Everything else
## is a scroll waiting to happen: held still it is a tap, moved past a
## few pixels it is the page following the finger, let go with speed it
## is the page carrying on alone, slowing the way paper slows.

const SLOP := 10.0            # canvas px a finger travels before a press becomes a scroll
const LONG_PRESS := 0.45      # s a finger rests on the ink before it means to choose
const FLING_FRICTION := 6.0   # the speed decays by this much per second, e-folds
const FLING_MIN := 40.0       # px/s below which a fling has spent itself
const FLING_MAX := 3000.0     # px/s above which a wild swipe is capped
const RELEASE_GRACE := 0.12   # s between the last drag and the release a fling still honours

## The one synthetic event this node makes: a mouse motion from far off
## the page, carrying no movement of its own, on a device number no real
## hardware holds. It is the "the hand has left" message, and it must pass
## this node untouched on its way to the GUI.
const CANCEL_DEVICE := 70001
const CANCEL_POSITION := Vector2(-100000.0, -100000.0)

# The one gesture this hand owns, from press to release:
#   index   the finger's own index, other fingers are not followed
#   scroll  the ScrollContainer under the finger
#   start   where the press landed
#   pos     where the finger stands now
#   active  the finger has travelled past the slop; the page follows now
#   speed   the last drag's speed, the candidate for a fling
#   moved   when the last drag arrived, in ticks
#   label   the watched, selectable label under the press (or null)
#   lp_done a resting finger has spoken its word-choice already
#   extend  the finger is steering a choice; the page holds still
var _gest: Dictionary = {}

# The page carrying on alone after the hand let go: the scroller and its
# remaining speed.
var _fling: Dictionary = {}

# The clock a resting finger reads against: while it runs, the finger is
# deciding between a scroll and a choice of words.
var _rest: Timer

# The choice's own caretaker, found once it is wanted: its edge math says
# exactly where a choice's two ends stand on the page.
var _handles: Control = null


func _ready() -> void:
        _rest = Timer.new()
        _rest.one_shot = true
        _rest.wait_time = LONG_PRESS
        _rest.timeout.connect(_on_rest)
        add_child(_rest)


func _input(event: InputEvent) -> void:
        # This node's own far-off message passes straight through.
        if event.device == CANCEL_DEVICE:
                return
        if event.device == InputEvent.DEVICE_ID_EMULATION:
                _echo(event)
                return
        if event is InputEventScreenTouch:
                _touch(event)
        elif event is InputEventScreenDrag:
                _drag(event)


# --- a real finger --------------------------------------------------------------


## Where a press lands decides whose it is: a field that owns its drags
## keeps it, a scroller's page arms it, anything else lets it through
## untouched. A release closes whatever gesture that finger owned.
func _touch(event: InputEventScreenTouch) -> void:
        if event.pressed:
                # Any new finger stops a page still coasting: the universal
                # way a reader catches a list that is moving.
                _fling = {}
                if not _gest.is_empty():
                        return  # one gesture at a time; other fingers are not ours
                var hit := _control_at(event.position)
                if hit == null:
                        return  # nothing under the finger asked for anything
                if _owns_its_drags(hit):
                        return  # the field or the rule keeps its hand
                var scroll := _scroller_under(hit)
                if scroll == null:
                        return  # a page that does not scroll; taps only
                _gest = {
                        "index": event.index,
                        "scroll": scroll,
                        "start": event.position,
                        "pos": event.position,
                        "active": false,
                        "speed": 0.0,
                        "moved": Time.get_ticks_msec(),
                        "label": _watched_label(hit),
                        "lp_done": false,
                        "extend": false,
                }
                if _gest["label"] != null:
                        _rest.start()  # the finger may be meaning to choose words
        else:
                if _gest.is_empty() or event.index != _gest["index"]:
                        return
                _rest.stop()
                # A page swapped under a standing gesture frees its scroller;
                # the typed lift reads the truth before it reads the value.
                var scroll: ScrollContainer = null
                if is_instance_valid(_gest["scroll"]):
                        scroll = _gest["scroll"]
                var speed: float = _gest["speed"]
                var moved: int = _gest["moved"]
                var was_active := bool(_gest["active"])
                var was_tap := not was_active and not bool(_gest["lp_done"]) \
                        and _gest["label"] != null
                _gest = {}
                if was_tap:
                        # A tap on the ink is how a hand lets a choice go --
                        # and if one went, the tap is spoken again so a link
                        # under the finger answers a page already clean.
                        if _let_choices_go():
                                _speak_tap(event.position)
                elif (
                        was_active
                        and is_instance_valid(scroll)
                        and absf(speed) >= FLING_MIN
                        and Time.get_ticks_msec() - moved <= RELEASE_GRACE * 1000.0
                ):
                        _fling = {"scroll": scroll, "speed": speed}


## The page follows the finger: past the slop every drag belongs to the
## scroll, the finger's mouse echo is shown out, and the press's own
## control is told the hand has left -- unless the finger is steering a
## choice, in which case the page holds still and the choice grows.
func _drag(event: InputEventScreenDrag) -> void:
        if _gest.is_empty() or event.index != _gest["index"]:
                return
        var scroll: ScrollContainer = null
        if is_instance_valid(_gest["scroll"]):
                scroll = _gest["scroll"]
        else:
                _gest = {}
                return
        _gest["pos"] = event.position
        if bool(_gest["extend"]):
                # The finger steers the choice now: the words follow it and
                # the page itself keeps its ground.
                get_viewport().set_input_as_handled()
                return
        if not _gest["active"]:
                if absf(event.position.y - _gest["start"].y) < SLOP:
                        return  # still held, still a tap until it travels
                _gest["active"] = true
                _rest.stop()
                if bool(_gest["lp_done"]) and _begin_finger_extend():
                        get_viewport().set_input_as_handled()
                        return
                # The control the press began on must hear, before anything
                # else, that the hand has left it -- a motion from far off
                # the page, carrying no movement, delivered at once. Without
                # it a scroll that ends where it began would land as a
                # click on the row the finger first pressed.
                get_viewport().push_input(_cancel_motion(), true)
        # The drag is this scroll's now: the GUI beneath is not asked.
        get_viewport().set_input_as_handled()
        scroll.scroll_vertical -= event.relative.y
        _gest["speed"] = clampf(event.velocity.y, -FLING_MAX, FLING_MAX)
        _gest["moved"] = Time.get_ticks_msec()


# --- the finger's mouse echo ------------------------------------------------------


## Every touch also becomes a mouse press, the echo that clicks buttons
## and arms the engine's own drag. The echo's press is spoken before the
## touch that bred it reaches this node, so no gesture can vouch for it
## yet -- the ink under it is asked instead: on the app's own selectable
## words, in a page that scrolls, the press is shown out unheard. It is
## the press that arms the engine's selection clock, and a clock armed
## under a finger that means to scroll answers with a wash of words
## nobody chose. The echo's motions are consumed while a scroll is being
## made -- the native scroller never wakes, no row lights up -- except
## while the finger steers a choice, when they are the very words the
## engine's clock reads the finger's place from. The releases always
## pass: a tap still clicks, a scroll still lets go.
func _echo(event: InputEvent) -> void:
        if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
                if event.pressed:
                        var hit := _control_at(event.position)
                        if hit != null and _watched_label(hit) != null \
                                        and _scroller_under(hit) != null:
                                get_viewport().set_input_as_handled()
                return
        if _gest.is_empty():
                return
        if event is InputEventMouseMotion:
                if not bool(_gest["extend"]):
                        get_viewport().set_input_as_handled()


# --- a resting finger chooses words ------------------------------------------------


## The finger rested on the ink: it means to choose, not to scroll. One
## double-click is spoken in its place, at the very point the finger
## holds -- the engine picks the word under it with its own word-breaks
## (shaping, BiDi and all its own honesty), and the pins stand at the
## word's two ends the moment the choice does. A finger resting on the
## air between two words is answered by the nearest word: the same
## double-click is spoken again a step to either side, and the first
## word found is the one the finger meant.
func _on_rest() -> void:
        if _gest.is_empty() or bool(_gest["active"]) or bool(_gest["lp_done"]):
                return
        var label: RichTextLabel = _gest["label"]
        if label == null or not is_instance_valid(label):
                return
        _gest["lp_done"] = true
        var pos: Vector2 = _gest["pos"]
        _speak_word_choice(label, pos)
        if label.get_selection_from() < 0:
                for offset in [14.0, -14.0, 28.0, -28.0]:
                        _speak_word_choice(label, pos + Vector2(offset, 0.0))
                        if label.get_selection_from() >= 0:
                                break


## One double-click, spoken at one point in the window's own numbers: a
## press and its release, the engine's own word-picking between them.
func _speak_word_choice(label: RichTextLabel, at: Vector2) -> void:
        var pos := _window_pos(at)
        var press := InputEventMouseButton.new()
        press.button_index = MOUSE_BUTTON_LEFT
        press.pressed = true
        press.double_click = true
        press.button_mask = MOUSE_BUTTON_MASK_LEFT
        press.position = pos
        press.global_position = pos
        get_viewport().push_input(press)
        var release := InputEventMouseButton.new()
        release.button_index = MOUSE_BUTTON_LEFT
        release.pressed = false
        release.double_click = true
        release.position = pos
        release.global_position = pos
        get_viewport().push_input(release)


## The resting finger now travels: the choice follows it. One press is
## spoken at the choice's far edge -- the end the finger is leaving to
## the engine's clock -- and from that breath the finger's own echo
## motions reach the label and the engine extends the choice along them,
## the way the pins' drags have always worked. The answer says whether
## the steering began; a finger with nothing chosen yet scrolls on.
func _begin_finger_extend() -> bool:
        var label: RichTextLabel = _gest["label"]
        if label == null or not is_instance_valid(label):
                return false
        var from_i := label.get_selection_from()
        var to_i := label.get_selection_to()
        if from_i < 0 or to_i < from_i or label.get_selected_text().strip_edges().is_empty():
                return false
        var handles := _handles_node()
        if handles == null:
                return false
        var start_at: Vector2 = handles.edge_global(label, from_i, false)
        var end_at: Vector2 = handles.edge_global(label, to_i, true)
        if is_inf(start_at.x) or is_inf(end_at.x):
                return false
        # The still end is the one farther from the finger: the finger
        # drags the nearer edge, the other keeps the choice's ground.
        var finger: Vector2 = _gest["pos"]
        var anchor := end_at \
                if finger.distance_squared_to(start_at) < finger.distance_squared_to(end_at) \
                else start_at
        var press := InputEventMouseButton.new()
        press.button_index = MOUSE_BUTTON_LEFT
        press.pressed = true
        press.button_mask = MOUSE_BUTTON_MASK_LEFT
        press.position = _window_pos(anchor)
        press.global_position = _window_pos(anchor)
        get_viewport().push_input(press)
        _gest["extend"] = true
        return true


## A tap on the ink lets a standing choice go, the way a tap has always
## dismissed one. The answer says whether anything was let go.
func _let_choices_go() -> bool:
        var cleared := false
        for entry in CopyChipScript._watched:
                if not is_instance_valid(entry):
                        continue
                var label := entry as RichTextLabel
                if label.get_selection_from() < 0:
                        continue
                if label.get_selected_text().strip_edges().is_empty():
                        continue
                label.deselect()
                cleared = true
        return cleared


## One tap, spoken twice-rounded: a press and its release at the same
## point, on a device number no finger holds -- the desk's own click,
## re-said after a choice was dismissed so a link under the finger is
## answered by a page the engine reads as clean.
func _speak_tap(pos: Vector2) -> void:
        var at := _window_pos(pos)
        var press := InputEventMouseButton.new()
        press.button_index = MOUSE_BUTTON_LEFT
        press.pressed = true
        press.position = at
        press.global_position = at
        get_viewport().push_input(press)
        var release := InputEventMouseButton.new()
        release.button_index = MOUSE_BUTTON_LEFT
        release.pressed = false
        release.position = at
        release.global_position = at
        get_viewport().push_input(release)


## A canvas point, said in the window's own numbers -- the numbers a
## pushed event is expected to wear. The engine walks a pushed event back
## across the final transform on its way to the canvas, so a canvas point
## pushed raw would land somewhere else entirely wherever the page is
## scaled (a stretched phone, a headless room).
func _window_pos(canvas_pos: Vector2) -> Vector2:
        return get_viewport().get_final_transform() * canvas_pos


## The watched label under a press, if the ink there is the app's own
## selectable kind: the label itself, or the first watched ancestor above
## whatever the finger met.
func _watched_label(hit: Control) -> RichTextLabel:
        var node: Node = hit
        while node is Control:
                if node is RichTextLabel and CopyChipScript._watched.has(node):
                        return node
                node = node.get_parent()
        return null


## The choice's caretaker on the window, found when first wanted (it
## joins the window a beat after this node does).
func _handles_node() -> Control:
        if _handles == null or not is_instance_valid(_handles):
                _handles = get_window().get_node_or_null("SelectHandles")
        return _handles


# --- the fling ----------------------------------------------------------------


## The page carries on alone, slowing the way paper slows: each frame the
## remaining speed moves the scroll a little less, until it is spent or
## the end of the page stands still.
func _process(delta: float) -> void:
        if _fling.is_empty():
                return
        var scroll: ScrollContainer = null
        if is_instance_valid(_fling["scroll"]):
                scroll = _fling["scroll"]
        else:
                _fling = {}
                return
        var before := scroll.scroll_vertical
        scroll.scroll_vertical -= _fling["speed"] * delta
        _fling["speed"] *= exp(-FLING_FRICTION * delta)
        var spent := absf(_fling["speed"]) < FLING_MIN
        var arrived := is_equal_approx(before, scroll.scroll_vertical)
        if spent or arrived:
                _fling = {}


# --- what a press lands on -------------------------------------------------------


## The controls that own their own drags: whatever the hand means to do
## with them, the page behind must not move. A writing field selects, a
## rule the thumb slides slides, the scrollbar drags its grabber.
func _owns_its_drags(hit: Control) -> bool:
        var node: Node = hit
        while node is Control:
                if (
                        node is LineEdit
                        or node is TextEdit
                        or node is Slider
                        or node is ScrollBar
                        or node is RtlFieldScript
                ):
                        return true
                node = node.get_parent()
        return false


## The control a point on the page stands on, found the way the engine
## finds it for a press: the deepest visible control under the point,
## children searched before parents and the last-added first (what stands
## on top is what the hand meets), a clipped parent hiding its children
## from points outside itself, and a control that ignores the mouse
## letting the page beneath it answer instead. The engine's own finder
## went away with 4.7, so the law is said here, for one point, at
## press-time only -- the one moment a scroll needs to know.
func _control_at(pos: Vector2) -> Control:
        var top: Array = get_viewport().get_children()
        for i in range(top.size() - 1, -1, -1):
                var item := top[i] as CanvasItem
                if item == null:
                        continue
                var found := _search(item, pos)
                if found != null:
                        return found
        return null


func _search(item: CanvasItem, pos: Vector2) -> Control:
        var control := item as Control
        if control != null and not control.is_visible_in_tree():
                return null  # what cannot be seen cannot be pressed
        var inside := true
        if control != null:
                inside = control.get_global_rect().has_point(pos)
        if control == null or not control.is_clipping_contents() or inside:
                var children: Array = item.get_children()
                for i in range(children.size() - 1, -1, -1):
                        var child := children[i] as CanvasItem
                        if child == null or child.is_set_as_top_level():
                                continue
                        var found := _search(child, pos)
                        if found != null:
                                return found
        if (
                control == null
                or control.mouse_filter == Control.MOUSE_FILTER_IGNORE
                or not inside
        ):
                return null
        return control


## The nearest scroller above the press, if it is one that can move.
func _scroller_under(hit: Control) -> ScrollContainer:
        var node: Node = hit
        while node is Control:
                if node is ScrollContainer:
                        var scroll := node as ScrollContainer
                        if (
                                scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED
                                and scroll.get_v_scroll_bar() != null
                                and scroll.get_v_scroll_bar().max_value > 0.0
                        ):
                                return scroll
                        return null  # a scroller that cannot move is no scroller
                node = node.get_parent()
        return null


## The "the hand has left" message: a mouse motion from far off the page,
## carrying no movement of its own (a carried movement would wake the
## very native drag this node is standing in for), wearing a device
## number this node itself recognises and passes.
func _cancel_motion() -> InputEventMouseMotion:
        var cancel := InputEventMouseMotion.new()
        cancel.device = CANCEL_DEVICE
        cancel.position = CANCEL_POSITION
        cancel.global_position = CANCEL_POSITION
        cancel.relative = Vector2.ZERO
        cancel.velocity = Vector2.ZERO
        return cancel
