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
const INK_SOFT := Color("#5C6B62")
const LINE := Color("#E6DFCE")
const GREEN := Color("#1E6B52")
const GREEN_DEEP := Color("#14513D")
const GREEN_SOFT := Color("#E3EFE8")
const GOLD := Color("#C29A3B")
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

const DISPLAY := 34
const TITLE := 22
const BODY := 18
const CAPTION := 14

const RADIUS := 18
const PAD := 24
const GAP := 14

static func vazir(size: int, bold := false) -> Font:
        return load(VAZIR_BOLD if bold else VAZIR) as Font


static func amiri(size: int, bold := false) -> Font:
        return load(AMIRI_BOLD if bold else AMIRI) as Font


## Which script is this line written in? Arabic gets the Quranic face and a
## generous size; Persian gets Vazirmatn; anything else reads as plain text.
##
## The two scripts share almost every letter, so the tell is the handful that
## belong to only one: Persian writes پ چ ژ گ ک ی and the zero-width joiner;
## Arabic writes ة ى ك and the hamza forms. A line with Persian-only letters
## and no Arabic-only ones is Persian; everything else that is not Latin
## defaults to Arabic, the face a memorised line must be read in.
static func script_of(text: String) -> String:
        var arabic_only := 0
        var persian_only := 0
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
                elif _is_arabic_block(code):
                        script += 1
        if script == 0:
                return "plain"
        if persian_only > 0 and arabic_only == 0:
                return "persian"
        return "arabic"


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


static func card_stylebox(accent: Color = CARD) -> StyleBoxFlat:
        var box := StyleBoxFlat.new()
        box.bg_color = accent
        box.border_color = LINE
        box.set_border_width_all(1)
        box.set_corner_radius_all(RADIUS)
        box.shadow_color = Color(0.16, 0.2, 0.17, 0.08)
        box.shadow_size = 10
        box.shadow_offset = Vector2(0, 3)
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


## Fade a control in, sliding it a breath upward. One shot, then it settles.
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
        var running: Variant = control.get_meta("_settle_tween", false)
        if running is Tween and (running as Tween).is_valid():
                (running as Tween).kill()
        control.modulate.a = 0.0
        var tween := control.create_tween()
        control.set_meta("_settle_tween", tween)
        if delay > 0.0:
                tween.tween_interval(delay)
        tween.tween_property(control, "modulate:a", 1.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
