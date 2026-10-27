class_name SelectHandles
extends Control
const ThemeScript := preload("res://scripts/ui/theme.gd")
const CopyChipScript := preload("res://scripts/ui/copy_chip.gd")

## The two pins a hand needs to say exactly which words it meant. On a desk
## the mouse drags a choice out word by word and a second drag redraws it;
## under a thumb a drag is a guess -- the finger stopped a letter wide of
## where the eye meant -- and every other reader the phone has ever taught
## answers the guess the same way: two small drops standing at the choice's
## two ends, each one draggable, so the guess is corrected where it stands
## instead of made again. The engine's own label offers no such pins (its
## selection is drawn but never handed over as handles), so the app draws
## them itself: two gold drops, one at each end of the wash, hanging under
## the line they end -- and a drag of either one re-anchors the choice
## through the engine's own selection machinery, the same machinery the
## first drag used, so the BiDi, the wrapping and the shaping all stay the
## engine's own honest word.
##
## The trick a drag plays is small and worth writing down. A pin is a
## control standing over the ink, so the engine never mistakes it for a
## press on the words. When a pin is taken, the pin steps aside (its mouse
## filter opens) and one press is spoken in the pin's place -- at the
## choice's OTHER end, which is the end the drag must keep still. From that
## breath on the finger's own motions reach the label (the engine gave it
## the mouse's focus with that press) and the label's own clock extends the
## choice along the finger, exactly as it did when the choice was first
## drawn; the pins only follow, placed anew from the live selection every
## frame. Nothing here maps a finger to a letter: the engine does that, and
## does it right.

## The pin's own drawing, said once: a drop whose tail reaches up to the
## words it pins and a round head a thumb can land on. The tip is the
## anchor -- the exact boundary between the chosen words and the rest --
## and everything else hangs from it.
const PIN_W := 44.0
const PIN_H := 48.0
const TIP := Vector2(PIN_W * 0.5, 6.0)  # where the tail meets the words
const HEAD_AT := Vector2(PIN_W * 0.5, 30.0)  # the round head's centre
const HEAD_R := 11.0

var _label: RichTextLabel = null  # whose choice the pins are standing at
var _from: Control  # the pin on the choice's first character
var _to: Control  # the pin on the choice's last character
var _dragging := false  # a pin is taken and the finger is steering a choice
var _drag_pin: Control = null  # which pin the finger holds (it follows, too)
var _saw_press := false  # the drag's own finger was heard by the Input itself

func _ready() -> void:
        name = "SelectHandles"
        # The pins answer presses, not the keyboard, and must never take the
        # focus from the label whose words they hold: focus leaving a label
        # is what ends its choice.
        focus_mode = Control.FOCUS_NONE
        # The root itself is nowhere: a hand never lands on it, and a press
        # never stops here. It cannot be IGNORE -- an ignored control takes
        # its whole subtree out of the engine's hit-test, and the pins would
        # draw for ever and never answer a finger -- so it is a STOP control
        # the size of a point, standing at the window's corner, whose only
        # work is to carry the two pins.
        mouse_filter = Control.MOUSE_FILTER_STOP
        position = Vector2.ZERO
        size = Vector2.ZERO
        clip_contents = false
        _from = _make_pin("PinFrom")
        _to = _make_pin("PinTo")
        visible = false

func _make_pin(pin_name: String) -> Control:
        var pin := Control.new()
        pin.name = pin_name
        pin.focus_mode = Control.FOCUS_NONE
        pin.mouse_filter = Control.MOUSE_FILTER_STOP
        pin.size = Vector2(PIN_W, PIN_H)
        pin.draw.connect(_draw_pin.bind(pin))
        pin.gui_input.connect(_on_pin_input.bind(pin))
        add_child(pin)
        return pin

## The life of the pins, asked every frame: find the one label holding a
## choice (the same quiet poll the copy pill runs -- the engine tells no
## one when a label's selection changes), stand at its two ends, and leave
## when the choice is gone. While a hand is drawing a fresh choice the pins
## already stand at its growing ends -- they are the same pins that will
## mend it the moment the hand lifts.
func _process(_delta: float) -> void:
        if _dragging:
                # A pin's drag ends the moment the button is up, whoever saw
                # the lift first. The button's state is only trusted once
                # this drag has seen it down -- a pin's anchor press never
                # rings the Input's own bell (it is spoken straight to the
                # label), so a drag whose grab the Input never heard ends
                # only by its own lift, which _input answers.
                if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
                        _saw_press = true
                elif _saw_press:
                        _end_drag()
                _follow_drag()
                return
        var found: RichTextLabel = null
        for entry in CopyChipScript._watched:
                if not is_instance_valid(entry):
                        continue
                var label := entry as RichTextLabel
                if not label.is_visible_in_tree():
                        continue
                if label.get_selection_from() < 0:
                        continue
                if label.get_selected_text().strip_edges().is_empty():
                        continue
                found = label
                break
        if found == null:
                _label = null
                visible = false
                return
        _label = found
        if not visible:
                visible = true
        _place_pins()

