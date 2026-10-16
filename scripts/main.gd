extends Control
const SettingsScript := preload("res://scripts/data/settings.gd")
const DeckScript := preload("res://scripts/data/deck.gd")
const CardScript := preload("res://scripts/data/card.gd")
const SchedulerScript := preload("res://scripts/data/scheduler.gd")
const HttpClientScript := preload("res://scripts/net/http_client.gd")
const GitHubAuthScript := preload("res://scripts/net/github_auth.gd")
const GitHubSyncScript := preload("res://scripts/net/github_sync.gd")
const SyncOverlayScript := preload("res://scripts/ui/sync_overlay.gd")
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
var _update_waiting := false  # a newer web version was announced; Home owes the user the offer
var _syncing := false  # one sync at a time; a second press is a question, not a demand
var _answers_waiting := 0  # answers given since the repo last heard from this deck
var _sync_failed := false  # the last sync could not finish; the deck is honest about it


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

        _watch_updates()
        _go_home()
        # A deck that is already connected says hello on its own, quietly: a
        # sync that finds nothing to do is three small questions and a green
        # line, and the user never again opens the app to a status that
        # pretends nothing has happened since yesterday.
        if _settings.has_token() and _settings.auto_sync:
                get_tree().create_timer(1.2).timeout.connect(func() -> void: _run_sync(true))
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
        # Home is the way back: it arrives from above, the direction of
        # returning, the way going deeper arrives from below.
        _swap(home, true)
        _refresh_home()
        home.study_pressed.connect(_start_session)
        home.sync_pressed.connect(_on_sync_pressed)
        home.settings_pressed.connect(_on_settings_pressed)
        home.update_pressed.connect(_apply_update)
        if _update_waiting:
                home.offer_update()


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
        study.closed.connect(_on_session_closed)


## A session's answers are the one thing this app makes that another device
## wants; when the session closes, the deck says so to GitHub on its own --
## quietly, under the page it returns to -- so "synced" is never a thing
## the user has to remember to ask for.
func _on_session_closed() -> void:
        _go_home()
        if _settings.has_token() and _settings.auto_sync and _answers_waiting > 0:
                _run_sync(true)


func _on_answered(card: CardScript, button: String) -> void:
        _deck.answer(card, button, _now())
        _deck.save_progress()
        _answers_waiting += 1


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
        _refresh_home()
        # Connecting is itself the request for a first sync: the user just
        # chose to keep their deck on GitHub, so carry it there without
        # making them find the button and wonder whether anything happened.
        if _settings.has_token() and _settings.last_sync == 0:
                await _run_sync()


func _on_sync_pressed() -> void:
        if not _settings.has_token():
                _on_settings_pressed()
                return
        _run_sync()


## Sync, with its own quiet screen while it works when the hand asked for
## it, and with only the turning coin when the app asked for itself: a
## phase in plain words, a bar that knows how far along it is, and the
## promise that the deck is safe on this machine whatever the network
## does. The app stays usable when it fails -- the deck is local first,
## always.
func _run_sync(quiet := false) -> void:
        if _syncing:
                return
        _syncing = true
        if _screen is HomeScript:
                (_screen as HomeScript).set_syncing()
        var overlay: Control = null
        if not quiet:
                overlay = SyncOverlayScript.new()
                overlay.name = "SyncOverlay"
                add_child(overlay)
        var result: Dictionary = await _sync.sync(
                USER_DECK, overlay.report if overlay != null else Callable()
        )
        if overlay != null:
                overlay.finish(bool(result.get("ok", false)))
                await get_tree().create_timer(0.6).timeout
                overlay.queue_free()
        _syncing = false
        # Only a finished sync may move the "last synced" clock: a failed run
        # must leave the app honest about when it last heard from the repo.
        if bool(result.get("ok", false)):
                _settings.last_sync = _now()
                _settings.save()
                _answers_waiting = 0
                _sync_failed = false
        else:
                _sync_failed = true

        # Progress may have merged in from another device; read the deck back.
        var reloaded: DeckScript = DeckScript.load(USER_DECK)
        if reloaded != null:
                _deck = reloaded
                _sync = GitHubSyncScript.new(_http, _auth)

        var line := ""
        if bool(result.get("ok", false)):
                if int(result.get("pushed", 0)) + int(result.get("pulled", 0)) + int(result.get("merged", 0)) == 0:
                        line = "Everything in step — synced just now"
                else:
                        line = "Synced just now · %d sent, %d fetched, %d merged" % [
                                result.get("pushed", 0), result.get("pulled", 0), result.get("merged", 0)
                        ]
        else:
                line = "Sync could not finish — your cards are safe here. Try again."
        if _screen is HomeScript:
                _refresh_home()
        elif _screen is SettingsScreenScript:
                var screen: SettingsScreenScript = _screen
                screen.note_sync_result(line)
                # The settings screen keeps its own account of the moment; the
                # home line recomputes when the user goes back to it.


