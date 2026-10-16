class_name TathbitTheme
extends RefCounted

## The app's wardrobe: one warm paper palette, a shelf of Quranic typefaces
## the reader chooses between, and the few numbers every screen shares.
## Nothing here draws -- it only dresses, so a heading on the home card is
## the same heading everywhere.
##
## Arabic verses wear the face the reader chose for them (Amiri Quran by
## default), Persian wears Vazirmatn, whose calm sans keeps long
## translations restful; the interface wears Vazirmatn too, so the chrome
## and the content agree.

## An inner class cannot call this file's own static functions by their bare
## name -- the parser looks for them on the inner class and finds nothing. The
## file pins itself the way every cross-file reference in this project does:
## by path, so a machine with no editor class cache boots just the same.
const THEME := preload("res://scripts/ui/theme.gd")
const I18N := preload("res://scripts/ui/i18n.gd")

const PAPER := Color("#FAF6ED")
const CARD := Color("#FFFFFF")
const INK := Color("#26302B")
const INK_SOFT := Color("#635F4E")
const LINE := Color("#E6DFCE")
const GREEN := Color("#1E6B52")
const GREEN_DEEP := Color("#14513D")
const GREEN_SOFT := Color("#E3EFE8")
const GOLD := Color("#C29A3B")
const GOLD_DEEP := Color("#8D6E24")
const GOLD_SOFT := Color("#F6EDD8")
const DANGER := Color("#B4553F")

const AMIRI := "res://assets/fonts/Amiri-Regular.ttf"
const AMIRI_BOLD := "res://assets/fonts/Amiri-Bold.ttf"
const AMIRI_QURAN := "res://assets/fonts/AmiriQuran-Regular.ttf"
const NOTO_NASKH := "res://assets/fonts/NotoNaskhArabic-Regular.ttf"
const NOTO_NASKH_BOLD := "res://assets/fonts/NotoNaskhArabic-Bold.ttf"
const VAZIR := "res://assets/fonts/Vazirmatn-Regular.ttf"
const VAZIR_BOLD := "res://assets/fonts/Vazirmatn-Bold.ttf"

## The faces a reader may choose between for the verses themselves, every
## one of them from Google Fonts and carried inside the app. The mushaf
## cut is the default because its harakat keep every curl at every size;
## Amiri is the family's reading cut; Noto Naskh Arabic is the quiet
## textbook Naskh. The labels are the fonts' own names and are never
## translated -- a font's name is its name in every language.
const AYAH_FACES := [
        {"key": "amiri_quran", "label": "Amiri Quran"},
        {"key": "amiri", "label": "Amiri"},
        {"key": "noto_naskh", "label": "Noto Naskh Arabic"},
]

## The face scripture currently wears, as the reader chose it (or the
## default before any choice). Set once at boot from the setting that
## travels with the deck, and again from Settings the moment a choice is
## made; every screen built afterwards dresses its verses in it.
static var _ayah_face := "amiri_quran"


static func set_ayah_face(key: String) -> void:
        for face in AYAH_FACES:
                if str(face["key"]) == key:
                        _ayah_face = key
                        return
        _ayah_face = "amiri_quran"


static func ayah_face_key() -> String:
        return _ayah_face


static func ayah_face_label(key: String) -> String:
        for face in AYAH_FACES:
                if str(face["key"]) == key:
                        return str(face["label"])
        return str(AYAH_FACES[0]["label"])


## The wash a selection wears. The engine's own RichTextLabel selection is a
## hard blue (0.1, 0.1, 1.0, 0.8) -- on this warm paper it reads as a spill
## from another app. A selection here is the reader's hand resting on a
## line: the gold of the page's own accents, at a whisper, with the ink left
## to speak through it.
const SELECT := Color(0.76, 0.60, 0.23, 0.30)

# Letters that belong to one script and not the other: the tell that
# separates an Arabic line from a Persian one.
const ARABIC_ONLY := [0x0629, 0x0643]  # teh marbuta, Arabic kaf
const PERSIAN_ONLY := [0x067E, 0x0686, 0x0698, 0x06AF, 0x06A9, 0x06CC, 0x06D2]
# The mushaf's own voice: fathatan through hah with sukun, and the
# superscript alef. Vocalised text is scripture; translations never carry
# these, and a bare Arabic word can.
const HARAKAT := [0x064B, 0x064C, 0x064D, 0x064E, 0x064F, 0x0650, 0x0651, 0x0652, 0x0653, 0x0654, 0x0655, 0x0670]

const DISPLAY := 34
const TITLE := 22
const BODY := 18
const CAPTION := 14

const RADIUS := 18
const PAD := 24
const GAP := 14

## The widest a card's text may run. Scripture set across a whole window is
## scripture nobody can recite: a page has edges, and the eye keeps its place
## between them. Everything wider than this centres itself instead.
const MEASURE := 720

## The line between a hand and a desk: narrower than this the page is a
## phone's -- margins tighten, rows halve, the layout leans in. The base
## canvas is 420 wide, so every phone lands below it and every desktop
## window above it.
const NARROW := 480


# --- the window the phone gives the app -----------------------------------------


## The top the phone keeps for itself -- notches, status bars, camera holes:
## whatever the display says belongs to the system above the app, read from
## the safe area against the window's own place on the screen and returned
## in design units. Zero on every desktop, where the window is its own
## whole world, and zero wherever the display reports no insets; a number a
## screen's chrome can trust only when the system actually drew one.
static func top_inset() -> float:
        return _inset_from(true)


## The same, from below: the home indicator's strip, the gesture bar -- the
## place a thumb swipes the phone itself, and so the last place a button
## should sit. Answer rows and footers ride above it.
static func bottom_inset() -> float:
        return _inset_from(false)


static func _inset_from(top: bool) -> float:
        var window := DisplayServer.window_get_size()
        if window.y <= 0:
                return 0.0
        var safe := DisplayServer.get_display_safe_area()
        var window_pos := DisplayServer.window_get_position()
        # How far the window reaches past the safe area, in the direction
        # asked about -- and no further: a window merely sitting inside the
        # safe area (every desktop window) owes nothing.
        var px := 0.0
        if top:
                px = float(safe.position.y - window_pos.y)
        else:
                px = float(window_pos.y + window.y - (safe.position.y + safe.size.y))
        if px <= 0.0 or px >= float(window.y):
                return 0.0
        var canvas := (Engine.get_main_loop() as SceneTree).root.get_visible_rect().size
        if canvas.y <= 0.0:
                return 0.0
        return px * canvas.y / float(window.y)


# --- drawn marks ----------------------------------------------------------------
#
# Neither Vazirmatn nor Amiri carries a play triangle, a status dot or a check
# mark -- typed into a button they render as tofu. So they are drawn, which
# also lets each mark sit at its own weight beside the type.


