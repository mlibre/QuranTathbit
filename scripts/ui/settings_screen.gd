class_name SettingsScreen
extends Control
const ThemeScript := preload("res://scripts/ui/theme.gd")
const HttpClientScript := preload("res://scripts/net/http_client.gd")
const GitHubAuthScript := preload("res://scripts/net/github_auth.gd")
const SettingsScript := preload("res://scripts/data/settings.gd")
const DeckScript := preload("res://scripts/data/deck.gd")
const DeckZipScript := preload("res://scripts/data/deck_zip.gd")
const BackupPickerScript := preload("res://scripts/ui/backup_picker.gd")
const VersionScript := preload("res://scripts/data/version.gd")
const I18nScript := preload("res://scripts/ui/i18n.gd")
const CopyChipScript := preload("res://scripts/ui/copy_chip.gd")
const FlavorScript := preload("res://scripts/data/flavor.gd")

## The two ladders a size is stepped along: the interface in wider steps
## (it moves everything, so a small step is a big step) and the words in
## narrower ones (a verse must never outgrow the card it is read on).
const UI_SCALE_STEPS := [0.85, 1.0, 1.15, 1.3]
const FONT_SCALE_STEPS := [0.9, 1.0, 1.1, 1.2]

## Settings is short on purpose: connect GitHub, name the repo, sync. The
## deck itself is edited as files -- in any editor, on any machine -- so
## there is deliberately nothing here to build a card with. What is here
## reads in the order a person arrives in: the deck in hand, the account
## beside it, and where the words come from at the end.

signal closed
signal account_changed
signal sync_requested
## A travelling choice has settled (the day's pace, the verses' face, the
## app's tongue): the progress file carries it, and the repo should hear
## it without the user having to ask.
signal choice_push_requested
## A backup has been joined to the deck: the deck on disk is now more than
## the one in memory, and whoever owns the deck (the app's root) should
## read it back -- adopting whatever choices arrived with it and speaking
## a tongue that changed underneath this page.
signal deck_imported

var _http: HttpClientScript
var _auth: GitHubAuthScript
var _settings: SettingsScript
var _deck: DeckScript
var _polling := false
var _flow_uri := ""  # where "Open GitHub" sends the user while a flow is live
var _choice_push: Timer  # one ask, once the hand stops choosing
var _zip_callback: Variant = null  # the page's backup hook, held while this screen stands

func _ready() -> void:
        _build()
        resized.connect(_layout)
        call_deferred("_layout")
        # A choice is one word, however many times the hand steps to say it:
        # the ask waits for the stepping to stop, then speaks once.
        _choice_push = Timer.new()
        _choice_push.name = "ChoicePush"
        _choice_push.one_shot = true
        _choice_push.wait_time = 1.4
        _choice_push.timeout.connect(func() -> void: choice_push_requested.emit())
        add_child(_choice_push)
        # In a browser the backup's two halves live in the page -- the way
        # out is a download, the way in is a file input -- so the hook that
        # carries them is installed the moment this page stands.
        if OS.has_feature("web"):
                _install_zip_bridge()
        # The cards arrive one after another, a beat apart: a page that
        # assembles itself reads as composed, not stamped.
        var column: VBoxContainer = get_node("Margin/Scroll/Wrap/Column")
        ThemeScript.stagger_in(column, 0.06, 0.26)

## The page said again in a new tongue: the words are chosen at building,
## so a language choice re-builds the page in place -- everything but the
## choice's own timer, which keeps its ear for the next word.
func _rebuild() -> void:
        for child in get_children():
                if child.name == "ChoicePush":
                        continue
                remove_child(child)
                child.queue_free()
        _build()
        call_deferred("_layout")
        _refresh()
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
        # A page whose tongue reads from the right is laid out from the right:
        # the way back stands where the reading starts, titles and labels hug
        # the reading's edge, rows run the way the words do. The root says it
        # once and every container below inherits it -- a page said again in
        # another tongue says its own direction again.
        layout_direction = (
                Control.LAYOUT_DIRECTION_RTL if I18nScript.is_rtl()
                else Control.LAYOUT_DIRECTION_LTR
        )
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
        var bar: Dictionary = ThemeScript.top_bar(I18nScript.t("Settings"), I18nScript.is_rtl())
        var back: Button = bar["back"]
        back.tooltip_text = I18nScript.t("Back to home")
        back.pressed.connect(func() -> void: closed.emit())
        column.add_child(bar["row"])

        column.add_child(_deck_body())
        column.add_child(_reading_body())
        column.add_child(_display_body())
        column.add_child(_github_body())
        # The deck as one file stands with the deck's own story: after the
        # account, before where the words come from -- the reader who walks
        # down the page meets their deck's safety next to their deck's
        # source, both of them about the deck rather than the machine.
        column.add_child(_backup_body())
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


## The phone's back key puts away whatever stands over the settings --
## today the backup page -- and then the settings themselves, the same
## door the page's own back button opens.
func request_back() -> bool:
        var picker := get_node_or_null("BackupPicker") as BackupPickerScript
        if picker != null:
                return picker.request_back()
        closed.emit()
        return true

## A card's own name, said inside the card: a small gold word over a rule,
## so each card reads as its own page with a running title -- not a label
## floating between cards, where the margin swallows it. The word stands at
## the edge the page reads from.
##
## The alignment is LEFT on purpose, in both directions. Under an RTL layout
## the engine reads a Label's LEFT as the reading's start -- the right edge --
## and RIGHT as its far end, so a RIGHT here would stand a Persian title at
## the page's LEFT margin: exactly the corner the reader reported it stuck in.
## LEFT means "where the reading begins" on every page this app speaks. (A
## RichTextLabel answers the other way -- see _text -- which is why the two
## builders say different words for the same edge.)
func _card_header(box: VBoxContainer, title: String) -> void:
        var label := Label.new()
        label.name = "CardTitle"
        label.text = title
        label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
        # A card's own name is the smallest word a reader hunts for, so it
        # stands one breath larger than the captions beneath it.
        ThemeScript.dress(label, 13, ThemeScript.GOLD_DEEP, true)
        box.add_child(label)
        box.add_child(ThemeScript.hairline(ThemeScript.LINE))

