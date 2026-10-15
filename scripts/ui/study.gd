class_name StudyScreen
extends Control
const ThemeScript := preload("res://scripts/ui/theme.gd")
const CardScript := preload("res://scripts/data/card.gd")
const SchedulerScript := preload("res://scripts/data/scheduler.gd")
const CardViewScript := preload("res://scripts/ui/card_view.gd")

## A session: one card at a time, question first, then the answer, then how
## well it went. Nothing else is on screen while you study -- no counters
## arguing for attention, no menus to wander into. The four answers carry
## their own intervals, so the cost of each choice is plain before you make
## it, exactly the way Anki asks.

signal closed
signal answered(card: CardScript, button: String)

const AGAIN_COLOR := Color("#B4553F")

var _cards: Array = []
var _index := 0
var _revealed := false
var _answered_count := 0
var _player: AudioStreamPlayer
var _view: CardViewScript
var _options: Array = []

func _ready() -> void:
        _player = AudioStreamPlayer.new()
        _player.name = "Player"
        add_child(_player)
        _build()
        resized.connect(_layout)
        call_deferred("_layout")
        ThemeScript.appear(self)

func _exit_tree() -> void:
        if _player != null and is_instance_valid(_player):
                _player.queue_free()

func start(cards: Array) -> void:
        _cards = cards
        _index = 0
        _answered_count = 0
        if not is_node_ready():
                await ready
        var scroll: ScrollContainer = get_node("Margin/Column/Surface")
        scroll.get_v_scroll_bar().value = 0
        _show_front()

func _build() -> void:
        set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        var margin := MarginContainer.new()
        margin.name = "Margin"
        margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        margin.add_theme_constant_override("margin_left", 22)
        margin.add_theme_constant_override("margin_right", 22)
        margin.add_theme_constant_override("margin_top", 26)
        margin.add_theme_constant_override("margin_bottom", 26)
        add_child(margin)

        var column := VBoxContainer.new()
        column.name = "Column"
        column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        column.add_theme_constant_override("separation", 14)
        margin.add_child(column)

        column.add_child(_top_bar())
        column.add_child(_session_bar())
        column.add_child(_surface())
        column.add_child(_answers())
        if not DisplayServer.is_touchscreen_available():
                column.add_child(_key_hints())
        column.add_child(_footer())

## The session's own quiet progress: a thin bar under the top row that fills
## as cards are answered. The count label above it stays for the exact number;
## the bar is for the feeling of being nearly done.
func _session_bar() -> Control:
        var bar := ProgressBar.new()
        bar.name = "SessionBar"
        bar.show_percentage = false
        bar.custom_minimum_size = Vector2(0, 5)
        var track := StyleBoxFlat.new()
        track.bg_color = ThemeScript.LINE
        track.set_corner_radius_all(3)
        var fill := StyleBoxFlat.new()
        fill.bg_color = ThemeScript.GREEN
        fill.set_corner_radius_all(3)
        bar.add_theme_stylebox_override("background", track)
        bar.add_theme_stylebox_override("fill", fill)
        return bar

func _key_hints() -> Control:
        var label := Label.new()
        label.name = "Keys"
        label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        label.text = "Space reveals · 1–4 answer · Esc closes"
        label.add_theme_font_override("font", ThemeScript.vazir(ThemeScript.CAPTION))
        label.add_theme_font_size_override("font_size", ThemeScript.CAPTION)
        label.add_theme_color_override("font_color", ThemeScript.INK_SOFT)
        return label

func _top_bar() -> Control:
        var row := HBoxContainer.new()
        row.name = "TopBar"
        row.custom_minimum_size = Vector2(0, 40)

        var close := Button.new()
        close.name = "Close"
        close.text = "×"
        close.custom_minimum_size = Vector2(44, 40)
        close.add_theme_font_override("font", ThemeScript.vazir(24))
        close.add_theme_font_size_override("font_size", 24)
        close.add_theme_color_override("font_color", ThemeScript.INK_SOFT)
        close.add_theme_color_override("font_hover_color", ThemeScript.INK)
        close.add_theme_stylebox_override("normal", ThemeScript.outline_stylebox(ThemeScript.LINE, 1, 20))
        close.add_theme_stylebox_override("hover", ThemeScript.soft_stylebox(Color(0.95, 0.94, 0.91), 20))
        close.add_theme_stylebox_override("pressed", ThemeScript.soft_stylebox(Color(0.95, 0.94, 0.91), 20))
        close.add_theme_stylebox_override("focus", ThemeScript.outline_stylebox(ThemeScript.LINE, 1, 20))
        close.pressed.connect(func() -> void: closed.emit())
        row.add_child(close)

        var progress := Label.new()
        progress.name = "Progress"
        progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        progress.add_theme_font_override("font", ThemeScript.vazir(ThemeScript.CAPTION))
        progress.add_theme_font_size_override("font_size", ThemeScript.CAPTION)
        progress.add_theme_color_override("font_color", ThemeScript.INK_SOFT)
        row.add_child(progress)

        var spacer := Control.new()
        spacer.custom_minimum_size = Vector2(44, 40)
        row.add_child(spacer)
        return row