## A play triangle that becomes a small breathing column of bars while the
## recitation speaks. The app moves only in answer to a hand, with one
## exception it has always allowed: the sound itself, showing that it sounds.
class SoundMark extends Control:
        var color := GREEN
        var speaking := false
        var _t := 0.0

        func _init(p_color: Color = GREEN) -> void:
                color = p_color
                custom_minimum_size = Vector2(15, 17)

        func _process(delta: float) -> void:
                if speaking:
                        _t += delta
                        queue_redraw()

        func _draw() -> void:
                if not speaking:
                        draw_colored_polygon(
                                PackedVector2Array([Vector2(3.5, 2), Vector2(15, 8.5), Vector2(3.5, 15)]),
                                color
                        )
                        return
                for i in 4:
                        var level := 0.35 + 0.65 * absf(sin(_t * 6.0 + i * 1.9))
                        var h := 4.0 + level * 11.0
                        draw_rect(Rect2(0.5 + i * 3.8, 8.5 - h / 2.0, 2.4, h), color)


## A check inside a soft medal: the end-of-session mark, quiet as a stamp.
class CheckMark extends Control:
        func _init() -> void:
                custom_minimum_size = Vector2(64, 64)

        func _draw() -> void:
                draw_circle(Vector2(32, 32), 31.0, GOLD_SOFT)
                draw_circle(Vector2(32, 32), 31.0, Color(GOLD.r, GOLD.g, GOLD.b, 0.35))
                var points := PackedVector2Array([Vector2(21, 33), Vector2(29, 41), Vector2(44, 23)])
                draw_polyline(points, GOLD, 5.5, true)
                draw_circle(points[0], 2.75, GOLD)
                draw_circle(points[1], 2.75, GOLD)
                draw_circle(points[2], 2.75, GOLD)


## A status dot for the sync caption: the coin's state, said small, beside
## the words that explain it -- so the line reads at a glance even far from
## the corner it belongs to.
class StatusDot extends Control:
        var color := INK_SOFT
        var hollow := false

        func _init(p_color: Color = INK_SOFT, p_hollow := false) -> void:
                color = p_color
                hollow = p_hollow
                custom_minimum_size = Vector2(9, 9)
                mouse_filter = Control.MOUSE_FILTER_IGNORE

        func _draw() -> void:
                # A hollow ring is a thing not yet begun -- the shelf's "new"
                # says itself as an empty circle, the way a reader's own
                # margin notes are ringed, not filled.
                if hollow:
                        draw_arc(Vector2(4.5, 4.5), 3.4, 0.0, TAU, 24, color, 1.6, true)
                        return
                draw_circle(Vector2(4.5, 4.5), 4.0, color)
                draw_circle(Vector2(4.5, 4.5), 4.0, Color(color.r, color.g, color.b, 0.22))


## The way a new version arrives: an arrow coming down into a tray, the
## shape every app's update wears. While a new version waits outside, a
## ring around it breathes -- gold, slow, the one attention the corner
## allows itself -- so the coin is found without shouting.
class UpdateMark extends Control:
        var color := GOLD_DEEP
        var waiting := false
        var _t := 0.0

        func _init(p_color: Color = GOLD_DEEP) -> void:
                color = p_color
                custom_minimum_size = Vector2(20, 20)

        func _process(delta: float) -> void:
                if waiting:
                        _t += delta
                        queue_redraw()

        func _draw() -> void:
                var c := Vector2(10, 10)
                if waiting:
                        var breath := 0.5 + 0.5 * sin(_t * 2.4)
                        draw_arc(
                                c, 9.0, 0.0, TAU, 40,
                                Color(color.r, color.g, color.b, 0.12 + 0.30 * breath),
                                1.6, true
                        )
                # The tray that receives what arrives.
                draw_arc(Vector2(10, 15.0), 5.5, 0.0, PI, 18, color, 2.2, true)
                draw_line(Vector2(4.5, 15.0), Vector2(4.5, 15.6), color, 2.2, true)
                draw_line(Vector2(15.5, 15.0), Vector2(15.5, 15.6), color, 2.2, true)
                # The arrow itself, on its way down.
                draw_line(Vector2(10, 3.0), Vector2(10, 10.5), color, 2.2, true)
                draw_line(Vector2(6.4, 7.4), Vector2(10, 11.0), color, 2.2, true)
                draw_line(Vector2(13.6, 7.4), Vector2(10, 11.0), color, 2.2, true)

        func set_waiting(on: bool) -> void:
                waiting = on
                queue_redraw()


## The tune mark: three rules and their knobs, for the place settings live.
## The rules sit 6 px apart with slim knobs -- a mark this small reads as
## one thing only when each rule keeps a clear breath of paper under it.
class SlidersMark extends Control:
        var color := INK_SOFT

        func _init(p_color: Color = INK_SOFT) -> void:
                color = p_color
                custom_minimum_size = Vector2(18, 18)

        func _draw() -> void:
                var ys := [3.0, 9.0, 15.0]
                var xs := [12.5, 6.0, 13.5]
                for i in 3:
                        draw_line(Vector2(2, ys[i]), Vector2(16, ys[i]), color, 1.6, true)
                for i in 3:
                        draw_circle(Vector2(xs[i], ys[i]), 2.9, color)


## A speaker with its own breath of sound: the volume mark, for the one
## corner of a study session that says how loud the recitation is. A silent
## app wears the speaker alone -- no breath, nothing to hear -- so the eye
## reads the number before the hand reaches for it.
class VolumeMark extends Control:
        var color := GREEN_DEEP
        var muted := false

        func _init(p_color: Color = GREEN_DEEP) -> void:
                color = p_color
                custom_minimum_size = Vector2(20, 18)

        func _draw() -> void:
                # The speaker itself: a small box opening into a horn.
                draw_colored_polygon(
                        PackedVector2Array([
                                Vector2(2.5, 6.5), Vector2(6.5, 6.5),
                                Vector2(11.5, 2.5), Vector2(11.5, 15.5),
                                Vector2(6.5, 11.5), Vector2(2.5, 11.5),
                        ]),
                        color
                )
                if muted:
                        # A straight line through the horn: the sound is off.
                        draw_line(Vector2(13.5, 4.0), Vector2(18.5, 14.0), color, 2.0, true)
                        return
                # The breath: two arcs, the second quieter than the first.
                draw_arc(Vector2(11.0, 9.0), 5.0, -0.85, 0.85, 12, color, 1.8, true)
                draw_arc(Vector2(11.0, 9.0), 8.5, -0.75, 0.75, 12, Color(color.r, color.g, color.b, 0.55), 1.8, true)


