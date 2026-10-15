class_name SettingsScreen
extends Control
const ThemeScript := preload("res://scripts/ui/theme.gd")
const HttpClientScript := preload("res://scripts/net/http_client.gd")
const GitHubAuthScript := preload("res://scripts/net/github_auth.gd")
const SettingsScript := preload("res://scripts/data/settings.gd")
const DeckScript := preload("res://scripts/data/deck.gd")

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
        column.add_child(_about())

func _section(title: String) -> Control:
        var label := Label.new()
        label.text = title
        label.add_theme_font_override("font", ThemeScript.vazir(ThemeScript.CAPTION, true))
        label.add_theme_font_size_override("font_size", ThemeScript.CAPTION)
        label.add_theme_color_override("font_color", ThemeScript.GOLD)
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

        var state := Label.new()
        state.name = "State"
        state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        state.add_theme_font_override("font", ThemeScript.vazir(ThemeScript.BODY))
        state.add_theme_font_size_override("font_size", ThemeScript.BODY)
        state.add_theme_color_override("font_color", ThemeScript.INK)
        box.add_child(state)

        var flow := VBoxContainer.new()
        flow.name = "Flow"
        flow.visible = false
        flow.add_theme_constant_override("separation", 10)
        box.add_child(flow)

        var code := Label.new()
        code.name = "Code"
        code.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        code.add_theme_font_override("font", ThemeScript.vazir(30, true))
        code.add_theme_font_size_override("font_size", 30)
        code.add_theme_color_override("font_color", ThemeScript.GREEN_DEEP)
        flow.add_child(code)

        var hint := Label.new()
        hint.name = "Hint"
        hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        hint.add_theme_font_override("font", ThemeScript.vazir(ThemeScript.CAPTION))
        hint.add_theme_font_size_override("font_size", ThemeScript.CAPTION)
        hint.add_theme_color_override("font_color", ThemeScript.INK_SOFT)
        hint.text = "Type this code at github.com/login/device, then wait here."
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
        token.placeholder_text = "…or paste a token with repo scope"
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

        var name := Label.new()
        name.name = "Name"
        name.add_theme_font_override("font", ThemeScript.vazir(ThemeScript.BODY, true))
        name.add_theme_font_size_override("font_size", ThemeScript.BODY)
        name.add_theme_color_override("font_color", ThemeScript.INK)
        box.add_child(name)

        var folder := Label.new()
        folder.name = "Folder"
        folder.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        folder.add_theme_font_override("font", ThemeScript.vazir(ThemeScript.CAPTION))
        folder.add_theme_font_size_override("font_size", ThemeScript.CAPTION)
        folder.add_theme_color_override("font_color", ThemeScript.INK_SOFT)
        box.add_child(folder)

        var note := Label.new()
        note.name = "Note"
        note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        note.add_theme_font_override("font", ThemeScript.vazir(ThemeScript.CAPTION))
        note.add_theme_font_size_override("font_size", ThemeScript.CAPTION)
        note.add_theme_color_override("font_color", ThemeScript.INK_SOFT)
        note.text = "Cards are folders on your disk. Edit them anywhere; sync carries them."
        box.add_child(note)
        return card

func _about() -> Control:
        var label := Label.new()
        label.name = "About"
        label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        label.text = "QuranTathbit · a quiet memorisation companion\nScheduling follows Anki's SM-2"
        label.add_theme_font_override("font", ThemeScript.vazir(ThemeScript.CAPTION))
        label.add_theme_font_size_override("font_size", ThemeScript.CAPTION)
        label.add_theme_color_override("font_color", ThemeScript.INK_SOFT)
        return label

# --- state ---------------------------------------------------------------------

func _refresh() -> void:
        var state: Label = get_node("Margin/Scroll/Column/GitHub/Padding/Box/State")
        var connect: Button = get_node("Margin/Scroll/Column/GitHub/Padding/Box/Buttons/Connect")
        var disconnect: Button = get_node("Margin/Scroll/Column/GitHub/Padding/Box/Buttons/Disconnect")
        var repo: LineEdit = get_node("Margin/Scroll/Column/GitHub/Padding/Box/Repo")
        repo.text = _settings.repo
        if _settings.has_token() and not _settings.owner.is_empty():
                state.text = "Connected as @%s" % _settings.owner
        elif _settings.has_token():
                state.text = "Token saved"
        else:
                state.text = "Not connected. Sync keeps your progress on your own GitHub repo."
        connect.visible = not _settings.has_token()
        disconnect.visible = _settings.has_token()
        var name: Label = get_node("Margin/Scroll/Column/DeckInfo/Padding/Box/Name")
        var folder: Label = get_node("Margin/Scroll/Column/DeckInfo/Padding/Box/Folder")
        name.text = "%s — %d cards" % [_deck.name, _deck.cards.size()]
        folder.text = _deck.folder

# --- the device flow ------------------------------------------------------------

func _begin_device_flow() -> void:
        if not _auth.is_configured():
                var state: Label = get_node("Margin/Scroll/Column/GitHub/Padding/Box/State")
                state.text = "This build has no GitHub app id yet. Add your OAuth app's client id to scripts/net/github_auth.gd, or paste a token below."
                return
        var began: Dictionary = await _auth.begin(_http)
        var flow: VBoxContainer = get_node("Margin/Scroll/Column/GitHub/Padding/Box/Flow")
        var code: Label = flow.get_node("Code")
        var open: Button = flow.get_node("Open")
        var connect: Button = get_node("Margin/Scroll/Column/GitHub/Padding/Box/Buttons/Connect")
        if began.has("error"):
                var state: Label = get_node("Margin/Scroll/Column/GitHub/Padding/Box/State")
                if OS.has_feature("web"):
                        # GitHub's sign-in endpoints send no CORS headers, so
                        # no browser build can ever reach them. Say so once,
                        # plainly, and hand the user the path that works.
                        state.text = "Browsers cannot open GitHub's sign-in page (cross-origin rules). Paste a personal access token with the repo scope below: GitHub, Settings, Developer settings, Personal access tokens, then Generate new token (classic)."
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
