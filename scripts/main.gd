extends Control
const SettingsScript := preload("res://scripts/data/settings.gd")
const DeckScript := preload("res://scripts/data/deck.gd")
const CardScript := preload("res://scripts/data/card.gd")
const SchedulerScript := preload("res://scripts/data/scheduler.gd")
const HttpClientScript := preload("res://scripts/net/http_client.gd")
const GitHubAuthScript := preload("res://scripts/net/github_auth.gd")
const GitHubSyncScript := preload("res://scripts/net/github_sync.gd")
const SyncOverlayScript := preload("res://scripts/ui/sync_overlay.gd")
const ConflictDialogScript := preload("res://scripts/ui/conflict_dialog.gd")
const ThemeScript := preload("res://scripts/ui/theme.gd")
const HomeScript := preload("res://scripts/ui/home.gd")
const StudyScript := preload("res://scripts/ui/study.gd")
const SettingsScreenScript := preload("res://scripts/ui/settings_screen.gd")
const BrowseScript := preload("res://scripts/ui/browse.gd")
const I18nScript := preload("res://scripts/ui/i18n.gd")
const LanguagePickerScript := preload("res://scripts/ui/language_picker.gd")
const TouchScrollScript := preload("res://scripts/ui/touch_scroll.gd")
const RtlFieldScript := preload("res://scripts/ui/rtl_field.gd")

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
var _syncing := false  # one sync at a time; a second ask waits its turn, it is never lost
var _sync_queued := false  # an ask that arrived while one ran; it goes when this one ends
var _sync_queued_quiet := true  # the queued ask's own voice -- a press of the button outranks a quiet one
var _answers_waiting := 0  # answers given since the repo last heard from this deck
var _deck_edited := false  # a card was edited in the app since the repo last heard
var _sync_failed := false  # the last sync could not finish; the deck is honest about it
var _sync_retrying := false  # a failed quiet sync is waiting to try again
var _sync_attempts := 0  # how many retries this quiet run has made
var _sync_generation := 0  # a new run cancels the retries an older one left pending
var _paste_callback: Variant = null  # the page's paste hook, kept alive for the app's whole life
var _cut_callback: Variant = null  # the page's cut hook, kept beside it
var _clip_state := ""  # what the page was last told the field in hand holds
var _menu_free := -1  # what the page was last told the mouse stands on: paper (1) or working parts (0)
var _menu_mouse := Vector2(-1.0, -1.0)  # where the mouse stood when that was last measured
var _menu_at := 0  # when, because the ground can move under a still mouse too


func _ready() -> void:
        # The engine's own tooltips arrive in the engine's own face, which
        # carries no Arabic letters: a Persian tooltip was a row of empty
        # boxes in no language at all. The window's theme dresses them in the
        # app's own hand and says nothing about anything else -- every control
        # that matters dresses itself.
        get_window().theme = ThemeScript.tooltip_theme()
        _install_deck()
        _patch_deck()
        _deliver_cards()
        _ensure_deck_audio()
        _sweep_sidecars()
        _settings = SettingsScript.load_settings()
        _deck = DeckScript.load(USER_DECK)
        if _deck == null:
                push_error("QuranTathbit: the deck could not be read from %s" % USER_DECK)
                get_tree().quit(1)
                return
        _adopt_deck_choices()
        I18nScript.set_lang(_settings.ui_lang)
        ThemeScript.set_ayah_face(_settings.ayah_font)
        # The device's own two sizes, worn before the first page is built: a
        # desk and a phone read at different distances, so these are this
        # machine's comfort and never travel with the deck. 1.0 is the size
        # the app has always been, so a reader who has never chosen sees the
        # app they had.
        ThemeScript.set_ui_scale(_settings.ui_scale)
        ThemeScript.set_font_scale(_settings.font_scale)

        _http = HttpClientScript.new()
        _http.name = "HttpClient"
        add_child(_http)
        _auth = GitHubAuthScript.new()
        _sync = GitHubSyncScript.new(_http, _auth)

        _install_paste_bridge()
        # Two quiet truths the page is told as they change, on the web alone:
        # what the field in hand holds (the words a Ctrl+C means -- the page's
        # own clipboard carries them; the engine's cannot), and whether the
        # mouse stands on the page's paper or on one of its working parts
        # (where nothing of the app lives, the browser's own menu answers a
        # right press).
        set_process(OS.has_feature("web"))
        _watch_updates()
        # The hand's own scroller, standing above every page from the first
        # one: on a phone the shelf answers a finger the way every list the
        # reader has ever scrolled does.
        var touch := TouchScrollScript.new()
        touch.name = "TouchScroll"
        add_child(touch)
        _go_home()
        # The app's very first question, over the page it asks on: which
        # tongue do its own words speak? Only a reader who has never
        # answered -- here or on any device the deck reached -- is asked.
        if _settings.ui_lang.is_empty():
                _show_language_picker()
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