## Every line of explanation on this screen is a selectable RichTextLabel:
## a person reads with their eyes and copies with their mouse, and neither
## should wait for the other. One builder, so every line looks and behaves
## the same everywhere on this screen.
func _text(what: String, color: Color, size: int, center := false, bold := false) -> RichTextLabel:
        var label := RichTextLabel.new()
        label.selection_enabled = true
        CopyChipScript.watch(label)
        label.fit_content = true
        label.scroll_active = false
        label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        if center:
                label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        else:
                # A line stands at the edge its page reads from -- but the two
                # controls answer differently under a right-reading layout:
                # a Label's LEFT is the reading's start (the visual right
                # edge), while a RichTextLabel's LEFT stays the visual left
                # edge, measured, whatever the paragraph inside it reads. A
                # RichTextLabel must therefore be told the reading's edge in
                # so many words: RIGHT when the tongue reads from the right.
                label.horizontal_alignment = (
                        HORIZONTAL_ALIGNMENT_RIGHT if I18nScript.is_rtl()
                        else HORIZONTAL_ALIGNMENT_LEFT
                )
        label.add_theme_font_override("normal_font", ThemeScript.vazir(size, bold))
        label.add_theme_font_size_override("normal_font_size", ThemeScript.fs(size))
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

## A field's label, close enough to belong to it and no closer. It stands
## at the edge the page reads from, like every word that names what follows.
func _field_label(text: String) -> Label:
        var label := Label.new()
        label.name = "FieldLabel"
        label.text = text
        # LEFT is the reading's start under either layout (see _card_header).
        label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
        return ThemeScript.dress(label, ThemeScript.CAPTION, ThemeScript.INK, true)

func _github_body() -> Control:
        var parts := _card("GitHub")
        var card: PanelContainer = parts[0]
        var box: VBoxContainer = parts[1]
        _card_header(box, I18nScript.t("GitHub sync"))

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
        # A code is a ticket, not a paragraph -- it never wraps. The _text
        # builder dresses every line to wrap its words, and a wrapping
        # label's least width is nothing at all, so the chip (which shrinks
        # to its child's least width) stood one letter wide and stacked the
        # code like a column of falling tiles -- the photograph from the
        # phone. With the wrap off, the label's least width is the code's
        # own width, and the chip closes around it, one line, centred.
        code.autowrap_mode = TextServer.AUTOWRAP_OFF
        chip_pad.add_child(code)
        flow.add_child(chip)

        var hint := _text(I18nScript.t("Type this code at github.com/login/device, then wait here."), ThemeScript.INK_SOFT, ThemeScript.CAPTION, true)
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

        var open := ThemeScript.ghost_button(I18nScript.t("Open GitHub"), ThemeScript.GREEN, 44)
        open.name = "Open"
        open.tooltip_text = I18nScript.t("Open the sign-in page")
        open.pressed.connect(func() -> void:
                if not _flow_uri.is_empty():
                        OS.shell_open(_flow_uri)
        )
        actions.add_child(open)

        var copy := ThemeScript.ghost_button(I18nScript.t("Copy code"), ThemeScript.GREEN, 44, 22)
        copy.name = "Copy"
        copy.tooltip_text = I18nScript.t("Copy the code to the clipboard")
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

        var connect := ThemeScript.primary_button(I18nScript.t("Connect GitHub"), 46)
        connect.name = "Connect"
        connect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        connect.tooltip_text = I18nScript.t("Sign in with GitHub")
        connect.pressed.connect(_begin_device_flow)
        buttons.add_child(connect)

        var disconnect := ThemeScript.ghost_button(I18nScript.t("Disconnect"), ThemeScript.DANGER, 46)
        disconnect.name = "Disconnect"
        disconnect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        disconnect.pressed.connect(_disconnect)
        buttons.add_child(disconnect)

        box.add_child(_field_label(I18nScript.t("Personal access token")))
        # The field owns its whole row: a token is forty characters, and a
        # thumb needs the field's full width to find its place in it. Paste
        # is not a button any more -- in a browser the page hands the app its
        # own paste events, so Ctrl+V simply works, and a finger pastes by
        # holding the field. What is left under it are the two things that
        # were always wanted: to see what arrived, and to keep it.
        var token := LineEdit.new()
        token.name = "Token"
        token.placeholder_text = (
                I18nScript.t("Paste the token GitHub shows you") if OS.has_feature("web") else I18nScript.t("…or paste a repo token")
        )
        token.secret = true
        token.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        token.custom_minimum_size = Vector2(0, 48)
        # A field on a right-reading page meets its reader at the reading's
        # start: LEFT is that edge under either layout (see _card_header), and
        # what is typed stays as it is written, Latin or otherwise.
        token.alignment = HORIZONTAL_ALIGNMENT_LEFT
        token.add_theme_font_override("font", ThemeScript.vazir(ThemeScript.CAPTION))
        token.add_theme_font_size_override("font_size", ThemeScript.fs(ThemeScript.CAPTION))
        _style_field(token)
        _paste_on_hold(token)
        token.text_submitted.connect(func(_text: String) -> void: _save_token())
        box.add_child(token)
        var token_row := HBoxContainer.new()
        token_row.name = "TokenRow"
        token_row.add_theme_constant_override("separation", 8)
        box.add_child(token_row)
        var show := ThemeScript.ghost_button(I18nScript.t("Show"), ThemeScript.INK_SOFT, 44, 22)
        show.name = "ShowToken"
        show.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        show.tooltip_text = I18nScript.t("Show or hide what was typed")
        show.pressed.connect(_toggle_token_shown)
        token_row.add_child(show)
        # Keeping the token is the row's errand, so it is the row's one
        # filled action; seeing is only a second thought beside it.
        var save_token := ThemeScript.primary_button(I18nScript.t("Save token"), 44)
        save_token.name = "SaveToken"
        save_token.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        save_token.pressed.connect(_save_token)
        token_row.add_child(save_token)

        # The page's own division: the account above, the deck's home below.
        box.add_child(ThemeScript.hairline())

        box.add_child(_field_label(I18nScript.t("Repository")))
        var repo := LineEdit.new()
        repo.name = "Repo"
        repo.placeholder_text = I18nScript.t("Repository name")
        repo.custom_minimum_size = Vector2(0, 44)
        # The reading's own edge, under either layout (see _card_header).
        repo.alignment = HORIZONTAL_ALIGNMENT_LEFT
        repo.add_theme_font_override("font", ThemeScript.vazir(ThemeScript.BODY))
        repo.add_theme_font_size_override("font_size", ThemeScript.fs(ThemeScript.BODY))
        _style_field(repo)
        repo.text_submitted.connect(_save_repo)
        box.add_child(repo)
        _paste_on_hold(repo)
        repo.focus_exited.connect(func() -> void: _save_repo(repo.text))
        # The deck's home on GitHub, said once under the field that names it:
        # a RichTextLabel, so under a right-reading tongue it stands at the
        # reading's own edge (see _text) -- the corner the reader reported
        # it stuck at when the line was left to the visual left edge.
        var repo_hint := _text(
                I18nScript.t("Where your deck lives on GitHub — created on first sync if it does not exist."),
                ThemeScript.INK_SOFT,
                ThemeScript.CAPTION
        )
        repo_hint.name = "RepoHint"
        box.add_child(repo_hint)

        # The quiet promise, said plainly and changeable: after each session
        # the deck tells GitHub on its own. A promise that matters is a row
        # of its own -- a page's worth of surface with a switch that reads
        # as a switch from across the room, and the whole row is the
        # button, so a thumb cannot miss it the way it missed a caption
        # with a dot after it. The promise's own words stand on their own;
        # nothing beneath them explains what they already said.
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
        auto_label.text = I18nScript.t("Sync quietly after each session")
        # LEFT is the reading's start under either layout (see _card_header).
        auto_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
        ThemeScript.dress(auto_label, ThemeScript.BODY, ThemeScript.INK, true)
        auto_words.add_child(auto_label)
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

        var sync := ThemeScript.primary_button(I18nScript.t("Sync now"), 46)
        sync.name = "Sync"
        sync.tooltip_text = I18nScript.t("Sync with GitHub")
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

        # The day's own offer: how many unseen cards a session may bring. The
        # number is the reader's pace, not the algorithm's -- Anki's deck
        # default of 20 is only where it starts -- so it lives here, beside
        # the deck it paces, as the one arithmetic the reader is asked to own.
        # The card's name line and its storage note are gone: a reader opening
        # Settings wants to turn a knob, not to be told what a folder is.
        _card_header(box, I18nScript.t("New cards each day"))
        var stepper := HBoxContainer.new()
        stepper.name = "NewPerDay"
        stepper.add_theme_constant_override("separation", 10)
        box.add_child(stepper)
        var less := ThemeScript.ghost_button("-", ThemeScript.GREEN_DEEP, 44)
        less.name = "StepLess"
        less.tooltip_text = I18nScript.t("Offer one fewer new card a day")
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
        more.tooltip_text = I18nScript.t("Offer one more new card a day")
        more.custom_minimum_size = Vector2(52, 44)
        more.pressed.connect(_step_new_per_day.bind(1))
        stepper.add_child(more)
        var pace := _text(
                I18nScript.t("How many new cards a day offers — 0 studies only reviews."),
                ThemeScript.INK_SOFT, 12
        )
        pace.name = "Pace"
        # The caption stands in the row of 44-tall buttons, so its one line
        # rides the row's own middle -- the height the chip's number and
        # the buttons' glyphs are centred at, not the row's top edge.
        pace.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        pace.size_flags_vertical = Control.SIZE_EXPAND_FILL
        stepper.add_child(pace)
        return card

