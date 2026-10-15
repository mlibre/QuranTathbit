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
## there is deliberately nothing here to build a card with.

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
        ThemeScript.appear(self)

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
        var margin := MarginContainer.new()
        margin.name = "Margin"
        margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        margin.add_theme_constant_override("margin_left", 24)
        margin.add_theme_constant_override("margin_right", 24)
        margin.add_theme_constant_override("margin_top", 28)
        margin.add_theme_constant_override("margin_bottom", 28)
        add_child(margin)

        var scroll := ScrollContainer.new()
        scroll.name = "Scroll"
        scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
        margin.add_child(scroll)

        var column := VBoxContainer.new()
        column.name = "Column"
        column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        column.add_theme_constant_override("separation", 16)
        scroll.add_child(column)

        var header := HBoxContainer.new()
        header.name = "Header"
        var title := Label.new()
        title.text = "Settings"
        title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        title.add_theme_font_override("font", ThemeScript.vazir(ThemeScript.TITLE, true))
        title.add_theme_font_size_override("font_size", ThemeScript.TITLE)
        title.add_theme_color_override("font_color", ThemeScript.GREEN_DEEP)
        header.add_child(title)
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
        header.add_child(close)
        column.add_child(header)

        column.add_child(_section("GitHub"))
        column.add_child(_github_body())
        column.add_child(_section("Deck"))
        column.add_child(_deck_body())
        column.add_child(_section("Data source"))
        column.add_child(_source_body())
        column.add_child(_about())

func _section(title: String) -> Control:
        var label := Label.new()
        label.text = title
        label.add_theme_font_override("font", ThemeScript.vazir(ThemeScript.CAPTION, true))
        label.add_theme_font_size_override("font_size", ThemeScript.CAPTION)
        label.add_theme_color_override("font_color", ThemeScript.GOLD)
        return label

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
        label.text = what
        return label

