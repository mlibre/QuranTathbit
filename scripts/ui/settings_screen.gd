class_name SettingsScreen
extends Control
const ThemeScript := preload("res://scripts/ui/theme.gd")
const HttpClientScript := preload("res://scripts/net/http_client.gd")
const GitHubAuthScript := preload("res://scripts/net/github_auth.gd")
const SettingsScript := preload("res://scripts/data/settings.gd")
const DeckScript := preload("res://scripts/data/deck.gd")
const VersionScript := preload("res://scripts/data/version.gd")

## Settings is short on purpose: connect GitHub, name the repo, sync. The
## deck itself is edited as files -- in any editor, on any machine -- so
## there is deliberately nothing here to build a card with. What is here
## reads in the order a person arrives in: the deck in hand, the account
## beside it, and where the words come from at the end.

signal closed
signal account_changed
signal sync_requested

var _http: HttpClientScript
var _auth: GitHubAuthScript
var _settings: SettingsScript
var _deck: DeckScript
var _polling := false
var _flow_uri := ""  # where "Open GitHub" sends the user while a flow is live

func _ready() -> void:
        _build()
        resized.connect(_layout)
        call_deferred("_layout")
        # The cards arrive one after another, a beat apart: a page that
        # assembles itself reads as composed, not stamped.
        var column: VBoxContainer = get_node("Margin/Scroll/Wrap/Column")
        ThemeScript.stagger_in(column, 0.06, 0.26)

func setup(http: HttpClientScript, auth: GitHubAuthScript, settings: SettingsScript, deck: DeckScript) -> void:
        _http = http
        _auth = auth
        _settings = settings
        _deck = deck
        if not is_node_ready():
                await ready
        _refresh()

func _build() -> void:
        set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        add_child(ThemeScript.paper_backdrop())
        add_child(ThemeScript.paper_pattern())
        var margin := MarginContainer.new()
        margin.name = "Margin"
        margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        margin.add_theme_constant_override("margin_left", 26)
        margin.add_theme_constant_override("margin_right", 26)
        margin.add_theme_constant_override("margin_top", 22)
        margin.add_theme_constant_override("margin_bottom", 28)
        add_child(margin)

        var scroll := ScrollContainer.new()
        scroll.name = "Scroll"
        scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
        ThemeScript.style_scroll(scroll)
        margin.add_child(scroll)

        # A ScrollContainer stretches its child to the whole window when the
        # horizontal scroll is off, so the capped column rides inside a
        # centre wrapper: the cards keep a reader's measure on a desktop and
        # fill a phone to its edges.
        var wrap := CenterContainer.new()
        wrap.name = "Wrap"
        wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        scroll.add_child(wrap)

        var column := VBoxContainer.new()
        column.name = "Column"
        column.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        column.add_theme_constant_override("separation", 18)
        wrap.add_child(column)

        # The same header every screen above home wears: back the way they came.
        var bar: Dictionary = ThemeScript.top_bar("Settings")
        var back: Button = bar["back"]
        back.tooltip_text = "Back to home"
        back.pressed.connect(func() -> void: closed.emit())
        column.add_child(bar["row"])

        column.add_child(_deck_body())
        column.add_child(_github_body())
        column.add_child(_source_body())
        column.add_child(_about())
        # The last card gets the same breath under it the page gives above:
        # a scroll that ends hard against its content reads as cut off.
        var tail := Control.new()
        tail.name = "Tail"
        tail.custom_minimum_size = Vector2(0, 14)
        column.add_child(tail)

## The page answers the window: the cards keep a reader's measure on a
## desktop -- never a stripe the width of a whole window -- and fill a phone
## to its edges. The top margin also answers the display: on a phone with a
## notch the way back sits below whatever the system draws up there.
func _layout() -> void:
        if size.x <= 0.0:
                return
        var margin: MarginContainer = get_node_or_null("Margin")
        if margin != null:
                margin.add_theme_constant_override("margin_top", int(22.0 + ThemeScript.top_inset()))
                margin.add_theme_constant_override("margin_bottom", int(28.0 + ThemeScript.bottom_inset()))
        var column: VBoxContainer = get_node_or_null("Margin/Scroll/Wrap/Column")
        if column == null:
                return
        column.custom_minimum_size = Vector2(minf(620.0, size.x - 52.0), 0.0)

## A card's own name, said inside the card: a small gold word over a rule,
## so each card reads as its own page with a running title -- not a label
## floating between cards, where the margin swallows it.
func _card_header(box: VBoxContainer, title: String) -> void:
        var label := Label.new()
        label.name = "CardTitle"
        label.text = title
        label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
        ThemeScript.dress(label, 12, ThemeScript.GOLD_DEEP, true)
        box.add_child(label)
        box.add_child(ThemeScript.hairline(ThemeScript.LINE))

