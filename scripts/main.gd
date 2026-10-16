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
const BrowseScript := preload("res://scripts/ui/browse.gd")

## QuranTathbit: one deck, kept in folders and files, studied one card at
## a time. This root owns the small amount of state the app has -- settings,
## the deck, the network clients, the session -- and moves between its four
## screens: home, the session, the library, settings. Cards are edited on
## the spot in the session and the library, through the same editor; every
## edit lands in the card's own files, and the deck's git-backed sync
## carries it to the repo from there.

const BUNDLED_DECK := "res://assets/decks/quran"
const USER_DECK := "user://decks/quran"

## How long a quiet sync waits before trying again after a network
## failure, and how many times. The sync is resumable by design -- whatever
## landed is the baseline the next attempt continues from -- so a retry is
## a resume, and three of them carry an interrupted opening across most
## bad connections without a hand on the button.
const SYNC_RETRY_WAITS := [8.0, 25.0, 60.0]

var _settings: SettingsScript
var _deck: DeckScript
var _http: HttpClientScript
var _auth: GitHubAuthScript
var _sync: GitHubSyncScript
var _screen: Control
var _update_waiting := false  # a newer web version was announced; Home owes the user the offer
var _syncing := false  # one sync at a time; a second press is a question, not a demand
var _answers_waiting := 0  # answers given since the repo last heard from this deck
var _deck_edited := false  # a card was edited in the app since the repo last heard
var _sync_failed := false  # the last sync could not finish; the deck is honest about it
var _sync_retrying := false  # a failed quiet sync is waiting to try again
var _sync_attempts := 0  # how many retries this quiet run has made
var _sync_generation := 0  # a new run cancels the retries an older one left pending
var _paste_callback: Variant = null  # the page's paste hook, kept alive for the app's whole life


func _ready() -> void:
        _install_deck()
        _deliver_translations()
        _settings = SettingsScript.load_settings()
        _deck = DeckScript.load(USER_DECK)
        if _deck == null:
                push_error("QuranTathbit: the deck could not be read from %s" % USER_DECK)
                get_tree().quit(1)
                return
        _adopt_deck_pace()

        _http = HttpClientScript.new()
        _http.name = "HttpClient"
        add_child(_http)
        _auth = GitHubAuthScript.new()
        _sync = GitHubSyncScript.new(_http, _auth)

        _install_paste_bridge()
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


## The deck the package first installed did not carry the Persian
## translations; an updated app does. They are delivered the way the deck
## itself was installed -- copied from the package into the user's deck,
## additively and quietly: a file that is already there is never touched,
## so nothing a user or a sync did here is undone. The files ride the
## deck's own sync afterwards, like any other card media. On the web the
## package carries no audio at all, so there is nothing to deliver and the
## recitations stream from the site, as they always have.
func _deliver_translations() -> void:
        if OS.has_feature("web"):
                return
        var delivered := 0
        for folder in DirAccess.get_directories_at(BUNDLED_DECK):
                var from := BUNDLED_DECK.path_join(folder)
                var into := USER_DECK.path_join(folder)
                for entry in DirAccess.get_files_at(from):
                        if not entry.ends_with("-fa.mp3"):
                                continue
                        var target := into.path_join(entry)
                        if FileAccess.file_exists(target):
                                continue
                        if not DirAccess.dir_exists_absolute(into):
                                DirAccess.make_dir_recursive_absolute(into)
                        var data := FileAccess.get_file_as_bytes(from.path_join(entry))
                        var file := FileAccess.open(target, FileAccess.WRITE)
                        if file == null:
                                push_error("QuranTathbit: cannot deliver %s" % target)
                                continue
                        file.store_buffer(data)
                        file.close()
                        delivered += 1
        if delivered > 0:
                print("QuranTathbit: delivered %d Persian translation(s)" % delivered)


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
        home.browse_pressed.connect(_on_browse_pressed)
        if _update_waiting:
                home.offer_update()


func _start_session() -> void:
        if _screen is StudyScript:
                return
        # The day's queue answers the reader's own offer of new cards, not
        # only the algorithm's default.
        var cards := SchedulerScript.queue(_deck, _now(), _settings.new_per_day)
        if cards.is_empty():
                return
        var study := StudyScript.new()
        study.name = "Study"
        # The recitation speaks as loudly as the last session left it: the
        # setting is set before the screen enters the tree, so its first
        # breath already carries the remembered loudness.
        study.volume = _settings.volume
        _swap(study)
        study.start(cards)
        study.answered.connect(_on_answered)
        study.edited.connect(_on_card_edited)
        study.closed.connect(_on_session_closed)
        study.volume_changed.connect(_on_volume_changed)


## A moved volume rule is remembered the moment the hand stops moving it, so
## the next session opens as quiet as this one ended.
func _on_volume_changed(value: float) -> void:
        _settings.volume = value
        _settings.save()