## Fixes the deck itself carries, asked of every boot: each patch touches
## only a file still byte-for-byte the one this app shipped -- a card the
## reader has edited is theirs, not ours -- and each is idempotent by
## construction: once applied, the old bytes are gone and it never fires
## again. The basmala card's author once wrapped its lines in stars for the
## app's old leaning reading; the reading retired in v1.0.38, the stars
## stayed, and the leading one reads as a stray the reader asked to see
## gone. To the sync this is exactly an edit the reader made on this
## machine: it wins the merge the way every honest edit does.
const DECK_PATCHES := [
        {
                "path": "007/back.md",
                "was": "*بِسمِ اللهِ الرَّحمانِ الرَّحیمِ * الم\n\n*بنام خداوند بخشنده مهربان* الم\n\n![002001.mp3](002001.mp3)\n\n[quran.makarem.ir · 2:1](https://quran.makarem.ir/#2:1)\n",
                "now": "بِسمِ اللهِ الرَّحمانِ الرَّحیمِ * الم\n\nبنام خداوند بخشنده مهربان* الم\n\n![002001.mp3](002001.mp3)\n\n[quran.makarem.ir · 2:1](https://quran.makarem.ir/#2:1)\n",
        },
]

func _patch_deck() -> void:
        for patch in DECK_PATCHES:
                var target := USER_DECK.path_join(str(patch["path"]))
                if not FileAccess.file_exists(target):
                        continue
                if FileAccess.get_file_as_string(target) != str(patch["was"]):
                        continue
                var file := FileAccess.open(target, FileAccess.WRITE)
                if file == null:
                        push_error("QuranTathbit: cannot patch %s" % target)
                        continue
                file.store_string(str(patch["now"]))
                file.close()


func _copy_tree(from: String, to: String) -> void:
        # Godot's editor sidecars (.import, .uid) are the editor's own
        # bookkeeping, never deck content: they never ride a sync or a
        # backup zip (both refuse them by name), and the copy never plants
        # them either.
        for entry in DirAccess.get_files_at(from):
                if entry.ends_with(".import") or entry.ends_with(".uid"):
                        continue
                var source := from.path_join(entry)
                var target := to.path_join(entry)
                var data := _bundled_bytes(source)
                if data.is_empty():
                        push_error("QuranTathbit: cannot read %s" % source)
                        continue
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

## One bundled file's real bytes, read the way the place it is read from
## actually keeps it. In the editor a bundle path is a folder on disk and
## raw bytes are the truth; in an exported package an imported file -- every
## one of the deck's mp3s -- is not a file the file system can see at its
## own path at all: the package carries it as a resource under
## .godot/imported, with an .import remap beside the name the deck knows.
## Measured on the engine, not guessed: in every export,
## FileAccess.file_exists on the mp3's own path is false while
## ResourceLoader.load of the same path returns the stream carrying the
## original bytes as its data -- which is why a deck installed by the file
## system alone arrived on phones with no audio at all, every button
## honestly saying it was unavailable. The loader is therefore asked first,
## in the editor and in a package alike, and the file system answers only
## for files that were never imported: the markdown, the deck's own json.
static func _bundled_bytes(path: String) -> PackedByteArray:
        if ResourceLoader.exists(path):
                var res: Variant = load(path)
                if res is AudioStreamMP3:
                        return (res as AudioStreamMP3).data
        if FileAccess.file_exists(path):
                return FileAccess.get_file_as_bytes(path)
        return PackedByteArray()

