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
const StudyEmptyScript := preload("res://scripts/ui/study_empty.gd")
const SettingsScreenScript := preload("res://scripts/ui/settings_screen.gd")
const BrowseScript := preload("res://scripts/ui/browse.gd")
const I18nScript := preload("res://scripts/ui/i18n.gd")
const LanguagePickerScript := preload("res://scripts/ui/language_picker.gd")
const FlavorScript := preload("res://scripts/data/flavor.gd")
const TouchScrollScript := preload("res://scripts/ui/touch_scroll.gd")
const RtlFieldScript := preload("res://scripts/ui/rtl_field.gd")
const CopyChipScript := preload("res://scripts/ui/copy_chip.gd")

## QuranTathbit: one deck, kept in folders and files, studied one card at
## a time. This root owns the small amount of state the app has -- settings,
## the deck, the network clients, the session -- and moves between its four
## screens: home, the session, the library, settings. Cards are edited on
## the spot in the session and the library, through the same editor; every
## edit lands in the card's own files, and the deck's git-backed sync
## carries it to the repo from there.

const BUNDLED_DECK := "res://assets/decks/quran"
const USER_DECK := "user://decks/quran"

## How long a failed sync waits before being asked again, and how many
## times. The first ask comes at once and takes the other road -- the
## files arrive from raw.githubusercontent.com instead of the API, a
## different door to the same bytes, the way a second downloader is tried
## when the first stalls -- and the patient ladder behind it takes the
## usual road: 8 seconds, then 25, then 60. Every ask is a resume --
## whatever landed is the baseline the next attempt continues from -- so
## four of them carry an interrupted sync across most bad connections
## without a hand on the button, whatever hand started the first one.
const SYNC_RETRY_WAITS := [1.0, 8.0, 25.0, 60.0]

## How often Home looks at the deck's own clock: a learning card comes due
## ten minutes after its answer, and the page must say so while the reader
## sits on it -- not when they happen to leave and come back.
const DUE_WATCH_PERIOD := 20.0

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
var _sync_retrying := false  # a failed sync is waiting to be asked again
var _sync_attempts := 0  # how many retries this run has made
var _sync_generation := 0  # a new run cancels the retries an older one left pending
var _due_watch: Timer  # Home's own clock: a card that comes due on the open page is said by the page
var _paste_callback: Variant = null  # the page's paste hook, kept alive for the app's whole life
var _cut_callback: Variant = null  # the page's cut hook, kept beside it
var _clip_state := ""  # what the page was last told the field in hand holds
var _menu_free := -1  # what the page was last told the mouse stands on: paper (1) or working parts (0)
var _menu_mouse := Vector2(-1.0, -1.0)  # where the mouse stood when that was last measured
var _menu_at := 0  # when, because the ground can move under a still mouse too
var _copy_chip: CopyChipScript  # the floating copy pill, standing over whatever label holds a choice
var _foot: Control  # the one bar at the app's foot, raised once and carried above every swap
var _foot_active := ""  # the door that wears the gold -- moved, never rebuilt


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
        # A flavoured build is born speaking its tongue: the Persian APK's
        # question is already answered by the build itself, so the pin is
        # set before the adoption below can see anything else, and the
        # first page is laid out from the right from its first frame -- no
        # picker ever stands over it.
        if FlavorScript.persian_build() and _settings.ui_lang != "fa":
                _settings.ui_lang = "fa"
                _settings.save()
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
        # The copy pill: a hand that chooses words is offered the copy, on a
        # phone above all -- no keyboard and no system menu stands over the
        # app's own ink there, so the app carries the words itself. It lives
        # on the window, above every page and every swap of pages, and
        # shows only while a selection lives. The window is still setting
        # its children up while this page readies itself, so the pill joins
        # it a beat later -- an add the window refuses is a pill that never
        # says Copy anywhere.
        _copy_chip = CopyChipScript.new()
        _copy_chip.name = "CopyChip"
        get_window().add_child.call_deferred(_copy_chip)
        # The foot's bar: raised once here, before the first page stands,
        # and carried above every swap of pages from this breath on -- the
        # reader never watches it being built. A small clock keeps its
        # standing current, whatever raises or lowers a sheet over a page.
        _build_foot()
        resized.connect(_lay_foot)
        var foot_watch := Timer.new()
        foot_watch.name = "FootWatch"
        foot_watch.wait_time = 0.1
        foot_watch.timeout.connect(_update_foot)
        add_child(foot_watch)
        foot_watch.start()
        _go_home()
        # The app's very first question, over the page it asks on: which
        # tongue do its own words speak? Only a reader who has never
        # answered -- here or on any device the deck reached -- is asked;
        # a flavoured build pinned its tongue before the first page was
        # built, so its question is already answered and this never stands.
        if _settings.ui_lang.is_empty():
                _show_language_picker()
        # A deck that is already connected says hello on its own, quietly: a
        # sync that finds nothing to do is three small questions and a green
        # line, and the user never again opens the app to a status that
        # pretends nothing has happened since yesterday.
        if _sync_active() and _settings.auto_sync:
                get_tree().create_timer(1.2).timeout.connect(func() -> void: _run_sync(true))
        # Home's own clock, ticking under everything: a card that comes due
        # while the reader sits on the page is said by the page itself, the
        # numbers and the day's news both -- never a page that waits for a
        # hand to refresh it.
        _due_watch = Timer.new()
        _due_watch.name = "DueWatch"
        _due_watch.wait_time = DUE_WATCH_PERIOD
        _due_watch.timeout.connect(_on_due_watch)
        add_child(_due_watch)
        _due_watch.start()
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