## A session's answers are the one thing this app makes that another device
## wants; when the session closes, the deck says so to GitHub on its own --
## quietly, under the page it returns to -- so "synced" is never a thing
## the user has to remember to ask for. An edit made on the spot rides the
## same closing door, even when the session answered nothing.
func _on_session_closed() -> void:
        _go_home()
        if _settings.has_token() and _settings.auto_sync and _pending_answers() > 0:
                _run_sync(true)


func _on_answered(card: CardScript, button: String) -> void:
        _deck.answer(card, button, _now())
        _deck.save_progress()
        _answers_waiting += 1


## A card edited on the spot: the files are written, the deck in memory is
## current, and the next sync -- asked for or automatic -- carries the edit
## to the repo as part of its one commit, exactly as a hand-edited file
## would have been.
func _on_card_edited(_card: CardScript) -> void:
        _deck_edited = true
        if _screen is HomeScript:
                _refresh_home()


func _on_settings_pressed() -> void:
        if _screen is SettingsScreenScript:
                return
        var screen := SettingsScreenScript.new()
        screen.name = "Settings"
        _swap(screen)
        screen.setup(_http, _auth, _settings, _deck)
        screen.closed.connect(_go_home)
        screen.sync_requested.connect(_on_sync_pressed)
        screen.pace_push_requested.connect(_on_pace_push_requested)
        screen.account_changed.connect(_on_account_changed)


## The reader's own pace travels with the deck, so a choice made on another
## device arrives with the deck's own sync: the number this device wakes with
## is the number the deck last heard. It is asked for quietly, under whatever
## screen stands -- the same door every quiet sync uses.
func _on_pace_push_requested() -> void:
        if _settings.has_token() and _settings.auto_sync:
                _run_sync(true)


## The deck's own word about the day's pace, said once at every arrival: a
## deck that has never carried one adopts this device's setting as its own
## (the first save writes it into progress.json), and a deck that has one
## becomes the setting -- so every device the deck reaches paces the day the
## same, and "New cards each day" in Settings is the deck's number, not the
## phone's.
func _adopt_deck_pace() -> void:
        if _deck == null:
                return
        if _deck.new_per_day < 0:
                _deck.new_per_day = _settings.new_per_day
                _deck.new_per_day_mod = _now()
                return
        if _deck.new_per_day != _settings.new_per_day:
                _settings.new_per_day = _deck.new_per_day
                _settings.save()


## The library: the whole deck, read and listened to, nothing scheduled.
## It opens with the loudness the last session chose, and if the hand
## changes it here, that choice is kept the same way.
func _on_browse_pressed() -> void:
        if _screen is BrowseScript:
                return
        var browse := BrowseScript.new()
        browse.name = "Browse"
        _swap(browse)
        browse.setup(_deck, _settings.volume)
        browse.closed.connect(_go_home)
        browse.edited.connect(_on_card_edited)
        browse.volume_changed.connect(_on_volume_changed)


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
## always. A quiet sync that the network interrupts is retried on the
## app's own -- each retry a resume, because everything that landed is
## already the baseline -- so an interrupted opening heals itself without
## a hand on the button.
func _run_sync(quiet := false) -> void:
        if _syncing:
                return
        _syncing = true
        _sync_generation += 1
        _sync_retrying = false
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
        var ok := bool(result.get("ok", false))
        if ok:
                _sync_attempts = 0
                _settings.last_sync = _now()
                _settings.save()
                _answers_waiting = 0
                _deck_edited = false
                _sync_failed = false
        else:
                _sync_failed = true
                _maybe_schedule_sync_retry(quiet, result)

        # Progress may have merged in from another device -- the cards and the
        # day's own pace alike; read the deck back.
        var reloaded: DeckScript = DeckScript.load(USER_DECK)
        if reloaded != null:
                _deck = reloaded
                _adopt_deck_pace()
                _sync = GitHubSyncScript.new(_http, _auth)

        var line := ""
        if ok:
                if int(result.get("pushed", 0)) + int(result.get("pulled", 0)) + int(result.get("merged", 0)) == 0:
                        line = "Everything in step — synced just now"
                else:
                        line = "Synced just now · %d sent, %d fetched, %d merged" % [
                                result.get("pushed", 0), result.get("pulled", 0), result.get("merged", 0)
                        ]
        elif _sync_retrying:
                line = "Connection trouble — the app will try again by itself"
        else:
                line = "Sync could not finish — your cards are safe here. Try again."
        if _screen is HomeScript:
                _refresh_home()
        elif _screen is SettingsScreenScript:
                var screen: SettingsScreenScript = _screen
                screen.note_sync_result(line)
                # The settings screen keeps its own account of the moment; the
                # home line recomputes when the user goes back to it.


## Should this failure be tried again without being asked? Anything the
## network could have caused, yes; a token the repo does not accept, no --
## that will not heal on its own, and the answer is in Settings, not in a
## retry loop.
func _sync_retryable(error: String) -> bool:
        return error != "no_token" and error != "auth_failed"