## Every audio file the bundle carries for a card folder, by the names the
## deck itself knows. A package lists an imported audio file only as its
## .import remap (the file system cannot see the mp3 itself), so the remaps
## are the manifest; in the editor the same names stand as the files
## themselves. The translation's own name is derived the way the study page
## derives it: a verse-numbered recitation implies its Persian twin,
## NNNNNN-fa.mp3 beside NNNNNN.mp3. Together these say what the bundle could
## hand the installed deck, whatever a folder's listing happens to show.
static func _bundled_audio_names(card_dir: String) -> PackedStringArray:
        var found := {}
        for entry in DirAccess.get_files_at(card_dir):
                var name := entry
                if entry.ends_with(".import"):
                        name = entry.trim_suffix(".import")
                elif not entry.ends_with(".mp3"):
                        continue
                if not name.ends_with(".mp3"):
                        continue
                found[name] = true
        var out := PackedStringArray()
        for name in found:
                out.append(name)
                var stem := (name as String).get_basename()
                if stem.is_valid_int() and stem.length() == 6:
                        var fa := "%s-fa.%s" % [stem, (name as String).get_extension()]
                        if not found.has(fa):
                                out.append(fa)
        return out

## Whether a file on disk begins as playable audio: an ID3 tag or an MPEG
## frame sync. The deck's mp3s are the only audio it carries, and a file
## that does not begin this way will never decode, whatever its name says.
static func _plays_audio(path: String) -> bool:
        var file := FileAccess.open(path, FileAccess.READ)
        if file == null:
                return false
        var head := file.get_buffer(3)
        file.close()
        if head.size() < 3:
                return false
        if head[0] == 0x49 and head[1] == 0x44 and head[2] == 0x33:
                return true
        return head[0] == 0xFF and (head[1] & 0xE0) == 0xE0


## The deck's audio, made whole on the installed deck every boot. A file
## the deck lacks is copied in from the bundle; a file that is there but
## does not begin as audio -- a truncated download, the litter an earlier
## release could leave -- is repaired from the bundle the same way. A file
## that already plays is never touched, whatever wrote it: the user's own
## deck is the truth, and this only fills what is missing, the same law
## every joining in this app lives by. On the web the package carries no
## audio at all, so there is nothing to ensure and the recitations stream
## from the site, as they always have.
func _ensure_deck_audio() -> void:
        if OS.has_feature("web"):
                return
        var filled := 0
        var repaired := 0
        for folder in DirAccess.get_directories_at(BUNDLED_DECK):
                var into := USER_DECK.path_join(folder)
                if not DirAccess.dir_exists_absolute(into):
                        continue
                var from := BUNDLED_DECK.path_join(folder)
                for name in _bundled_audio_names(from):
                        var target := into.path_join(name)
                        var existed := FileAccess.file_exists(target)
                        if existed and _plays_audio(target):
                                continue
                        var bytes := _bundled_bytes(from.path_join(name))
                        if bytes.is_empty():
                                continue
                        var file := FileAccess.open(target, FileAccess.WRITE)
                        if file == null:
                                push_error("QuranTathbit: cannot write %s" % target)
                                continue
                        file.store_buffer(bytes)
                        file.close()
                        if existed:
                                repaired += 1
                        else:
                                filled += 1
        if filled > 0 or repaired > 0:
                print("QuranTathbit: deck audio -- %d filled, %d repaired" % [filled, repaired])

## An install made by an earlier release could still carry the editor's
## sidecars in place; sync and the zip refuse them, but the folder itself
## should not hold what the deck never asked for. One quiet walk removes
## them wherever the deck keeps them, and says nothing when there is
## nothing to do.
func _sweep_sidecars() -> void:
        if not DirAccess.dir_exists_absolute(USER_DECK):
                return
        var swept := 0
        var walk := [USER_DECK]
        while not walk.is_empty():
                var dir: String = walk.pop_back()
                for entry in DirAccess.get_files_at(dir):
                        if entry.ends_with(".import") or entry.ends_with(".uid"):
                                if DirAccess.remove_absolute(dir.path_join(entry)) == OK:
                                        swept += 1
                for sub in DirAccess.get_directories_at(dir):
                        walk.push_back(dir.path_join(sub))
        if swept > 0:
                print("QuranTathbit: swept %d editor sidecar(s) from the deck" % swept)