## A press on the stepper is the reader choosing their own pace: the number
## moves at once, the settings file is written at once, and the deck's own
## progress file is stamped with it -- where it travels to every device the
## deck reaches, and where the repo hears it at the next sync. The bounds
## keep the choice sane -- 0 is a day of reviews only, and no day needs more
## new cards than this.
func _step_new_per_day(delta: int) -> void:
        _settings.new_per_day = clampi(_settings.new_per_day + delta, 0, 200)
        _settings.save()
        if _deck != null:
                _deck.new_per_day = _settings.new_per_day
                _deck.new_per_day_mod = int(Time.get_unix_time_from_system())
                _deck.save_progress()
        var value: Label = get_node("Margin/Scroll/Wrap/Column/DeckInfo/Padding/Box/NewPerDay/Chip/StepValue")
        value.text = I18nScript.num(_settings.new_per_day)
        _ask_deck_push()

## How the reading reads: the hand the verses are written in, and the tongue
## the app's own words speak. Both are the reader's to choose, both are
## shown rather than explained (a font's name in the UI's own face beside a
## verse drawn in the font itself; a language named in its own script) -- the
## choice is judged on what it chooses -- and both travel with the deck: one
## reader, one way of reading, every device. The tongue is the standard
## build's to choose; a Persian build was born speaking it, so there the
## question would only offer to unmake what the build already is, and it
## is not asked at all.
func _reading_body() -> Control:
        var parts := _card("Reading")
        var card: PanelContainer = parts[0]
        var box: VBoxContainer = parts[1]
        _card_header(box, I18nScript.t("Reading"))

        box.add_child(_field_label(I18nScript.t("Ayah font")))
        var faces := HBoxContainer.new()
        faces.name = "AyahFaces"
        faces.add_theme_constant_override("separation", 8)
        box.add_child(faces)
        # The standing choices are read from the theme and the tongue it
        # speaks, not from the settings object: this page builds before its
        # setup() arrives, and the theme already wears whatever choice the
        # deck carried into boot. A choice made here re-says the page, so
        # the segments can never disagree with what they chose.
        var current_face := ThemeScript.ayah_face_key()
        # One height for every segment: the row is one question and its
        # boxes must align, so the tallest face's own sample -- measured,
        # not guessed -- says the height for all three.
        var seg_height := _face_segment_height()
        for face in ThemeScript.AYAH_FACES:
                faces.add_child(_ayah_font_segment(
                        str(face["key"]), str(face["label"]),
                        str(face["key"]) == current_face, seg_height
                ))

        # The tongue the app's own words speak: the standard build's one
        # question about itself. A Persian build never asks it here -- the
        # build answered it the day it was exported, and a row offering to
        # change what the build is would be a question with only wrong
        # answers.
        if not FlavorScript.persian_build():
                box.add_child(ThemeScript.hairline())

                box.add_child(_field_label(I18nScript.t("App language")))
                var langs := HBoxContainer.new()
                langs.name = "AppLanguages"
                langs.add_theme_constant_override("separation", 8)
                box.add_child(langs)
                # The standing tongue, straight from the mouth that speaks it.
                var current_lang := I18nScript.lang()
                for code in I18nScript.LANGS:
                        langs.add_child(_language_segment(code, code == current_lang))
        return card

