class_name LanguagePicker
extends Control
const ThemeScript := preload("res://scripts/ui/theme.gd")
const I18nScript := preload("res://scripts/ui/i18n.gd")

## The app's very first question, asked once: which tongue do its own words
## speak? It stands over the home page on the first run -- the one visit
## that has no answer yet -- and never again after the choice is made (the
## answer lives in Settings afterwards, and travels with the deck so a new
## device inherits it without asking twice). The verses and their Persian
## translation are the deck's own content and never change; this chooses
## only the language of the chrome around them.
##
## Each language is named in its own script, whatever the page is speaking:
## a person finds their tongue by reading it, not by reading about it. The
## question itself is asked three times over, once in each language, so no
## answer is needed before the question can be understood.

signal chosen(code: String)

func _ready() -> void:
        set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        mouse_filter = Control.MOUSE_FILTER_STOP
        add_child(ThemeScript.paper_backdrop())
        add_child(ThemeScript.paper_pattern())
        resized.connect(_layout)
        call_deferred("_layout")

        var center := CenterContainer.new()
        center.name = "Centre"
        center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        center.mouse_filter = Control.MOUSE_FILTER_IGNORE
        add_child(center)

        var card := PanelContainer.new()
        card.name = "Card"
        card.add_theme_stylebox_override("panel", ThemeScript.card_stylebox())
        card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        center.add_child(card)

        var pad := MarginContainer.new()
        pad.name = "Pad"
        pad.add_theme_constant_override("margin_left", 30)
        pad.add_theme_constant_override("margin_right", 30)
        pad.add_theme_constant_override("margin_top", 26)
        pad.add_theme_constant_override("margin_bottom", 26)
        card.add_child(pad)

        var box := VBoxContainer.new()
        box.name = "Box"
        box.add_theme_constant_override("separation", 14)
        pad.add_child(box)

        # The app's own name, the wordmark home wears, so the question is
        # asked by the thing being asked about.
        var arabic := Label.new()
        arabic.name = "WordmarkArabic"
        arabic.text = "تثبيت القرآن"
        arabic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        arabic.add_theme_font_override("font", ThemeScript.amiri(17))
        arabic.add_theme_font_size_override("font_size", ThemeScript.fs(17))
        arabic.add_theme_color_override("font_color", ThemeScript.GOLD_DEEP)
        box.add_child(arabic)
        var latin := Label.new()
        latin.name = "WordmarkLatin"
        latin.text = "QuranTathbit"
        latin.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        ThemeScript.dress(latin, 18, ThemeScript.GREEN_DEEP, true)
        box.add_child(latin)
        box.add_child(ThemeScript.hairline())

        # The question, said in every tongue the app speaks, stacked in the
        # order the buttons stand: no translation is needed before the
        # answer can be chosen.
        var asking: Dictionary = I18nScript.STRINGS.get("Choose your language", {})
        for code in I18nScript.LANGS:
                var line := Label.new()
                line.name = "Asking" + code
                line.text = str(asking.get(code, "Choose your language"))
                line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
                ThemeScript.dress(line, ThemeScript.CAPTION, ThemeScript.INK_SOFT)
                box.add_child(line)

        var buttons := VBoxContainer.new()
        buttons.name = "Languages"
        buttons.add_theme_constant_override("separation", 10)
        box.add_child(buttons)
        for code in I18nScript.LANGS:
                buttons.add_child(_language_button(code))
        ThemeScript.stagger_in(box, 0.05, 0.24)

## One language, one wide button, named in its own script: the choice
## itself, big enough to be sure of and quiet enough not to shout. At rest
## it is a ruled field of the page -- white, hairline edge, the way the
## app's own input fields stand -- so it reads as something that gives
## under the hand, not as another line of the question.
func _language_button(code: String) -> Button:
        var button := Button.new()
        button.name = "Lang" + code
        button.custom_minimum_size = Vector2(240, 52)
        var rest := ThemeScript.soft_stylebox(ThemeScript.CARD, 14)
        rest.border_color = Color("#D9CFBB")
        rest.set_border_width_all(1)
        rest.content_margin_left = 16
        rest.content_margin_right = 16
        rest.content_margin_top = 6
        rest.content_margin_bottom = 6
        var wash := rest.duplicate() as StyleBoxFlat
        wash.bg_color = Color(
                ThemeScript.GREEN.r, ThemeScript.GREEN.g, ThemeScript.GREEN.b, 0.10
        )
        wash.border_color = ThemeScript.GREEN
        var held := rest.duplicate() as StyleBoxFlat
        held.bg_color = Color(
                ThemeScript.GREEN.r, ThemeScript.GREEN.g, ThemeScript.GREEN.b, 0.16
        )
        held.border_color = ThemeScript.GREEN
        button.add_theme_stylebox_override("normal", rest)
        button.add_theme_stylebox_override("hover", wash)
        button.add_theme_stylebox_override("pressed", held)
        button.add_theme_stylebox_override("focus", wash)
        button.add_theme_font_override("font", ThemeScript.vazir(ThemeScript.BODY + 2, true))
        button.add_theme_font_size_override("font_size", ThemeScript.fs(ThemeScript.BODY + 2))
        button.add_theme_color_override("font_color", ThemeScript.INK)
        button.add_theme_color_override("font_hover_color", ThemeScript.GREEN_DEEP)
        button.add_theme_color_override("font_pressed_color", ThemeScript.GREEN_DEEP)
        button.add_theme_color_override("font_focus_color", ThemeScript.GREEN_DEEP)
        ThemeScript.pressable(button)
        button.text = I18nScript.lang_label(code)
        button.pressed.connect(func() -> void: chosen.emit(code))
        return button

## The page answers the window: the card keeps a reader's measure and
## never runs wider than a phone can hold.
func _layout() -> void:
        if size.x <= 0.0:
                return
        var card: PanelContainer = get_node_or_null("Centre/Card")
        if card != null:
                card.custom_minimum_size = Vector2(minf(360.0, size.x - 48.0), 0.0)