## Every line of explanation on this screen is a selectable RichTextLabel:
## a person reads with their eyes and copies with their mouse, and neither
## should wait for the other. One builder, so every line looks and behaves
## the same everywhere on this screen.
func _text(what: String, color: Color, size: int, center := false, bold := false) -> RichTextLabel:
        var label := RichTextLabel.new()
        label.selection_enabled = true
        label.fit_content = true
        label.scroll_active = false
        label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        if center:
                label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        label.add_theme_font_override("normal_font", ThemeScript.vazir(size, bold))
        label.add_theme_font_size_override("normal_font_size", size)
        label.add_theme_color_override("default_color", color)
        label.add_theme_color_override("selection_color", ThemeScript.SELECT)
        label.text = what
        return label

## The engine's LineEdit arrives as a grey plastic trench. This dresses it
## as a ruled line on the page: white, thin border, green while focused.
func _style_field(field: LineEdit) -> void:
        var rest := StyleBoxFlat.new()
        rest.bg_color = ThemeScript.CARD
        rest.border_color = Color("#D9CFBB")
        rest.set_border_width_all(1)
        rest.set_corner_radius_all(12)
        rest.content_margin_left = 14
        rest.content_margin_right = 14
        rest.content_margin_top = 8
        rest.content_margin_bottom = 8
        var focused := rest.duplicate() as StyleBoxFlat
        focused.border_color = ThemeScript.GREEN
        focused.set_border_width_all(2)
        field.add_theme_stylebox_override("normal", rest)
        field.add_theme_stylebox_override("focus", focused)
        field.add_theme_color_override("font_color", ThemeScript.INK)
        field.add_theme_color_override("caret_color", ThemeScript.GREEN_DEEP)
        field.add_theme_color_override("font_placeholder_color", ThemeScript.INK_SOFT)
        field.add_theme_color_override("selection_color", ThemeScript.SELECT)

## One card's bones: the panel, the padding, the column. Settings' cards all
## wear the same frame, so only their contents differ.
func _card(card_name: String, box_name := "Box") -> Array:
        var card := PanelContainer.new()
        card.name = card_name
        card.add_theme_stylebox_override("panel", ThemeScript.card_stylebox())
        var pad := MarginContainer.new()
        pad.name = "Padding"
        pad.add_theme_constant_override("margin_left", ThemeScript.PAD)
        pad.add_theme_constant_override("margin_right", ThemeScript.PAD)
        pad.add_theme_constant_override("margin_top", 18)
        pad.add_theme_constant_override("margin_bottom", 18)
        card.add_child(pad)
        var box := VBoxContainer.new()
        box.name = box_name
        box.add_theme_constant_override("separation", 12)
        pad.add_child(box)
        return [card, box]

## A field's label, close enough to belong to it and no closer.
func _field_label(text: String) -> Label:
        var label := Label.new()
        label.text = text
        return ThemeScript.dress(label, ThemeScript.CAPTION, ThemeScript.INK, true)

