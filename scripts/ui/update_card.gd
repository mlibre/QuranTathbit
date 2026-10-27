class_name UpdateCard
extends PanelContainer

## The app asks its own home for a newer self, downloads it with the
## phone's own hands, and hands it to the phone's own installer.
##
## The release lives on GitHub; the card asks the releases API for the
## newest one and compares its tag against the version the app was born
## with. A newer one is downloaded by Android's own DownloadManager -- not
## by the app's HTTP machinery -- because the installer will not take a
## file out of the app's private storage: it takes a content:// URI, and
## the DownloadManager is the one piece of the phone that both fetches a
## URL and lends the result back as one. When the download stands complete,
## an ACTION_VIEW intent carries that URI (with the read grant and the
## new-task flag a context outside an activity owes) to the package
## installer, which updates the app in place -- same key, same package,
## a higher version code, so Android calls it an update, not a second app.
## All of it is spoken in pure GDScript through JavaClassWrapper and the
## built-in AndroidRuntime plugin; no Java plugin of the app's own exists.
##
## Every Android call is guarded: the wrapper, the runtime plugin and the
## download service are asked for before they are used, and any answer
## that is not the one hoped for folds the card back to the way it has
## always worked -- the release page in the browser. The card never traps
## a reader inside a broken handoff.
##
## The card stands on the phone alone (the web build updates by reloading;
## a desktop build is a QA rig), behind a test door the battery and the
## visual harness speak through. The state machine itself -- the words,
## the buttons, the progress -- is dressed by dress_state(), so the
## battery can swear to every state without a network or a phone.

const ThemeScript := preload("res://scripts/ui/theme.gd")
const I18nScript := preload("res://scripts/ui/i18n.gd")
const CopyChipScript := preload("res://scripts/ui/copy_chip.gd")
const VersionScript := preload("res://scripts/data/version.gd")
const FlavorScript := preload("res://scripts/data/flavor.gd")

const LATEST_API := "https://api.github.com/repos/mlibre/QuranTathbit/releases/latest"
const FALLBACK_PAGE := "https://github.com/mlibre/QuranTathbit/releases"
const APK_MIME := "application/vnd.android.package-archive"
const STANDARD_APK := "QuranTathbit-Android.apk"
const PERSIAN_APK := "QuranTathbit-Android-fa.apk"

enum State { IDLE, CHECKING, UP_TO_DATE, AVAILABLE, DOWNLOADING, READY, CHECK_FAILED, DOWNLOAD_FAILED }

## The battery's and the harness's door: a headless engine cannot wear the
## android export feature, so the test says the platform here instead. One
## process, no leaks.
static var test_android := false

## What a card needs survives the page being rebuilt under it (a language
## change rebuilds every card in the column) and a download that outlives
## the page it began on: the release the card offered, the DownloadManager
## id of a download in flight or finished, and the content URI the finished
## download lends the installer. Process-lifetime on purpose -- an app that
## has restarted to finish an update reads the world fresh.
static var _release := {}  # {tag, version, page, asset_name, asset_url}
static var _download_id := 0  # 0 = nothing in flight or finished
static var _apk_uri = null  # android.net.Uri once the download stands complete
static var _checked_once := false  # the quiet auto-check speaks once per run

var _state: int = State.IDLE
var _box: VBoxContainer
var _line: RichTextLabel
var _progress: ProgressBar
var _action: Button
var _side: Button
var _poll_wait := 0.0


## Does the update card belong on this build? The phone yes; the web and
## the desk no -- unless a test has said otherwise.
static func wanted_on_this_platform() -> bool:
        return test_android or OS.has_feature("android")


# ---- the pure arithmetic (the battery swears to these) -----------------------------


## "v2.0.30" -> [2, 0, 30]. A tag that is not a version reads as empty --
## an honest nothing, and nothing newer than anything.
static func tag_version(tag: String) -> Array:
        var clean := tag.strip_edges().trim_prefix("v").trim_prefix("V")
        var parts := []
        for piece in clean.split(".", false):
                if not piece.is_valid_int():
                        return []
                parts.append(int(piece))
        return parts


