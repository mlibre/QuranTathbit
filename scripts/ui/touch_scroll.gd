extends Node
const RtlFieldScript := preload("res://scripts/ui/rtl_field.gd")

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
## What the hand is doing is decided by where it lands. A press on a field
## that owns its own drags -- the writing fields, a rule the thumb slides,
## the scrollbar itself -- belongs to that field, and nothing here moves.
## A press over no scroller belongs to the page beneath. Everything else
## is a scroll waiting to happen: held still it is a tap, moved past a
## few pixels it is the page following the finger, let go with speed it
## is the page carrying on alone, slowing the way paper slows.

const SLOP := 10.0            # canvas px a finger travels before a press becomes a scroll
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
#   active  the finger has travelled past the slop; the page follows now
#   speed   the last drag's speed, the candidate for a fling
#   moved   when the last drag arrived, in ticks
var _gest: Dictionary = {}

# The page carrying on alone after the hand let go: the scroller and its
# remaining speed.
var _fling: Dictionary = {}


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
                        "active": false,
                        "speed": 0.0,
                        "moved": Time.get_ticks_msec(),
                }
        else:
                if _gest.is_empty() or event.index != _gest["index"]:
                        return
                var scroll: ScrollContainer = _gest["scroll"]
                var speed: float = _gest["speed"]
                var moved: int = _gest["moved"]
                var was_active := bool(_gest["active"])
                _gest = {}
                if (
                        was_active
                        and is_instance_valid(scroll)
                        and absf(speed) >= FLING_MIN
                        and Time.get_ticks_msec() - moved <= RELEASE_GRACE * 1000.0
                ):
                        _fling = {"scroll": scroll, "speed": speed}


## The page follows the finger: past the slop every drag belongs to the
## scroll, the finger's mouse echo is shown out, and the press's own
## control is told the hand has left.
func _drag(event: InputEventScreenDrag) -> void:
        if _gest.is_empty() or event.index != _gest["index"]:
                return
        var scroll: ScrollContainer = _gest["scroll"]
        if not is_instance_valid(scroll):
                _gest = {}
                return
        if not _gest["active"]:
                if absf(event.position.y - _gest["start"].y) < SLOP:
                        return  # still held, still a tap until it travels
                _gest["active"] = true
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
## and arms the engine's own drag. While a scroll is being made here the
## echo's motions are consumed -- the native scroller never wakes, no row
## the finger passes over lights up -- and its releases always pass: a
## tap still clicks, a scroll still lets go.
func _echo(event: InputEvent) -> void:
        if _gest.is_empty():
                return
        if event is InputEventMouseMotion:
                get_viewport().set_input_as_handled()


# --- the fling ----------------------------------------------------------------


## The page carries on alone, slowing the way paper slows: each frame the
## remaining speed moves the scroll a little less, until it is spent or
## the end of the page stands still.
func _process(delta: float) -> void:
        if _fling.is_empty():
                return
        var scroll: ScrollContainer = _fling["scroll"]
        if not is_instance_valid(scroll):
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