## Where the choice's two ends stand, in the label's own geometry: the
## engine hands over the chosen characters (indices into the label's parsed
## text), the line each end sits on, and every line's laid-out width -- the
## rest is the line's own alignment and its first strong letter, the same
## reading the engine's AUTO base uses. The answer is a tip position in the
## label's local space for the pin at each end, and the same point again in
## window coordinates for the one press a drag speaks in the pin's place.
func _edge_of(label: RichTextLabel, char_index: int, after: bool) -> Dictionary:
        var parsed := label.get_parsed_text()
        var line := label.get_character_line(char_index)
        if line < 0:
                return {}
        var range_v := label.get_line_range(line)
        var first := range_v.x
        var line_top := label.get_line_offset(line)
        var line_h := label.get_line_height(line)
        var line_w := label.get_line_width(line)
        # The words before this end on their own line, and the words through
        # it -- the boundary the pin stands on is between the two measures.
        var before := parsed.substr(first, clampi(char_index - first, 0, parsed.length() - first))
        var through := parsed.substr(first, clampi(char_index - first + (1 if after else 0), 0, parsed.length() - first))
        var face: Font = label.get_theme_font("normal_font")
        var fsz := label.get_theme_font_size("normal_font_size")
        var before_w := face.get_string_size(before, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x if not before.is_empty() else 0.0
        var through_w := face.get_string_size(through, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x if not through.is_empty() else 0.0
        # Where the line's own ink begins: the label aligns every line by the
        # one alignment it was given.
        var origin := 0.0
        match label.horizontal_alignment:
                HORIZONTAL_ALIGNMENT_CENTER:
                        origin = (label.size.x - line_w) * 0.5
                HORIZONTAL_ALIGNMENT_RIGHT:
                        origin = label.size.x - line_w
        # A right-reading line lays its first character at the line's right
        # edge, so a count of words measured from the line's start walks from
        # the RIGHT -- the pin's boundary is the line's origin plus the width
        # that remains to its right. A left-reading line walks from the left
        # as the count does. (The first strong letter of the line's own words
        # is the same law the engine's AUTO base reads; punctuation and marks
        # standing before it are the neutrals both readings agree to skip.)
        var rtl := _line_reads_rtl(parsed.substr(first, clampi(range_v.y - first, 0, parsed.length() - first)))
        var x := origin + (line_w - (through_w if after else before_w)) if rtl \
                else origin + (through_w if after else before_w)
        return {
                "local": Vector2(x, line_top + line_h * 0.5),
                "bottom": line_top + line_h,
        }

## Where a choice's boundary stands on the page, in window coordinates:
## the same edge the pins hang from, said to whoever else needs to speak a
## press at a choice's end -- the finger's own steering after a long-press
## does. An empty answer (the character off the laid-out page) reads as
## the point at infinity, which no caller will mistake for a place.
func edge_global(label: RichTextLabel, char_index: int, after: bool) -> Vector2:
        var edge := _edge_of(label, char_index, after)
        if edge.is_empty():
                return Vector2.INF
        return label.get_global_rect().position + edge["local"]

## The line's first strong letter: Arabic, Persian's own letters, Hebrew and
## friends read from the right; anything else from the left. Marks, vowel
## signs and the neutral marks of punctuation are skipped, the way a base
## direction has always been read.
func _line_reads_rtl(line_text: String) -> bool:
        for i in line_text.length():
                var code := line_text.unicode_at(i)
                if _is_neutral(code):
                        continue
                return _is_rtl_letter(code)
        return false

func _is_neutral(code: int) -> bool:
        # Marks that join or decorate (harakat, tatweel, ZWJ/ZWNJ) and the
        # spaces and common punctuation say nothing of direction.
        return code == 0x20 or (code >= 0x200C and code <= 0x200F) \
                or (code >= 0x0610 and code <= 0x061A) \
                or code == 0x0640 or (code >= 0x064B and code <= 0x065F) \
                or code == 0x0670 or (code >= 0x06D6 and code <= 0x06ED) \
                or (code >= 0x30 and code <= 0x3F)  # digits and ASCII punctuation

func _is_rtl_letter(code: int) -> bool:
        return (code >= 0x0590 and code <= 0x05FF) \
                or (code >= 0x0600 and code <= 0x06FF) \
                or (code >= 0x0700 and code <= 0x074F) \
                or (code >= 0x0750 and code <= 0x077F) \
                or (code >= 0x08A0 and code <= 0x08FF) \
                or (code >= 0xFB50 and code <= 0xFDFF) \
                or (code >= 0xFE70 and code <= 0xFEFF)

func _place_pins() -> void:
        if _label == null or not is_instance_valid(_label):
                visible = false
                return
        var from_i := _label.get_selection_from()
        var to_i := _label.get_selection_to()
        if from_i < 0 or to_i < from_i:
                visible = false
                return
        var from_edge := _edge_of(_label, from_i, false)
        var to_edge := _edge_of(_label, to_i, true)
        if from_edge.is_empty() or to_edge.is_empty():
                visible = false
                return
        var origin := _label.get_global_rect().position
        _set_pin(_from, origin + from_edge["local"], origin.y + from_edge["bottom"])
        _set_pin(_to, origin + to_edge["local"], origin.y + to_edge["bottom"])

## One pin at one boundary: the tip rides the exact point between the
## chosen words and the rest, at the bottom edge of the line the end stands
## on, so the drop hangs beneath the words like a thumb's bookmark.
func _set_pin(pin: Control, tip: Vector2, line_bottom_global_y: float) -> void:
        var top := Vector2(tip.x - TIP.x, line_bottom_global_y - 2.0)
        if pin.position != top:
                pin.position = top

## A pin taken: the drag begins. The press the finger made never reached the
## label (the pin stood over the ink), so one is spoken for it -- at the
## choice's other end, the end the drag keeps still -- and the pin steps
## out of the engine's way (its filter opens, its own drawing stays). From
## the next breath the label holds the mouse's focus and the finger's own
## motions drive the engine's selection, the pins merely following.
func _on_pin_input(event: InputEvent, pin: Control) -> void:
        var taken := false
        if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
                taken = true
        elif event is InputEventScreenTouch and event.pressed:
                taken = true
        if not taken or _dragging or _label == null:
                return
        _dragging = true
        _drag_pin = pin
        # The still end: the choice's other edge, pressed where its own
        # character stands so the engine anchors there and the drag extends
        # or shrinks from the pin's side -- the way a handle has always
        # mended a choice.
        var from_i := _label.get_selection_from()
        var to_i := _label.get_selection_to()
        var anchor_char := to_i if pin == _from else from_i
        var after := pin != _from
        var edge := _edge_of(_label, anchor_char, after)
        if edge.is_empty():
                _dragging = false
                _drag_pin = null
                return
        var anchor_global: Vector2 = _label.get_global_rect().position + edge["local"]
        # The press is spoken in window coordinates, straight to the viewport
        # -- never through Input, whose own touch emulation would answer a
        # synthetic mouse press with a phantom finger of its own (a press
        # nobody lifted, a choice that re-makes itself under a parked
        # cursor). push_input lands the press on the label and starts the
        # engine's own selection clock, and nothing else stirs.
        var window_pos: Vector2 = get_viewport_transform() * anchor_global
        var press := InputEventMouseButton.new()
        press.button_index = MOUSE_BUTTON_LEFT
        press.pressed = true
        press.button_mask = MOUSE_BUTTON_MASK_LEFT
        press.position = window_pos
        press.global_position = window_pos
        for p: Control in [_from, _to]:
                p.mouse_filter = Control.MOUSE_FILTER_IGNORE
                p.queue_redraw()
        get_viewport().push_input(press)

## While a pin steers the choice, the pins keep standing at the live ends:
## the held pin slides under the still finger, the other holds its ground.
func _follow_drag() -> void:
        if _label != null and is_instance_valid(_label):
                _place_pins()

func _end_drag() -> void:
        _dragging = false
        _drag_pin = null
        _saw_press = false
        for p: Control in [_from, _to]:
                p.mouse_filter = Control.MOUSE_FILTER_STOP
                p.queue_redraw()

## The lift a pin's drag ends by never comes back to the pin (it opened its
## filter the moment the drag began, and the engine gave the label the
## mouse's focus with the press the pin spoke). So the release is heard
## here, before the gui routes it on to the label that owns it.
func _input(event: InputEvent) -> void:
        if not _dragging:
                return
        var lifted := false
        if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
                lifted = true
        elif event is InputEventScreenTouch and not event.pressed:
                lifted = true
        if lifted:
                _end_drag()

## One drop, drawn: a tail reaching up from a round head, the tip touching
## the line the choice ends on. Gold, the wash's own metal, with the deep
## edge so it reads against the paper and against the chosen words alike.
func _draw_pin(pin: Control) -> void:
        var active := pin == _drag_pin
        var fill := ThemeScript.GOLD
        var edge := ThemeScript.GOLD_DEEP
        if active:
                fill = ThemeScript.GOLD_DEEP
        var center := HEAD_AT
        # The tail: a slim triangle from the head's shoulders up to the tip.
        pin.draw_colored_polygon(PackedVector2Array([
                center + Vector2(-5.0, -HEAD_R + 3.0),
                center + Vector2(5.0, -HEAD_R + 3.0),
                TIP,
        ]), fill)
        pin.draw_circle(center, HEAD_R, fill)
        pin.draw_arc(center, HEAD_R - 1.0, 0.0, TAU, 40, edge, 1.6, true)
        pin.draw_arc(TIP + Vector2(0.0, -1.0), 2.2, 0.0, TAU, 16, edge, 1.4, true)