## The height every font segment in the row shares: the tallest face's
## measured sample, plus the name label above it and the padding the
## segment carries inside. The faces themselves say the number, so the
## row grows with whatever a future face needs and no preview can outgrow
## its box at any scale the reader steps the words to.
static func _face_segment_height() -> float:
        var name_h := ceili(ThemeScript.vazir(12).get_height(ThemeScript.fs(12)))
        return 8.0 + name_h + 2.0 + ThemeScript.basmala_sample_height()

## One font, one segment: its own name in the UI's face, and beneath it a
## line of scripture drawn in the font itself -- the choice is judged on
## what it chooses, not on a description of it.
func _ayah_font_segment(key: String, label: String, on: bool, min_height: float) -> Button:
        var button := Button.new()
        button.name = "Face" + key.capitalize()
        button.set_meta("choice", key)
        button.toggle_mode = false
        button.custom_minimum_size = Vector2(0, min_height)
        button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        _dress_segment(button, on)
        var stack := VBoxContainer.new()
        stack.name = "Stack"
        stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        stack.alignment = BoxContainer.ALIGNMENT_CENTER
        stack.add_theme_constant_override("separation", 2)
        stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
        var name := Label.new()
        name.name = "Name"
        name.text = label
        name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        ThemeScript.dress(name, 12, ThemeScript.GREEN_DEEP if on else ThemeScript.INK_SOFT, on)
        stack.add_child(name)
        var sample := Label.new()
        sample.name = "Sample"
        # The basmala, harakat and all: every curl a verse's face draws, at
        # the size a shelf's preview shows it.
        sample.text = ThemeScript.BASMALA_SAMPLE
        sample.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        sample.text_direction = TextDirection.TEXT_DIRECTION_AUTO
        var face: Font = ThemeScript.ayah_face_for(key)
        var sample_size := ThemeScript.fs(19)
        sample.add_theme_font_override("font", face)
        sample.add_theme_font_size_override("font_size", sample_size)
        sample.add_theme_color_override("font_color", ThemeScript.INK)
        # The sample's ink is measured, not guessed: a face whose marks
        # stand past its font's box is given the room they ask for -- the
        # same law every verse on every page is drawn by.
        ThemeScript.give_label_room(sample, sample.text, face, sample_size)
        stack.add_child(sample)
        var pad := MarginContainer.new()
        pad.name = "Pad"
        pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
        pad.add_theme_constant_override("margin_left", 8)
        pad.add_theme_constant_override("margin_right", 8)
        pad.add_theme_constant_override("margin_top", 4)
        pad.add_theme_constant_override("margin_bottom", 4)
        pad.add_child(stack)
        button.add_child(pad)
        ThemeScript.pressable(button)
        button.pressed.connect(_choose_ayah_font.bind(key))
        return button

## One language, one segment, named in its own script.
func _language_segment(code: String, on: bool) -> Button:
        var button := Button.new()
        button.name = "Lang" + code.capitalize()
        button.set_meta("choice", code)
        button.toggle_mode = false
        button.custom_minimum_size = Vector2(0, 46)
        button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        _dress_segment(button, on)
        var label := Label.new()
        label.name = "Name"
        label.text = I18nScript.lang_label(code)
        label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        ThemeScript.dress(label, ThemeScript.BODY, ThemeScript.GREEN_DEEP if on else ThemeScript.INK_SOFT, on)
        var pad := MarginContainer.new()
        pad.name = "Pad"
        pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
        pad.add_theme_constant_override("margin_left", 8)
        pad.add_theme_constant_override("margin_right", 8)
        pad.add_child(label)
        button.add_child(pad)
        ThemeScript.pressable(button)
        button.pressed.connect(_choose_ui_lang.bind(code))
        return button

## A segment at rest is quiet paper; the chosen one wears the page's own
## green wash -- the way a book's folios are marked, not the way a form's
## checkboxes are.
func _dress_segment(button: Button, on: bool) -> void:
        var rest := ThemeScript.soft_stylebox(Color(0, 0, 0, 0), 12)
        rest.border_color = Color(
                ThemeScript.GREEN.r, ThemeScript.GREEN.g, ThemeScript.GREEN.b, 0.35 if on else 0.16
        )
        rest.set_border_width_all(1)
        var wash := rest.duplicate() as StyleBoxFlat
        wash.bg_color = Color(ThemeScript.GREEN.r, ThemeScript.GREEN.g, ThemeScript.GREEN.b, 0.10)
        var held := wash.duplicate() as StyleBoxFlat
        held.bg_color = Color(ThemeScript.GREEN.r, ThemeScript.GREEN.g, ThemeScript.GREEN.b, 0.16)
        if on:
                rest.bg_color = Color(ThemeScript.GREEN.r, ThemeScript.GREEN.g, ThemeScript.GREEN.b, 0.10)
        button.add_theme_stylebox_override("normal", rest)
        button.add_theme_stylebox_override("hover", held if not on else wash)
        button.add_theme_stylebox_override("pressed", held)
        button.add_theme_stylebox_override("focus", wash)

