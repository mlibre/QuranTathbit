extends SceneTree

## Animated capture: the app's whole day, filmed continuously at ten
## frames a second so tools/make_gif.py can assemble one GIF of the app at
## work. Needs a display -- Xvfb is enough; headless mode cannot render, so
## it cannot carry this one.
##
## The film is landscape, the desk's own shape: a window with room for the
## card beside its margins, the library's shelf at a reader's measure. Run
## it at the same size the film should show:
##
##     Xvfb :99 -screen 0 1280x800x24 &
##     DISPLAY=:99 godot --path . --resolution 1280x800 \
##             --script tests/capture_gif.gd -- /tmp/gifframes
##     python3 tools/make_gif.py /tmp/gifframes docs/media/app.gif 640
##
## The out directory defaults to /tmp/gifframes; name another after -- to
## put the frames somewhere else. The install is wiped first, so every
## run films the same first run.

var _out := "/tmp/gifframes"
var _filming := true
var _frames := 0
var _next := 0

func _init() -> void:
        var args := OS.get_cmdline_user_args()
        if args.size() > 0:
                _out = args[0]
        DirAccess.make_dir_recursive_absolute(_out)
        _fresh_install()

        var main = (load("res://scripts/main.gd") as GDScript).new()
        # The scene file gives the root its full-rect anchors; match it here,
        # or every screen lays out at zero size and the film lies.
        main.set_anchors_preset(Control.PRESET_FULL_RECT)
        root.add_child(main)
        await main.ready
        _film()
        await _beat(12)

        main._start_session()
        await _beat(13)
        var study: Control = main.get_node("Study")
        study._reveal()
        await _beat(17)
        study._answer("good")
        await _beat(11)
        study._reveal()
        await _beat(17)
        study._answer("easy")
        await _beat(11)
        study._reveal()
        await _beat(15)
        study._answer("hard")
        await _beat(11)
        study.closed.emit()
        await _beat(11)

        # The library: the shelf, its search field, and the card a search
        # finds -- the deck as a book, asked a question and answering.
        main._on_browse_pressed()
        await _beat(13)
        var browse: Control = main.get_node("Browse")
        var search: LineEdit = browse.get_node_or_null("Margin/Column/Search")
        if search != null:
                for typed in ["2", ":", "9", "3"]:
                        search.text = search.text + typed
                        browse._on_search_changed(search.text)
                        await _beat(6)
                await _beat(8)
                var column: VBoxContainer = browse.get_node("Margin/Column/Scroll/Wrap/Column")
                for child in column.get_children():
                        if child.name.begins_with("Entry"):
                                (child.get_node("Row") as Button).pressed.emit()
                                break
                await _beat(16)
        browse.closed.emit()
        await _beat(11)

        _filming = false
        await create_timer(0.15).timeout
        print("gif: %d frame(s) in %s" % [_frames, _out])
        quit(0 if _frames > 0 else 1)

## The camera: one frame every tenth of a second, on a wall-clock timer, so
## the film runs at the speed the app runs whatever the machine's frame
## rate decides to be under Xvfb.
func _film() -> void:
        while _filming:
                await create_timer(0.1).timeout
                if not _filming:
                        return
                var image := root.get_viewport().get_texture().get_image()
                _next += 1
                if image.save_png(_out.path_join("%04d.png" % _next)) == OK:
                        _frames += 1

## A beat the walk can wait in: so many tenths of a second, one timer at a
## time, so the film and the walk share the same clock.
func _beat(tenths: int) -> void:
        for i in tenths:
                await create_timer(0.1).timeout

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
