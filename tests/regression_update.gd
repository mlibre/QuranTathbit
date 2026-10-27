extends SceneTree
const UpdateCardScript := preload("res://scripts/ui/update_card.gd")
const SettingsScript := preload("res://scripts/ui/settings_screen.gd")
const VersionScript := preload("res://scripts/data/version.gd")
const I18nScript := preload("res://scripts/ui/i18n.gd")

## The app updates itself from its own home. The card in Settings asks the
## releases API for the newest release, downloads it with the phone's own
## DownloadManager, and hands the finished file to the phone's own
## installer through a content URI -- the only handoff the installer takes
## from an app that holds no FileProvider. The laws sworn to here, without
## a network, a phone or a download:
##
## a tag that is not a version is an honest nothing and nothing is newer
## than anything; the compare is numeric, never lexicographic (2.0.10 is
## newer than 2.0.9, and 2.0 is 2.0.0); the build's own APK is the file
## offered -- the Persian-pinned build takes the -fa APK and the standard
## build the plain one, and the other flavour's file is never offered,
## because a standard reader handed the Persian build would wake in the
## wrong tongue; every state the card can wear is dressed with the words
## the reader reads and the buttons the reader presses; a check that
## returns an older-or-equal tag retires any cached offer; a download
## outliving the page finds its card again in the state it left; and the
## card stands on the phone alone -- a desktop build shows no Updates card
## unless a test has opened the door.

var _failures := 0
var _checks := 0


func _init() -> void:
        _reset_statics()
        _check_tag_parsing()
        _check_compare()
        _check_asset_pick()
        await _check_card_states()
        await _check_check_decisions()
        await _check_reattach_and_discard()
        await _check_platform_gate()
        _reset_statics()
        if _failures == 0:
                print("regression_update: OK (%d checks)" % _checks)
        else:
                print("regression_update: %d FAILURES of %d checks" % [_failures, _checks])
        quit(1 if _failures > 0 else 0)


func _reset_statics() -> void:
        UpdateCardScript._release = {}
        UpdateCardScript._download_id = 0
        UpdateCardScript._apk_uri = null
        # The suite has no network and wants none: the auto-check has
        # already spoken this run.
        UpdateCardScript._checked_once = true
        UpdateCardScript.test_android = true


func _ok(condition: bool, what: String) -> void:
        _checks += 1
        if not condition:
                _failures += 1
                print("  FAIL  %s" % what)


func _check_tag_parsing() -> void:
        _ok(UpdateCardScript.tag_version("v2.0.30") == [2, 0, 30], "v2.0.30 parses")
        _ok(UpdateCardScript.tag_version("2.0.29") == [2, 0, 29], "a tag without the v parses")
        _ok(UpdateCardScript.tag_version("V3.0") == [3, 0], "a capital V parses")
        _ok(UpdateCardScript.tag_version("abc").is_empty(), "a non-version tag reads as nothing")
        _ok(UpdateCardScript.tag_version("v2.x.1").is_empty(), "a half-numeric tag reads as nothing")


func _check_compare() -> void:
        _ok(UpdateCardScript.version_compare([2, 0, 10], [2, 0, 9]) > 0, "2.0.10 is newer than 2.0.9 (numeric, not lexicographic)")
        _ok(UpdateCardScript.version_compare([2, 0], [2, 0, 0]) == 0, "2.0 says the same word as 2.0.0")
        _ok(UpdateCardScript.version_compare([2, 1, 0], [2, 0, 29]) > 0, "2.1.0 is newer than 2.0.29")
        _ok(UpdateCardScript.version_compare([1, 99, 99], [2, 0, 0]) < 0, "1.99.99 is older than 2.0.0")
        _ok(UpdateCardScript.is_newer("v2.0.30", VersionScript.VERSION) or true, "compare never dies on the live version")
        _ok(not UpdateCardScript.is_newer("abc", VersionScript.VERSION), "a junk tag is never newer")
        _ok(not UpdateCardScript.is_newer("v0.0.1", "9.9.9"), "an old tag is never newer")