## A quiet explanatory line under a choice, the caption a field's label
## never quite is. It carries a stable name, the way field labels do, so a
## page's own words can be found by their path.
func _caption_line(what: String) -> RichTextLabel:
        var label := _text(what, ThemeScript.INK_SOFT, 12)
        label.name = "Caption"
        return label

## The verses' own face, chosen: the setting remembers it on this device,
## the theme wears it from this breath on, and the deck's own progress file
## carries it to every device the deck reaches.
func _choose_ayah_font(key: String) -> void:
        if key == _settings.ayah_font:
                return
        _settings.ayah_font = key
        _settings.save()
        ThemeScript.set_ayah_face(key)
        if _deck != null:
                _deck.ayah_font = key
                _deck.ayah_font_mod = int(Time.get_unix_time_from_system())
                _deck.save_progress()
        _redress_segments("Margin/Scroll/Wrap/Column/Reading/Padding/Box/AyahFaces", key)
        _ask_deck_push()

## The app's own tongue, chosen: remembered here, spoken through the app at
## once, carried with the deck -- and this page is said again in it, because
## this is the page the choice was made on.
func _choose_ui_lang(code: String) -> void:
        if code == _settings.ui_lang:
                return
        _settings.ui_lang = code
        _settings.save()
        I18nScript.set_lang(code)
        if _deck != null:
                _deck.ui_lang = code
                _deck.ui_lang_mod = int(Time.get_unix_time_from_system())
                _deck.save_progress()
        _rebuild()
        _ask_deck_push()

## The chosen segment says itself, without rebuilding the page: the font
## row re-dresses in place (its samples already wear every face), and the
## language row -- re-said by _rebuild -- never reaches this.
func _redress_segments(path: String, chosen: String) -> void:
        var row: HBoxContainer = get_node_or_null(path)
        if row == null:
                return
        for child in row.get_children():
                var button := child as Button
                if button == null:
                        continue
                var key := str(button.get_meta("choice", ""))
                _dress_segment(button, key == chosen)
                var name: Label = button.get_node_or_null("Pad/Stack/Name")
                if name != null:
                        ThemeScript.dress(name, 12, ThemeScript.GREEN_DEEP if key == chosen else ThemeScript.INK_SOFT, key == chosen)

## One ask, once the hand stops choosing: the deck's own file has the word,
## and the repo hears it without anyone pressing anything.
func _ask_deck_push() -> void:
        if _choice_push != null:
                # The engine's Timer has no restart(); a stopped start is one.
                _choice_push.stop()
                _choice_push.start()


# --- how the app sizes itself ------------------------------------------------------

## Two ways to size the app for the eyes in front of it: the whole interface
## at once, or the words alone. Both take hold the moment they are stepped --
## the interface because the window re-flows everything under the new factor,
## the words because the theme wears the new factor from that breath on and
## this page is said again in it. Both are this device's own comfort; unlike
## the pace, the face and the tongue, neither travels with the deck.
func _display_body() -> Control:
        var parts := _card("Display")
        var card: PanelContainer = parts[0]
        var box: VBoxContainer = parts[1]
        _card_header(box, I18nScript.t("Display"))

        box.add_child(_scale_row(
                "UiScale",
                I18nScript.t("Interface scale"),
                I18nScript.t("Shrink the interface one step"),
                I18nScript.t("Grow the interface one step"),
                ThemeScript.ui_scale(),
                _step_ui_scale
        ))
        box.add_child(_caption_line(I18nScript.t(
                "Scales the whole interface — cards, pills and words together — the way a phone's display-size setting does."
        )))

        box.add_child(ThemeScript.hairline())

        box.add_child(_scale_row(
                "TextScale",
                I18nScript.t("Text scale"),
                I18nScript.t("Shrink the text one step"),
                I18nScript.t("Grow the text one step"),
                ThemeScript.font_scale(),
                _step_font_scale
        ))
        box.add_child(_caption_line(I18nScript.t(
                "Scales the words only — verses, translations and messages — leaving the layout where it is."
        )))
        return card

## One scale, one row: a field's label, the stepper the pace already speaks,
## and the standing value as a percentage in the reader's own digits. The
## value the theme wears is the value the row says, whatever this device
## booted with -- the page builds before its setup() arrives, and the theme
## was dressed at boot.
func _scale_row(row_name: String, label_text: String, less_tip: String, more_tip: String, value: float, on_step: Callable) -> Control:
        var wrap := VBoxContainer.new()
        wrap.name = row_name
        wrap.add_theme_constant_override("separation", 8)
        wrap.add_child(_field_label(label_text))
        var stepper := HBoxContainer.new()
        stepper.name = "Stepper"
        stepper.add_theme_constant_override("separation", 10)
        wrap.add_child(stepper)
        var less := ThemeScript.ghost_button("-", ThemeScript.GREEN_DEEP, 44)
        less.name = "StepLess"
        less.tooltip_text = less_tip
        less.custom_minimum_size = Vector2(52, 44)
        less.pressed.connect(func() -> void: on_step.call(-1))
        stepper.add_child(less)
        var value_chip := PanelContainer.new()
        value_chip.name = "Chip"
        value_chip.custom_minimum_size = Vector2(72, 44)
        value_chip.add_theme_stylebox_override(
                "panel", ThemeScript.soft_stylebox(ThemeScript.GOLD_SOFT, 14)
        )
        var value_label := Label.new()
        value_label.name = "StepValue"
        value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        value_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
        ThemeScript.dress(value_label, ThemeScript.BODY + 2, ThemeScript.GOLD_DEEP, true)
        value_label.text = _percent(value)
        value_chip.add_child(value_label)
        stepper.add_child(value_chip)
        var more := ThemeScript.ghost_button("+", ThemeScript.GREEN_DEEP, 44)
        more.name = "StepMore"
        more.tooltip_text = more_tip
        more.custom_minimum_size = Vector2(52, 44)
        more.pressed.connect(func() -> void: on_step.call(1))
        stepper.add_child(more)
        return wrap