## The volume's own small page: a speaker that mutes on press, a rule the
## hand drags, and the number it stands at -- one quiet row, the size of the
## thing it controls, with no title to read first. Both places that play a
## recitation (a session and the browser) open the same page, so loudness is
## one idea everywhere it can be changed.
class VolumePopover extends PanelContainer:
        ## Every nudge of the rule, live -- the hand hears the change as it
        ## makes it.
        signal changed(value: float)
        ## The rule's final word, once the hand has stopped moving it: what a
        ## screen persists.
        signal committed(value: float)

        var _slider: HSlider
        var _mark: VolumeMark
        var _readout: Label
        var _ticket := 0  # only the latest nudge commits
        var _loud := 1.0  # the last loudness above silence, for unmuting

        func _init() -> void:
                name = "VolumePopup"
                visible = false
                mouse_filter = Control.MOUSE_FILTER_STOP
                add_theme_stylebox_override("panel", THEME.card_stylebox())

                var pad := MarginContainer.new()
                pad.name = "Pad"
                pad.add_theme_constant_override("margin_left", 16)
                pad.add_theme_constant_override("margin_right", 16)
                pad.add_theme_constant_override("margin_top", 12)
                pad.add_theme_constant_override("margin_bottom", 12)
                add_child(pad)

                var row := HBoxContainer.new()
                row.name = "Row"
                row.add_theme_constant_override("separation", 12)
                pad.add_child(row)

                # The speaker is also the mute: one press for silence, one
                # press for the loudness silence replaced.
                var mute := Button.new()
                mute.name = "Mute"
                mute.custom_minimum_size = Vector2(38, 38)
                mute.tooltip_text = I18N.t("Mute or unmute")
                THEME.apply_mark_styles(mute, THEME.mark_button_styles(GREEN, true))
                _mark = VolumeMark.new(GREEN_DEEP)
                _mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
                var mute_center := CenterContainer.new()
                mute_center.name = "Centre"
                mute_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
                mute_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
                mute_center.add_child(_mark)
                mute.add_child(mute_center)
                THEME.pressable(mute)
                mute.pressed.connect(_toggle_mute)
                row.add_child(mute)

                _slider = HSlider.new()
                _slider.name = "Slider"
                _slider.min_value = 0.0
                _slider.max_value = 1.0
                _slider.step = 0.01
                _slider.custom_minimum_size = Vector2(170, 36)
                _slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
                var track := StyleBoxFlat.new()
                track.bg_color = Color("#E6DFCE")
                track.set_corner_radius_all(4)
                track.content_margin_top = 4
                track.content_margin_bottom = 4
                var filled := StyleBoxFlat.new()
                filled.bg_color = GREEN
                filled.set_corner_radius_all(4)
                filled.content_margin_top = 4
                filled.content_margin_bottom = 4
                _slider.add_theme_stylebox_override("slider", track)
                _slider.add_theme_stylebox_override("grabber_area", filled)
                _slider.add_theme_stylebox_override("grabber_area_highlight", filled)
                _slider.add_theme_icon_override("grabber", THEME.knob_icon(18, GREEN_DEEP))
                _slider.add_theme_icon_override("grabber_highlight", THEME.knob_icon(22, GREEN_DEEP))
                _slider.add_theme_icon_override("grabber_disabled", THEME.knob_icon(18, Color("#9AA79E")))
                _slider.value_changed.connect(_on_dragged)
                row.add_child(_slider)

                _readout = Label.new()
                _readout.name = "Readout"
                _readout.custom_minimum_size = Vector2(46, 0)
                _readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
                _readout.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
                THEME.dress(_readout, CAPTION, INK)
                row.add_child(_readout)
                _say(1.0)

        ## Say a loudness without saying it out loud: the rule, the mark and
        ## the number move to it, and no signal leaves -- for a screen
        ## restating what it already knows.
        func set_volume(v: float) -> void:
                _slider.set_value_no_signal(clampf(v, 0.0, 1.0))
                _say(_slider.value)

        func _on_dragged(v: float) -> void:
                _say(v)
                changed.emit(v)
                _commit_later()

        func _toggle_mute() -> void:
                var v := 0.0
                if _slider.value <= 0.005:
                        v = _loud if _loud > 0.005 else 1.0
                _slider.set_value_no_signal(v)
                _say(v)
                changed.emit(v)
                committed.emit(v)

        ## What the page says about a loudness: the mark goes quiet at
        ## silence, the number keeps the number's own place.
        func _say(v: float) -> void:
                if v > 0.005:
                        _loud = v
                _mark.muted = v <= 0.005
                _mark.queue_redraw()
                _readout.text = "%d%%" % int(round(v * 100.0))

        ## A save waits for the hand to stop moving: only the latest nudge
        ## commits, so one drag is one word, not one per tick along it.
        func _commit_later() -> void:
                _ticket += 1
                var ticket := _ticket
                var tree := (Engine.get_main_loop() as SceneTree)
                if tree == null:
                        return
                tree.create_timer(0.45).timeout.connect(func() -> void:
                        if ticket == _ticket:
                                committed.emit(_slider.value)
                )


## The volume's own small rig, as one thing every screen that can play a
## recitation shares: the popup under the coin, its opening and closing, and
## the loudness said once to the player and the coin's face -- so no screen's
## copy of the plumbing can drift from another's. The screen keeps its own
## `volume` and its own `volume_changed` signal (the one place a remembered
## loudness is read and the one place it is spoken); the rig reads and writes
## the number through the screen, and finds the coin's face wherever the
## screen's own bar hid it.
class VolumeRig extends RefCounted:
        var _screen: Control
        var _player: AudioStreamPlayer
        var _popup: VolumePopover

        func _init(screen: Control, player: AudioStreamPlayer) -> void:
                _screen = screen
                _player = player
                apply(float(screen.get("volume")))

        ## The popup itself, wired and named, ready to be added as the last
        ## child of the screen it speaks for.
        func popup() -> Control:
                var node := VolumePopover.new()
                node.changed.connect(apply)
                node.committed.connect(func(v: float) -> void:
                        (_screen as Object).emit_signal("volume_changed", v)
                )
                _popup = node
                return node

        func toggle() -> void:
                if _popup == null or not is_instance_valid(_popup) or not _popup.is_inside_tree():
                        return
                _popup.visible = not _popup.visible
                if _popup.visible:
                        _popup.set_volume(float(_screen.get("volume")))
                        THEME.settle_in(_popup, 0.0, 0.16)

        ## Loudness to the screen's own word, the player and the coin's face
        ## -- one place, so they can never disagree. linear_to_db(0) is
        ## negative infinity; a true zero is its own quiet floor instead,
        ## silence for the ear and a number for the maths.
        func apply(v: float) -> void:
                var loud := clampf(v, 0.0, 1.0)
                (_screen as Object).set("volume", loud)
                if _player != null and is_instance_valid(_player):
                        _player.volume_db = linear_to_db(maxf(loud, 0.0001))
                var mark := _coin_mark()
                if mark != null:
                        mark.muted = loud <= 0.005
                        mark.queue_redraw()

        ## The coin's own face, found under the top bar wherever the bar put
        ## it -- one screen tucks its coin under a Pair, another leaves it
        ## bare. Only the bar is searched, so the popup's own speaker never
        ## answers for the coin.
        func _coin_mark() -> VolumeMark:
                var bar := _screen.get_node_or_null("Margin/Column/TopBar")
                if bar == null:
                        return null
                return _find_mark(bar)

        func _find_mark(node: Node) -> VolumeMark:
                if node is VolumeMark:
                        return node
                for child in node.get_children():
                        var found := _find_mark(child)
                        if found != null:
                                return found
                return null