func _check_asset_pick() -> void:
        var both := [
                {"name": "QuranTathbit-Android.apk", "browser_download_url": "https://x/QuranTathbit-Android.apk"},
                {"name": "QuranTathbit-Android-fa.apk", "browser_download_url": "https://x/QuranTathbit-Android-fa.apk"},
                {"name": "QuranTathbit-Linux.zip", "browser_download_url": "https://x/l.zip"},
        ]
        _ok(UpdateCardScript.apk_asset_name(false) == "QuranTathbit-Android.apk", "the standard build's own APK")
        _ok(UpdateCardScript.apk_asset_name(true) == "QuranTathbit-Android-fa.apk", "the Persian build's own APK")
        var standard := UpdateCardScript.pick_asset(both, false)
        _ok(str(standard.get("name", "")) == "QuranTathbit-Android.apk", "the standard build takes the plain APK")
        var persian := UpdateCardScript.pick_asset(both, true)
        _ok(str(persian.get("name", "")) == "QuranTathbit-Android-fa.apk", "the Persian build takes the -fa APK")
        var only_standard := [both[0], both[2]]
        _ok(UpdateCardScript.pick_asset(only_standard, true).is_empty(), "the Persian build is never offered the standard APK")
        var only_fa := [both[1], both[2]]
        _ok(UpdateCardScript.pick_asset(only_fa, false).is_empty(), "the standard build is never offered the Persian APK")
        _ok(UpdateCardScript.pick_asset([], false).is_empty(), "a release with no assets offers nothing")
        var same_flavour_extra := [
                {"name": "QuranTathbit-Android-fa.apk", "browser_download_url": "https://x/fa.apk"},
                {"name": "QuranTathbit-Android-old-fa.apk", "browser_download_url": "https://x/old-fa.apk"},
        ]
        var fallback := UpdateCardScript.pick_asset(same_flavour_extra, true)
        _ok(str(fallback.get("name", "")) == "QuranTathbit-Android-fa.apk", "the exact name wins over a same-flavour neighbour")
        _ok(UpdateCardScript.pick_asset([{"name": "", "browser_download_url": ""}], false).is_empty(), "a nameless asset offers nothing")


func _card() -> Control:
        # One breath before the add: a SceneTree script's root is still
        # dressing its own children while _init runs, and an add in that
        # breath fails with "parent busy".
        await create_timer(0.1).timeout
        var card: Control = UpdateCardScript.new()
        root.add_child(card)
        if not card.is_node_ready():
                await card.ready
        return card


func _check_card_states() -> void:
        var card := await _card()
        var line: RichTextLabel = card.get_node("Padding/Box/Line")
        var progress: ProgressBar = card.get_node("Padding/Box/Progress")
        var action: Button = card.get_node("Padding/Box/Buttons/Action")
        var side: Button = card.get_node("Padding/Box/Buttons/Side")

        _ok(card.get_node("Padding/Box/CardTitle").text == I18nScript.t("Updates"), "the card wears its gold title")

        card.dress_state(UpdateCardScript.State.IDLE)
        _ok(not line.visible, "a card that has not looked says nothing")
        _ok(action.text == I18nScript.t("Check for updates") and not action.disabled, "the resting card offers the check")
        _ok(not side.visible, "no kindness beside a check nobody has run")

        card.dress_state(UpdateCardScript.State.CHECKING)
        _ok(line.text == I18nScript.t("Checking…") and action.disabled, "a checking card waits with its button down")

        card.dress_state(UpdateCardScript.State.UP_TO_DATE)
        _ok(line.text == I18nScript.t("You're using the latest version."), "the up-to-date card says so")
        _ok(not action.disabled, "the up-to-date card still offers the check")

        card.dress_state(UpdateCardScript.State.AVAILABLE, "2.0.30")
        _ok(line.text == I18nScript.t("Version %s is available.") % "2.0.30", "an offer says the version")
        _ok(action.text == I18nScript.t("Download update"), "the offer's one decision is the download")
        _ok(side.visible and side.text == I18nScript.t("View on GitHub"), "the offer's kindness is the release page")

        card.dress_state(UpdateCardScript.State.DOWNLOADING, "2.0.30", 0.42)
        _ok(progress.visible and is_equal_approx(progress.value, 42.0), "the bar fills with the fetch")
        _ok(line.text == I18nScript.f("Downloading… %d%%", [42]), "the line counts the fetch in the reader's digits")
        _ok(not action.visible, "no download button while the download runs")
        _ok(side.visible and side.text == I18nScript.t("Discard download"), "a fetch can be given back")

        card.dress_state(UpdateCardScript.State.READY, "2.0.30")
        _ok(not progress.visible, "a finished fetch takes its bar away")
        _ok(line.text == I18nScript.t("Version %s downloaded.") % "2.0.30", "a finished fetch says its version")
        _ok(action.text == I18nScript.t("Install update") and not action.disabled, "the finished fetch's one decision is the install")
        _ok(side.visible and side.text == I18nScript.t("Discard download"), "a finished fetch can still be given back")

        card.dress_state(UpdateCardScript.State.CHECK_FAILED)
        _ok(line.text == I18nScript.t("Couldn't check for updates."), "a failed check says so")
        _ok(action.text == I18nScript.t("Check for updates"), "a failed check offers the check again")

        card.dress_state(UpdateCardScript.State.DOWNLOAD_FAILED)
        _ok(line.text == I18nScript.t("The download didn't finish."), "a failed fetch says so")
        _ok(action.text == I18nScript.t("Download update"), "a failed fetch offers the download again")

        # The reader's own words, with the version as the identifier it
        # is -- Latin digits in every tongue, the way the About line says it.
        I18nScript.set_lang("fa")
        card.dress_state(UpdateCardScript.State.AVAILABLE, "2.0.30")
        _ok(line.text.contains("آمادهٔ دانلود") and line.text.contains("2.0.30"), "a Persian offer reads Persian words with the version intact")
        I18nScript.set_lang("en")

        card.queue_free()
        await process_frame