func _github_body() -> Control:
        var parts := _card("GitHub")
        var card: PanelContainer = parts[0]
        var box: VBoxContainer = parts[1]
        _card_header(box, "GitHub sync")

        var state := _text("", ThemeScript.INK, ThemeScript.BODY)
        state.name = "State"
        box.add_child(state)

        var flow := VBoxContainer.new()
        flow.name = "Flow"
        flow.visible = false
        flow.add_theme_constant_override("separation", 10)
        box.add_child(flow)

        # The code sits in a chip of its own, the way a code looks on a ticket:
        # set apart, big, and centred under the words that explain it.
        var chip := PanelContainer.new()
        chip.name = "Code"
        chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        chip.add_theme_stylebox_override("panel", ThemeScript.soft_stylebox(ThemeScript.GREEN_SOFT, 14))
        var chip_pad := MarginContainer.new()
        chip_pad.name = "Pad"
        chip_pad.add_theme_constant_override("margin_left", 20)
        chip_pad.add_theme_constant_override("margin_right", 20)
        chip_pad.add_theme_constant_override("margin_top", 8)
        chip_pad.add_theme_constant_override("margin_bottom", 8)
        chip.add_child(chip_pad)
        var code := _text("", ThemeScript.GREEN_DEEP, 34, true, true)
        code.name = "CodeText"
        chip_pad.add_child(code)
        flow.add_child(chip)

        var hint := _text("Type this code at github.com/login/device, then wait here.", ThemeScript.INK_SOFT, ThemeScript.CAPTION, true)
        hint.name = "Hint"
        flow.add_child(hint)

        # The flow's two ways onward, side by side: the way to GitHub, and
        # the code on the clipboard for the walk there. Copying is what a
        # person does with a code; the app does it for them.
        var actions := HBoxContainer.new()
        actions.name = "Actions"
        actions.alignment = BoxContainer.ALIGNMENT_CENTER
        actions.add_theme_constant_override("separation", 10)
        flow.add_child(actions)

        var open := ThemeScript.ghost_button("Open GitHub", ThemeScript.GREEN, 44)
        open.name = "Open"
        open.tooltip_text = "Open the sign-in page"
        open.pressed.connect(func() -> void:
                if not _flow_uri.is_empty():
                        OS.shell_open(_flow_uri)
        )
        actions.add_child(open)

        var copy := ThemeScript.ghost_button("Copy code", ThemeScript.GREEN, 44, 22)
        copy.name = "Copy"
        copy.tooltip_text = "Copy the code to the clipboard"
        copy.pressed.connect(func() -> void:
                var code_text: RichTextLabel = flow.get_node("Code/Pad/CodeText")
                if not code_text.text.is_empty():
                        DisplayServer.clipboard_set(code_text.text)
        )
        actions.add_child(copy)

        var buttons := HBoxContainer.new()
        buttons.name = "Buttons"
        buttons.add_theme_constant_override("separation", 10)
        box.add_child(buttons)

        var connect := ThemeScript.primary_button("Connect GitHub", 46)
        connect.name = "Connect"
        connect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        connect.tooltip_text = "Sign in with GitHub"
        connect.pressed.connect(_begin_device_flow)
        buttons.add_child(connect)

        var disconnect := ThemeScript.ghost_button("Disconnect", ThemeScript.DANGER, 46)
        disconnect.name = "Disconnect"
        disconnect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        disconnect.pressed.connect(_disconnect)
        buttons.add_child(disconnect)

        box.add_child(_field_label("Personal access token"))
        # The field owns its whole row: a token is forty characters, and a
        # thumb needs the field's full width to find its place in it. Paste
        # is not a button any more -- in a browser the page hands the app its
        # own paste events, so Ctrl+V simply works, and a finger pastes by
        # holding the field. What is left under it are the two things that
        # were always wanted: to see what arrived, and to keep it.
        var token := LineEdit.new()
        token.name = "Token"
        token.placeholder_text = ("Paste the token GitHub shows you" if OS.has_feature("web") else "…or paste a repo token")
        token.secret = true
        token.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        token.custom_minimum_size = Vector2(0, 48)
        token.add_theme_font_override("font", ThemeScript.vazir(ThemeScript.CAPTION))
        token.add_theme_font_size_override("font_size", ThemeScript.CAPTION)
        _style_field(token)
        _paste_on_hold(token)
        token.text_submitted.connect(func(_text: String) -> void: _save_token())
        box.add_child(token)
        var token_row := HBoxContainer.new()
        token_row.name = "TokenRow"
        token_row.add_theme_constant_override("separation", 8)
        box.add_child(token_row)
        var show := ThemeScript.ghost_button("Show", ThemeScript.INK_SOFT, 44, 12)
        show.name = "ShowToken"
        show.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        show.tooltip_text = "Show or hide what was typed"
        show.pressed.connect(_toggle_token_shown)
        token_row.add_child(show)
        # Keeping the token is the row's errand, so it is the row's one
        # filled action; seeing is only a second thought beside it.
        var save_token := ThemeScript.primary_button("Save token", 44)
        save_token.name = "SaveToken"
        save_token.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        save_token.pressed.connect(_save_token)
        token_row.add_child(save_token)
        var token_hint := _text(
                "From github.com/settings/tokens — needs the repo scope. Stays on this device.",
                ThemeScript.INK_SOFT, ThemeScript.CAPTION
        )
        token_hint.name = "TokenHint"
        box.add_child(token_hint)

        # The page's own division: the account above, the deck's home below.
        box.add_child(ThemeScript.hairline())

        box.add_child(_field_label("Repository"))
        var repo := LineEdit.new()
        repo.name = "Repo"
        repo.placeholder_text = "Repository name"
        repo.custom_minimum_size = Vector2(0, 44)
        repo.add_theme_font_override("font", ThemeScript.vazir(ThemeScript.BODY))
        repo.add_theme_font_size_override("font_size", ThemeScript.BODY)
        _style_field(repo)
        repo.text_submitted.connect(_save_repo)
        box.add_child(repo)
        _paste_on_hold(repo)
        var repo_hint := _text(
                "Where your deck lives on GitHub — created on first sync if it does not exist.",
                ThemeScript.INK_SOFT, ThemeScript.CAPTION
        )
        repo_hint.name = "RepoHint"
        box.add_child(repo_hint)
        repo.focus_exited.connect(func() -> void: _save_repo(repo.text))

        # The quiet promise, said plainly and changeable: after each session
        # the deck tells GitHub on its own. A promise that matters is a row
        # of its own -- a page's worth of surface with a switch that reads
        # as a switch from across the room, and the whole row is the
        # button, so a thumb cannot miss it the way it missed a caption
        # with a dot after it.
        var auto_row := Button.new()
        auto_row.name = "AutoRow"
        auto_row.toggle_mode = true
        auto_row.custom_minimum_size = Vector2(0, 62)
        _dress_promise_row(auto_row, false)
        ThemeScript.pressable(auto_row)
        var auto_pad := MarginContainer.new()
        auto_pad.name = "AutoPad"
        auto_pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        auto_pad.add_theme_constant_override("margin_left", 16)
        auto_pad.add_theme_constant_override("margin_right", 16)
        auto_pad.add_theme_constant_override("margin_top", 10)
        auto_pad.add_theme_constant_override("margin_bottom", 10)
        auto_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
        auto_row.add_child(auto_pad)
        var auto_line := HBoxContainer.new()
        auto_line.name = "AutoLine"
        auto_line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        auto_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
        auto_line.add_theme_constant_override("separation", 12)
        auto_pad.add_child(auto_line)
        var auto_words := VBoxContainer.new()
        auto_words.name = "Words"
        auto_words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        auto_words.alignment = BoxContainer.ALIGNMENT_CENTER
        auto_words.add_theme_constant_override("separation", 2)
        auto_words.mouse_filter = Control.MOUSE_FILTER_IGNORE
        auto_line.add_child(auto_words)
        var auto_label := Label.new()
        auto_label.name = "Label"
        auto_label.text = "Sync quietly after each session"
        ThemeScript.dress(auto_label, ThemeScript.BODY, ThemeScript.INK, true)
        auto_words.add_child(auto_label)
        var auto_sub := _text("after each session, and when the app opens", ThemeScript.INK_SOFT, 12)
        auto_sub.name = "Sub"
        auto_words.add_child(auto_sub)
        var auto_switch := ThemeScript.SwitchMark.new(false)
        auto_switch.name = "Switch"
        auto_switch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        auto_line.add_child(auto_switch)
        auto_row.toggled.connect(func(on: bool) -> void:
                _settings.auto_sync = on
                _settings.save()
                _dress_promise_row(auto_row, on)
                auto_switch.set_on(on)
        )
        box.add_child(auto_row)

        var sync := ThemeScript.primary_button("Sync now", 46)
        sync.name = "Sync"
        sync.tooltip_text = "Sync with GitHub"
        sync.pressed.connect(func() -> void: sync_requested.emit())
        box.add_child(sync)

        var note := _text("", ThemeScript.INK_SOFT, ThemeScript.CAPTION, true)
        note.name = "SyncNote"
        box.add_child(note)
        return card

