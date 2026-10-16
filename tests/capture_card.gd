extends SceneTree

## Visual QA for one card: drives the real study screen with a chosen card so
## a card that reads badly can be seen exactly as a person sees it.
##
##     godot --path . --script tests/capture_card.gd -- /tmp/cardshots 007

const MainScript := preload("res://scripts/main.gd")

var _out := "/tmp/cardshots"
var _card_id := "007"

func _init() -> void:
        var args := OS.get_cmdline_user_args()
        if args.size() > 0:
                _out = args[0]
        if args.size() > 1:
                _card_id = args[1]
        DirAccess.make_dir_recursive_absolute(_out)
        _remove_tree("user://decks")
        _remove_tree("user://settings.json")
        _remove_tree("user://sync_manifest.json")

        var main = (load("res://scripts/main.gd") as GDScript).new()
        main.set_anchors_preset(Control.PRESET_FULL_RECT)
        root.add_child(main)
        await main.ready
        await create_timer(0.8).timeout

        var deck = main._deck
        var card = null
        for c in deck.cards:
                if c.id == _card_id:
                        card = c
        if card == null:
                print("no card %s" % _card_id)
                quit(1)
                return

        var study = load("res://scripts/ui/study.gd").new()
        study.name = "Study"
        main.add_child(study)
        # start() itself waits for readiness; awaiting the ready signal here
        # would hang -- it fired inside add_child, before the await connected.
        study.start([card])
        await create_timer(0.9).timeout
        await _shot("front")
        study._reveal()
        await create_timer(1.0).timeout
        await _shot("back")

        print("card %s captured in %s" % [_card_id, _out])
        quit(0)

func _shot(name: String) -> void:
        await process_frame
        await process_frame
        var image := root.get_viewport().get_texture().get_image()
        image.save_png(_out.path_join(name + ".png"))
        print("shot: %s" % name)

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
