extends SceneTree

## The Persian build, proven in a headless stand-in: the export feature the
## Persian APK carries is spoken here through flavor.gd's test door, and the
## app's whole first hour is checked -- the question never asked, the tongue
## pinned before the first page stands, the choice written into the files it
## travels in from the very first boot, Settings carrying no question it
## would be wrong to ask, the page laid out from the right with its doors in
## the reading's own order and the update coin keeping the corner it has
## always stood in, and a deck arriving from an English phone
## answered in this one. The standard build's asking is regression_boot's
## own check; this suite proves the other clothes.

const FlavorScript := preload("res://scripts/data/flavor.gd")
const I18nScript := preload("res://scripts/ui/i18n.gd")

var _failures := 0

func _init() -> void:
        FlavorScript.force_test("persian")
        _fresh_install()
        await create_timer(0.4).timeout
        var main: Control = (load("res://scripts/main.gd") as GDScript).new()
        main.set_anchors_preset(Control.PRESET_FULL_RECT)
        root.add_child(main)
        if not main.is_node_ready():
                await main.ready
        await create_timer(0.9).timeout

        _check_the_question_is_never_asked(main)
        _check_the_tongue_is_written_down()
        _check_home_speaks_it(main)
        _check_the_coin_keeps_its_corner(main)
        await _check_settings_never_asks(main)
        _check_an_english_deck_is_answered(main)

        if _failures > 0:
                print("persian: %d FAILURE(S)" % _failures)
                quit(1)
        else:
                print("persian: all checks passed")
                quit(0)

func _fresh_install() -> void:
        _remove_tree("user://decks")
        _remove_tree("user://settings.json")
        _remove_tree("user://sync_manifest.json")

## Born speaking: the first question of the standard build never stands over
## the page, and the page beneath is already there, in this tongue.
func _check_the_question_is_never_asked(main: Control) -> void:
        _ok(
                main.get_node_or_null("LanguagePicker") == null,
                "the Persian build never asks its first question -- the build is the answer"
        )
        _ok(
                main.get_node_or_null("Home") != null,
                "home stands beneath, never waiting on a question"
        )

## The choice is not a mood -- it is written down where it travels: this
## device's own file and the deck's own file both say fa from the first
## boot, so a sync and a new device both inherit the tongue without asking.
func _check_the_tongue_is_written_down() -> void:
        var settings: Variant = JSON.parse_string(
                FileAccess.get_file_as_string("user://settings.json")
        )
        _ok(
                typeof(settings) == TYPE_DICTIONARY
                        and str((settings as Dictionary).get("ui_lang", "")) == "fa",
                "settings.json says fa from the first boot"
        )
        var progress: Variant = JSON.parse_string(
                FileAccess.get_file_as_string("user://decks/quran/progress.json")
        )
        _ok(
                typeof(progress) == TYPE_DICTIONARY
                        and str((progress as Dictionary).get("ui_lang", "")) == "fa",
                "the deck's own progress file says fa from the first boot, so the choice travels"
        )
        _is(I18nScript.lang(), "fa", "the app speaks fa before its first page stands")

## The page itself: laid out from the right, its words in this tongue, its
## numbers in this script, and its doors in the reading's own order -- the
## library first, where the reading begins.
func _check_home_speaks_it(main: Control) -> void:
        var home: Control = main.get_node("Home")
        _ok(
                home.layout_direction == Control.LAYOUT_DIRECTION_RTL,
                "the Persian home is laid out from the right"
        )
        var study: Button = home.get_node("Margin/Column/Study")
        _is(
                study.text,
                str(I18nScript.STRINGS["Learn new cards"]["fa"]),
                "the day's button names its session in Persian"
        )
        _is(
                home.get_node("Margin/Column/Stats/Due/Box/Value").text,
                "۰",
                "the day's numbers arrive in the reader's own script"
        )
        # The reading's own order: the library door stands where the reading
        # begins -- the right -- and settings stands last, where it ends.
        var browse: Control = home.get_node("Dock/Pad/Row/Browse")
        var sync: Control = home.get_node("Dock/Pad/Row/Sync")
        var settings_door: Control = home.get_node("Dock/Pad/Row/Settings")
        _ok(
                browse.get_global_rect().get_center().x > sync.get_global_rect().get_center().x
                        and sync.get_global_rect().get_center().x
                        > settings_door.get_global_rect().get_center().x,
                "the dock's doors stand in the reading's own order -- the library first, from the right"
        )