func _deck_body() -> Control:
        var parts := _card("DeckInfo")
        var card: PanelContainer = parts[0]
        var box: VBoxContainer = parts[1]
        box.add_theme_constant_override("separation", 8)

        var name := _text("", ThemeScript.INK, ThemeScript.BODY, false, true)
        name.name = "Name"
        box.add_child(name)

        var folder := _text("", ThemeScript.INK_SOFT, ThemeScript.CAPTION)
        folder.name = "Folder"
        box.add_child(folder)

        var note := _text("Cards are folders on your disk. Edit them anywhere; sync carries them.", ThemeScript.INK_SOFT, ThemeScript.CAPTION)
        note.name = "Note"
        box.add_child(note)

        # The day's own offer: how many unseen cards a session may bring. The
        # number is the reader's pace, not the algorithm's -- Anki's deck
        # default of 20 is only where it starts -- so it lives here, beside
        # the deck it paces, as the one arithmetic the reader is asked to own.
        box.add_child(ThemeScript.hairline())
        box.add_child(_field_label("New cards each day"))
        var stepper := HBoxContainer.new()
        stepper.name = "NewPerDay"
        stepper.add_theme_constant_override("separation", 10)
        box.add_child(stepper)
        var less := ThemeScript.ghost_button("-", ThemeScript.GREEN_DEEP, 44)
        less.name = "StepLess"
        less.tooltip_text = "Offer one fewer new card a day"
        less.custom_minimum_size = Vector2(52, 44)
        less.pressed.connect(_step_new_per_day.bind(-1))
        stepper.add_child(less)
        var value_chip := PanelContainer.new()
        value_chip.name = "Chip"
        value_chip.custom_minimum_size = Vector2(72, 44)
        value_chip.add_theme_stylebox_override(
                "panel", ThemeScript.soft_stylebox(ThemeScript.GOLD_SOFT, 14)
        )
        var value := Label.new()
        value.name = "StepValue"
        value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        value.size_flags_vertical = Control.SIZE_EXPAND_FILL
        ThemeScript.dress(value, ThemeScript.BODY + 2, ThemeScript.GOLD_DEEP, true)
        value_chip.add_child(value)
        stepper.add_child(value_chip)
        var more := ThemeScript.ghost_button("+", ThemeScript.GREEN_DEEP, 44)
        more.name = "StepMore"
        more.tooltip_text = "Offer one more new card a day"
        more.custom_minimum_size = Vector2(52, 44)
        more.pressed.connect(_step_new_per_day.bind(1))
        stepper.add_child(more)
        var pace := _text(
                "How many unseen cards a day offers — 0 studies only reviews. Anki's default is 20.",
                ThemeScript.INK_SOFT, 12
        )
        pace.name = "Pace"
        stepper.add_child(pace)
        return card