func _surface() -> Control:
        var scroll := ScrollContainer.new()
        scroll.name = "Surface"
        scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
        scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

        # The view fills the panel directly: a fit-content label inside a
        # centering container collapses the card to the width of its widest
        # word. The width is pinned by _layout(); the content centres itself.
        var card := PanelContainer.new()
        card.name = "CardPanel"
        card.custom_minimum_size = Vector2(640, 240)
        card.add_theme_stylebox_override("panel", ThemeScript.card_stylebox())
        scroll.add_child(card)

        var pad := MarginContainer.new()
        pad.name = "Padding"
        pad.add_theme_constant_override("margin_left", ThemeScript.PAD)
        pad.add_theme_constant_override("margin_right", ThemeScript.PAD)
        pad.add_theme_constant_override("margin_top", 30)
        pad.add_theme_constant_override("margin_bottom", 30)
        card.add_child(pad)

        var view: CardViewScript = CardViewScript.new(_player)
        view.name = "View"
        view.alignment = BoxContainer.ALIGNMENT_CENTER
        pad.add_child(view)
        _view = view
        return scroll

func _answers() -> Control:
        var grid := GridContainer.new()
        grid.name = "Answers"
        grid.columns = 2
        grid.add_theme_constant_override("h_separation", 10)
        grid.add_theme_constant_override("v_separation", 10)
        grid.custom_minimum_size = Vector2(0, 58)
        return grid

func _footer() -> Control:
        var row := CenterContainer.new()
        row.name = "Footer"

        var show := Button.new()
        show.name = "ShowAnswer"
        show.text = "Show answer"
        show.custom_minimum_size = Vector2(300, 58)
        show.add_theme_font_override("font", ThemeScript.vazir(20, true))
        show.add_theme_font_size_override("font_size", 20)
        show.add_theme_color_override("font_color", Color.WHITE)
        show.add_theme_color_override("font_hover_color", Color.WHITE)
        show.add_theme_stylebox_override("normal", ThemeScript.button_stylebox(ThemeScript.GREEN))
        show.add_theme_stylebox_override("hover", ThemeScript.button_stylebox(ThemeScript.GREEN_DEEP))
        show.add_theme_stylebox_override("pressed", ThemeScript.button_stylebox(ThemeScript.GREEN_DEEP))
        show.add_theme_stylebox_override("focus", ThemeScript.button_stylebox(ThemeScript.GREEN_DEEP))
        show.pressed.connect(_reveal)
        row.add_child(show)

        var done := Button.new()
        done.name = "Done"
        done.text = "Done"
        done.custom_minimum_size = Vector2(300, 58)
        done.visible = false
        done.add_theme_font_override("font", ThemeScript.vazir(20, true))
        done.add_theme_font_size_override("font_size", 20)
        done.add_theme_color_override("font_color", ThemeScript.GREEN_DEEP)
        done.add_theme_stylebox_override("normal", ThemeScript.outline_stylebox(ThemeScript.GREEN))
        done.add_theme_stylebox_override("hover", ThemeScript.soft_stylebox(ThemeScript.GREEN_SOFT, 23))
        done.add_theme_stylebox_override("pressed", ThemeScript.soft_stylebox(ThemeScript.GREEN_SOFT, 23))
        done.add_theme_stylebox_override("focus", ThemeScript.outline_stylebox(ThemeScript.GREEN))
        done.pressed.connect(func() -> void: closed.emit())
        row.add_child(done)
        return row

func _layout() -> void:
        if size.x <= 0.0:
                return
        _layout_answers()
        # The card spans the column: as wide as the window allows, which keeps it
        # centred by construction on every screen this app runs on.
        var card: PanelContainer = get_node("Margin/Column/Surface/CardPanel")
        card.custom_minimum_size = Vector2(maxf(size.x - 44.0, 280.0), 240.0)

func _layout_answers() -> void:
        var grid: GridContainer = get_node("Margin/Column/Answers")
        grid.columns = 4 if size.x >= 620 else 2