## New cards the package carries, joined to the installed deck the same way
## the translations were: a folder the deck lacks is copied in whole, and a
## folder the deck already has is never touched -- so an update to the app
## adds what is new without eating anything that is there, the same law
## every joining in this app lives by. The deck is read after this, so the
## day's queue offers the new cards on the same breath the deck grows. In a
## browser the package carries the deck's text but no audio, so a card
## folder there is its words -- exactly what a new card is.
func _deliver_cards() -> void:
        var delivered := 0
        for folder in DirAccess.get_directories_at(BUNDLED_DECK):
                if not folder.is_valid_int():
                        continue
                var into := USER_DECK.path_join(folder)
                if DirAccess.dir_exists_absolute(into):
                        continue
                var from := BUNDLED_DECK.path_join(folder)
                var made := DirAccess.make_dir_recursive_absolute(into)
                if made != OK:
                        push_error("QuranTathbit: cannot create %s" % into)
                        continue
                for entry in DirAccess.get_files_at(from):
                        if entry.ends_with(".import") or entry.ends_with(".uid"):
                                continue
                        var target := into.path_join(entry)
                        var data := _bundled_bytes(from.path_join(entry))
                        if data.is_empty():
                                push_error("QuranTathbit: cannot read %s" % from.path_join(entry))
                                continue
                        var file := FileAccess.open(target, FileAccess.WRITE)
                        if file == null:
                                push_error("QuranTathbit: cannot write %s" % target)
                                continue
                        file.store_buffer(data)
                        file.close()
                        delivered += 1
        if delivered > 0:
                print("QuranTathbit: delivered %d new card file(s)" % delivered)


# --- screens -------------------------------------------------------------------

## The phone's back key, arriving as a window message the engine would
## otherwise answer by leaving the app entirely (quit_on_go_back, off in
## the project settings, is what turns the leaving into this question).
## It is answered the way the keyboard's Esc is answered everywhere: by
## whatever stands over the page first, then by the page itself, and only
## from home by the app's own going.
func _notification(what: int) -> void:
        if what == NOTIFICATION_WM_GO_BACK_REQUEST:
                # The key arrives while the engine walks the window's
                # children, and a page swapped mid-walk is a child added to
                # a parent that is busy setting up children -- refused. The
                # answer is given a frame later, which no hand can tell.
                call_deferred("_handle_back")


func _handle_back() -> void:
        # Work under way is not a page: back cannot hurry a sync, and the
        # sync is resumable by design, so the key is simply kept.
        if get_node_or_null("SyncOverlay") != null:
                return
        # The app's one first question stands over the page: back puts it
        # away, the app speaks its fallback tongue, and the question asks
        # itself again the next time the app opens (until it is answered,
        # or answered in Settings).
        var asking := get_node_or_null("LanguagePicker")
        if asking != null:
                asking.queue_free()
                return
        if _screen != null and _screen.has_method("request_back") and _screen.request_back():
                return
        if _screen == null or _screen is HomeScript:
                # The way out of the app itself: from its first page, the
                # way every app on the phone leaves.
                get_tree().quit()
                return
        _go_home()


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
        home.extra_new_pressed.connect(_start_extra_new_session)
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
        _open_study(cards)


## The day's offer is spent, but the deck still holds an unseen card and the
## reader asked for it: a session of exactly one card, the same card a
## larger offer would have brought next. The session itself is the session
## any queue opens -- same wiring, same doors home -- only its queue is the
## one card the reader took.
func _start_extra_new_session() -> void:
        if _screen is StudyScript:
                return
        var card = SchedulerScript.first_fresh(_deck, _now())
        if card == null:
                return
        _open_study([card])


## One session, one wiring: whatever queue a session is opened with -- the
## day's own, or the one card taken beyond it -- its answers, defers,
## suspensions, edits and choices all ride the same doors home.
func _open_study(cards: Array) -> void:
        var study := StudyScript.new()
        study.name = "Study"
        # The recitation speaks as loudly as the last session left it: the
        # setting is set before the screen enters the tree, so its first
        # breath already carries the remembered loudness.
        study.volume = _settings.volume
        _swap(study)
        study.start(cards)
        study.answered.connect(_on_answered)
        study.deferred.connect(_on_deferred)
        study.suspended.connect(_on_suspended)
        study.edited.connect(_on_card_edited)
        study.closed.connect(_on_session_closed)
        study.volume_changed.connect(_on_volume_changed)
        study.ayah_font_chosen.connect(_on_ayah_font_chosen)


## A moved volume rule is remembered the moment the hand stops moving it, so
## the next session opens as quiet as this one ended.
func _on_volume_changed(value: float) -> void:
        _settings.volume = value
        _settings.save()