## A percentage, said in the reader's own digits: 85% reads as ۸۵٪ in Persian,
## the way every number the app says about itself does.
static func _percent(value: float) -> String:
        return I18nScript.num("%d%%" % [int(round(value * 100.0))])

## Where a step lands: the ladder's own rung nearest the standing value, one
## rung along in the direction asked, and no further than the ladder goes.
static func _stepped(current: float, delta: int, ladder: Array) -> float:
        var at := 0
        for i in ladder.size():
                if absf(float(ladder[i]) - current) < absf(float(ladder[at]) - current):
                        at = i
        return float(ladder[clampi(at + delta, 0, ladder.size() - 1)])

## The interface, one step larger or smaller: remembered on this device, and
## worn by the window at once -- every card, pill and margin grows together
## and the layout re-flows under the new factor, so there is nothing to say
## again and the chip is the only thing that moves.
func _step_ui_scale(delta: int) -> void:
        var value := _stepped(ThemeScript.ui_scale(), delta, UI_SCALE_STEPS)
        if is_equal_approx(value, ThemeScript.ui_scale()):
                return
        _settings.ui_scale = value
        _settings.save()
        ThemeScript.set_ui_scale(value)
        _say_scale_value("UiScale", value)

## The words, one step larger or smaller: remembered on this device, worn by
## the theme from this breath on, and said again wherever they were already
## standing -- this page rebuilt in its own new size, the window's tooltip
## theme re-dressed (a Theme holds only what it is given), and every page
## built afterwards dresses itself at the new size without being asked.
func _step_font_scale(delta: int) -> void:
        var value := _stepped(ThemeScript.font_scale(), delta, FONT_SCALE_STEPS)
        if is_equal_approx(value, ThemeScript.font_scale()):
                return
        _settings.font_scale = value
        _settings.save()
        ThemeScript.set_font_scale(value)
        get_window().theme = ThemeScript.tooltip_theme()
        _say_scale_value("TextScale", value)
        _rebuild()

## The chip says the new size without the page being rebuilt: a step is a
## small thing, and the row it was made on should answer it in place.
func _say_scale_value(row_name: String, value: float) -> void:
        var label: Label = get_node_or_null(
                "Margin/Scroll/Wrap/Column/Display/Padding/Box/%s/Stepper/Chip/StepValue" % row_name
        )
        if label != null:
                label.text = _percent(value)

# --- the deck as one file ----------------------------------------------------------

## The whole deck as one zip: everything a reader would grieve to lose,
## packed where a person keeps their files. The bringing-back joins rather
## than replaces -- the same card-by-card merge sync speaks -- so an old
## backup can never take a review away, and the note under the buttons
## only ever says what arrived.
func _backup_body() -> Control:
        var parts := _card("Backup")
        var card: PanelContainer = parts[0]
        var box: VBoxContainer = parts[1]
        _card_header(box, I18nScript.t("Backup"))

        box.add_child(_caption_line(I18nScript.t(
                "The whole deck — verses, recitations and your progress — in one zip file. Import joins a backup to this deck; nothing is removed."
        )))

        var row := HBoxContainer.new()
        row.name = "Buttons"
        row.add_theme_constant_override("separation", 10)
        box.add_child(row)
        var export_button := ThemeScript.primary_button(I18nScript.t("Export"), 46)
        export_button.name = "Export"
        export_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        export_button.tooltip_text = I18nScript.t("Pack the whole deck, with its progress, into one zip")
        export_button.pressed.connect(_on_export_pressed)
        row.add_child(export_button)
        var import_button := ThemeScript.ghost_button(I18nScript.t("Import"), ThemeScript.GREEN, 46)
        import_button.name = "Import"
        import_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        import_button.tooltip_text = I18nScript.t("Choose a backup zip; its learning joins this deck")
        import_button.pressed.connect(_on_import_pressed)
        row.add_child(import_button)

        var note := _text("", ThemeScript.INK_SOFT, ThemeScript.CAPTION, true)
        note.name = "BackupNote"
        box.add_child(note)
        return card


func _backup_note(what: String) -> void:
        var note: RichTextLabel = get_node_or_null("Margin/Scroll/Wrap/Column/Backup/Padding/Box/BackupNote")
        if note != null:
                note.text = what


## One press, one file: the deck packs itself into a zip that tries the
## shared Downloads folder first, then the app's own storage wherever the
## shared one is not this machine's to write, and the note says exactly
## where the file landed -- a place, not a promise. The path is said as it
## is, digits and all: it is the name of a real file, and dressing it in
## another script's digits would name a file that does not exist.
func _on_export_pressed() -> void:
        if _deck == null:
                return
        var file_name := DeckZipScript.backup_name()
        if OS.has_feature("web"):
                _export_web(file_name)
                return
        for place in DeckZipScript.destination_dirs():
                var dir := str(place["path"])
                DirAccess.make_dir_recursive_absolute(dir)
                var result: Dictionary = DeckZipScript.export_deck(_deck.folder, dir.path_join(file_name))
                if bool(result.get("ok", false)):
                        _backup_note(I18nScript.t("Backup saved — %s") % str(result.get("path", "")))
                        return
        _backup_note(I18nScript.t("The backup could not be written — your deck is safe here."))


## The way in depends on the world: in a browser the page owns the
## filesystem, so it opens its own picker and hands the bytes over;
## anywhere else the app's own page of found backups stands over this one.
func _on_import_pressed() -> void:
        if get_node_or_null("BackupPicker") != null:
                return
        if OS.has_feature("web"):
                var bridge := _zip_bridge()
                if bridge == null:
                        _backup_note(I18nScript.t("This build cannot open a file picker."))
                        return
                bridge.call("eval", "window.__qtZipPick && window.__qtZipPick()")
                return
        var picker := BackupPickerScript.new()
        picker.name = "BackupPicker"
        picker.setup(DeckZipScript.find_backups())
        add_child(picker)
        picker.picked.connect(_run_import)


