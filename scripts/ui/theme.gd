class_name TathbitTheme
extends RefCounted

## The app's wardrobe: one warm paper palette, three typefaces, and the few
## numbers every screen shares. Nothing here draws -- it only dresses, so a
## heading on the home card is the same heading everywhere.
##
## Arabic verses wear Amiri, a Naskh typeface cut for Quranic text; Persian
## wears Vazirmatn, whose calm sans keeps long translations restful; the
## interface wears Vazirmatn too, so the chrome and the content agree.

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
const VAZIR := "res://assets/fonts/Vazirmatn-Regular.ttf"
const VAZIR_BOLD := "res://assets/fonts/Vazirmatn-Bold.ttf"

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
## move -- rest is also an answer.
static func count_up(label: Label, to: int, duration := 0.55) -> void:
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


static func button_stylebox(color: Color, radius := 22) -> StyleBoxFlat:
        var box := StyleBoxFlat.new()
        box.bg_color = color
        box.set_corner_radius_all(radius)
        return box


static func outline_stylebox(color: Color, width := 2, radius := 22) -> StyleBoxFlat:
        var box := StyleBoxFlat.new()
        box.bg_color = Color(1, 1, 1, 0.55)
        box.border_color = color
        box.set_border_width_all(width)
        box.set_corner_radius_all(radius)
        return box