## The verses' hand, chosen where they are read: remembered here, worn by
## the theme from this breath on, stamped into the deck's own travelling
## file so every device the deck reaches reads the same hand, and carried
## to the repo the same quiet way every travelling choice is. A sync
## already running drops the ask without losing the word -- the deck's file
## already has it, and the next sync carries it.
func _on_ayah_font_chosen(key: String) -> void:
        ThemeScript.set_ayah_face(key)
        _settings.ayah_font = key
        _settings.save()
        if _deck != null:
                _deck.ayah_font = key
                _deck.ayah_font_mod = _now()
                _deck.save_progress()
        if _settings.has_token() and _settings.auto_sync:
                _run_sync(true)


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


## A card put back in the initial basket: not an answer, but progress all
## the same -- the day has claimed the card, and every device the deck
## reaches must pass over it until tomorrow returns it as new. It rides
## the same door an answer rides, so the deck says so to GitHub when the
## session closes, without the reader being asked to remember it.
func _on_deferred(card: CardScript) -> void:
        _deck.defer(card, _now())
        _deck.save_progress()
        _answers_waiting += 1


## A card taken out of the schedule for good: not an answer, but a change
## every device the deck reaches must honour -- as though the card was
## never started at all. It rides the same door an answer rides, so the
## deck says so to GitHub when the session closes, without the reader
## being asked to remember it.
func _on_suspended(card: CardScript) -> void:
        _deck.suspend(card, _now())
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
        screen.choice_push_requested.connect(_on_choice_push_requested)
        screen.account_changed.connect(_on_account_changed)
        screen.deck_imported.connect(_on_deck_imported)


## A travelling choice has settled -- the day's pace, the verses' face, the
## app's tongue -- and the repo should hear it without the user having to
## ask, under whatever screen stands: the same door every quiet sync uses.
func _on_choice_push_requested() -> void:
        if _settings.has_token() and _settings.auto_sync:
                _run_sync(true)


## A backup has been joined to the deck on disk: the deck in memory is
## behind what the folder now holds, so the folder's new word is taken
## into the deck the app already holds -- in place, the same way a finished
## sync takes it -- adopting whatever travelling choices arrived (a tongue
## the backup carried is spoken at once, and the page it landed on is said
## again in it) -- and the current deck is handed back to the page that
## asked. What arrived should reach the repo on its own too, the same
## quiet way every arrival does, so the next device to sync finds it
## already there.
func _on_deck_imported() -> void:
        _adopt_deck_from_disk()
        if _deck == null:
                return
        if not _settings.ui_lang.is_empty() and _settings.ui_lang != I18nScript.lang():
                _apply_language(_settings.ui_lang)
        else:
                ThemeScript.set_ayah_face(_settings.ayah_font)
        if _screen is SettingsScreenScript:
                (_screen as SettingsScreenScript).deck_reloaded(_deck)
        elif _screen is HomeScript:
                _refresh_home()
        if _settings.has_token() and _settings.auto_sync:
                _run_sync(true)


## The folder's own word about the deck, taken into the deck the app
## already holds: same object, current word, every card reference in
## flight (a session's queue, the library's page, home's next card)
## landing on a card that is still the deck's own. A deck that could not
## be read at all is left exactly as it stands -- the folder may be
## mid-write, and the deck in memory is the reader's safest copy.
func _adopt_deck_from_disk() -> void:
        var reloaded: DeckScript = DeckScript.load(USER_DECK)
        if reloaded == null:
                return
        if _deck == null:
                _deck = reloaded
        else:
                _deck.adopt(reloaded)
        _adopt_deck_choices()


## The deck's own word about the choices that travel with it, said once at
## every arrival: a deck that has never carried one adopts this device's
## setting as its own (the first save writes it into progress.json), and a
## deck that has one becomes the setting -- so every device the deck
## reaches paces the day, dresses the verses and speaks the chrome the
## same. The pace is an int whose silence is -1; the face and the tongue
## are strings whose silence is "" -- the same adoption, three shapes of
## the same silence.
func _adopt_deck_choices() -> void:
        if _deck == null:
                return
        if _deck.new_per_day < 0:
                _deck.new_per_day = _settings.new_per_day
                _deck.new_per_day_mod = _now()
        elif _deck.new_per_day != _settings.new_per_day:
                _settings.new_per_day = _deck.new_per_day
                _settings.save()
        if _deck.ayah_font.is_empty():
                if not _settings.ayah_font.is_empty():
                        _deck.ayah_font = _settings.ayah_font
                        _deck.ayah_font_mod = _now()
        elif _deck.ayah_font != _settings.ayah_font:
                _settings.ayah_font = _deck.ayah_font
                _settings.save()
        if _deck.ui_lang.is_empty():
                if not _settings.ui_lang.is_empty():
                        _deck.ui_lang = _settings.ui_lang
                        _deck.ui_lang_mod = _now()
        elif _deck.ui_lang != _settings.ui_lang:
                _settings.ui_lang = _deck.ui_lang
                _settings.save()