## A round grabber for a slider, drawn rather than typed: a white disc in a
## coloured ring, at 4x and scaled down so its edge lands soft. The engine's
## own grabber is a grey plastic bead from another app.
static func knob_icon(diameter: int, ring_color: Color) -> ImageTexture:
        var scale := 4
        var side := diameter * scale
        var image := Image.create(side, side, false, Image.FORMAT_RGBA8)
        var c := Vector2(side, side) / 2.0
        var r_outer := float(side) / 2.0 - float(scale)
        var r_ring := r_outer - 2.4 * float(scale)
        for y in side:
                for x in side:
                        var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
                        if d > r_outer:
                                continue
                        var col := Color(1, 1, 1, 1)
                        if d > r_ring:
                                col = ring_color
                        image.set_pixel(x, y, col)
        return ImageTexture.create_from_image(image)


## The switch a promise is made with: a rounded rule and the knob that
## crosses it, drawn -- on in the app's green, off in the page's own grey.
## The engine's checkbox is a grey plastic bead beside a dot; a promise this
## quiet deserves a switch that reads as one from across the room.
class SwitchMark extends Control:
        var on := false
        var track_on := GREEN
        var track_off := Color("#D8CFBC")

        func _init(p_on := false) -> void:
                on = p_on
                custom_minimum_size = Vector2(40, 22)
                mouse_filter = Control.MOUSE_FILTER_IGNORE

        func _draw() -> void:
                var r := 10.0
                draw_rect(Rect2(1, 1, 38, 20), track_on if on else track_off, true)
                # A breath of light on the track's far side, so the knob has
                # somewhere to have come from.
                var knob := Vector2(30.0, 11.0) if on else Vector2(11.0, 11.0)
                draw_circle(knob, 8.0, Color.WHITE)
                draw_circle(knob, 8.0, Color(0, 0, 0, 0.06))

        func set_on(p_on: bool) -> void:
                on = p_on
                queue_redraw()


## The way a list opens: a chevron that has somewhere to point. Closed it
## points onward, the direction of reading; open it points down, into what
## it opened -- the same arrow, turned by hand-drawing rather than by
## rotation, so it never swings outside its own box.
class DisclosureMark extends Control:
        var color := INK_SOFT
        var open := false

        func _init(p_color: Color = INK_SOFT) -> void:
                color = p_color
                custom_minimum_size = Vector2(14, 14)
                mouse_filter = Control.MOUSE_FILTER_IGNORE

        func _draw() -> void:
                var head := Vector2(11, 5) if open else Vector2(5, 2)
                var fall := Vector2(3, 8) if open else Vector2(11, 7)
                draw_polyline(
                        PackedVector2Array([head, Vector2(7, 10 if open else 7), fall]),
                        color,
                        2.2,
                        true
                )


## A chevron pointing back the way the user came: the universal way out.
class BackMark extends Control:
        var color := INK

        func _init(p_color: Color = INK) -> void:
                color = p_color
                custom_minimum_size = Vector2(14, 22)

        func _draw() -> void:
                draw_polyline(
                        PackedVector2Array([Vector2(11, 3), Vector2(4, 11), Vector2(11, 19)]),
                        color,
                        2.4,
                        true
                )


## The way onward, for the one button that begins a session.
class AheadMark extends Control:
        var color := Color.WHITE

        func _init(p_color: Color = Color.WHITE) -> void:
                color = p_color
                custom_minimum_size = Vector2(14, 22)

        func _draw() -> void:
                draw_polyline(
                        PackedVector2Array([Vector2(3, 3), Vector2(10, 11), Vector2(3, 19)]),
                        color,
                        2.4,
                        true
                )


## A pencil at a diagonal, tip down-left: the mark of the one action that
## rewrites the page it stands on. Drawn like every other mark, because no
## font in this app carries a pencil, and a drawn pencil keeps the app's own
## weight of line.
class PencilMark extends Control:
        var color := INK

        func _init(p_color: Color = INK) -> void:
                color = p_color
                custom_minimum_size = Vector2(18, 18)

        func _draw() -> void:
                # The shaft, from the eraser end down to the tip.
                draw_line(Vector2(5.6, 12.4), Vector2(12.2, 5.8), color, 3.0, true)
                # The tip: a small triangle pointing to the page's corner.
                draw_colored_polygon(
                        PackedVector2Array([
                                Vector2(3.0, 15.0), Vector2(6.6, 13.4), Vector2(4.6, 10.4),
                        ]),
                        color
                )
                # The eraser: a softer cap on the far end.
                draw_line(
                        Vector2(12.6, 5.4), Vector2(14.6, 7.4), Color(color.r, color.g, color.b, 0.55),
                        3.0, true
                )