## The file's word, joined to this deck: progress merges card by card, the
## travelling choices by their own moments, and files land only where the
## deck lacks them -- so the note counts arrivals and never losses. What
## arrived is the app's to adopt: the root owns the deck and hears it
## here, then hands the re-read deck back to this page.
func _run_import(zip_path: String) -> void:
        if _deck == null:
                return
        var result: Dictionary = DeckZipScript.import_deck(_deck.folder, zip_path)
        if not bool(result.get("ok", false)):
                if str(result.get("error", "")) == "not_a_deck":
                        _backup_note(I18nScript.t("That file is not a QuranTathbit backup."))
                else:
                        _backup_note(I18nScript.t("The backup could not be read."))
                return
        var new_cards := int(result.get("cards_new", 0))
        var merged := int(result.get("merged", 0))
        var added := int(result.get("added", 0))
        var parts: Array = []
        if new_cards > 0:
                parts.append(I18nScript.f(
                        "%d new card" if new_cards == 1 else "%d new cards", [new_cards]
                ))
        if merged > 0:
                parts.append(I18nScript.f(
                        "%d card's progress arrived" if merged == 1 else "%d cards' progress arrived", [merged]
                ))
        if added > 0:
                parts.append(I18nScript.f(
                        "%d file added" if added == 1 else "%d files added", [added]
                ))
        if parts.is_empty():
                _backup_note(I18nScript.t("This deck already holds everything the backup has."))
        else:
                _backup_note(" · ".join(parts))
        deck_imported.emit()


## The deck, re-read after a backup joined it: this page says the new
## count, and a tongue that arrived with the backup re-says the page in
## its own words -- the choice was made somewhere else, but this is the
## page the change lands on, so this is the page that answers it.
func deck_reloaded(deck: DeckScript) -> void:
        _deck = deck
        if not _settings.ui_lang.is_empty() and I18nScript.lang() != _settings.ui_lang:
                _rebuild()
        else:
                _refresh()

func _source_body() -> Control:
        var parts := _card("DataSource")
        var card: PanelContainer = parts[0]
        var box: VBoxContainer = parts[1]
        _card_header(box, I18nScript.t("Data source"))
        box.add_theme_constant_override("separation", 8)

        var what := RichTextLabel.new()
        what.name = "What"
        what.bbcode_enabled = true
        what.fit_content = true
        what.scroll_active = false
        what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        # The reading's own edge, said in so many words: a RichTextLabel's
        # LEFT stays the visual left edge under a right-reading layout too
        # (see _text), so the tongue itself decides the edge.
        what.horizontal_alignment = (
                HORIZONTAL_ALIGNMENT_RIGHT if I18nScript.is_rtl()
                else HORIZONTAL_ALIGNMENT_LEFT
        )
        what.text = I18nScript.t(
                "The deck's verses, Persian translation and recitations come from [url=https://quran.makarem.ir/]quran.makarem.ir[/url], carried unchanged from the deck package."
        )
        what.add_theme_font_override("normal_font", ThemeScript.vazir(ThemeScript.CAPTION))
        what.add_theme_font_size_override("normal_font_size", ThemeScript.fs(ThemeScript.CAPTION))
        what.add_theme_color_override("default_color", ThemeScript.INK)
        # Selection lets a user copy the line; the link opens in the browser.
        what.selection_enabled = true
        CopyChipScript.watch(what)
        what.add_theme_color_override("selection_color", ThemeScript.SELECT)
        what.meta_clicked.connect(func(meta: Variant) -> void: OS.shell_open(str(meta)))
        box.add_child(what)
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
        arabic.add_theme_font_size_override("font_size", ThemeScript.fs(16))
        arabic.add_theme_color_override("font_color", ThemeScript.GOLD)
        box.add_child(arabic)
        var label := _text(I18nScript.t("QuranTathbit v%s") % VersionScript.VERSION, ThemeScript.INK_SOFT, ThemeScript.CAPTION, true)
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
                state.text = I18nScript.t("Connected as @%s") % _settings.owner
        elif _settings.has_token():
                state.text = I18nScript.t("Token saved")
        elif OS.has_feature("web"):
                state.text = I18nScript.t("Not connected. In a browser you sign in with a one-minute token — press Connect GitHub and it walks you through.")
        else:
                state.text = I18nScript.t("Not connected. Sync keeps your progress on your own GitHub repo.")
        connect.visible = not _settings.has_token()
        disconnect.visible = _settings.has_token()
        # The day's offer is said here too, not only on a press: a reader
        # returning to this page reads their pace off the chip.
        var pace_value: Label = get_node("Margin/Scroll/Wrap/Column/DeckInfo/Padding/Box/NewPerDay/Chip/StepValue")
        pace_value.text = I18nScript.num(_settings.new_per_day)
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
                state0.text = I18nScript.t("This build has no GitHub app id yet. Add your OAuth app's client id to scripts/net/github_auth.gd, or paste a token below.")
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
                        state.text = I18nScript.t("Browsers cannot open GitHub's sign-in page (cross-origin rules). Use Connect GitHub for the token steps instead.")
                else:
                        state.text = I18nScript.t("Could not reach GitHub. Check your connection and try again.")
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
                get_node("Margin/Scroll/Wrap/Column/GitHub/Padding/Box/State").text = I18nScript.t("That flow did not complete. Try again when ready.")
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
        state.text = I18nScript.t("Signing in inside a browser takes a token — GitHub's sign-in page cannot be opened from another site, and no static site can change that. One minute, three steps:")
        var flow: VBoxContainer = get_node("Margin/Scroll/Wrap/Column/GitHub/Padding/Box/Flow")
        var code: PanelContainer = flow.get_node("Code")
        var hint: RichTextLabel = flow.get_node("Hint")
        var open: Button = flow.get_node("Actions/Open")
        code.visible = false
        (flow.get_node("Actions/Copy") as Button).visible = false
        hint.text = I18nScript.t(
                "1. Press the button — GitHub opens with the form filled in: the name and the repo permission are already set.\n2. Generate the token, then copy the string it shows you.\n3. Come back here, paste it into the box below (Ctrl+V, or hold the box on a phone), then press Save."
        )
        open.text = I18nScript.t("Create a token on GitHub")
        _flow_uri = "https://github.com/settings/tokens/new?scopes=repo&description=QuranTathbit%20sync"
        flow.visible = true
        get_node("Margin/Scroll/Wrap/Column/GitHub/Padding/Box/Token").grab_focus()

