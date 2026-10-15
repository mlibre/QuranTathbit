extends Control
const SettingsScript := preload("res://scripts/data/settings.gd")
const DeckScript := preload("res://scripts/data/deck.gd")
const CardScript := preload("res://scripts/data/card.gd")
const SchedulerScript := preload("res://scripts/data/scheduler.gd")
const HttpClientScript := preload("res://scripts/net/http_client.gd")
const GitHubAuthScript := preload("res://scripts/net/github_auth.gd")
const GitHubSyncScript := preload("res://scripts/net/github_sync.gd")
const ThemeScript := preload("res://scripts/ui/theme.gd")
const HomeScript := preload("res://scripts/ui/home.gd")
const StudyScript := preload("res://scripts/ui/study.gd")
const SettingsScreenScript := preload("res://scripts/ui/settings_screen.gd")

## QuranTathbit: one deck, kept in folders and files, studied one card at a
## time. This root owns the small amount of state the app has -- settings,
## the deck, the network clients, the session -- and moves between the three
## screens. Nothing else exists: no deck manager, no card editor, no browser.

const BUNDLED_DECK := "res://assets/decks/quran"
const USER_DECK := "user://decks/quran"

var _settings: SettingsScript
var _deck: DeckScript
var _http: HttpClientScript
var _auth: GitHubAuthScript
var _sync: GitHubSyncScript
var _screen: Control


func _ready() -> void:
        _install_deck()
        _settings = SettingsScript.load_settings()
        _deck = DeckScript.load(USER_DECK)
        if _deck == null:
                push_error("QuranTathbit: the deck could not be read from %s" % USER_DECK)
                get_tree().quit(1)
                return

        _http = HttpClientScript.new()
        _http.name = "HttpClient"
        add_child(_http)
        _auth = GitHubAuthScript.new()
        _sync = GitHubSyncScript.new(_http, _auth)

        _go_home()
        # The one line the release workflow's smoke test looks for: the deck is
        # installed, loaded, and the first screen is standing.
        print("QURAN_TATHBIT_BOOT_OK")


# --- deck installation ---------------------------------------------------------

## The bundled deck is copied into place once. After that the copy under
## user:// is the real one -- edited by the user, synced with GitHub -- and
## this never touches it again, so an update to the app cannot eat progress.
func _install_deck() -> void:
        if DirAccess.dir_exists_absolute(USER_DECK):
                return
        if not DirAccess.dir_exists_absolute(BUNDLED_DECK):
                push_error("QuranTathbit: no bundled deck at %s" % BUNDLED_DECK)
                return
        var err := DirAccess.make_dir_recursive_absolute(USER_DECK)
        if err != OK:
                push_error("QuranTathbit: cannot create %s" % USER_DECK)
                return
        _copy_tree(BUNDLED_DECK, USER_DECK)


func _copy_tree(from: String, to: String) -> void:
        for entry in DirAccess.get_files_at(from):
                var source := from.path_join(entry)
                var target := to.path_join(entry)
                var data := FileAccess.get_file_as_bytes(source)
                var file := FileAccess.open(target, FileAccess.WRITE)
                if file == null:
                        push_error("QuranTathbit: cannot write %s" % target)
                        continue
                file.store_buffer(data)
                file.close()
        for entry in DirAccess.get_directories_at(from):
                var sub_to := to.path_join(entry)
                DirAccess.make_dir_recursive_absolute(sub_to)
                _copy_tree(from.path_join(entry), sub_to)


# --- screens -------------------------------------------------------------------

func _go_home() -> void:
        if _screen is HomeScript:
                return
        var home := HomeScript.new()
        home.name = "Home"
        _swap(home)
        home.setup(_deck, SchedulerScript.counts(_deck, _now()), _sync_line(), _settings.has_token())
        home.study_pressed.connect(_start_session)
        home.sync_pressed.connect(_on_sync_pressed)
        home.settings_pressed.connect(_on_settings_pressed)


func _start_session() -> void:
        if _screen is StudyScript:
                return
        var cards := SchedulerScript.queue(_deck, _now())
        if cards.is_empty():
                return
        var study := StudyScript.new()
        study.name = "Study"
        _swap(study)
        study.start(cards)
        study.answered.connect(_on_answered)
        study.closed.connect(_go_home)