# --- the app's own tongue -------------------------------------------------------


## The app's very first question, asked over the home page: a quiet card
## naming each language in its own script, dismissed the moment it is
## answered -- and never asked again, because the answer travels with the
## deck (a new device inherits it in _adopt_deck_choices instead of being
## asked twice).
func _show_language_picker() -> void:
        if get_node_or_null("LanguagePicker") != null:
                return
        var picker := LanguagePickerScript.new()
        picker.name = "LanguagePicker"
        add_child(picker)
        picker.chosen.connect(_on_language_chosen)


func _on_language_chosen(code: String) -> void:
        var picker := get_node_or_null("LanguagePicker")
        if picker != null:
                picker.queue_free()
        _apply_language(code)


## The choice, wherever it was made: remembered on this device, spoken
## through the app at once, and stamped into the deck's own progress so
## every device the deck reaches inherits it. A home page already standing
## in the old tongue is said again in the new one, because it is the page
## the choice is most visible on.
func _apply_language(code: String) -> void:
        I18nScript.set_lang(code)
        _settings.ui_lang = code
        _settings.save()
        if _deck != null:
                _deck.ui_lang = code
                _deck.ui_lang_mod = _now()
                _deck.save_progress()
        if _screen is HomeScript:
                var old: Control = _screen
                _screen = null
                # The fading page keeps its place but gives up its name: two
                # children of one parent cannot both be called Home, and the
                # engine would quietly rename the newcomer instead.
                old.name = "HomeLeaving"
                old.mouse_filter = Control.MOUSE_FILTER_IGNORE
                ThemeScript.vanish(old)
                _go_home()


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
##
## One exchange at a time, always: two syncs racing one repo is the very
## race that loses work. But an ask that arrives while one runs is never
## dropped -- a session that closed, a choice that settled, a press of the
## button -- it waits for the running one to end and then goes itself, so
## every answer is carried without the reader having to ask twice.
func _run_sync(quiet := false) -> void:
        if _syncing:
                _sync_queued = true
                _sync_queued_quiet = _sync_queued_quiet and quiet
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
                USER_DECK,
                overlay.report if overlay != null else Callable(),
                _ask_conflict
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
        # deck's own choices alike (pace, verses' face, tongue); the folder's
        # new word is taken into the deck the app already holds, in place, so
        # the card objects a session in flight holds are still the deck's own
        # cards and an answer given mid-sync lands on a card the deck will
        # save -- never on an orphan a wholesale replacement would forget.
        _adopt_deck_from_disk()
        _sync = GitHubSyncScript.new(_http, _auth)
        # A language that arrived from another device is spoken at once, and
        # the home page under this one is said again in it; a deck that has
        # never answered keeps its own silence (the picker is asking, or
        # Settings will).
        if not _settings.ui_lang.is_empty() and _settings.ui_lang != I18nScript.lang():
                _apply_language(_settings.ui_lang)
        else:
                ThemeScript.set_ayah_face(_settings.ayah_font)

        var line := ""
        if ok:
                if int(result.get("pushed", 0)) + int(result.get("pulled", 0)) + int(result.get("merged", 0)) == 0:
                        line = I18nScript.t("Everything in step — synced just now")
                else:
                        line = I18nScript.f(
                                "Synced just now · %d sent, %d fetched, %d merged",
                                [result.get("pushed", 0), result.get("pulled", 0), result.get("merged", 0)]
                        )
        elif _sync_retrying:
                line = I18nScript.t("Connection trouble — the app will try again by itself")
        elif str(result.get("error", "")) == "conflict_declined":
                line = I18nScript.t(
                        "Some cards changed in two places — press Sync to choose which copy wins"
                )
        else:
                line = I18nScript.t("Sync could not finish — your cards are safe here. Try again.")
        if _screen is HomeScript:
                _refresh_home()
        elif _screen is SettingsScreenScript:
                var screen: SettingsScreenScript = _screen
                screen.note_sync_result(line)
                # The settings screen keeps its own account of the moment; the
                # home line recomputes when the user goes back to it.

        # The ask that waited behind this one goes now: one exchange at a
        # time, and none of them ever dropped.
        if _sync_queued:
                _sync_queued = false
                var queued_quiet := _sync_queued_quiet
                _sync_queued_quiet = true  # the next wait starts from silence, not this one's echo
                _run_sync(queued_quiet)