## Two circular arrows, hand over hand: sync, in plain sight. While the
## work is actually running the mark turns, slowly -- the one motion the
## app allows itself for ongoing work, the recitation's bars being the
## other -- and when the work ends it settles upright at the nearest
## full turn, the way a wheel stops.
class SyncMark extends Control:
        var color := GREEN_DEEP
        var working := false

        func _init(p_color: Color = GREEN_DEEP) -> void:
                color = p_color
                custom_minimum_size = Vector2(20, 20)

        func _process(delta: float) -> void:
                if working:
                        # The turn is about the mark's own centre: rotation
                        # pivots at the top-left corner unless the pivot is
                        # set, and a mark swinging out of its coin is a mark
                        # that has left the button it lives in.
                        pivot_offset = size / 2.0
                        rotation += delta * 1.5

        func _draw() -> void:
                var c := Vector2(10, 10)
                var r := 7.0
                # One arrow sweeps down and around to the left...
                var a_from := deg_to_rad(-30.0)
                var a_to := deg_to_rad(150.0)
                draw_arc(c, r, a_from, a_to, 28, color, 2.2, true)
                _head(c + Vector2(cos(a_to), sin(a_to)) * r, a_to + PI / 2.0)
                # ...and its twin sweeps up and around to the right.
                var b_from := deg_to_rad(150.0)
                var b_to := deg_to_rad(330.0)
                draw_arc(c, r, b_from, b_to, 28, color, 2.2, true)
                _head(c + Vector2(cos(b_to), sin(b_to)) * r, b_to + PI / 2.0)

        func _head(at: Vector2, direction: float) -> void:
                var dir := Vector2(cos(direction), sin(direction))
                var n := Vector2(-dir.y, dir.x)
                draw_colored_polygon(
                        PackedVector2Array([at + n * 2.6, at - n * 2.6, at + dir * 4.8]),
                        color
                )

        ## Work beginning and work ending: the turn only runs while there is
        ## something to turn for, and it finishes standing up.
        func set_working(on: bool) -> void:
                working = on
                if on:
                        return
                var upright := TAU * ceilf(rotation / TAU) if rotation > 0.0 else 0.0
                var tween := create_tween()
                tween.tween_property(self, "rotation", upright, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## A title-page ornament: a small eight-pointed star riding a short rule,
## the way a reverent book dresses the space under its name. One mark, gold,
## quiet -- the paper pattern's lattice in miniature.
class OrnamentMark extends Control:
        var color := GOLD

        func _init(p_color: Color = GOLD) -> void:
                color = p_color
                custom_minimum_size = Vector2(84, 18)
                mouse_filter = Control.MOUSE_FILTER_IGNORE

        func _draw() -> void:
                var c := size / 2.0
                var tint := Color(color.r, color.g, color.b, 0.7)
                var gap := 14.0
                draw_line(Vector2(4, c.y), Vector2(c.x - gap, c.y), tint, 1.4, true)
                draw_line(Vector2(c.x + gap, c.y), Vector2(size.x - 4, c.y), tint, 1.4, true)
                for turn in [0.0, PI / 8.0]:
                        var points := PackedVector2Array()
                        for i in 4:
                                var ang: float = float(turn) + TAU * i / 4.0
                                points.append(c + Vector2(cos(ang), sin(ang)) * 5.5)
                        points.append(points[0])
                        draw_polyline(points, GOLD_DEEP, 1.5, true)


## A chapter's own mark: the eight-pointed star of the paper's lattice,
## drawn small beside a surah's name -- the rosette a mushaf sets before
## its surahs' titles, in miniature, gold and quiet.
class StarMark extends Control:
        var color := GOLD

        func _init(p_color: Color = GOLD) -> void:
                color = p_color
                custom_minimum_size = Vector2(14, 14)
                mouse_filter = Control.MOUSE_FILTER_IGNORE

        func _draw() -> void:
                var c := size / 2.0
                for turn in [0.0, PI / 8.0]:
                        var points := PackedVector2Array()
                        for i in 4:
                                var ang: float = float(turn) + TAU * i / 4.0
                                points.append(c + Vector2(cos(ang), sin(ang)) * 6.0)
                        points.append(points[0])
                        draw_polyline(points, color, 1.4, true)
                draw_circle(c, 1.5, color)


## A still lattice of eight-pointed stars behind the page: the margin
## decoration of a reverent book, drawn once in gold at a whisper. It never
## moves and never competes -- cards and words sit on top of it.
class PaperPattern extends Control:
        var spacing := 148.0
        var star := 14.0
        var tint := Color(GOLD.r, GOLD.g, GOLD.b, 0.075)

        func _ready() -> void:
                mouse_filter = Control.MOUSE_FILTER_IGNORE

        func _draw() -> void:
                if size.x <= 0.0 or size.y <= 0.0:
                        return
                var rows := int(ceil(size.y / spacing)) + 1
                var cols := int(ceil(size.x / spacing)) + 1
                for row in rows:
                        var offset := spacing / 2.0 if row % 2 == 1 else 0.0
                        for col in cols:
                                _star(Vector2(col * spacing + offset, row * spacing))

        ## Rub el Hizb: two squares, one turned a half-step, eight points.
        func _star(at: Vector2) -> void:
                for turn in [0.0, PI / 8.0]:
                        var points := PackedVector2Array()
                        for i in 4:
                                var ang: float = float(turn) + TAU * i / 4.0
                                points.append(at + Vector2(cos(ang), sin(ang)) * star)
                        points.append(points[0])
                        draw_polyline(points, tint, 1.1, true)


## A one-pixel rule the colour of the page's edges: for dividing a card's
## interior without drawing a box around it.
static func hairline(color: Color = LINE) -> Control:
        var rule := PanelContainer.new()
        rule.name = "Hairline"
        rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
        rule.custom_minimum_size = Vector2(0, 2)
        rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        var box := StyleBoxFlat.new()
        box.bg_color = Color(color.r, color.g, color.b, 0.55)
        box.set_corner_radius_all(1)
        box.content_margin_top = 0.5
        box.content_margin_bottom = 0.5
        rule.add_theme_stylebox_override("panel", box)
        return rule


## A slow paper gradient behind everything: the screen breathes top-to-bottom
## instead of sitting on one flat colour. Every screen wears the same one, so
## moving between them feels like turning pages of the same book. A
## TextureRect, not a ColorRect -- a ColorRect cannot carry a texture, and
## assigning one to it is silently swallowed on every build.
static func paper_backdrop() -> Control:
        var rect := TextureRect.new()
        rect.name = "Backdrop"
        rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
        rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        var gradient := Gradient.new()
        gradient.colors = PackedColorArray([Color("#FBF8F0"), Color("#F0E8D5")])
        var texture := GradientTexture2D.new()
        texture.gradient = gradient
        texture.fill_from = Vector2(0, 0)
        texture.fill_to = Vector2(0, 1)
        rect.texture = texture
        rect.stretch_mode = TextureRect.STRETCH_SCALE
        return rect


## The star lattice, full-rect, behind the page's margins.
static func paper_pattern() -> PaperPattern:
        var pattern := PaperPattern.new()
        pattern.name = "Pattern"
        pattern.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        return pattern


## The engine's scrollbar is a grey plastic ridge from another app. This one
## is a slim rail the colour of the page's edges, with a gold thumb while it
## is being dragged -- present when needed, invisible when not. The item
## names are 4.x's own ("scroll", "grabber"): the 3.x names do nothing
## here, quietly, which is how a grey scrollbar sneaks back in.
static func style_scroll(scroll: ScrollContainer) -> void:
        var empty := StyleBoxEmpty.new()
        var grabber := StyleBoxFlat.new()
        grabber.bg_color = Color("#DCD2BD")
        grabber.set_corner_radius_all(4)
        grabber.content_margin_left = 3
        grabber.content_margin_right = 3
        var grabbed := StyleBoxFlat.new()
        grabbed.bg_color = GOLD_SOFT
        grabbed.set_corner_radius_all(4)
        grabbed.content_margin_left = 3
        grabbed.content_margin_right = 3
        var bar := scroll.get_v_scroll_bar()
        bar.add_theme_stylebox_override("scroll", empty)
        bar.add_theme_stylebox_override("scroll_focus", empty)
        bar.add_theme_stylebox_override("grabber", grabber)
        bar.add_theme_stylebox_override("grabber_highlight", grabber)
        bar.add_theme_stylebox_override("grabber_pressed", grabbed)


# --- the shared buttons -----------------------------------------------------------


## Every button answers the hand before the click lands. Three states, one
## voice: visited grows a breath (2%), held settles toward its centre
## (3.5%), let go returns to whichever of the two it is still in -- so a
## click while hovering never pops, and leaving while held never jumps.
## One helper, wired once, so the whole app agrees on what a press feels
## like -- on the mouse and, through the same scale, on the keyboard.
static func pressable(button: Button, press_scale := 0.965, hover_scale := 1.02) -> void:
        button.resized.connect(func() -> void:
                if button.size.x > 0.0:
                        button.pivot_offset = button.size / 2.0
        )
        var state := {"hovered": false, "held": false}
        var apply := func() -> void:
                var target := 1.0
                if state["held"]:
                        target = press_scale
                elif state["hovered"]:
                        target = hover_scale
                _scale_to(button, target, 0.13)
        button.mouse_entered.connect(func() -> void:
                state["hovered"] = true
                apply.call()
        )
        button.mouse_exited.connect(func() -> void:
                state["hovered"] = false
                apply.call()
        )
        button.button_down.connect(func() -> void:
                state["held"] = true
                apply.call()
        )
        button.button_up.connect(func() -> void:
                state["held"] = false
                apply.call()
        )
        # The keyboard's press rides the focus path, which never touches
        # button_down/up: route it through the same states so Enter feels
        # like the mouse does.
        button.focus_entered.connect(func() -> void:
                if state["held"]:
                        return
                state["hovered"] = true
                apply.call()
        )
        button.focus_exited.connect(func() -> void:
                if state["held"]:
                        return
                state["hovered"] = false
                apply.call()
        )


static func _scale_to(button: Button, to: float, duration: float) -> void:
        # has_meta, not get_meta's default: 4.7's get_meta prints an ERROR for
        # a missing key even when a default is given, so a button's first
        # hover would cry wolf in the console once apiece.
        var running: Variant = button.get_meta("_press_tween") if button.has_meta("_press_tween") else null
        if running is Tween and (running as Tween).is_valid():
                (running as Tween).kill()
        var tween := button.create_tween()
        button.set_meta("_press_tween", tween)
        tween.tween_property(button, "scale", Vector2(to, to), duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## The filled green: the one button on a screen that means "go".
static func primary_button(label_text: String, height := 56) -> Button:
        var button := Button.new()
        button.text = label_text
        button.custom_minimum_size = Vector2(0, height)
        button.add_theme_font_override("font", vazir(BODY + 2, true))
        button.add_theme_font_size_override("font_size", BODY + 2)
        button.add_theme_color_override("font_color", Color.WHITE)
        button.add_theme_color_override("font_hover_color", Color.WHITE)
        button.add_theme_color_override("font_pressed_color", Color.WHITE)
        button.add_theme_color_override("font_focus_color", Color.WHITE)
        button.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.72))
        button.add_theme_stylebox_override("normal", button_stylebox(GREEN))
        button.add_theme_stylebox_override("hover", button_stylebox(GREEN_DEEP))
        button.add_theme_stylebox_override("pressed", button_stylebox(GREEN_DEEP))
        button.add_theme_stylebox_override("disabled", button_stylebox(Color("#9AA79E")))
        var focus := button_stylebox(GREEN_DEEP)
        focus.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.9)
        focus.set_border_width_all(2)
        button.add_theme_stylebox_override("focus", focus)
        pressable(button)
        return button