## -1 when a is older, 0 when they say the same word, 1 when a is newer.
## Numeric, never lexicographic: 2.0.10 is newer than 2.0.9.
static func version_compare(a: Array, b: Array) -> int:
        var depth := maxi(a.size(), b.size())
        for i in depth:
                var left: int = a[i] if i < a.size() else 0
                var right: int = b[i] if i < b.size() else 0
                if left < right:
                        return -1
                if left > right:
                        return 1
        return 0


static func is_newer(tag: String, current: String) -> bool:
        var tag_parts := tag_version(tag)
        var own_parts := tag_version(current)
        if tag_parts.is_empty() or own_parts.is_empty():
                return false
        return version_compare(tag_parts, own_parts) > 0


## The file this build updates itself with: the Persian-pinned build takes
## its own APK (the same app in its own clothes), the standard build the
## standard one.
static func apk_asset_name(persian: bool) -> String:
        return PERSIAN_APK if persian else STANDARD_APK


## The release's assets, read for the one file this build updates itself
## with: the build's own APK by exact name first, then any .apk of the
## same flavour. The other flavour's file is never offered -- a standard
## reader handed the Persian-pinned build would wake in the wrong tongue,
## and the polite cross-offer is a trap, not a kindness.
static func pick_asset(assets: Array, persian: bool) -> Dictionary:
        var want := apk_asset_name(persian)
        var fallback := {}
        for asset in assets:
                if typeof(asset) != TYPE_DICTIONARY:
                        continue
                var asset_name := str(asset.get("name", ""))
                var url := str(asset.get("browser_download_url", ""))
                if asset_name.is_empty() or url.is_empty():
                        continue
                if not asset_name.to_lower().ends_with(".apk"):
                        continue
                # "-fa" in the name is the Persian build's own mark; a name
                # without it belongs to the standard build.
                if asset_name.contains("-fa") != persian:
                        continue
                if asset_name == want:
                        return {"name": asset_name, "url": url}
                if fallback.is_empty():
                        fallback = {"name": asset_name, "url": url}
        return fallback


# ---- the card's bones ---------------------------------------------------------------


func _ready() -> void:
        name = "Updates"
        add_theme_stylebox_override("panel", ThemeScript.card_stylebox())
        var pad := MarginContainer.new()
        pad.name = "Padding"
        pad.add_theme_constant_override("margin_left", ThemeScript.PAD)
        pad.add_theme_constant_override("margin_right", ThemeScript.PAD)
        pad.add_theme_constant_override("margin_top", 18)
        pad.add_theme_constant_override("margin_bottom", 18)
        add_child(pad)
        _box = VBoxContainer.new()
        _box.name = "Box"
        _box.add_theme_constant_override("separation", 12)
        pad.add_child(_box)

        # The header every card on this page wears: a small gold word over
        # a rule, at the edge the page reads from.
        var title := Label.new()
        title.name = "CardTitle"
        title.text = I18nScript.t("Updates")
        title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
        ThemeScript.dress(title, 13, ThemeScript.GOLD_DEEP, true)
        _box.add_child(title)
        _box.add_child(ThemeScript.hairline(ThemeScript.LINE))

        _line = _page_line()
        _line.name = "Line"
        _box.add_child(_line)

        # The download's own bar: a thin green rule that fills as the phone
        # fetches, shown only while the fetch runs.
        _progress = ProgressBar.new()
        _progress.name = "Progress"
        _progress.show_percentage = false
        _progress.min_value = 0.0
        _progress.max_value = 100.0
        _progress.custom_minimum_size = Vector2(0, 8)
        _progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        _progress.visible = false
        var trough := StyleBoxFlat.new()
        trough.bg_color = ThemeScript.GREEN_SOFT
        trough.set_corner_radius_all(4)
        var fill := StyleBoxFlat.new()
        fill.bg_color = ThemeScript.GREEN
        fill.set_corner_radius_all(4)
        _progress.add_theme_stylebox_override("background", trough)
        _progress.add_theme_stylebox_override("fill", fill)
        _box.add_child(_progress)

        var row := HBoxContainer.new()
        row.name = "Buttons"
        row.add_theme_constant_override("separation", 10)
        _box.add_child(row)
        _action = ThemeScript.primary_button("", 46)
        _action.name = "Action"
        _action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        _action.pressed.connect(_on_action)
        row.add_child(_action)
        _side = ThemeScript.ghost_button("", ThemeScript.GREEN, 46)
        _side.name = "Side"
        _side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        _side.pressed.connect(_on_side)
        row.add_child(_side)

        # A download outliving the page finds its card again: the same id,
        # back under the bar, and the next poll reads wherever the fetch
        # has got to -- finished and waiting, failed, or still running.
        if _download_id > 0:
                _state = State.DOWNLOADING
        dress_state(_state)

        # The quiet check: once per run, on the first time the reader opens
        # the settings. It never wakes the card alone -- a page opened with
        # no network stays calm -- and it never fires twice in a run.
        if not _checked_once and _download_id == 0:
                _checked_once = true
                check_now(true)