func _on_answered(card: CardScript, button: String) -> void:
        _deck.answer(card, button, _now())
        _deck.save_progress()


func _on_settings_pressed() -> void:
        if _screen is SettingsScreenScript:
                return
        var screen := SettingsScreenScript.new()
        screen.name = "Settings"
        _swap(screen)
        screen.setup(_http, _auth, _settings, _deck)
        screen.closed.connect(_go_home)
        screen.sync_requested.connect(_on_sync_pressed)
        screen.account_changed.connect(_on_account_changed)


func _on_account_changed() -> void:
        _settings = SettingsScript.load_settings()


func _on_sync_pressed() -> void:
        if not _settings.has_token():
                _on_settings_pressed()
                return
        await _run_sync()


## Sync, with a small word on screen while it works. The app stays usable
## when it fails -- the deck is local first, always.
func _run_sync() -> void:
        var overlay := _sync_overlay()
        add_child(overlay)
        var result: Dictionary = await _sync.sync(USER_DECK, func(text: String, done: int, total: int) -> void:
                var line: Label = overlay.get_node("Panel/Box/Progress")
                if total > 0:
                        line.text = "%s… %d / %d" % [text.capitalize(), done, total]
                else:
                        line.text = "%s…" % text.capitalize()
        )
        overlay.queue_free()
        _settings.last_sync = _now()
        _settings.save()

        # Progress may have merged in from another device; read the deck back.
        var reloaded: DeckScript = DeckScript.load(USER_DECK)
        if reloaded != null:
                _deck = reloaded
                _sync = GitHubSyncScript.new(_http, _auth)

        var line := ""
        if bool(result.get("ok", false)):
                line = "Synced just now · %d pushed, %d pulled, %d merged" % [
                        result.get("pushed", 0), result.get("pulled", 0), result.get("merged", 0)
                ]
        else:
                line = "Sync could not finish (%s). Your cards are safe here." % str(result.get("error", "?"))
        if _screen is HomeScript:
                var home: HomeScript = _screen
                home.setup(_deck, SchedulerScript.counts(_deck, _now()), line, _settings.has_token())


func _sync_overlay() -> Control:
        var dim := ColorRect.new()
        dim.name = "SyncOverlay"
        dim.color = Color(0.1, 0.14, 0.11, 0.35)
        dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        var center := CenterContainer.new()
        center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        dim.add_child(center)
        var panel := PanelContainer.new()
        panel.name = "Panel"
        panel.custom_minimum_size = Vector2(280, 0)
        panel.add_theme_stylebox_override("panel", ThemeScript.card_stylebox())
        center.add_child(panel)
        var box := VBoxContainer.new()
        box.name = "Box"
        box.add_theme_constant_override("separation", 8)
        panel.add_child(box)
        var title := Label.new()
        title.text = "Syncing"
        title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        title.add_theme_font_override("font", ThemeScript.vazir(ThemeScript.TITLE, true))
        title.add_theme_font_size_override("font_size", ThemeScript.TITLE)
        title.add_theme_color_override("font_color", ThemeScript.GREEN_DEEP)
        box.add_child(title)
        var progress := Label.new()
        progress.name = "Progress"
        progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        progress.add_theme_font_override("font", ThemeScript.vazir(ThemeScript.CAPTION))
        progress.add_theme_font_size_override("font_size", ThemeScript.CAPTION)
        progress.add_theme_color_override("font_color", ThemeScript.INK_SOFT)
        progress.text = "reading your repo…"
        box.add_child(progress)
        return dim


func _sync_line() -> String:
        if not _settings.has_token():
                return "Not connected — your deck lives on this device only"
        if _settings.last_sync > 0:
                return "Last synced %s" % _ago(_now() - _settings.last_sync)
        return "Connected — not synced yet"


static func _ago(seconds: int) -> String:
        if seconds < 90:
                return "just now"
        if seconds < 3600:
                return "%d min ago" % (seconds / 60)
        if seconds < 86400:
                return "%dh ago" % (seconds / 3600)
        return "%dd ago" % (seconds / 86400)


func _swap(next: Control) -> void:
        if _screen != null:
                var old: Control = _screen
                old.mouse_filter = Control.MOUSE_FILTER_IGNORE  # a fading screen stops taking input
                ThemeScript.vanish(old)
        _screen = next
        add_child(next)


func _now() -> int:
        return int(Time.get_unix_time_from_system())