func _github_body() -> Control:
        var card := PanelContainer.new()
        card.name = "GitHub"
        card.add_theme_stylebox_override("panel", ThemeScript.card_stylebox())
        var pad := MarginContainer.new()
        pad.name = "Padding"
        pad.add_theme_constant_override("margin_left", ThemeScript.PAD)
        pad.add_theme_constant_override("margin_right", ThemeScript.PAD)
        pad.add_theme_constant_override("margin_top", 18)
        pad.add_theme_constant_override("margin_bottom", 18)
        card.add_child(pad)
        var box := VBoxContainer.new()
        box.name = "Box"
        box.add_theme_constant_override("separation", 12)
        pad.add_child(box)

        var state := _text("", ThemeScript.INK, ThemeScript.BODY)
        state.name = "State"
        box.add_child(state)

        var flow := VBoxContainer.new()
        flow.name = "Flow"
        flow.visible = false
        flow.add_theme_constant_override("separation", 10)
        box.add_child(flow)

        var code := _text("", ThemeScript.GREEN_DEEP, 30, true, true)
        code.name = "Code"
        flow.add_child(code)

        var hint := _text("Type this code at github.com/login/device, then wait here.", ThemeScript.INK_SOFT, ThemeScript.CAPTION, true)
        hint.name = "Hint"
        flow.add_child(hint)

        var open := Button.new()
        open.name = "Open"
        open.text = "Open GitHub"
        open.custom_minimum_size = Vector2(0, 44)
        open.add_theme_font_override("font", ThemeScript.vazir(ThemeScript.BODY))
        open.add_theme_font_size_override("font_size", ThemeScript.BODY)
        open.add_theme_color_override("font_color", ThemeScript.GREEN_DEEP)
        open.add_theme_stylebox_override("normal", ThemeScript.outline_stylebox(ThemeScript.GREEN))
        open.add_theme_stylebox_override("hover", ThemeScript.soft_stylebox(ThemeScript.GREEN_SOFT, 23))
        open.add_theme_stylebox_override("pressed", ThemeScript.soft_stylebox(ThemeScript.GREEN_SOFT, 23))
        open.add_theme_stylebox_override("focus", ThemeScript.outline_stylebox(ThemeScript.GREEN))
        open.pressed.connect(func() -> void:
                if not _flow_uri.is_empty():
                        OS.shell_open(_flow_uri)
        )
        flow.add_child(open)

        var buttons := HBoxContainer.new()
        buttons.name = "Buttons"
        buttons.add_theme_constant_override("separation", 10)
        box.add_child(buttons)

        var connect := Button.new()
        connect.name = "Connect"
        connect.text = "Connect GitHub"
        connect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        connect.custom_minimum_size = Vector2(0, 46)
        connect.add_theme_font_override("font", ThemeScript.vazir(ThemeScript.BODY, true))
        connect.add_theme_font_size_override("font_size", ThemeScript.BODY)
        connect.add_theme_color_override("font_color", Color.WHITE)
        connect.add_theme_color_override("font_hover_color", Color.WHITE)
        connect.add_theme_stylebox_override("normal", ThemeScript.button_stylebox(ThemeScript.GREEN, 23))
        connect.add_theme_stylebox_override("hover", ThemeScript.button_stylebox(ThemeScript.GREEN_DEEP, 23))
        connect.add_theme_stylebox_override("pressed", ThemeScript.button_stylebox(ThemeScript.GREEN_DEEP, 23))
        connect.add_theme_stylebox_override("focus", ThemeScript.button_stylebox(ThemeScript.GREEN_DEEP, 23))
        connect.pressed.connect(_begin_device_flow)
        buttons.add_child(connect)

        var disconnect := Button.new()
        disconnect.name = "Disconnect"
        disconnect.text = "Disconnect"
        disconnect.custom_minimum_size = Vector2(0, 46)
        disconnect.add_theme_font_override("font", ThemeScript.vazir(ThemeScript.BODY))
        disconnect.add_theme_font_size_override("font_size", ThemeScript.BODY)
        disconnect.add_theme_color_override("font_color", ThemeScript.DANGER)
        disconnect.add_theme_stylebox_override("normal", ThemeScript.outline_stylebox(ThemeScript.DANGER, 1, 23))
        disconnect.add_theme_stylebox_override("hover", ThemeScript.soft_stylebox(Color(0.7, 0.33, 0.25, 0.12), 23))
        disconnect.add_theme_stylebox_override("pressed", ThemeScript.soft_stylebox(Color(0.7, 0.33, 0.25, 0.12), 23))
        disconnect.add_theme_stylebox_override("focus", ThemeScript.outline_stylebox(ThemeScript.DANGER, 1, 23))
        disconnect.pressed.connect(_disconnect)
        buttons.add_child(disconnect)

        var token_row := HBoxContainer.new()
        token_row.name = "TokenRow"
        token_row.add_theme_constant_override("separation", 8)
        box.add_child(token_row)
        var token := LineEdit.new()
        token.name = "Token"
        token.placeholder_text = ("Paste the token GitHub shows you" if OS.has_feature("web") else "…or paste a token with repo scope")
        token.secret = true
        token.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        token.custom_minimum_size = Vector2(0, 44)
        token.add_theme_font_override("font", ThemeScript.vazir(ThemeScript.CAPTION))
        token.add_theme_font_size_override("font_size", ThemeScript.CAPTION)
        token_row.add_child(token)
        var save_token := Button.new()
        save_token.name = "SaveToken"
        save_token.text = "Save"
        save_token.custom_minimum_size = Vector2(88, 44)
        save_token.add_theme_font_override("font", ThemeScript.vazir(ThemeScript.CAPTION))
        save_token.add_theme_font_size_override("font_size", ThemeScript.CAPTION)
        save_token.add_theme_color_override("font_color", ThemeScript.GREEN_DEEP)
        save_token.add_theme_stylebox_override("normal", ThemeScript.outline_stylebox(ThemeScript.GREEN, 1, 22))
        save_token.add_theme_stylebox_override("hover", ThemeScript.soft_stylebox(ThemeScript.GREEN_SOFT, 22))
        save_token.add_theme_stylebox_override("pressed", ThemeScript.soft_stylebox(ThemeScript.GREEN_SOFT, 22))
        save_token.add_theme_stylebox_override("focus", ThemeScript.outline_stylebox(ThemeScript.GREEN, 1, 22))
        save_token.pressed.connect(_save_token)
        token_row.add_child(save_token)

        var repo := LineEdit.new()
        repo.name = "Repo"
        repo.placeholder_text = "Repository name"
        repo.custom_minimum_size = Vector2(0, 44)
        repo.add_theme_font_override("font", ThemeScript.vazir(ThemeScript.BODY))
        repo.add_theme_font_size_override("font_size", ThemeScript.BODY)
        repo.text_submitted.connect(_save_repo)
        box.add_child(repo)

        var sync := Button.new()
        sync.name = "Sync"
        sync.text = "Sync now"
        sync.custom_minimum_size = Vector2(0, 46)
        sync.add_theme_font_override("font", ThemeScript.vazir(ThemeScript.BODY, true))
        sync.add_theme_font_size_override("font_size", ThemeScript.BODY)
        sync.add_theme_color_override("font_color", ThemeScript.GREEN_DEEP)
        sync.add_theme_stylebox_override("normal", ThemeScript.outline_stylebox(ThemeScript.GREEN))
        sync.add_theme_stylebox_override("hover", ThemeScript.soft_stylebox(ThemeScript.GREEN_SOFT, 23))
        sync.add_theme_stylebox_override("pressed", ThemeScript.soft_stylebox(ThemeScript.GREEN_SOFT, 23))
        sync.add_theme_stylebox_override("focus", ThemeScript.outline_stylebox(ThemeScript.GREEN))
        sync.pressed.connect(func() -> void: sync_requested.emit())
        box.add_child(sync)

        var note := _text("", ThemeScript.INK_SOFT, ThemeScript.CAPTION, true)
        note.name = "SyncNote"
        box.add_child(note)
        return card