## A line of explanation, dressed the way every line on the settings page
## is dressed: readable, selectable, at the page's reading edge.
func _page_line() -> RichTextLabel:
        var label := RichTextLabel.new()
        label.selection_enabled = true
        CopyChipScript.watch(label)
        label.fit_content = true
        label.scroll_active = false
        label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        label.horizontal_alignment = (
                HORIZONTAL_ALIGNMENT_RIGHT if I18nScript.is_rtl()
                else HORIZONTAL_ALIGNMENT_LEFT
        )
        label.add_theme_font_override("normal_font", ThemeScript.vazir(ThemeScript.BODY))
        label.add_theme_font_size_override("normal_font_size", ThemeScript.fs(ThemeScript.BODY))
        label.add_theme_color_override("default_color", ThemeScript.INK)
        label.add_theme_color_override("selection_color", ThemeScript.SELECT)
        return label


func _process(delta: float) -> void:
        if _state != State.DOWNLOADING or _download_id <= 0:
                return
        _poll_wait += delta
        if _poll_wait < 0.4:
                return
        _poll_wait = 0.0
        _poll_download()


# ---- the states, dressed -------------------------------------------------------------


## The one door every state walks through: what the line says, what the
## buttons say, what shows. The battery drives this directly, so a state
## can be sworn to without a network, a phone, or a download.
func dress_state(state: int, version := "", pct := -1.0) -> void:
        _state = state
        _line.visible = state != State.IDLE
        _progress.visible = state == State.DOWNLOADING
        match state:
                State.IDLE:
                        _line.text = ""
                        _dress_action(I18nScript.t("Check for updates"), true)
                        _dress_side("", false)
                State.CHECKING:
                        _line.text = I18nScript.t("Checking…")
                        _dress_action(I18nScript.t("Checking…"), false)
                        _dress_side("", false)
                State.UP_TO_DATE:
                        _line.text = I18nScript.t("You're using the latest version.")
                        _dress_action(I18nScript.t("Check for updates"), true)
                        _dress_side("", false)
                State.AVAILABLE:
                        # A version is an identifier, not a number: said the
                        # same way in every tongue, the way the About line
                        # says it -- only the fetch's percentage localises.
                        _line.text = I18nScript.t("Version %s is available.") % version
                        _dress_action(I18nScript.t("Download update"), true)
                        _dress_side(I18nScript.t("View on GitHub"), true)
                State.DOWNLOADING:
                        var shown := pct if pct >= 0.0 else 0.0
                        _progress.value = shown * 100.0
                        _line.text = I18nScript.f("Downloading… %d%%", [int(round(shown * 100.0))])
                        _dress_action("", false)
                        _action.visible = false
                        _dress_side(I18nScript.t("Discard download"), true)
                State.READY:
                        _line.text = I18nScript.t("Version %s downloaded.") % version
                        _dress_action(I18nScript.t("Install update"), true)
                        _dress_side(I18nScript.t("Discard download"), true)
                State.CHECK_FAILED:
                        _line.text = I18nScript.t("Couldn't check for updates.")
                        _dress_action(I18nScript.t("Check for updates"), true)
                        _dress_side("", false)
                State.DOWNLOAD_FAILED:
                        _line.text = I18nScript.t("The download didn't finish.")
                        _dress_action(I18nScript.t("Download update"), true)
                        _dress_side("", false)


func _dress_action(text: String, enabled: bool) -> void:
        _action.visible = true
        _action.text = text
        _action.disabled = not enabled


func _dress_side(text: String, shown: bool) -> void:
        _side.visible = shown
        _side.text = text