# --- the foot -------------------------------------------------------------------

## The one bar every page stands on, raised here once and carried above
## every swap of pages: the reader never watches it being built, and a
## page change is only the gold moving to the door that names the page
## they stand on -- the same nodes, the same row, the same words. The
## doors ring the root's own doors, the same hands the pages' own buttons
## ring; the library's door, behind a chapter's page, asks the library for
## the one step only it knows. The session carries no foot -- a page
## mid-answer has no place a thumb should wander to -- and a sheet opened
## over a page (the pencil's page, the backup's) covers the reader's work,
## so the bar steps aside while it stands.
func _build_foot() -> void:
        var made := ThemeScript.foot_dock("", I18nScript.is_rtl())
        _foot = made["bar"]
        _foot.name = "Dock"
        (made["home"] as Button).pressed.connect(_go_home)
        (made["study"] as Button).pressed.connect(_start_session)
        (made["library"] as Button).pressed.connect(_on_foot_library)
        (made["settings"] as Button).pressed.connect(_on_settings_pressed)
        add_child(_foot)
        _lay_foot()


## The library's own door on the root's bar: on the library itself it is
## the page's own step -- out of a chapter onto its shelf -- and anywhere
## else it opens the library.
func _on_foot_library() -> void:
        if _screen is BrowseScript:
                (_screen as BrowseScript).foot_library_door()
                return
        _on_browse_pressed()


## The bar's own answering of the window: laid by the theme's one law,
## above whatever the display keeps for itself, doors at a thumb's measure
## on a desk and the whole hand's width on a phone.
func _lay_foot() -> void:
        if _foot != null:
                ThemeScript.lay_foot_dock(_foot, size.x)


## What the bar says of the moment, wherever it is asked from: the door
## that names the screen on top wears the gold (moved in place, the bar
## never rebuilt), and the bar itself stands down for a page mid-answer
## and for a sheet standing over the page -- the pencil's page, the
## backup's -- so it never crowds the work in hand.
func _update_foot() -> void:
        if _foot == null:
                return
        var hidden := _screen == null or _screen is StudyScript \
                or (_screen is BrowseScript and _screen.get_node_or_null("Editor") != null) \
                or (_screen is SettingsScreenScript and _screen.get_node_or_null("BackupPicker") != null)
        var active := ""
        if _screen is HomeScript:
                active = "home"
        elif _screen is BrowseScript:
                active = "library"
        elif _screen is SettingsScreenScript:
                active = "settings"
        if _foot.visible == hidden:
                _foot.visible = not hidden
        if active != _foot_active:
                _foot_active = active
                ThemeScript.focus_foot_door(_foot, active)


## The bar said again -- a new tongue, or a new measure for the words:
## raised fresh where it stood, wearing the same gold. Rare, and always
## the app's own doing (a choice made in Settings, a tongue arrived with a
## sync); never a page change.
func _rebuild_foot() -> void:
        if _foot == null:
                return
        var shown := _foot.visible
        remove_child(_foot)
        _foot.queue_free()
        _foot = null
        _foot_active = ""
        _build_foot()
        _foot.visible = shown
        _update_foot()


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
        # A question standing over the page is answered first: back puts
        # the caught-up day's question away, deciding nothing.
        var standing := get_node_or_null("EmptyStudy")
        if standing != null:
                standing.queue_free()
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
                # A queue with nothing in it is an answer, not a silence:
                # the door says so, and holds out the one thing a caught-up
                # deck can still take -- a new card of the reader's own.
                _ask_empty_study()
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