## A press on the stepper is the reader choosing their own pace: the number
## moves at once, the file is written at once, and the chip says what the
## next session will bring. The bounds keep the choice sane -- 0 is a day of
## reviews only, and no day needs more new cards than this.
func _step_new_per_day(delta: int) -> void:
        _settings.new_per_day = clampi(_settings.new_per_day + delta, 0, 200)
        _settings.save()
        var value: Label = get_node("Margin/Scroll/Wrap/Column/DeckInfo/Padding/Box/NewPerDay/Chip/StepValue")
        value.text = str(_settings.new_per_day)

func _source_body() -> Control:
        var parts := _card("DataSource")
        var card: PanelContainer = parts[0]
        var box: VBoxContainer = parts[1]
        _card_header(box, "Data source")
        box.add_theme_constant_override("separation", 8)

        var what := RichTextLabel.new()
        what.name = "What"
        what.bbcode_enabled = true
        what.fit_content = true
        what.scroll_active = false
        what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        what.text = (
                "The deck's verses, Persian translation and recitations come from "
                + "[url=https://quran.makarem.ir/]quran.makarem.ir[/url], carried unchanged from the deck package."
        )
        what.add_theme_font_override("normal_font", ThemeScript.vazir(ThemeScript.CAPTION))
        what.add_theme_font_size_override("normal_font_size", ThemeScript.CAPTION)
        what.add_theme_color_override("default_color", ThemeScript.INK)
        # Selection lets a user copy the line; the link opens in the browser.
        what.selection_enabled = true
        what.add_theme_color_override("selection_color", ThemeScript.SELECT)
        what.meta_clicked.connect(func(meta: Variant) -> void: OS.shell_open(str(meta)))
        box.add_child(what)

        var open := ThemeScript.ghost_button("Open quran.makarem.ir", ThemeScript.GOLD_DEEP, 42)
        open.name = "Open"
        # The deck's source is read when the button is pressed: the screen
        # builds before its setup() brings the deck in.
        open.pressed.connect(func() -> void:
                var url := "https://quran.makarem.ir/"
                if _deck != null and not _deck.source.is_empty():
                        url = _deck.source
                OS.shell_open(url)
        )
        box.add_child(open)

        if OS.has_feature("web"):
                var note := _text("In the browser, recitations stream from this site while you study.", ThemeScript.INK_SOFT, ThemeScript.CAPTION)
                note.name = "WebNote"
                box.add_child(note)
        return card

func _about() -> Control:
        var box := VBoxContainer.new()
        box.name = "About"
        box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        box.alignment = BoxContainer.ALIGNMENT_CENTER
        box.add_theme_constant_override("separation", 4)
        # The name in the script it was given, then the version it runs.
        var ornament := ThemeScript.OrnamentMark.new()
        ornament.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        box.add_child(ornament)
        var arabic := Label.new()
        arabic.text = "تثبيت القرآن"
        arabic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        arabic.add_theme_font_override("font", ThemeScript.amiri(16))
        arabic.add_theme_font_size_override("font_size", 16)
        arabic.add_theme_color_override("font_color", ThemeScript.GOLD)
        box.add_child(arabic)
        var label := _text("QuranTathbit v%s" % VersionScript.VERSION, ThemeScript.INK_SOFT, ThemeScript.CAPTION, true)
        label.name = "Line"
        box.add_child(label)
        return box