func _on_action() -> void:
        match _state:
                State.IDLE, State.CHECK_FAILED, State.UP_TO_DATE:
                        check_now(false)
                State.AVAILABLE, State.DOWNLOAD_FAILED:
                        begin_download()
                State.READY:
                        install()
                _:
                        pass


func _on_side() -> void:
        match _state:
                State.AVAILABLE:
                        OS.shell_open(str(_release.get("page", FALLBACK_PAGE)))
                State.DOWNLOADING, State.READY:
                        discard_download()
                _:
                        pass


# ---- the check ------------------------------------------------------------------------


## Ask the releases API for the newest release. `quiet` is the auto-check's
## manner: a failure folds back to IDLE without a word, because the reader
## never asked. A pressed button is loud -- its failure says itself.
func check_now(quiet: bool) -> void:
        if _state == State.CHECKING:
                return
        dress_state(State.CHECKING)
        var req := HTTPRequest.new()
        req.timeout = 20.0
        add_child(req)
        var headers := PackedStringArray(["Accept: application/vnd.github+json"])
        var err := req.request(LATEST_API, headers, HTTPClient.METHOD_GET)
        if err != OK:
                req.queue_free()
                _check_finished({}, quiet)
                return
        var outcome: Array = await req.request_completed
        req.queue_free()
        var data := {}
        if int(outcome[0]) == HTTPRequest.RESULT_SUCCESS and int(outcome[1]) == 200:
                var parsed: Variant = JSON.parse_string((outcome[3] as PackedByteArray).get_string_from_utf8())
                if typeof(parsed) == TYPE_DICTIONARY:
                        data = parsed
        _check_finished(data, quiet)


func _check_finished(data: Dictionary, quiet: bool) -> void:
        var tag := str(data.get("tag_name", ""))
        if tag.is_empty():
                dress_state(State.IDLE if quiet else State.CHECK_FAILED)
                return
        if not is_newer(tag, VersionScript.VERSION):
                # An older-or-equal tag retires anything the card was
                # offering: an offer must stand on the release that is
                # actually newer, never on a cached one.
                _release = {}
                dress_state(State.UP_TO_DATE)
                return
        var assets: Array = []
        if typeof(data.get("assets", null)) == TYPE_ARRAY:
                assets = data["assets"]
        var asset := pick_asset(assets, FlavorScript.persian_build())
        if asset.is_empty():
                # A release without this build's own file: no offer, and a
                # loud check says so rather than pretending all is well.
                print("UpdateCard: release %s carries no APK for this build" % tag)
                dress_state(State.IDLE if quiet else State.CHECK_FAILED)
                return
        _release = {
                "tag": tag,
                "version": tag.trim_prefix("v").trim_prefix("V"),
                "page": str(data.get("html_url", FALLBACK_PAGE)),
                "asset_name": str(asset["name"]),
                "asset_url": str(asset["url"]),
        }
        dress_state(State.AVAILABLE)


# ---- the download, by the phone's own hands --------------------------------------------


## The JNI doorway, or null wherever there is none. JavaClassWrapper is
## asked for at runtime, never by name in the script's own class space: a
## desktop or web engine has no such class, and a script that spoke the
## name bare would refuse to parse there at all -- the card must load
## everywhere, and only reach for the door on the phone.
static func _java() -> Variant:
        if OS.get_name() != "Android":
                return null
        if not Engine.has_singleton("JavaClassWrapper"):
                return null
        return Engine.get_singleton("JavaClassWrapper")


## The phone's download service, or null wherever it cannot be reached.
## Everything the handoff needs is asked for before it is used, so a
## missing piece folds the card to the browser instead of trapping it.
static func _download_manager():
        if OS.get_name() != "Android":
                return null
        if not Engine.has_singleton("AndroidRuntime"):
                return null
        var runtime = Engine.get_singleton("AndroidRuntime")
        var activity = runtime.getActivity()
        if activity == null:
                return null
        var jcw = _java()
        if jcw == null:
                return null
        var ctx_cls = jcw.wrap("android.content.Context")
        var service: String = str(ctx_cls.DOWNLOAD_SERVICE)
        var manager = activity.getSystemService(service)
        return manager