## A caught-up day, answered: the study door said so and offered a new
## card, and the reader took it. The way in is the library's -- a card
## belongs beside its kin -- with the pencil already standing on the new
## page, so the errand the message offered is the errand that begins.
func _ask_empty_study() -> void:
        if get_node_or_null("EmptyStudy") != null:
                return
        var ask := StudyEmptyScript.new()
        ask.name = "EmptyStudy"
        add_child(ask)
        ask.new_card_requested.connect(_open_new_card_in_library)


func _open_new_card_in_library() -> void:
        var ask := get_node_or_null("EmptyStudy")
        if ask != null:
                ask.queue_free()
        if _screen is BrowseScript:
                (_screen as BrowseScript).open_new_card()
                return
        _on_browse_pressed()
        if _screen is BrowseScript:
                (_screen as BrowseScript).open_new_card()


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
        if _sync_active() and _settings.auto_sync:
                _run_sync(true)


## A session's answers are the one thing this app makes that another device
## wants; when the session closes, the deck says so to GitHub on its own --
## quietly, under the page it returns to -- so "synced" is never a thing
## the user has to remember to ask for. An edit made on the spot rides the
## same closing door, even when the session answered nothing.
func _on_session_closed() -> void:
        _go_home()
        if _sync_active() and _settings.auto_sync and _pending_answers() > 0:
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
        # The page's own chrome -- a tongue re-said, a measure for the
        # words -- is heard by the bar at the foot, which says itself
        # again to match.
        screen.chrome_changed.connect(_rebuild_foot)
        # The page opens speaking the deck's standing with the repo: last
        # heard from, work waiting, or the quiet never-yet. The line lives
        # under the sync it speaks of.
        screen.say_sync_line(_sync_line())


## A travelling choice has settled -- the day's pace, the verses' face, the
## app's tongue -- and the repo should hear it without the user having to
## ask, under whatever screen stands: the same door every quiet sync uses.
func _on_choice_push_requested() -> void:
        if _sync_active() and _settings.auto_sync:
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
        if _sync_active() and _settings.auto_sync:
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
                        # A flavoured build's inherited tongue is the build's
                        # own answer, and an answer is written down when it
                        # is made: the choice travels from the very first
                        # boot, not from the first answered card.
                        if FlavorScript.persian_build():
                                _deck.save_progress()
        elif _deck.ui_lang != _settings.ui_lang:
                if FlavorScript.persian_build():
                        # A Persian build is Persian all the way through: a
                        # deck arriving from an English phone does not bring
                        # its tongue here -- the deck is answered in this
                        # one, and the answer is written down so every
                        # device the deck reaches hears what this build said.
                        _deck.ui_lang = "fa"
                        _deck.ui_lang_mod = _now()
                        _deck.save_progress()
                else:
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
        # The bar at the foot says its four words in the app's own tongue,
        # and reads from the right when the tongue does: said again here,
        # once, wherever the choice was made.
        _rebuild_foot()
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
        # The foot below is the root's own bar; its doors ring here by
        # their own wiring, and the page raises none of its own.


func _on_account_changed() -> void:
        # One settings object, held for the app's whole life: the page that
        # raised this signal wrote the very object this root holds, and
        # saved it -- re-reading the file here would fork the page's copy
        # from the root's, and a switch pressed after a quiet sync would
        # write yesterday's clock over today's. The object is the truth.
        _refresh_home()
        # Connecting is itself the request for a first sync: the user just
        # chose to keep their deck on GitHub, so carry it there without
        # making them find the button and wonder whether anything happened.
        if _sync_active() and _settings.last_sync == 0:
                await _run_sync()


func _on_sync_pressed() -> void:
        # A hand that found a sync door is taken to where the door is made:
        # without the switch turned on, or without the account behind it,
        # there is nothing to exchange yet -- Settings is where both live.
        if not _sync_active():
                _on_settings_pressed()
                return
        _run_sync()