## A file both sides changed is the reader's to settle, never the engine's:
## the dialog stands over whatever is on the page -- the sync overlay
## included, quiet or loud alike -- names what changed, and its word hard
## forces one copy over the other. Standing down decides nothing: both
## sides keep what they have, and the next sync asks again.
func _ask_conflict(paths: Array) -> String:
        var dialog := ConflictDialogScript.new(paths)
        dialog.name = "ConflictDialog"
        add_child(dialog)
        var verdict: String = await dialog.ask()
        dialog.queue_free()
        return verdict


## Should this failure be tried again without being asked? Anything the
## network could have caused, yes; a token the repo does not accept, no --
## that will not heal on its own, and the answer is in Settings, not in a
## retry loop. A conflict the reader stood down from is not the network's
## either: they said "later", and an unprompted re-ask would be a nag.
func _sync_retryable(error: String) -> bool:
        return error != "no_token" and error != "auth_failed" and error != "conflict_declined"


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
                return I18nScript.t("Not connected — your deck lives on this device only")
        if _syncing:
                return I18nScript.t("Syncing…")
        if _sync_retrying:
                return I18nScript.t("Connection trouble — the app will try again by itself")
        var waiting := _pending_answers()
        if waiting > 0:
                if _answers_waiting > 0:
                        var template := (
                                "%d answer waiting to sync" if waiting == 1 else "%d answers waiting to sync"
                        )
                        return I18nScript.f(template, [waiting])
                # Progress moved without a session -- the deck's own choices
                # were changed here -- and the number of "answers" would be
                # a lie.
                return I18nScript.t("Changes waiting to sync")
        if _settings.last_sync > 0:
                return I18nScript.f("Last synced %s", [_ago(_now() - _settings.last_sync)])
        return I18nScript.t("Connected — not synced yet")


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
                return I18nScript.t("just now")
        if seconds < 3600:
                return I18nScript.f("%d min ago", [seconds / 60])
        if seconds < 86400:
                return I18nScript.f("%dh ago", [seconds / 3600])
        return I18nScript.f("%dd ago", [seconds / 86400])


## Screens change hands like pages: the outgoing one fades where it stands
## and stops taking input at once, and the incoming one arrives -- from
## below when the user is going deeper into the app, from above when they
## are coming back home. One vocabulary, every transition.
func _swap(next: Control, from_above := false) -> void:
        if _screen != null:
                var old: Control = _screen
                old.mouse_filter = Control.MOUSE_FILTER_IGNORE  # a fading screen stops taking input
                ThemeScript.vanish(old)
        # A page still fading under its successor keeps its place but gives
        # up its name the moment that name is asked for again: two children
        # of one parent cannot share one, and the engine would quietly
        # rename the newcomer -- @Control@44 -- leaving every hand that
        # asks for Home holding nothing. A quick there-and-back is exactly
        # when it happens.
        for sibling in get_children():
                if sibling != next and sibling.name == next.name:
                        sibling.name = String(next.name) + "Leaving"
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
        # Cut's other half rides the same install: the page takes the words
        # to the browser's own clipboard (a keydown is a gesture the browser
        # accepts), then hands the field back its empty.
        _cut_callback = bridge.call("create_callback", _on_web_cut)
        var clip: Variant = bridge.call("get_interface", "__qtClipInstall")
        if clip != null:
                clip.install(_cut_callback)


## The page handed us its paste. A settings field takes one line -- a
## multi-line clipboard pastes its first line, the way every single-line
## field everywhere treats it -- and the editor's own right-reading fields
## answer for themselves: a verse keeps the shape the clipboard carried, a
## reference takes its first line. A selection is replaced, never prepended
## to.
func _on_web_paste(args: Array) -> void:
        if args.is_empty():
                return
        var raw := str(args[0]).replace("\r\n", "\n").replace("\r", "\n")
        var focus := get_viewport().gui_get_focus_owner()
        if focus is LineEdit:
                var text := raw.split("\n")[0].strip_edges()
                if text.is_empty():
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
                return
        if focus is TextEdit:
                # The editor's field is a TextEdit under the app's own mirror
                # (rtl_field.gd); the field itself places the words, selection
                # and caret together.
                var editor := focus as TextEdit
                if not editor.editable:
                        return
                var writing := editor.get_parent() as RtlFieldScript
                if writing == null:
                        return
                var text := raw.split("\n")[0].strip_edges()
                if not writing.one_line:
                        text = raw.strip_edges()
                if text.is_empty():
                        return
                writing.paste_text(text)
                var note := ("ok:%d:%s" % [writing.get_text().length(), writing.get_text().substr(0, 8)]).uri_encode()
                var bridge := _bridge()
                if bridge != null:
                        bridge.call("eval", "document.documentElement.setAttribute('data-qt-pasted','" + note + "')")