func _show_front() -> void:
        _revealed = false
        if _index >= _cards.size():
                _show_done()
                return
        var card: CardScript = _cards[_index]
        var progress: Label = get_node("Margin/Column/TopBar/Progress")
        progress.text = "%d / %d" % [_index + 1, _cards.size()]
        (get_node("Margin/Column/SessionBar") as ProgressBar).value = 100.0 * float(_index) / float(_cards.size())
        _view.show_text(card.front, card.folder, true)
        ThemeScript.settle_in(_view)
        get_node("Margin/Column/Footer/ShowAnswer").visible = true
        get_node("Margin/Column/Footer/Done").visible = false
        var grid: GridContainer = get_node("Margin/Column/Answers")
        for child in grid.get_children():
                grid.remove_child(child)
                child.queue_free()
        _layout_answers()

func _reveal() -> void:
        if _revealed or _index >= _cards.size():
                return
        _revealed = true
        var card: CardScript = _cards[_index]
        _view.show_text(card.back, card.folder)
        ThemeScript.settle_in(_view)
        var scroll: ScrollContainer = get_node("Margin/Column/Surface")
        scroll.scroll_vertical = 0
        get_node("Margin/Column/Footer/ShowAnswer").visible = false

        var grid: GridContainer = get_node("Margin/Column/Answers")
        for child in grid.get_children():
                grid.remove_child(child)
                child.queue_free()
        _options = SchedulerScript.options(SchedulerScript.id_seed(card.id), card.state, int(Time.get_unix_time_from_system()))
        for i in _options.size():
                var button := _answer_button(_options[i])
                grid.add_child(button)
                ThemeScript.settle_in(button, 0.05 * i, 0.18)
        _layout_answers()
        if grid.get_child_count() > 0:
                grid.get_child(0).grab_focus()

func _answer_button(option: Dictionary) -> Control:
        var button := Button.new()
        button.name = str(option.button).capitalize()
        button.custom_minimum_size = Vector2(0, 54)
        button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        var caption := "%s\n%s" % [str(option.button).capitalize(), str(option.interval)]
        button.text = caption
        button.add_theme_font_override("font", ThemeScript.vazir(ThemeScript.BODY))
        button.add_theme_font_size_override("font_size", ThemeScript.BODY)
        var color: Color = ThemeScript.INK
        match str(option.button):
                "again":
                        color = AGAIN_COLOR
                "hard":
                        color = ThemeScript.GOLD
                "good":
                        color = ThemeScript.GREEN
                "easy":
                        color = ThemeScript.GREEN_DEEP
        button.add_theme_color_override("font_color", color)
        button.add_theme_color_override("font_hover_color", color)
        button.add_theme_stylebox_override("normal", ThemeScript.outline_stylebox(color, 2, 14))
        button.add_theme_stylebox_override("hover", ThemeScript.soft_stylebox(_wash(color), 16))
        button.add_theme_stylebox_override("pressed", ThemeScript.soft_stylebox(_wash(color), 16))
        button.add_theme_stylebox_override("focus", ThemeScript.outline_stylebox(color, 2, 14))
        button.pressed.connect(_answer.bind(str(option.button)))
        return button

static func _wash(color: Color) -> Color:
        var washed := color
        washed.a = 0.14
        return washed

func _answer(button: String) -> void:
        if _index >= _cards.size():
                return
        var card: CardScript = _cards[_index]
        answered.emit(card, button)
        _answered_count += 1
        _index += 1
        _show_front()

func _show_done() -> void:
        (get_node("Margin/Column/SessionBar") as ProgressBar).value = 100.0
        var view: CardViewScript = get_node("Margin/Column/Surface/CardPanel/Padding/View")
        view.show_text("**Session complete**\n\nYou answered %d cards. Everything is saved.\n\nRest is part of learning." % _answered_count, "")
        ThemeScript.settle_in(view)
        get_node("Margin/Column/Footer/ShowAnswer").visible = false
        get_node("Margin/Column/Footer/Done").visible = true
        var progress: Label = get_node("Margin/Column/TopBar/Progress")
        progress.text = "done"

func _input(event: InputEvent) -> void:
        if not visible:
                return
        if event is InputEventKey and event.pressed and not event.echo:
                match event.keycode:
                        KEY_ESCAPE:
                                closed.emit()
                                get_viewport().set_input_as_handled()
                        KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
                                # Consume the key here: the focused answer button
                                # must not also fire on the same press.
                                if not _revealed:
                                        _reveal()
                                        get_viewport().set_input_as_handled()
                                elif _options.size() >= 3:
                                        _answer("good")
                                        get_viewport().set_input_as_handled()
                        KEY_1:
                                if _revealed:
                                        _answer("again")
                                        get_viewport().set_input_as_handled()
                        KEY_2:
                                if _revealed:
                                        _answer("hard")
                                        get_viewport().set_input_as_handled()
                        KEY_3:
                                if _revealed:
                                        _answer("good")
                                        get_viewport().set_input_as_handled()
                        KEY_4:
                                if _revealed:
                                        _answer("easy")
                                        get_viewport().set_input_as_handled()