## The one gold way a newer version arrives keeps the corner it has always
## stood in: the coin is chrome, not the reading's flow, so a page laid out
## from the right turns its rows and never the coin -- it waits at the
## page's right head, as it does on the page laid out from the left.
func _check_the_coin_keeps_its_corner(main: Control) -> void:
        var home: Control = main.get_node("Home")
        home.offer_update()
        var coin: Button = home.get_node("UpdateCoin")
        _ok(coin.visible, "the waiting version wakes the coin")
        var window := root.get_visible_rect()
        var coin_rect := coin.get_global_rect()
        _ok(
                not coin.is_layout_rtl()
                        and coin_rect.get_center().x > window.get_center().x
                        and coin_rect.end.x >= window.end.x - 40.0,
                "the coin keeps the page's right head on the page laid out from the right (%s)"
                        % coin_rect
        )

## Settings never asks about the tongue: the build answered it the day it
## was exported, and a row offering to change what the build is would be a
## question with only wrong answers.
func _check_settings_never_asks(main: Control) -> void:
        main._on_settings_pressed()
        await create_timer(0.5).timeout
        var settings: Control = main.get_node_or_null("Settings")
        _ok(settings != null, "settings opens in the Persian build")
        if settings != null:
                _ok(
                        settings.get_node_or_null(
                                "Margin/Scroll/Wrap/Column/Reading/Padding/Box/AppLanguages"
                        ) == null,
                        "settings carries no language row -- the build is the answer"
                )
                _ok(
                        settings.get_node_or_null(
                                "Margin/Scroll/Wrap/Column/Reading/Padding/Box/AyahFaces"
                        ) != null,
                        "the Reading card still offers the verse's own faces"
                )
                settings.closed.emit()
                await create_timer(0.3).timeout

## A deck arriving from an English phone does not bring its tongue here:
## the adoption answers in this one, writes the answer down so it travels
## back, and the reader never sees a page turn English on them.
func _check_an_english_deck_is_answered(main: Control) -> void:
        main._deck.ui_lang = "en"
        main._deck.ui_lang_mod = main._now() + 100
        main._adopt_deck_choices()
        _is(main._deck.ui_lang, "fa", "a deck arriving in English is answered in Persian")
        _is(main._settings.ui_lang, "fa", "the device's own word stays fa")
        var progress: Variant = JSON.parse_string(
                FileAccess.get_file_as_string("user://decks/quran/progress.json")
        )
        _ok(
                typeof(progress) == TYPE_DICTIONARY
                        and str((progress as Dictionary).get("ui_lang", "")) == "fa",
                "the answer is written into the deck's own file, so it travels back"
        )

func _ok(condition: bool, what: String) -> void:
        if not condition:
                _failures += 1
                print("  FAIL: %s" % what)

func _is(got: Variant, expected: Variant, what: String) -> void:
        if got != expected:
                _failures += 1
                print("  FAIL: %s — got %s, expected %s" % [what, str(got), str(expected)])

func _remove_tree(path: String) -> void:
        if FileAccess.file_exists(path):
                DirAccess.remove_absolute(path)
                return
        if DirAccess.dir_exists_absolute(path):
                for entry in DirAccess.get_files_at(path):
                        DirAccess.remove_absolute(path.path_join(entry))
                for entry in DirAccess.get_directories_at(path):
                        _remove_tree(path.path_join(entry))
                DirAccess.remove_absolute(path)
