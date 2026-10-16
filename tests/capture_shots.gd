extends SceneTree

## Visual QA: drive the real app through its first session on a fresh install
## and save a PNG at each step, so tools/shot_qa.py can read what a person
## would see. Run it on a display -- Xvfb is enough; headless mode cannot
## render, so it cannot carry this one.
##
##     godot --path . --script tests/capture_shots.gd -- /tmp/shots
##     python3 tools/shot_qa.py /tmp/shots
##
## The out directory defaults to /tmp/shots; name another after -- to put the
## PNGs somewhere else. The install is wiped first, so the shots are always of
## the same first run.

const MainScript := preload("res://scripts/main.gd")

const SHOTS := 16

var _out := "/tmp/shots"
var _saved := 0

func _init() -> void:
        var args := OS.get_cmdline_user_args()
        if args.size() > 0:
                _out = args[0]
        DirAccess.make_dir_recursive_absolute(_out)
        _fresh_install()

        var main = (load("res://scripts/main.gd") as GDScript).new()
        # The scene file gives the root its full-rect anchors; match it here,
        # or every screen lays out at zero size and the shots lie.
        main.set_anchors_preset(Control.PRESET_FULL_RECT)
        root.add_child(main)
        await main.ready
        await create_timer(0.8).timeout

        # The app's very first question: which tongue its own words speak.
        # A frame of the question, then the answer this film reads in.
        await _shot("language")
        var picker: Control = main.get_node_or_null("LanguagePicker")
        if picker != null:
                (picker.get_node("Centre/Card/Pad/Box/Languages/Langen") as Button).pressed.emit()
                await create_timer(0.6).timeout

        await _shot("home")
        main._start_session()
        await create_timer(0.8).timeout
        await _shot("study_front")
        var study: Control = main.get_node("Study")
        study._reveal()
        await create_timer(0.9).timeout
        await _shot("study_back")
        study._answer("good")
        await create_timer(0.7).timeout
        await _shot("study_next")
        study._answer("easy")
        await create_timer(0.7).timeout
        await _shot("study_two")
        # The recitation's own control, open under its coin: the popover is
        # part of the page a person sees, so the film keeps a frame of it.
        study._rig.toggle()
        await create_timer(0.5).timeout
        await _shot("volume")
        study._rig.toggle()
        await create_timer(0.3).timeout
        # The pencil: a card noticed mid-study is fixed mid-study, on the
        # card's own page over the session.
        study._open_editor()
        await create_timer(0.8).timeout
        await _shot("editor")
        if study.get_node_or_null("Editor") != null:
                (study.get_node("Editor") as Control).queue_free()
                await create_timer(0.3).timeout
        study.closed.emit()
        await create_timer(0.7).timeout
        main._on_settings_pressed()
        await create_timer(0.8).timeout
        await _shot("settings")
        # The reading card: the verses' face and the app's tongue, offered as
        # what they are -- a basmala drawn in each hand, a language named in
        # its own script.
        var settings_screen: Control = main.get_node("Settings")
        var reading: Control = settings_screen.get_node_or_null("Margin/Scroll/Wrap/Column/Reading")
        if reading != null:
                var scroll: ScrollContainer = settings_screen.get_node("Margin/Scroll")
                scroll.scroll_vertical = int(
                        maxf(0.0, reading.get_global_rect().position.y - scroll.get_global_rect().position.y)
                )
                await create_timer(0.5).timeout
                await _shot("reading")
        main.get_node("Settings").closed.emit()
        await create_timer(0.6).timeout
        await _shot("home_again")
        # The library: the deck as a book, a row opening its own page.
        main._on_browse_pressed()
        await create_timer(1.4).timeout
        await _shot("browse")
        var browse: Control = main.get_node("Browse")
        var list: VBoxContainer = browse.get_node("Margin/Column/Scroll/Wrap/Column")
        var first_entry: VBoxContainer = null
        for child in list.get_children():
                if child.name.begins_with("Entry"):
                        first_entry = child
                        break
        if first_entry != null:
                (first_entry.get_node("Row") as Button).pressed.emit()
                await create_timer(0.7).timeout
                await _shot("browse_open")
        # The shelf answers its search field: an address finds its card.
        var search: LineEdit = browse.get_node_or_null("Margin/Column/Search")
        if search != null:
                search.text = "2:93"
                browse._on_search_changed("2:93")
                await create_timer(0.8).timeout
                await _shot("browse_search")
                search.text = ""
                browse._on_search_changed("")
                await create_timer(0.4).timeout
        browse.closed.emit()
        await create_timer(0.6).timeout
        await _shot("home_third")
        # The app said again in the reader's own tongue: the same home page,
        # the same verses, only the chrome translated.
        main._apply_language("fa")
        await create_timer(0.8).timeout
        await _shot("home_fa")
        main._apply_language("en")
        await create_timer(0.5).timeout

        print("captures: %d of %d shot(s) in %s" % [_saved, SHOTS, _out])
        quit(0 if _saved >= SHOTS else 1)

func _shot(name: String) -> void:
        await process_frame
        await process_frame
        var image := root.get_viewport().get_texture().get_image()
        if image.save_png(_out.path_join(name + ".png")) == OK:
                _saved += 1
                print("shot: %s" % name)

func _fresh_install() -> void:
        _remove_tree("user://decks")
        _remove_tree("user://settings.json")
        _remove_tree("user://sync_manifest.json")

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