## Sync, with its own quiet screen while it works when the hand asked for
## it, and with only the dock's turning mark when the app asked for itself:
## a phase in plain words, a bar that knows how far along it is, and the
## promise that the deck is safe on this machine whatever the network
## does. The app stays usable when it fails -- the deck is local first,
## always. A sync the network interrupts is asked again on the app's own,
## at once and by the other road, and then patiently up the ladder --
## each ask a resume, because everything that landed is already the
## baseline -- whatever hand started the first one, so an interrupted
## sync heals itself without the reader pressing twice.
##
## One exchange at a time, always: two syncs racing one repo is the very
## race that loses work. But an ask that arrives while one runs is never
## dropped -- a session that closed, a choice that settled, a press of the
## button -- it waits for the running one to end and then goes itself, so
## every answer is carried without the reader having to ask twice.
func _run_sync(quiet := false, alternate := false, fresh := true) -> void:
        # No exchange runs behind a closed door: whatever asked -- the hand,
        # a session closing, a retry the ladder still owed -- finds the
        # switch off and stands down. The deck is local first; nothing here
        # is lost, it only waits for the door to open again.
        if not _sync_active():
                return
        if _syncing:
                _sync_queued = true
                _sync_queued_quiet = _sync_queued_quiet and quiet
                return
        _syncing = true
        _sync_generation += 1
        _sync_retrying = false
        # A fresh ask -- the hand's own press, a session closing -- starts the
        # ladder over; only an ask that is itself a retry keeps its place in
        # it, so a promise that ran out is not a promise refused forever.
        if fresh:
                _sync_attempts = 0
        if _screen is SettingsScreenScript:
                (_screen as SettingsScreenScript).note_sync_result(I18nScript.t("Syncing…"))
        var overlay: Control = null
        if not quiet:
                overlay = SyncOverlayScript.new()
                overlay.name = "SyncOverlay"
                add_child(overlay)
        var result: Dictionary = await _sync.sync(
                USER_DECK,
                overlay.report if overlay != null else Callable(),
                _ask_conflict,
                alternate
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
                _maybe_schedule_sync_retry(result)

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
        if _screen is SettingsScreenScript:
                (_screen as SettingsScreenScript).say_sync_line(line)
                # The settings screen keeps its own account of the moment; the
                # page's own line is said there, under the sync it speaks of.

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


## The quiet promise kept: a network-failed sync is asked again by the app
## itself -- the first ask at once, by the other road, and then a patient
## ladder with a longer wait each time, until one lands or the waits run
## out. Whatever hand started the failed run, the asking-back is quiet:
## the page beneath is never covered twice. A newer run -- the hand's own
## press, a session closing -- cancels whatever this one left waiting,
## because that run speaks for itself.
func _maybe_schedule_sync_retry(result: Dictionary) -> bool:
        if _sync_attempts >= SYNC_RETRY_WAITS.size():
                return false
        if not _sync_retryable(str(result.get("error", ""))):
                return false
        var other_road := _sync_attempts == 0  # the first ask-back comes at once, differently
        var wait: float = SYNC_RETRY_WAITS[_sync_attempts]
        _sync_attempts += 1
        _sync_retrying = true
        var generation := _sync_generation
        get_tree().create_timer(wait).timeout.connect(func() -> void:
                if generation == _sync_generation and not _syncing:
                        _sync_retrying = false
                        _run_sync(true, other_road, false)
        )
        return true


## Home is told the same two things every time it is refreshed -- from its
## first arrival, from an account changing, from a sync finishing -- so one
## hand says them, and no door into the screen can drift from another. Sync
## says nothing here: its whole story lives in Settings.
func _refresh_home() -> void:
        if not _screen is HomeScript:
                return
        var home: HomeScript = _screen
        home.setup(
                _deck,
                SchedulerScript.counts(_deck, _now(), _settings.new_per_day)
        )


## The page's own tick: every little while the deck's numbers are read
## again, and when they have moved -- a learning card's ten minutes
## elapsed, the day's offer reset at rollover, another device's study
## merged in -- the page is said again with the new numbers and the new
## next card, never left telling the morning's story to the afternoon.
## Only a true move earns the re-saying: a page that re-counts its pills
## on every tick is a page that flickers.
func _on_due_watch() -> void:
        if not _screen is HomeScript:
                return
        var home: HomeScript = _screen
        var counts := SchedulerScript.counts(_deck, _now(), _settings.new_per_day)
        var said := home.current_counts()
        if int(counts["due"]) == int(said.get("due", -1)) \
                        and int(counts["new"]) == int(said.get("new", -1)) \
                        and int(counts["learned"]) == int(said.get("learned", -1)):
                return
        _refresh_home()


func _sync_line() -> String:
        if not _settings.sync_enabled:
                return I18nScript.t("Sync is off — your deck lives on this device only")
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


## Whether the deck's GitHub life is on at all: the door in Settings is
## switched on and a token is in hand. Every ask reads this first -- the
## quiet ones, the hand's own press, the ladder's retries -- so a sync can
## never run behind a closed door, whatever hand knocked.
func _sync_active() -> bool:
        return _settings.sync_enabled and _settings.has_token()


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
        # The bar is the one thing that does not arrive and does not
        # leave: it rides above the page that just landed, where it rode
        # above the one before it, and only its gold moves.
        if _foot != null:
                move_child(_foot, get_child_count() - 1)
        ThemeScript.appear(next, 0.0, -14.0 if from_above else 14.0)
        _update_foot()


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