## The page took the words to the browser's own clipboard; the field's half
## of a cut is simply letting them go. The engine's own cut cannot be asked
## for this: on the web its clipboard half is a no-op, and the words would
## leave without ever arriving anywhere.
func _on_web_cut(_args: Array) -> void:
        var focus := get_viewport().gui_get_focus_owner()
        if focus is LineEdit:
                var field := focus as LineEdit
                if not field.editable or not field.has_selection():
                        return
                var from := field.get_selection_from_column()
                var to := field.get_selection_to_column()
                field.text = field.text.substr(0, from) + field.text.substr(to)
                field.caret_column = from
                field.deselect()
                field.grab_focus()
        elif focus is TextEdit:
                var editor := focus as TextEdit
                if not editor.editable:
                        return
                var writing := editor.get_parent() as RtlFieldScript
                if writing == null:
                        if editor.has_selection():
                                editor.delete_selection()
                        return
                writing.cut_selection()


## What the field in hand holds, told to the page whenever it changes: the
## words a Ctrl+C means, and whether there is a field in hand at all. The
## page's own clipboard is the honest one on the web; this is how it knows
## what to carry.
func _publish_clipboard() -> void:
        var sel := ""
        var on := false
        var focus := get_viewport().gui_get_focus_owner()
        if focus is LineEdit:
                var field := focus as LineEdit
                on = field.editable
                if field.has_selection():
                        sel = field.get_selected_text()
        elif focus is TextEdit:
                var editor := focus as TextEdit
                on = editor.editable
                if editor.has_selection():
                        sel = editor.get_selected_text()
        var state := "%d%s" % [1 if on else 0, sel]
        if state == _clip_state:
                return
        _clip_state = state
        var bridge := _bridge()
        if bridge != null:
                bridge.call(
                        "eval",
                        "window.__qtClipSel=" + JSON.stringify(sel)
                                + ";window.__qtClipOn=" + ("true" if on else "false")
                )


# --- the browser's own menu ------------------------------------------------------------

## Whether the mouse stands on the page's paper or on one of its working
## parts, told to the page for the browser's own menu: a right press where
## nothing of the app lives is the browser's to answer. Measured when the
## mouse moves -- and every half second besides, because the ground can
## move under a still mouse: a page turned, a popover closed.
func _publish_menu() -> void:
        var mouse := get_viewport().get_mouse_position()
        var now := Time.get_ticks_msec()
        if mouse == _menu_mouse and now - _menu_at < 500:
                return
        _menu_mouse = mouse
        _menu_at = now
        var free := not _interactive_under(get_tree().root, mouse)
        var state := 1 if free else 0
        if state == _menu_free:
                return
        _menu_free = state
        var bridge := _bridge()
        if bridge != null:
                bridge.call("eval", "window.__qtNativeMenu=" + ("true" if free else "false"))


## Does one of the page's working parts stand under this point -- a button,
## a field, a slider, a shelf row? The paper behind them does not count,
## nor a verse's ink: the reader asked for the browser's menu where nothing
## of the app lives, and the app's working parts are exactly what "something
## lives here" means.
func _interactive_under(node: Node, pos: Vector2) -> bool:
        if node is Control:
                var control := node as Control
                if (
                        control.is_visible_in_tree()
                        and control.mouse_filter != Control.MOUSE_FILTER_IGNORE
                        and control.get_global_rect().has_point(pos)
                        and (
                                control is Button
                                or control is LineEdit
                                or control is TextEdit
                                or control is ItemList
                                or control is Range
                                or control is ScrollBar
                                or control is Tree
                        )
                ):
                        return true
        for child in node.get_children():
                if _interactive_under(child, pos):
                        return true
        return false


func _process(_delta: float) -> void:
        _publish_clipboard()
        _publish_menu()


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