func _deck_body() -> Control:
        var card := PanelContainer.new()
        card.name = "DeckInfo"
        card.add_theme_stylebox_override("panel", ThemeScript.card_stylebox())
        var pad := MarginContainer.new()
        pad.name = "Padding"
        pad.add_theme_constant_override("margin_left", ThemeScript.PAD)
        pad.add_theme_constant_override("margin_right", ThemeScript.PAD)
        pad.add_theme_constant_override("margin_top", 16)
        pad.add_theme_constant_override("margin_bottom", 16)
        card.add_child(pad)
        var box := VBoxContainer.new()
        box.name = "Box"
        box.add_theme_constant_override("separation", 8)
        pad.add_child(box)

        var name := _text("", ThemeScript.INK, ThemeScript.BODY, false, true)
        name.name = "Name"
        box.add_child(name)

        var folder := _text("", ThemeScript.INK_SOFT, ThemeScript.CAPTION)
        folder.name = "Folder"
        box.add_child(folder)

        var note := _text("Cards are folders on your disk. Edit them anywhere; sync carries them.", ThemeScript.INK_SOFT, ThemeScript.CAPTION)
        note.name = "Note"
        box.add_child(note)
        return card

func _source_body() -> Control:
        var card := PanelContainer.new()
        card.name = "DataSource"
        card.add_theme_stylebox_override("panel", ThemeScript.card_stylebox())
        var pad := MarginContainer.new()
        pad.name = "Padding"
        pad.add_theme_constant_override("margin_left", ThemeScript.PAD)
        pad.add_theme_constant_override("margin_right", ThemeScript.PAD)
        pad.add_theme_constant_override("margin_top", 16)
        pad.add_theme_constant_override("margin_bottom", 16)
        card.add_child(pad)
        var box := VBoxContainer.new()
        box.name = "Box"
        box.add_theme_constant_override("separation", 8)
        pad.add_child(box)

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
        what.meta_clicked.connect(func(meta: Variant) -> void: OS.shell_open(str(meta)))
        box.add_child(what)

        var open := Button.new()
        open.name = "Open"
        open.text = "Open quran.makarem.ir"
        open.custom_minimum_size = Vector2(0, 42)
        open.add_theme_font_override("font", ThemeScript.vazir(ThemeScript.CAPTION))
        open.add_theme_font_size_override("font_size", ThemeScript.CAPTION)
        open.add_theme_color_override("font_color", ThemeScript.GOLD)
        open.add_theme_color_override("font_hover_color", ThemeScript.GOLD)
        open.add_theme_stylebox_override("normal", ThemeScript.outline_stylebox(ThemeScript.GOLD, 1, 21))
        open.add_theme_stylebox_override("hover", ThemeScript.soft_stylebox(ThemeScript.GOLD_SOFT, 21))
        open.add_theme_stylebox_override("pressed", ThemeScript.soft_stylebox(ThemeScript.GOLD_SOFT, 21))
        open.add_theme_stylebox_override("focus", ThemeScript.outline_stylebox(ThemeScript.GOLD, 1, 21))
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
        var label := _text("QuranTathbit v%s\na quiet memorisation companion" % VersionScript.VERSION, ThemeScript.INK_SOFT, ThemeScript.CAPTION, true)
        label.name = "About"
        return label

# --- state ---------------------------------------------------------------------

## The main screen reports how a sync went while Settings is the screen on
## top; the note sits under the Sync button and clears when asked again.
func note_sync_result(text: String) -> void:
        var note: RichTextLabel = get_node_or_null("Margin/Scroll/Column/GitHub/Padding/Box/SyncNote")
        if note != null:
                note.text = text