## The promise row's two faces: kept is the app's own green ground, a
## decision already standing; unkept is the page's own paper, a decision
## still waiting to be made. The border says the same thing more quietly.
func _dress_promise_row(row: Button, on: bool) -> void:
        var rest := ThemeScript.soft_stylebox(
                Color(ThemeScript.GREEN.r, ThemeScript.GREEN.g, ThemeScript.GREEN.b, 0.10), 14
        )
        rest.border_color = Color(
                ThemeScript.GREEN.r, ThemeScript.GREEN.g, ThemeScript.GREEN.b, 0.45 if on else 0.22
        )
        rest.set_border_width_all(1)
        var held := ThemeScript.soft_stylebox(
                Color(ThemeScript.GREEN.r, ThemeScript.GREEN.g, ThemeScript.GREEN.b, 0.16), 14
        )
        held.border_color = Color(
                ThemeScript.GREEN.r, ThemeScript.GREEN.g, ThemeScript.GREEN.b, 0.6
        )
        held.set_border_width_all(1)
        row.add_theme_stylebox_override("normal", rest)
        row.add_theme_stylebox_override("hover", held)
        row.add_theme_stylebox_override("pressed", held)
        row.add_theme_stylebox_override("checked", rest)
        row.add_theme_stylebox_override("checked_hover", held)
        row.add_theme_stylebox_override("checked_pressed", held)
        var focus := rest.duplicate() as StyleBoxFlat
        focus.border_color = ThemeScript.GREEN
        focus.set_border_width_all(2)
        row.add_theme_stylebox_override("focus", focus)


# --- state ---------------------------------------------------------------------

## The main screen reports how a sync went while Settings is the screen on
## top; the note sits under the Sync button and clears when asked again.
func note_sync_result(text: String) -> void:
        var note: RichTextLabel = get_node_or_null("Margin/Scroll/Wrap/Column/GitHub/Padding/Box/SyncNote")
        if note != null:
                note.text = text

func _refresh() -> void:
        var state: RichTextLabel = get_node("Margin/Scroll/Wrap/Column/GitHub/Padding/Box/State")
        var connect: Button = get_node("Margin/Scroll/Wrap/Column/GitHub/Padding/Box/Buttons/Connect")
        var disconnect: Button = get_node("Margin/Scroll/Wrap/Column/GitHub/Padding/Box/Buttons/Disconnect")
        var repo: LineEdit = get_node("Margin/Scroll/Wrap/Column/GitHub/Padding/Box/Repo")
        var auto: Button = get_node("Margin/Scroll/Wrap/Column/GitHub/Padding/Box/AutoRow")
        repo.text = _settings.repo
        # No signal: this is the settings being said, not the settings being
        # changed -- a refresh that toggled its own switch would overwrite
        # the file it is only reading.
        auto.set_pressed_no_signal(_settings.auto_sync)
        _dress_promise_row(auto, _settings.auto_sync)
        (auto.get_node("AutoPad/AutoLine/Switch") as ThemeScript.SwitchMark).set_on(_settings.auto_sync)
        if _settings.has_token() and not _settings.owner.is_empty():
                state.text = "Connected as @%s" % _settings.owner
        elif _settings.has_token():
                state.text = "Token saved"
        elif OS.has_feature("web"):
                state.text = "Not connected. In a browser you sign in with a one-minute token — press Connect GitHub and it walks you through."
        else:
                state.text = "Not connected. Sync keeps your progress on your own GitHub repo."
        connect.visible = not _settings.has_token()
        disconnect.visible = _settings.has_token()
        var name: RichTextLabel = get_node("Margin/Scroll/Wrap/Column/DeckInfo/Padding/Box/Name")
        var folder: RichTextLabel = get_node("Margin/Scroll/Wrap/Column/DeckInfo/Padding/Box/Folder")
        name.text = "%s — %d cards" % [_deck.name, _deck.cards.size()]
        folder.text = _deck.folder
        # The day's offer is said here too, not only on a press: a reader
        # returning to this page reads their pace off the chip.
        var pace_value: Label = get_node("Margin/Scroll/Wrap/Column/DeckInfo/Padding/Box/NewPerDay/Chip/StepValue")
        pace_value.text = str(_settings.new_per_day)
        note_sync_result("")

# --- the device flow ------------------------------------------------------------

