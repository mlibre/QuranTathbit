extends SceneTree
const CardScript := preload("res://scripts/data/card.gd")

## The phone's back key, replayed as the window message the engine sends
## it as: the key must not leave the app from a page that has a way back,
## and whatever stands over a page must close before the page does. The
## message is propagated the way the engine propagates it on a phone --
## from the root window down -- so the law is measured on the real road,
## not on a private side door.

var _failures := 0

func _init() -> void:
        _fresh_install()
        var main = (load("res://scripts/main.gd") as GDScript).new()
        main.set_anchors_preset(Control.PRESET_FULL_RECT)
        root.add_child(main)
        # After the tree has run frames, _ready fires inside add_child
        # itself, and awaiting a signal that already fired would stand
        # still forever.
        if not main.is_node_ready():
                await main.ready
        await create_timer(0.9).timeout

        _ok(
                not ProjectSettings.get_setting("application/config/quit_on_go_back", true),
                "the project hands the back key to the app, not to the engine's quit"
        )

        await _check_first_question(main)
        await _check_settings(main)
        await _check_browse(main)
        await _check_editor_over_browse(main)
        await _check_study(main)
        _check_sync_keeps_page(main)

        if _failures > 0:
                print("back-button: %d FAILURE(S)" % _failures)
                quit(1)
        else:
                print("back-button: all checks passed")
                quit(0)


## The key is pressed the way the engine delivers it on a phone: one
## notification from the root window, which every node below may answer.
func _back(main: Node) -> void:
        root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)


func _check_first_question(main: Node) -> void:
        var asking: Node = main.get_node_or_null("LanguagePicker")
        _ok(asking != null, "the first run asks its first question")
        if asking == null:
                return
        _back(main)
        await process_frame
        await process_frame
        _ok(main.get_node_or_null("LanguagePicker") == null, "the back key puts the question away")
        _ok(main.get_node_or_null("Home") != null, "the page beneath the question stays")


func _check_settings(main: Node) -> void:
        main._on_settings_pressed()
        await process_frame
        _ok(main.get_node_or_null("Settings") != null, "settings opens")
        _back(main)
        await create_timer(0.35).timeout
        _ok(main.get_node_or_null("Settings") == null, "the back key leaves settings")
        _ok(main.get_node_or_null("Home") != null, "the back key from settings lands on home")


func _check_browse(main: Node) -> void:
        main._on_browse_pressed()
        await process_frame
        var browse: Node = main.get_node_or_null("Browse")
        _ok(browse != null, "the library opens")
        if browse == null:
                return
        # The shelf streams, not dumps: the opening breath lays a
        # screenful and the rest arrive a batch a frame -- a phone meets
        # a library, not a frozen page -- so one frame in, part of the
        # shelf stands and the whole deck does not; and a moment later
        # every card is there with the shelf's tail beside it.
        var total: int = main._deck.cards.size()
        var built := _entries_on(browse)
        if total > 40:
                _ok(
                        built >= 1 and built < total,
                        "the shelf opens on a screenful, not the whole deck (%d of %d)" % [built, total]
                )
        # The rest arrive frame by frame; the machine's own pace says how
        # many frames that takes, so the test waits for the shelf's own
        # word (every card standing, the tail beside them) rather than a
        # clock's.
        var waited := 0.0
        while built < total and waited < 20.0:
                await create_timer(0.3).timeout
                waited += 0.3
                built = _entries_on(browse)
        _ok(built == total, "the streamed shelf arrives whole (%d of %d, %.1fs)" % [built, total, waited])
        _ok(
                browse.get_node_or_null("Margin/Column/Scroll/Wrap/Column/Tail") != null,
                "the streamed shelf carries its tail"
        )
        # The volume's popover closes first, the page beneath it stays.
        var popup: Node = browse.get_node_or_null("VolumePopup")
        if popup == null:
                _ok(false, "the library carries the volume's popover")
                return
        popup.visible = true
        _back(main)
        await process_frame
        _ok(not popup.visible, "the back key closes the popover, not the page")
        _ok(main.get_node_or_null("Browse") != null, "the page beneath the popover stays")
        # The search field's own keys are given up before the page is.
        var search: LineEdit = browse.get_node_or_null("Margin/Column/Search")
        if search != null:
                search.grab_focus()
                await process_frame
                _back(main)
                await process_frame
                _ok(not search.has_focus(), "the back key leaves the search field first")
                _ok(main.get_node_or_null("Browse") != null, "the page beneath the field stays")
        # And only then the page itself.
        _back(main)
        await create_timer(0.35).timeout
        _ok(main.get_node_or_null("Browse") == null, "the back key leaves the library")
        _ok(main.get_node_or_null("Home") != null, "the back key from the library lands on home")


func _check_editor_over_browse(main: Node) -> void:
        main._on_browse_pressed()
        await create_timer(0.5).timeout
        var browse: Node = main.get_node_or_null("Browse")
        if browse == null:
                _ok(false, "the library opens again")
                return
        var card: CardScript = main._deck.cards[0]
        browse._open_editor(card)
        await process_frame
        _ok(browse.get_node_or_null("Editor") != null, "the editor stands over the library")
        _back(main)
        await create_timer(0.4).timeout
        _ok(browse.get_node_or_null("Editor") == null, "the back key closes the editor alone")
        _ok(main.get_node_or_null("Browse") != null, "the library beneath the editor stays")
        _back(main)
        await create_timer(0.35).timeout
        _ok(main.get_node_or_null("Home") != null, "a second back leaves the library for home")


func _check_study(main: Node) -> void:
        main._start_session()
        await create_timer(0.5).timeout
        _ok(main.get_node_or_null("Study") != null, "a session opens")
        _back(main)
        await create_timer(0.35).timeout
        _ok(main.get_node_or_null("Study") == null, "the back key ends the session")
        _ok(main.get_node_or_null("Home") != null, "the back key from a session lands on home")


## Work under way is not a page: the key is kept, and nothing moves.
func _check_sync_keeps_page(main: Node) -> void:
        var home: Node = main.get_node_or_null("Home")
        if home == null:
                _ok(false, "home stands for the sync check")
                return
        var busy := Control.new()
        busy.name = "SyncOverlay"
        main.add_child(busy)
        _back(main)
        await process_frame
        _ok(main.get_node_or_null("SyncOverlay") != null, "the back key does not touch a sync under way")
        _ok(main.get_node_or_null("Home") != null, "the page beneath a sync stays")
        busy.queue_free()
        await process_frame


func _fresh_install() -> void:
        _remove_tree("user://decks")
        _remove_tree("user://settings.json")


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


func _ok(what: bool, saying: String) -> void:
        if what:
                print("  ok  %s" % saying)
        else:
                _failures += 1
                print("  FAIL  %s" % saying)

## The shelf's own account of how many of its rows stand.
func _entries_on(browse: Node) -> int:
        var column := browse.get_node_or_null("Margin/Column/Scroll/Wrap/Column")
        if column == null:
                return 0
        var count := 0
        for child in column.get_children():
                if child.name.begins_with("Entry"):
                        count += 1
        return count