## Home is told the same five things every time it is refreshed -- from its
## first arrival, from an account changing, from a sync finishing -- so one
## hand says them, and no door into the screen can drift from another.
func _refresh_home() -> void:
        if not _screen is HomeScript:
                return
        var home: HomeScript = _screen
        home.setup(_deck, SchedulerScript.counts(_deck, _now()), _sync_line(), _sync_state())


func _sync_line() -> String:
        if not _settings.has_token():
                return "Not connected — your deck lives on this device only"
        if _syncing:
                return "Syncing…"
        var waiting := _pending_answers()
        if waiting > 0:
                return "%d %s waiting to sync" % [waiting, "answer" if waiting == 1 else "answers"]
        if _settings.last_sync > 0:
                return "Last synced %s" % _ago(_now() - _settings.last_sync)
        return "Connected — not synced yet"


## Which of the coin's states the page is in: not connected at all; agreed
## with the repo at least once; connected but never yet taken there;
## holding work the repo has not seen; or the last attempt could not
## finish.
func _sync_state() -> String:
        if not _settings.has_token():
                return "off"
        if _syncing:
                return "syncing"
        if _pending_answers() > 0:
                return "pending"
        if _sync_failed:
                return "error"
        if _settings.last_sync > 0:
                return "synced"
        return "pending"


## Answers the repo has not seen: the ones this session gave, or the ones a
## previous session left behind when its sync could not finish -- read from
## the same baseline the sync engine keeps, without touching the network.
func _pending_answers() -> int:
        if _answers_waiting > 0:
                return _answers_waiting
        return 1 if GitHubSyncScript.progress_dirty(USER_DECK) else 0


static func _ago(seconds: int) -> String:
        if seconds < 90:
                return "just now"
        if seconds < 3600:
                return "%d min ago" % (seconds / 60)
        if seconds < 86400:
                return "%dh ago" % (seconds / 3600)
        return "%dd ago" % (seconds / 86400)


## Screens change hands like pages: the outgoing one fades where it stands
## and stops taking input at once, and the incoming one arrives -- from
## below when the user is going deeper into the app, from above when they
## are coming back home. One vocabulary, every transition.
func _swap(next: Control, from_above := false) -> void:
        if _screen != null:
                var old: Control = _screen
                old.mouse_filter = Control.MOUSE_FILTER_IGNORE  # a fading screen stops taking input
                ThemeScript.vanish(old)
        _screen = next
        add_child(next)
        ThemeScript.appear(next, 0.0, -14.0 if from_above else 14.0)


# --- web updates ----------------------------------------------------------------

## The web build runs inside a page that can outlive the version it carries.
## The page's head script asks the service worker to re-check itself -- every
## fifteen minutes, and each time the tab is looked at again -- and the engine
## turns a newer waiting worker into one signal, answered on Home as a quiet
## Update offer. Taking it asks the worker to take the page over; a reload is
## the hand-turned version of the same thing, held back until the ask has had
## its chance.
func _watch_updates() -> void:
        var bridge := _bridge()
        if bridge == null:
                return
        # Arming is the ask: from here the worker reports on its own, and a
        # version already waiting outside the door is announced at once.
        bridge.call("pwa_needs_update")
        bridge.connect("pwa_update_available", _on_pwa_update_available)


func _on_pwa_update_available() -> void:
        _update_waiting = true
        if _screen is HomeScript:
                var home: HomeScript = _screen
                home.offer_update()


## The page's bridge to the engine, read at runtime rather than by name: on
## every other platform there is none, and the same line then reads as "not
## here" instead of refusing to load.
func _bridge() -> Object:
        if not OS.has_feature("web"):
                return null
        return Engine.get_singleton("JavaScriptBridge")


func _apply_update() -> void:
        var bridge := _bridge()
        if bridge == null:
                return
        bridge.call("pwa_update")
        # If the worker never answers, the page can still be turned by hand;
        # a reload re-checks the worker either way.
        get_tree().create_timer(6.0).timeout.connect(func() -> void:
                bridge.call("eval", "location.reload()")
        )


func _now() -> int:
        return int(Time.get_unix_time_from_system())