func begin_download() -> void:
        if _release.is_empty():
                return
        var manager = _download_manager()
        if manager == null:
                # No phone machinery under this card: the browser has always
                # carried this journey, and still does.
                OS.shell_open(str(_release.get("page", FALLBACK_PAGE)))
                return
        var jcw = _java()
        if jcw == null:
                # No phone machinery under this card: the browser has always
                # carried this journey, and still does.
                OS.shell_open(str(_release.get("page", FALLBACK_PAGE)))
                return
        var req_cls = jcw.wrap("android.app.DownloadManager$Request")
        var uri_cls = jcw.wrap("android.net.Uri")
        var request = req_cls.Request(uri_cls.parse(str(_release["asset_url"])))
        request.setTitle("QuranTathbit " + str(_release["version"]))
        request.setMimeType(APK_MIME)
        request.setNotificationVisibility(req_cls.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
        var id := int(manager.enqueue(request))
        if id < 0:
                dress_state(State.DOWNLOAD_FAILED)
                return
        _download_id = id
        _apk_uri = null
        dress_state(State.DOWNLOADING, str(_release["version"]), 0.0)


## Where the fetch has got to, read from the phone's own book. The card
## polls between heartbeats while it is visible; a card the reader leaves
## behind simply stops asking, and the one that opens next picks the
## thread up from wherever the download stands.
func _poll_download() -> void:
        var manager = _download_manager()
        if manager == null:
                return
        var jcw = _java()
        if jcw == null:
                return
        var dm_cls = jcw.wrap("android.app.DownloadManager")
        var query_cls = jcw.wrap("android.app.DownloadManager$Query")
        var query = query_cls.Query()
        query.setFilterById(_download_id)
        var cursor = manager.query(query)
        if cursor == null:
                return
        if cursor.moveToFirst():
                var status: int = cursor.getInt(cursor.getColumnIndex(dm_cls.COLUMN_STATUS))
                if status == dm_cls.STATUS_SUCCESSFUL:
                        _apk_uri = manager.getUriForDownloadedFile(_download_id)
                        cursor.close()
                        dress_state(State.READY, str(_release.get("version", "")))
                        return
                if status == dm_cls.STATUS_FAILED:
                        _download_id = 0
                        cursor.close()
                        dress_state(State.DOWNLOAD_FAILED)
                        return
                var total: int = cursor.getLong(cursor.getColumnIndex(dm_cls.COLUMN_TOTAL_SIZE_BYTES))
                var done: int = cursor.getLong(cursor.getColumnIndex(dm_cls.COLUMN_BYTES_DOWNLOADED_SO_FAR))
                if total > 0 and done >= 0:
                        dress_state(
                                State.DOWNLOADING,
                                str(_release.get("version", "")),
                                clampf(float(done) / float(total), 0.0, 1.0)
                        )
        cursor.close()


## Give the fetch (or the finished file) back to the phone, and stand
## where the offer stood -- or nowhere, if no release is on offer.
func discard_download() -> void:
        if _download_id > 0:
                var manager = _download_manager()
                if manager != null:
                        manager.remove(_download_id)
        _download_id = 0
        _apk_uri = null
        dress_state(State.AVAILABLE if not _release.is_empty() else State.IDLE)


# ---- the handoff ------------------------------------------------------------------------


## Hand the finished file to the phone's installer. The content URI is the
## download manager's own, and the read grant rides with the intent: the
## installer may read what the phone itself fetched. If the phone first
## wants the reader's blessing for installs from this app, the system asks
## in its own words; the card need say nothing.
func install() -> void:
        if _apk_uri == null:
                return
        var runtime = Engine.get_singleton("AndroidRuntime") if Engine.has_singleton("AndroidRuntime") else null
        if runtime == null:
                OS.shell_open(str(_release.get("page", FALLBACK_PAGE)))
                return
        var activity = runtime.getActivity()
        if activity == null:
                OS.shell_open(str(_release.get("page", FALLBACK_PAGE)))
                return
        var jcw = _java()
        if jcw == null:
                OS.shell_open(str(_release.get("page", FALLBACK_PAGE)))
                return
        var intent_cls = jcw.wrap("android.content.Intent")
        var intent = intent_cls.Intent()
        intent.setAction(intent_cls.ACTION_VIEW)
        intent.setDataAndType(_apk_uri, APK_MIME)
        intent.addFlags(intent_cls.FLAG_ACTIVITY_NEW_TASK | intent_cls.FLAG_GRANT_READ_URI_PERMISSION)
        activity.startActivity(intent)