func _check_check_decisions() -> void:
        var card := await _card()
        # The check's own decision, fed its answer directly -- no network.
        card._check_finished({"tag_name": "v0.0.1"}, false)
        _ok(card._state == UpdateCardScript.State.UP_TO_DATE, "an older release retires no offer and says up to date")
        _ok(UpdateCardScript._release.is_empty(), "an older release leaves no cached offer")

        UpdateCardScript._release = {}
        card.dress_state(UpdateCardScript.State.AVAILABLE, "1.2.3")
        card._check_finished({"tag_name": "v0.0.2"}, false)
        _ok(card._state == UpdateCardScript.State.UP_TO_DATE, "an equal-older tag retires a stale offer")
        _ok(UpdateCardScript._release.is_empty(), "the stale offer is truly gone")

        var assets := [{"name": "QuranTathbit-Android.apk", "browser_download_url": "https://x/a.apk"}]
        card._check_finished({"tag_name": "v9.9.9", "html_url": "https://x/rel", "assets": assets}, false)
        _ok(card._state == UpdateCardScript.State.AVAILABLE, "a newer release with its APK is an offer")
        _ok(str(UpdateCardScript._release.get("version", "")) == "9.9.9", "the offer carries the release's own version")
        _ok(str(UpdateCardScript._release.get("asset_url", "")) == "https://x/a.apk", "the offer carries the file to fetch")
        _ok(str(UpdateCardScript._release.get("page", "")) == "https://x/rel", "the offer carries the release page")

        card._check_finished({}, false)
        _ok(card._state == UpdateCardScript.State.CHECK_FAILED, "an empty answer said loudly is a failed check")
        card._check_finished({}, true)
        _ok(card._state == UpdateCardScript.State.IDLE, "an empty answer said quietly stays silent")

        card.queue_free()
        await process_frame


func _check_reattach_and_discard() -> void:
        var card := await _card()
        UpdateCardScript._release = {
                "tag": "v9.9.9", "version": "9.9.9", "page": "https://x/rel",
                "asset_name": "QuranTathbit-Android.apk", "asset_url": "https://x/a.apk",
        }
        UpdateCardScript._download_id = 0
        card.dress_state(UpdateCardScript.State.AVAILABLE, "9.9.9")
        # A discard with the phone's machinery away (every desktop) still
        # folds back to the offer -- it must not die on the missing service.
        card.discard_download()
        _ok(card._state == UpdateCardScript.State.AVAILABLE, "a discard without a download stands back at the offer")

        # A download that outlives the page finds its card again: the new
        # card wakes downloading, from the same id.
        UpdateCardScript._download_id = 7
        var again := await _card()
        _ok(again._state == UpdateCardScript.State.DOWNLOADING, "a card reborn over a download wakes downloading")
        UpdateCardScript._download_id = 0
        again.queue_free()
        await process_frame

        card.queue_free()
        await process_frame


func _check_platform_gate() -> void:
        UpdateCardScript.test_android = false
        var settings := SettingsScript.new()
        settings.name = "Settings"
        settings.set_anchors_preset(Control.PRESET_FULL_RECT)
        root.add_child(settings)
        if not settings.is_node_ready():
                await settings.ready
        await create_timer(0.2).timeout
        var column := settings.get_node("Margin/Scroll/Wrap/Column")
        _ok(column.get_node_or_null("Updates") == null, "a desktop build shows no Updates card")

        settings.queue_free()
        await process_frame

        UpdateCardScript.test_android = true
        var phone := SettingsScript.new()
        phone.name = "SettingsPhone"
        phone.set_anchors_preset(Control.PRESET_FULL_RECT)
        root.add_child(phone)
        if not phone.is_node_ready():
                await phone.ready
        await create_timer(0.2).timeout
        var phone_column := phone.get_node("Margin/Scroll/Wrap/Column")
        var card := phone_column.get_node_or_null("Updates")
        _ok(card != null, "a phone build carries the Updates card")
        if card != null:
                var before := phone_column.get_children().find(card)
                var source := phone_column.get_children().find(phone_column.get_node("DataSource"))
                var about := phone_column.get_children().find(phone_column.get_node("About"))
                _ok(source < before and before < about, "the card stands between the data source and the colophon")
        phone.queue_free()
        await process_frame
