class_name StudyEmptyDialog
extends ColorRect
const ThemeScript := preload("res://scripts/ui/theme.gd")
const I18nScript := preload("res://scripts/ui/i18n.gd")

## The session door's answer when the day holds nothing: not a silence the
## reader has to wonder about, but a small page that says so plainly and
## holds out the one thing a caught-up deck can still take -- a new card of
## the reader's own. It stands over whatever screen the reader came from
## (the foot's study door is on every page), the way the conflict dialog
## stands over a sync: the question of the moment, asked and gone.

signal new_card_requested

var _panel: PanelContainer


func _ready() -> void:
        color = Color(0.10, 0.14, 0.11, 0.0)
        mouse_filter = Control.MOUSE_FILTER_STOP
        set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        # A question asked on a right-reading page is asked the way that
        # page reads: the row of answers runs from the reading's own start.
        layout_direction = (
                Control.LAYOUT_DIRECTION_RTL if I18nScript.is_rtl()
                else Control.LAYOUT_DIRECTION_LTR
        )
        resized.connect(_layout)
        call_deferred("_layout")
        # The dim arrives with the card on it, not before it: a screen that
        # darkens before it has anything to say reads as a freeze.
        var dim := create_tween()
        dim.tween_property(self, "color:a", 0.55, 0.18)

        var center := CenterContainer.new()
        center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        center.mouse_filter = Control.MOUSE_FILTER_IGNORE
        add_child(center)

        var panel := PanelContainer.new()
        panel.name = "Panel"
        panel.add_theme_stylebox_override("panel", ThemeScript.card_stylebox())
        center.add_child(panel)
        _panel = panel

        var pad := MarginContainer.new()
        for side in ["left", "right"]:
                pad.add_theme_constant_override("margin_" + side, 26)
        for side in ["top", "bottom"]:
                pad.add_theme_constant_override("margin_" + side, 24)
        panel.add_child(pad)

        var box := VBoxContainer.new()
        box.add_theme_constant_override("separation", 10)
        pad.add_child(box)

        var title := Label.new()
        title.name = "Title"
        title.text = I18nScript.t("Nothing to review right now")
        title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        ThemeScript.dress(title, ThemeScript.TITLE, ThemeScript.GREEN_DEEP, true)
        box.add_child(title)

        var body := Label.new()
        body.name = "Body"
        body.text = I18nScript.t(
                "There is no card waiting — not a review, not a new one. You can add a new card to your deck."
        )
        body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        ThemeScript.dress(body, ThemeScript.BODY, ThemeScript.INK)
        box.add_child(body)

        # The one errand a caught-up deck can still take, in the place the
        # app's own gold always arrives at; beside it, the quiet way back to
        # the page the reader came from.
        var row := HBoxContainer.new()
        row.name = "Actions"
        row.alignment = BoxContainer.ALIGNMENT_CENTER
        row.add_theme_constant_override("separation", 10)
        box.add_child(row)

        var add := ThemeScript.primary_button(I18nScript.t("New card"), 46)
        add.name = "AddCard"
        add.custom_minimum_size = Vector2(150, 0)
        add.tooltip_text = I18nScript.t("Add a new card to your deck")
        add.pressed.connect(func() -> void: new_card_requested.emit())
        row.add_child(add)

        var close := ThemeScript.ghost_button(I18nScript.t("Close"), ThemeScript.INK_SOFT, 46, 22)
        close.name = "Close"
        close.custom_minimum_size = Vector2(110, 0)
        close.tooltip_text = I18nScript.t("Back to the page you came from")
        close.pressed.connect(_close)
        row.add_child(close)

        # The card fades in where the container put it -- a position tween
        # would fight the CenterContainer's own layout: appear() reads the
        # panel's y before the container's first sort has placed it, and the
        # slide then drags the card off the vertical centre (it showed in
        # Firefox, where no late resize came to lay the card straight again).
        # settle_in is the helper written for exactly this: children of
        # containers fade, and the container keeps the geometry.
        ThemeScript.settle_in(panel, 0.0, 0.26)


## The question answered by the way back: the key, like the close button,
## decides nothing -- the page stands again exactly as it was.
func _input(event: InputEvent) -> void:
        if event is InputEventKey and event.pressed and not event.echo:
                if event.keycode == KEY_ESCAPE:
                        _close()
                        get_viewport().set_input_as_handled()


func _close() -> void:
        queue_free()


## The card answers the window: capped at its own measure, never wider than
## what a phone can hold.
func _layout() -> void:
        if size.x <= 0.0 or _panel == null:
                return
        var avail := minf(420.0, size.x - 48.0)
        _panel.custom_minimum_size = Vector2(avail, 0)