## The quiet promise kept: a network-failed sync schedules its own next
## attempt, with a longer wait each time, until one lands or the waits run
## out. A newer run -- the hand's own press, a session closing -- cancels
## whatever this one left waiting, because that run speaks for itself.
func _maybe_schedule_sync_retry(quiet: bool, result: Dictionary) -> bool:
        if not quiet:
                return false
        if _sync_attempts >= SYNC_RETRY_WAITS.size():
                return false
        if not _sync_retryable(str(result.get("error", ""))):
                return false
        var wait: float = SYNC_RETRY_WAITS[_sync_attempts]
        _sync_attempts += 1
        _sync_retrying = true
        var generation := _sync_generation
        get_tree().create_timer(wait).timeout.connect(func() -> void:
                if generation == _sync_generation and not _syncing:
                        _sync_retrying = false
                        _run_sync(true)
        )
        return true


## Home is told the same five things every time it is refreshed -- from its
## first arrival, from an account changing, from a sync finishing -- so one
## hand says them, and no door into the screen can drift from another.
func _refresh_home() -> void:
        if not _screen is HomeScript:
                return
        var home: HomeScript = _screen
        home.setup(
                _deck,
                SchedulerScript.counts(_deck, _now(), _settings.new_per_day),
                _sync_line(),
                _sync_state()
        )


func _sync_line() -> String:
        if not _settings.has_token():
                return "Not connected — your deck lives on this device only"
        if _syncing:
                return "Syncing…"
        if _sync_retrying:
                return "Connection trouble — the app will try again by itself"
        var waiting := _pending_answers()
        if waiting > 0:
                if _answers_waiting > 0:
                        return "%d %s waiting to sync" % [waiting, "answer" if waiting == 1 else "answers"]
                # Progress moved without a session -- the day's own pace was
                # chosen here -- and the number of "answers" would be a lie.
                return "Changes waiting to sync"
        if _settings.last_sync > 0:
                return "Last synced %s" % _ago(_now() - _settings.last_sync)
        return "Connected — not synced yet"


## Which of the coin's states the page is in: not connected at all; agreed
## with the repo at least once; connected but never yet taken there;
## holding work the repo has not seen; waiting to try a failed sync again;
## or the last attempt could not finish.
func _sync_state() -> String:
        if not _settings.has_token():
                return "off"
        if _syncing:
                return "syncing"
        if _sync_retrying:
                return "pending"
        if _pending_answers() > 0:
                return "pending"
        if _sync_failed:
                return "error"
        if _settings.last_sync > 0:
                return "synced"
        return "pending"


## Answers the repo has not seen: the ones this session gave, a card the
## pencil touched, or the ones a previous session left behind when its sync
## could not finish -- read from the same baseline the sync engine keeps,
## without touching the network.
func _pending_answers() -> int:
        if _answers_waiting > 0:
                return _answers_waiting
        if _deck_edited:
                return 1
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


# --- the web's clipboard ------------------------------------------------------------

## In a browser the engine's own paste is a keystroke behind: its Ctrl+V
## reads a clipboard cache that only the PREVIOUS paste filled, so the first
## press pastes nothing and the second pastes what may since have been
## replaced -- and reading the clipboard directly (the engine's fallback)
## is a permission sheet, a whole conversation for a paste. The page's own
## paste event carries the text itself, no prompt, so the head script hides
## Ctrl+V from the engine and forwards the event here instead. What arrives
## lands in whichever field the user is typing in, the way paste has always
## worked everywhere else.
func _install_paste_bridge() -> void:
        var bridge := _bridge()
        if bridge == null:
                return
        # The callback object is reference-counted: a local would die with
        # the function, and the page would be left calling a hook nobody
        # answers. It is held for the app's whole life instead.
        _paste_callback = bridge.call("create_callback", _on_web_paste)
        var installer: Variant = bridge.call("get_interface", "__qtPasteInstall")
        if installer == null:
                return
        installer.install(_paste_callback)


## The page handed us its paste. One line is all a field takes; a
## multi-line clipboard pastes its first line, the way every single-line
## field everywhere treats it. A selection is replaced, not prepended to.
func _on_web_paste(args: Array) -> void:
        if args.is_empty():
                return
        var raw := str(args[0]).replace("\r\n", "\n").replace("\r", "\n")
        var text := raw.split("\n")[0].strip_edges()
        if text.is_empty():
                return
        var focus := get_viewport().gui_get_focus_owner()
        if not focus is LineEdit:
                return
        var field := focus as LineEdit
        if not field.editable:
                return
        if field.has_selection():
                var from := field.get_selection_from_column()
                var to := field.get_selection_to_column()
                field.text = field.text.substr(0, from) + text + field.text.substr(to)
                field.caret_column = from + text.length()
                field.deselect()
        else:
                field.insert_text_at_caret(text)
        field.grab_focus()
        # The page is told what its paste became -- length and a first look,
        # never the whole secret -- so the live web test can prove the hand
        # arrived, the same corner-of-the-document pattern as always.
        var note := ("ok:%d:%s" % [field.text.length(), field.text.substr(0, 8)]).uri_encode()
        var bridge := _bridge()
        if bridge != null:
                bridge.call("eval", "document.documentElement.setAttribute('data-qt-pasted','" + note + "')")


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