## The outline: a second thought, in the tone of whatever it leads to.
static func ghost_button(label_text: String, tone: Color, height := 46, radius := 23) -> Button:
        var button := Button.new()
        button.text = label_text
        button.custom_minimum_size = Vector2(0, height)
        button.add_theme_font_override("font", vazir(BODY))
        button.add_theme_font_size_override("font_size", BODY)
        button.add_theme_color_override("font_color", tone)
        button.add_theme_color_override("font_hover_color", tone)
        button.add_theme_color_override("font_pressed_color", tone)
        button.add_theme_color_override("font_focus_color", tone)
        button.add_theme_stylebox_override("normal", outline_stylebox(tone, 2, radius))
        var held := outline_stylebox(tone, 2, radius)
        held.bg_color = Color(tone.r, tone.g, tone.b, 0.10)
        button.add_theme_stylebox_override("hover", held)
        button.add_theme_stylebox_override("pressed", held)
        var ring := outline_stylebox(Color(tone.r, tone.g, tone.b, 0.55), 2, radius)
        button.add_theme_stylebox_override("focus", ring)
        pressable(button)
        return button


## The styleboxes of a quiet square icon button (back marks, corner coins):
## nothing at rest, a wash while visited, a soft ring while focused. With
## `wash`, the coin is visible at rest too -- a tinted roundel in the
## button's own tone, deepening when visited -- for the corner buttons a
## first-time reader has to find.
static func mark_button_styles(tone: Color = INK, wash := false) -> Dictionary:
        var rest := StyleBoxFlat.new()
        rest.bg_color = Color(tone.r, tone.g, tone.b, 0.08) if wash else Color(0, 0, 0, 0)
        rest.set_corner_radius_all(24)
        var hover := StyleBoxFlat.new()
        hover.bg_color = Color(tone.r, tone.g, tone.b, 0.16) if wash else Color(tone.r, tone.g, tone.b, 0.08)
        hover.set_corner_radius_all(24)
        var focus := StyleBoxFlat.new()
        focus.bg_color = Color(0, 0, 0, 0)
        focus.border_color = Color(tone.r, tone.g, tone.b, 0.55)
        focus.set_border_width_all(2)
        focus.set_corner_radius_all(24)
        return {"normal": rest, "hover": hover, "pressed": hover, "focus": focus}


## Apply a stylebox dictionary from mark_button_styles() to its button.
static func apply_mark_styles(button: Button, styles: Dictionary) -> void:
        button.add_theme_stylebox_override("normal", styles["normal"])
        button.add_theme_stylebox_override("hover", styles["hover"])
        button.add_theme_stylebox_override("pressed", styles["pressed"])
        button.add_theme_stylebox_override("focus", styles["focus"])


## One voice for every plain label: the face, the size, the colour, one
## call -- so no screen's body text drifts from another's.
static func dress(label: Label, size: int, color: Color, bold := false) -> Label:
        label.add_theme_font_override("font", vazir(size, bold))
        label.add_theme_font_size_override("font_size", size)
        label.add_theme_color_override("font_color", color)
        return label