func _finish(token: String) -> void:
        var who: Dictionary = await _auth.whoami(_http, token)
        if who.has("error"):
                get_node("Margin/Scroll/Wrap/Column/GitHub/Padding/Box/State").text = I18nScript.t("Connected, but we could not read your login.")
                _settings.token = token
        else:
                _settings.owner = str(who.login)
                get_node("Margin/Scroll/Wrap/Column/GitHub/Padding/Box/State").text = I18nScript.t("Connected as @%s") % _settings.owner
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
                get_node("Margin/Scroll/Wrap/Column/GitHub/Padding/Box/State").text = I18nScript.t("That token did not work. Check it and try again.")
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
                _token_note(I18nScript.t("Nothing on the clipboard. Copy the token first, then hold the field to paste."))
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
                _token_note(I18nScript.t("This build cannot read the clipboard — type the token instead."))
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
                                _token_note(I18nScript.t("The clipboard is empty. Copy the token on GitHub, then hold the field to paste."))
                                return
                        field.text = clip
                        field.caret_column = clip.length()
                        field.grab_focus()
                        _token_note(I18nScript.t("Pasted — press Save token when it looks right."))
                        return
                _token_note(I18nScript.t("This browser would not share its clipboard. Copy the token, tap the field, and use your keyboard's paste."))
                return
        _token_note(I18nScript.t("The clipboard did not answer. Hold the field again to paste."))


## A secret field keeps neither typos nor pastes visible; a hand that wants
## to see what arrived before it commits may, and the button says which way
## it stands.
func _toggle_token_shown() -> void:
        var field := _token_field()
        field.secret = not field.secret
        var show: Button = get_node("Margin/Scroll/Wrap/Column/GitHub/Padding/Box/TokenRow/ShowToken")
        show.text = I18nScript.t("Hide") if not field.secret else I18nScript.t("Show")


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

# --- the backup, in a browser -------------------------------------------------------

## The page's bridge to the engine, read at runtime rather than by name: on
## every other platform there is none, and the same line then reads as "not
## here" instead of refusing to load.
func _zip_bridge() -> Object:
        if not OS.has_feature("web"):
                return null
        return Engine.get_singleton("JavaScriptBridge")

## In a browser the engine cannot write where a person keeps their files,
## and cannot open the machine's own picker either -- both belong to the
## page. The page's head script offers a hook for each direction (the same
## hand-off the paste bridge uses); this installs the engine's side of it,
## a callback the page calls with what the reader chose. The callback is
## reference-counted and held for as long as this screen stands, and a
## rebuilt page installs a fresh one over it.
func _install_zip_bridge() -> void:
        var bridge := _zip_bridge()
        if bridge == null:
                return
        _zip_callback = bridge.call("create_callback", _on_web_zip)
        var installer: Variant = bridge.call("get_interface", "__qtZipInstall")
        if installer != null:
                installer.install(_zip_callback)

## The page handed us a file. It arrives as one word -- "import", the file's
## name, and the whole archive as base64 -- and is written to a staging
## corner of the app's own storage, where it goes through exactly the same
## import door a native file does, then tidied away.
func _on_web_zip(args: Array) -> void:
        if args.is_empty() or _deck == null:
                return
        var word := str(args[0])
        if not word.begins_with("import:"):
                return
        var body := word.substr(7)
        var cut := body.find(":")
        if cut < 1:
                return
        var archive := body.substr(cut + 1)
        if archive.is_empty():
                return
        DirAccess.make_dir_recursive_absolute("user://backups")
        var staging := "user://backups".path_join("incoming.zip")
        var file := FileAccess.open(staging, FileAccess.WRITE)
        if file == null:
                _backup_note(I18nScript.t("The backup could not be read."))
                return
        file.store_buffer(Marshalls.base64_to_raw(archive))
        file.close()
        _run_import(staging)
        DirAccess.remove_absolute(staging)

## The browser's way out: the zip is staged in the app's own storage, read
## back, and handed to the page in base64 pieces -- a page-sized string at
## a time, never the whole archive in one eval -- where the head script
## gathers them into a Blob and offers it as a download under the backup's
## own name. The staging file is removed afterwards: the download is the
## reader's copy.
func _export_web(file_name: String) -> void:
        DirAccess.make_dir_recursive_absolute("user://backups")
        var staging := "user://backups".path_join(file_name)
        var result: Dictionary = DeckZipScript.export_deck(_deck.folder, staging)
        if not bool(result.get("ok", false)):
                _backup_note(I18nScript.t("The backup could not be written — your deck is safe here."))
                return
        var bridge := _zip_bridge()
        if bridge == null:
                _backup_note(I18nScript.t(
                        "This build cannot download files — the backup is saved inside the app's storage."
                ))
                return
        var archive := Marshalls.raw_to_base64(FileAccess.get_file_as_bytes(staging))
        bridge.call("eval", "window.__qtZipChunks=[]")
        var step := 393216
        for start in range(0, archive.length(), step):
                bridge.call(
                        "eval", "window.__qtZipChunks.push(atob('%s'))" % archive.substr(start, step)
                )
        bridge.call(
                "eval",
                "(function(){var b=new Blob(window.__qtZipChunks,{type:'application/zip'});"
                        + "window.__qtZipChunks=null;var u=URL.createObjectURL(b);"
                        + "var a=document.createElement('a');a.href=u;a.download='" + file_name + "';"
                        + "document.body.appendChild(a);a.click();a.remove();"
                        + "setTimeout(function(){URL.revokeObjectURL(u)},4000)})()"
        )
        DirAccess.remove_absolute(staging)
        _backup_note(I18nScript.t("Backup downloaded — it is in your browser's downloads."))