func _begin_device_flow() -> void:
        # A browser can never reach GitHub's device-flow endpoints (they send
        # no CORS headers), so on the web Connect takes the one-minute token
        # path instead of trying and failing in front of the user.
        if OS.has_feature("web"):
                _begin_web_connect()
                return
        if not _auth.is_configured():
                var state0: RichTextLabel = get_node("Margin/Scroll/Wrap/Column/GitHub/Padding/Box/State")
                state0.text = "This build has no GitHub app id yet. Add your OAuth app's client id to scripts/net/github_auth.gd, or paste a token below."
                return
        var began: Dictionary = await _auth.begin(_http)
        var flow: VBoxContainer = get_node("Margin/Scroll/Wrap/Column/GitHub/Padding/Box/Flow")
        var code: PanelContainer = flow.get_node("Code")
        var open: Button = flow.get_node("Actions/Open")
        var connect: Button = get_node("Margin/Scroll/Wrap/Column/GitHub/Padding/Box/Buttons/Connect")
        if began.has("error"):
                var state: RichTextLabel = get_node("Margin/Scroll/Wrap/Column/GitHub/Padding/Box/State")
                if OS.has_feature("web"):
                        # Unreachable on the web (the branch above), kept as a
                        # safety net: say what works instead of what failed.
                        state.text = "Browsers cannot open GitHub's sign-in page (cross-origin rules). Use Connect GitHub for the token steps instead."
                else:
                        state.text = "Could not reach GitHub. Check your connection and try again."
                return
        (code.get_node("Pad/CodeText") as RichTextLabel).text = _pretty_code(str(began.user_code))
        code.visible = true
        (flow.get_node("Actions/Copy") as Button).visible = true
        _flow_uri = str(began.verification_uri)
        connect.disabled = true
        flow.visible = true
        _polling = true
        var deadline := int(Time.get_unix_time_from_system()) + int(began.expires_in)
        var interval: float = maxf(float(began.interval) - 0.5, 1.0)
        while _polling and int(Time.get_unix_time_from_system()) < deadline:
                await get_tree().create_timer(interval).timeout
                if not _polling:
                        break
                var polled: Dictionary = await _auth.poll(_http, str(began.device_code))
                if polled.has("token"):
                        _polling = false
                        await _finish(str(polled.token))
                        return
                if str(polled.get("error", "")) in ["authorization_pending", "slow_down"]:
                        if str(polled.get("error", "")) == "slow_down":
                                interval = minf(interval + 5.0, 30.0)
                        continue
                _polling = false
                flow.visible = false
                connect.disabled = false
                _flow_uri = ""
                get_node("Margin/Scroll/Wrap/Column/GitHub/Padding/Box/State").text = "That flow did not complete. Try again when ready."
                return
        _polling = false
        _flow_uri = ""

func _pretty_code(code: String) -> String:
        if code.length() > 4 and code.contains("-"):
                return code
        if code.length() <= 4:
                return code
        return "%s-%s" % [code.substr(0, 4), code.substr(4)]

## The browser's way in: GitHub's sign-in page cannot be opened from another
## site (cross-origin rules, and no static site can change that), so Connect
## walks the one-minute token path instead. The button opens GitHub's token
## form with the name and the permission prefilled; the user generates,
## copies, pastes below, saves. Everything after -- sync included -- runs in
## the browser against api.github.com, which does allow it.
func _begin_web_connect() -> void:
        var state: RichTextLabel = get_node("Margin/Scroll/Wrap/Column/GitHub/Padding/Box/State")
        state.text = "Signing in inside a browser takes a token — GitHub's sign-in page cannot be opened from another site, and no static site can change that. One minute, three steps:"
        var flow: VBoxContainer = get_node("Margin/Scroll/Wrap/Column/GitHub/Padding/Box/Flow")
        var code: PanelContainer = flow.get_node("Code")
        var hint: RichTextLabel = flow.get_node("Hint")
        var open: Button = flow.get_node("Actions/Open")
        code.visible = false
        (flow.get_node("Actions/Copy") as Button).visible = false
        hint.text = (
                "1. Press the button — GitHub opens with the form filled in: the name and the repo permission are already set.\n"
                + "2. Generate the token, then copy the string it shows you.\n"
                + "3. Come back here, paste it into the box below (Ctrl+V, or hold the box on a phone), then press Save."
        )
        open.text = "Create a token on GitHub"
        _flow_uri = "https://github.com/settings/tokens/new?scopes=repo&description=QuranTathbit%20sync"
        flow.visible = true
        get_node("Margin/Scroll/Wrap/Column/GitHub/Padding/Box/Token").grab_focus()

func _finish(token: String) -> void:
        var who: Dictionary = await _auth.whoami(_http, token)
        if who.has("error"):
                get_node("Margin/Scroll/Wrap/Column/GitHub/Padding/Box/State").text = "Connected, but we could not read your login."
                _settings.token = token
        else:
                _settings.owner = str(who.login)
                get_node("Margin/Scroll/Wrap/Column/GitHub/Padding/Box/State").text = "Connected as @%s" % _settings.owner
        _settings.token = token
        _settings.setup_done = true
        _settings.save()
        _flow_uri = ""
        var flow: VBoxContainer = get_node("Margin/Scroll/Wrap/Column/GitHub/Padding/Box/Flow")
        flow.visible = false
        var connect: Button = get_node("Margin/Scroll/Wrap/Column/GitHub/Padding/Box/Buttons/Connect")
        connect.disabled = false
        _refresh()
        account_changed.emit()

func _save_token() -> void:
        var token: LineEdit = get_node("Margin/Scroll/Wrap/Column/GitHub/Padding/Box/Token")
        if token.text.strip_edges().is_empty():
                return
        var value := token.text.strip_edges()
        var who: Dictionary = await _auth.whoami(_http, value)
        if who.has("error"):
                get_node("Margin/Scroll/Wrap/Column/GitHub/Padding/Box/State").text = "That token did not work. Check it and try again."
                return
        _settings.token = value
        _settings.owner = str(who.login)
        _settings.setup_done = true
        _settings.save()
        token.text = ""
        _refresh()
        account_changed.emit()