## One shared header for the screens that sit on top of home: a back mark
## that says where it goes, a title in the middle, room on the right for
## whatever only that screen needs. The same bones everywhere, so leaving is
## never a new thing to learn.
static func top_bar(title_text: String) -> Dictionary:
        var row := HBoxContainer.new()
        row.name = "TopBar"
        row.custom_minimum_size = Vector2(0, 48)

        var back := Button.new()
        back.name = "Back"
        back.custom_minimum_size = Vector2(48, 48)
        apply_mark_styles(back, mark_button_styles())
        back.add_child(_centered_mark(BackMark.new(INK)))
        pressable(back)
        row.add_child(back)

        var title := Label.new()
        title.name = "Title"
        title.text = title_text
        title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        title.add_theme_font_override("font", vazir(TITLE, true))
        title.add_theme_font_size_override("font_size", TITLE)
        title.add_theme_color_override("font_color", GREEN_DEEP)
        row.add_child(title)

        var right := Control.new()
        right.name = "Right"
        right.custom_minimum_size = Vector2(48, 48)
        row.add_child(right)
        return {"row": row, "back": back, "title": title, "right": right}


static func _centered_mark(mark: Control) -> CenterContainer:
        var center := CenterContainer.new()
        center.name = "Mark"
        center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        center.mouse_filter = Control.MOUSE_FILTER_IGNORE
        mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
        center.add_child(mark)
        return center


## A round grabber for a slider, drawn rather than typed: no icon font in
## this app, and the engine's default grabber is a grey plastic bead from
## another app. The circle is drawn at 4x and scaled down, so its edge
## lands soft instead of stair-stepped.
static func circle_icon(diameter: int, color: Color, ring := false) -> ImageTexture:
        var scale := 4
        var side := diameter * scale
        var image := Image.create(side, side, false, Image.FORMAT_RGBA8)
        var c := Vector2(side, side) / 2.0
        var r_fill := float(side) / 2.0 - float(scale)
        var r_ring := r_fill - 2.0 * float(scale)
        for y in side:
                for x in side:
                        var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
                        var alpha := 0.0
                        if d <= r_fill:
                                alpha = 1.0
                                if ring and d < r_ring:
                                        alpha = 0.0
                        if alpha > 0.0:
                                image.set_pixel(x, y, Color(color.r, color.g, color.b, alpha))
        var texture := ImageTexture.create_from_image(image)
        return texture


## A small key cap, the way a key looks on the keyboard it names.
static func key_chip(label_text: String) -> PanelContainer:
        var chip := PanelContainer.new()
        chip.add_theme_stylebox_override("panel", soft_stylebox(Color(INK.r, INK.g, INK.b, 0.07), 7))
        chip.add_theme_constant_override("margin_left", 7)
        chip.add_theme_constant_override("margin_right", 7)
        chip.add_theme_constant_override("margin_top", 2)
        chip.add_theme_constant_override("margin_bottom", 3)
        var label := Label.new()
        label.text = label_text
        label.add_theme_font_override("font", vazir(12, true))
        label.add_theme_font_size_override("font_size", 12)
        label.add_theme_color_override("font_color", INK_SOFT)
        chip.add_child(label)
        return chip


# --- motion ---------------------------------------------------------------------


## A number that arrives: 0 to its value over half a second, easing out,
## the way a page's own numbers do when they matter. One shot, then it
## rests. Numbers that are already 0 (nothing due, nothing learned) never
## move -- rest is also an answer -- and a number that has not changed
## since the last telling does not retell itself: a page that recounts its
## own inventory every time it is glanced at reads as nervous, not alive.
static func count_up(label: Label, to: int, duration := 0.55) -> void:
        var shown: Variant = label.get_meta("counted", -1) if label.has_meta("counted") else -1
        if int(shown) == to:
                label.text = str(to)
                return
        label.set_meta("counted", to)
        if to <= 0:
                label.text = str(to)
                return
        label.text = "0"
        var tween := label.create_tween()
        tween.tween_method(
                func(v: float) -> void: label.text = str(int(round(v))),
                0.0,
                float(to),
                duration
        ).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
        tween.tween_callback(func() -> void: label.text = str(to))