func _refresh() -> void:
        var state: RichTextLabel = get_node("Margin/Scroll/Column/GitHub/Padding/Box/State")
        var connect: Button = get_node("Margin/Scroll/Column/GitHub/Padding/Box/Buttons/Connect")
        var disconnect: Button = get_node("Margin/Scroll/Column/GitHub/Padding/Box/Buttons/Disconnect")
        var repo: LineEdit = get_node("Margin/Scroll/Column/GitHub/Padding/Box/Repo")
        repo.text = _settings.repo
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
        var name: RichTextLabel = get_node("Margin/Scroll/Column/DeckInfo/Padding/Box/Name")
        var folder: RichTextLabel = get_node("Margin/Scroll/Column/DeckInfo/Padding/Box/Folder")
        name.text = "%s — %d cards" % [_deck.name, _deck.cards.size()]
        folder.text = _deck.folder
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
                var state0: RichTextLabel = get_node("Margin/Scroll/Column/GitHub/Padding/Box/State")
                state0.text = "This build has no GitHub app id yet. Add your OAuth app's client id to scripts/net/github_auth.gd, or paste a token below."
                return
        var began: Dictionary = await _auth.begin(_http)
        var flow: VBoxContainer = get_node("Margin/Scroll/Column/GitHub/Padding/Box/Flow")
        var code: RichTextLabel = flow.get_node("Code")
        var open: Button = flow.get_node("Open")
        var connect: Button = get_node("Margin/Scroll/Column/GitHub/Padding/Box/Buttons/Connect")
        if began.has("error"):
                var state: RichTextLabel = get_node("Margin/Scroll/Column/GitHub/Padding/Box/State")
                if OS.has_feature("web"):
                        # Unreachable on the web (the branch above), kept as a
                        # safety net: say what works instead of what failed.
                        state.text = "Browsers cannot open GitHub's sign-in page (cross-origin rules). Use Connect GitHub for the token steps instead."
                else:
                        state.text = "Could not reach GitHub. Check your connection and try again."
                return
        code.text = _pretty_code(str(began.user_code))
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
                get_node("Margin/Scroll/Column/GitHub/Padding/Box/State").text = "That flow did not complete. Try again when ready."
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
        var state: RichTextLabel = get_node("Margin/Scroll/Column/GitHub/Padding/Box/State")
        state.text = "Signing in inside a browser takes a token — GitHub's sign-in page cannot be opened from another site, and no static site can change that. One minute, three steps:"
        var flow: VBoxContainer = get_node("Margin/Scroll/Column/GitHub/Padding/Box/Flow")
        var code: RichTextLabel = flow.get_node("Code")
        var hint: RichTextLabel = flow.get_node("Hint")
        var open: Button = flow.get_node("Open")
        code.visible = false
        hint.text = (
                "1. Press the button — GitHub opens with the form filled in: the name and the repo permission are already set.\n"
                + "2. Generate the token, then copy the string it shows you.\n"
                + "3. Paste it below and press Save."
        )
        open.text = "Create a token on GitHub"
        _flow_uri = "https://github.com/settings/tokens/new?scopes=repo&description=QuranTathbit%20sync"
        flow.visible = true
        get_node("Margin/Scroll/Column/GitHub/Padding/Box/TokenRow/Token").grab_focus()

func _finish(token: String) -> void:
        var who: Dictionary = await _auth.whoami(_http, token)
        if who.has("error"):
                get_node("Margin/Scroll/Column/GitHub/Padding/Box/State").text = "Connected, but we could not read your login."
                _settings.token = token
        else:
                _settings.owner = str(who.login)
                get_node("Margin/Scroll/Column/GitHub/Padding/Box/State").text = "Connected as @%s" % _settings.owner
        _settings.token = token
        _settings.setup_done = true
        _settings.save()
        _flow_uri = ""
        var flow: VBoxContainer = get_node("Margin/Scroll/Column/GitHub/Padding/Box/Flow")
        flow.visible = false
        var connect: Button = get_node("Margin/Scroll/Column/GitHub/Padding/Box/Buttons/Connect")
        connect.disabled = false
        _refresh()
        account_changed.emit()

func _save_token() -> void:
        var token: LineEdit = get_node("Margin/Scroll/Column/GitHub/Padding/Box/TokenRow/Token")
        if token.text.strip_edges().is_empty():
                return
        var value := token.text.strip_edges()
        var who: Dictionary = await _auth.whoami(_http, value)
        if who.has("error"):
                get_node("Margin/Scroll/Column/GitHub/Padding/Box/State").text = "That token did not work. Check it and try again."
                return
        _settings.token = value
        _settings.owner = str(who.login)
        _settings.setup_done = true
        _settings.save()
        token.text = ""
        _refresh()
        account_changed.emit()

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