# --- the clipboard, both of its worlds ------------------------------------------

## In a browser the field itself is the paste button: a finger held on the
## field for half a second pastes the clipboard into it. The engine's own
## touch menu is switched off for this -- its Paste reads a cache a
## keystroke behind -- and the hold takes its place; on a keyboard Ctrl+V
## works too, carried by the page's own paste event.
func _paste_on_hold(field: LineEdit) -> void:
        if not OS.has_feature("web"):
                return
        field.context_menu_enabled = false
        var hold := {"armed": null, "held": false}
        field.gui_input.connect(func(event: InputEvent) -> void:
                if not event is InputEventScreenTouch:
                        return
                if event.pressed:
                        hold["held"] = true
                        var timer := get_tree().create_timer(0.55)
                        hold["armed"] = timer
                        timer.timeout.connect(func() -> void:
                                if hold["held"] and hold["armed"] == timer:
                                        hold["held"] = false
                                        _paste_token()
                        )
                else:
                        hold["held"] = false
        )


## One field, two worlds: on a desktop the clipboard is the engine's to read;
## in a browser the page owns it, and only the page's own JavaScript can
## ask. The hand that pastes should not have to know which world it is in.
func _paste_token() -> void:
        var field := _token_field()
        if OS.has_feature("web"):
                await _paste_from_page(field)
                return
        var clip := DisplayServer.clipboard_get().strip_edges()
        if clip.is_empty():
                _token_note("Nothing on the clipboard. Copy the token first, then hold the field to paste.")
                return
        field.text = clip
        field.caret_column = clip.length()
        field.grab_focus()


## The browser's clipboard answers a promise, and eval cannot wait for one:
## the page is asked to write the answer into a corner of the document
## itself, and the field watches that corner until it changes -- the same
## hand-off the page and the engine use for everything else.
func _paste_from_page(field: LineEdit) -> void:
        var bridge: Object = Engine.get_singleton("JavaScriptBridge")
        if bridge == null:
                _token_note("This build cannot read the clipboard — type the token instead.")
                return
        var ask := (
                "(function(){var d=document.documentElement;"
                + "d.setAttribute('data-qt-clipboard','asked');"
                + "if(navigator.clipboard&&navigator.clipboard.readText){"
                + "navigator.clipboard.readText().then(function(t){"
                + "d.setAttribute('data-qt-clipboard','ok:'+(t||''))"
                + "},function(){d.setAttribute('data-qt-clipboard','no')})"
                + "}else{d.setAttribute('data-qt-clipboard','no')}})()"
        )
        bridge.call("eval", ask)
        # Up to three seconds of watching: the browser may be waiting for the
        # person to allow the read, and that is a conversation, not a lag.
        for i in 30:
                await get_tree().create_timer(0.1).timeout
                var answer := str(bridge.call(
                        "eval",
                        "document.documentElement.getAttribute('data-qt-clipboard')||''"
                ))
                if answer == "asked":
                        continue
                if answer.begins_with("ok:"):
                        var clip := answer.substr(3).strip_edges()
                        if clip.is_empty():
                                _token_note("The clipboard is empty. Copy the token on GitHub, then hold the field to paste.")
                                return
                        field.text = clip
                        field.caret_column = clip.length()
                        field.grab_focus()
                        _token_note("Pasted — press Save token when it looks right.")
                        return
                _token_note("This browser would not share its clipboard. Copy the token, tap the field, and use your keyboard's paste.")
                return
        _token_note("The clipboard did not answer. Hold the field again to paste.")


## A secret field keeps neither typos nor pastes visible; a hand that wants
## to see what arrived before it commits may, and the button says which way
## it stands.
func _toggle_token_shown() -> void:
        var field := _token_field()
        field.secret = not field.secret
        var show: Button = get_node("Margin/Scroll/Wrap/Column/GitHub/Padding/Box/TokenRow/ShowToken")
        show.text = "Hide" if not field.secret else "Show"


func _token_field() -> LineEdit:
        return get_node("Margin/Scroll/Wrap/Column/GitHub/Padding/Box/Token")


func _token_note(what: String) -> void:
        var state: RichTextLabel = get_node("Margin/Scroll/Wrap/Column/GitHub/Padding/Box/State")
        state.text = what

func _save_repo(text: String) -> void:
        var value := text.strip_edges()
        if value.is_empty():
                return
        _settings.repo = value
        _settings.save()

func _disconnect() -> void:
        _settings.token = ""
        _settings.owner = ""
        _settings.setup_done = false
        _settings.save()
        _polling = false
        _refresh()
        account_changed.emit()