## Fade a control in, sliding it a breath. A positive distance arrives
## from below -- the direction of going deeper into the app; a negative
## one arrives from above, the direction of coming back home. One shot,
## then it settles.
static func appear(control: Control, delay := 0.0, distance := 14.0) -> void:
        if control == null:
                return
        var target_y: float = control.position.y
        control.modulate.a = 0.0
        control.position.y = target_y + distance
        var tween := control.create_tween()
        if delay > 0.0:
                tween.tween_interval(delay)
        tween.set_parallel(true)
        tween.tween_property(control, "modulate:a", 1.0, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
        tween.tween_property(control, "position:y", target_y, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Fade out and free. Screen changes call this on the outgoing screen.
static func vanish(control: Control) -> void:
        if control == null:
                return
        var tween := control.create_tween()
        tween.tween_property(control, "modulate:a", 0.0, 0.16)
        tween.tween_callback(control.queue_free)


## Fade a control in where it stands -- for the children of containers, whose
## layout a position tween would fight. One shot, then it settles.
static func settle_in(control: Control, delay := 0.0, duration := 0.22) -> void:
        if control == null:
                return
        var running: Variant = control.get_meta("_settle_tween") if control.has_meta("_settle_tween") else null
        if running is Tween and (running as Tween).is_valid():
                (running as Tween).kill()
        control.modulate.a = 0.0
        var tween := control.create_tween()
        control.set_meta("_settle_tween", tween)
        if delay > 0.0:
                tween.tween_interval(delay)
        tween.tween_property(control, "modulate:a", 1.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Arrive one after another: every child of a container settles in, each a
## beat behind the last, so a reveal reads as a sequence instead of one swap.
static func stagger_in(box: Container, step := 0.07, duration := 0.24) -> void:
        var i := 0
        for child in box.get_children():
                if child is Control:
                        settle_in(child, step * i, duration)
                        i += 1


# --- type -----------------------------------------------------------------------


static func vazir(size: int, bold := false) -> Font:
        return load(VAZIR_BOLD if bold else VAZIR) as Font


static func amiri(size: int, bold := false) -> Font:
        return load(AMIRI_BOLD if bold else AMIRI) as Font


static func quran() -> Font:
        return load(AMIRI_QURAN) as Font


static func noto_naskh(bold := false) -> Font:
        return load(NOTO_NASKH_BOLD if bold else NOTO_NASKH) as Font


## The face a verse wears, wherever scripture itself is shown: the study
## card, the open page in the library, the shelf's own preview. The reader
## chooses the hand the verses are read in (Amiri Quran by default -- the
## family's mushaf cut, the same hand with the harakat drawn larger and
## rounder, the way a vocalised text is read from). Amiri's own damma at
## the shelf's small sizes flattens into a fatha's stroke -- a reader
## learning the vowels read exactly that mistake off the preview -- and
## Amiri Quran's curl stays a curl at every size this app draws. There is
## no bold in the mushaf cut: bold scripture falls back to the family's
## own Bold, and references (which carry no vowels to lose) stay with Amiri.
static func verse_face(script: String, bold := false) -> Font:
        match script:
                "arabic":
                        return ayah_face(bold)
                _:
                        return vazir(BODY, bold)


## The chosen face itself, without asking what a line's script is: the
## verse, the question's heading, the eyebrow above an answer -- all of
## them Arabic, all of them in the hand the reader chose.
static func ayah_face(bold := false) -> Font:
        return ayah_face_for(_ayah_face, bold)


## Any face by its key, chosen or not: the settings page draws one sample
## in every face it offers, side by side, so the choice is judged on what
## it chooses rather than on a description of it.
static func ayah_face_for(key: String, bold := false) -> Font:
        match key:
                "amiri":
                        return load(AMIRI_BOLD if bold else AMIRI) as Font
                "noto_naskh":
                        return load(NOTO_NASKH_BOLD if bold else NOTO_NASKH) as Font
                _:
                        return load(AMIRI_BOLD if bold else AMIRI_QURAN) as Font


## Which script is this line written in? Arabic gets the Quranic face and a
## generous size; Persian gets Vazirmatn; anything else reads as plain text.
##
## The two scripts share almost every letter, so the tell is the handful that
## belong to only one: Persian writes پ چ ژ گ ک ی and the zero-width joiner;
## Arabic writes ة and the harakat. The rules, in order:
##
##   1. One Persian-only letter settles it -- nothing in the Arabic script
##      writes پ چ ژ گ, so a line carrying one is Persian even when it quotes
##      Arabic words in Arabic orthography. A translation that names a surah
##      is still a translation.
##   2. Harakat or an Arabic-only letter is the mushaf's own voice: vocalised
##      text is scripture.
##   3. Bare shared-script text with no tell either way is, in this deck, the
##      Persian translation -- "بنام خداوند بخشنده مهربان" carries no
##      Persian-only letter at all, yet is Persian, and rendered in Amiri at
##      scripture's size it was neither. Verses never land here: every verse
##      in this deck is vocalised.
static func script_of(text: String) -> String:
        var arabic_only := 0
        var persian_only := 0
        var harakat := 0
        var script := 0
        for i in text.length():
                var code := text.unicode_at(i)
                if code == 0x200C:  # the zero-width joiner is Persian's habit
                        persian_only += 1
                        script += 1
                elif code in ARABIC_ONLY:
                        arabic_only += 1
                        script += 1
                elif code in PERSIAN_ONLY:
                        persian_only += 1
                        script += 1
                elif code in HARAKAT:
                        harakat += 1
                        script += 1
                elif _is_arabic_block(code):
                        script += 1
        if script == 0:
                return "plain"
        if persian_only > 0:
                return "persian"
        if arabic_only > 0 or harakat > 0:
                return "arabic"
        return "persian"


## The classifier for references -- the "next up" line, the eyebrow above an
## answer, the question side of a card. A reference is a surah's name and a
## range: Arabic by construction, whether or not its letters happen to carry
## a tell (قريش carries none). So anything of the Arabic block reads as
## Arabic here, in the Quranic face, and only Latin stays plain.
static func reference_script(text: String) -> String:
        var script := 0
        for i in text.length():
                if _is_arabic_block(text.unicode_at(i)):
                        script += 1
        return "arabic" if script > 0 else "plain"


static func _is_arabic_block(code: int) -> bool:
        return (
                (code >= 0x0600 and code <= 0x06FF)
                or (code >= 0xFB50 and code <= 0xFDFF)
                or (code >= 0xFE70 and code <= 0xFEFF)
        )


static func font_for(script: String, size: int, bold := false) -> Font:
        match script:
                "arabic":
                        return amiri(size + 8, bold)
                "persian":
                        return vazir(size, bold)
                _:
                        return vazir(size, bold)


## The lean an author's asterisks asked for: neither Amiri nor Vazirmatn
## ships an italic, and RichTextLabel's [i] falls straight back to the
## normal face -- emphasis that changes nothing at all, which is how the
## deck's stars once vanished. A FontVariation sheared by hand is the
## italic the marks meant, in every script the deck is written in.
static var _lean_cache := {}

static func leaning(base: Font) -> FontVariation:
        var key := base.get_instance_id()
        if _lean_cache.has(key):
                return _lean_cache[key]
        var lean := FontVariation.new()
        lean.base_font = base
        # A shear, not a rotation: the baseline keeps its place and the
        # strokes lean the way italic type has always leaned.
        lean.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(0.24, 1.0), Vector2.ZERO)
        _lean_cache[key] = lean
        return lean


# --- surfaces -------------------------------------------------------------------


## A page lying on the desk: white, warm-edged, lifted by one deep soft
## shadow instead of a hard outline. The shadow is the app's sense of depth;
## everything that matters sits on a card like this.
static func card_stylebox(accent: Color = CARD) -> StyleBoxFlat:
        var box := StyleBoxFlat.new()
        box.bg_color = accent
        box.border_color = LINE
        box.set_border_width_all(1)
        box.set_corner_radius_all(RADIUS)
        box.shadow_color = Color(0.42, 0.34, 0.16, 0.13)
        box.shadow_size = 24
        box.shadow_offset = Vector2(0, 10)
        return box


static func soft_stylebox(color: Color, radius := RADIUS) -> StyleBoxFlat:
        var box := StyleBoxFlat.new()
        box.bg_color = color
        box.set_corner_radius_all(radius)
        return box


## A pill of the stats row: its own soft ground with a hairline of its own
## tone around it, so the number sits in a shape even on the palest fill.
static func pill_stylebox(fill: Color, edge: Color) -> StyleBoxFlat:
        var box := StyleBoxFlat.new()
        box.bg_color = fill
        box.border_color = Color(edge.r, edge.g, edge.b, 0.35)
        box.set_border_width_all(1)
        box.set_corner_radius_all(RADIUS)
        return box


static func button_stylebox(color: Color, radius := 22) -> StyleBoxFlat:
        var box := StyleBoxFlat.new()
        box.bg_color = color
        box.set_corner_radius_all(radius)
        # The go-buttons sit a breath above the page: one soft shadow under
        # each, the same light the cards already cast.
        box.shadow_color = Color(0.30, 0.22, 0.10, 0.20)
        box.shadow_size = 12
        box.shadow_offset = Vector2(0, 5)
        return box


static func outline_stylebox(color: Color, width := 2, radius := 22) -> StyleBoxFlat:
        var box := StyleBoxFlat.new()
        box.bg_color = Color(1, 1, 1, 0.55)
        box.border_color = color
        box.set_border_width_all(width)
        box.set_corner_radius_all(radius)
        return box
