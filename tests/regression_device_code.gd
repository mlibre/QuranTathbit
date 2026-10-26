extends SceneTree
const SettingsScript := preload("res://scripts/ui/settings_screen.gd")
const ThemeScript := preload("res://scripts/ui/theme.gd")
const HttpClientScript := preload("res://scripts/net/http_client.gd")
const GitHubAuthScript := preload("res://scripts/net/github_auth.gd")
const DeckScript := preload("res://scripts/data/deck.gd")

## The device code stands across, not down. The report: the phone's
## photograph of the connect card showed the code a column of falling
## tiles -- one letter a line, nine lines tall, unreadable as a code.
## The cause was a kindness turned against itself: every line on the
## settings page wraps its words, and a wrapping label's least width is
## nothing at all, so the chip that shrinks to its child's least width
## stood one letter wide and let the wrap do the rest. A code is a
## ticket, not a paragraph: the wrap is off, the chip closes around the
## whole code, and the proof is the geometry -- one line, wider than
## tall, snug as a ticket in its sleeve.
##
## Two laws stand beside that one now, from the second photograph:
## a connected reader must never read the flow's words -- a refresh that
## tied the flow to the master switch stood an empty code ticket (a pale
## pill with nothing in it) under the reader's own name, with the two
## flow buttons under it, answers to a question nobody was asking; and
## the flow's two buttons wear the row grammar every button row on the
## page wears -- one height (46), full width, the way onward solid green,
## the kindness beside it hollow.

var _failures := 0

func _init() -> void:
        _fresh_install()
        var settings := SettingsScript.new()
        settings.name = "Settings"
        settings.set_anchors_preset(Control.PRESET_FULL_RECT)
        root.add_child(settings)
        if not settings.is_node_ready():
                await settings.ready
        await create_timer(0.3).timeout

        var flow: VBoxContainer = settings.get_node("Margin/Scroll/Wrap/Column/GitHub/Padding/Box/Flow")
        var chip: PanelContainer = flow.get_node("Code")
        var code_text: RichTextLabel = flow.get_node("Code/Pad/CodeText")
        # The shape GitHub hands the device flow: eight letters, a dash at
        # the middle -- what _pretty_code passes through untouched.
        code_text.text = "WDJB-MJHT"
        chip.visible = true
        flow.visible = true
        await create_timer(0.3).timeout

        _ok(code_text.get_line_count() == 1,
                "the code stands on one line, not a column of tiles")
        var rect := code_text.get_global_rect().size
        _ok(rect.x > rect.y,
                "the code reads across, not down (w %s, h %s)" % [rect.x, rect.y])
        # Snug as a ticket: the chip's own width is the code's width plus its
        # sleeve -- twenty a side, and nothing more to spare.
        _is(int(chip.size.x - rect.x), 40,
                "the chip closes around the code with only its sleeve to spare")
        # A second shape -- a bare code _pretty_code would dash itself --
        # keeps the same stance.
        code_text.text = "1A2B3C4D"
        await create_timer(0.2).timeout
        _ok(code_text.get_line_count() == 1,
                "an undashed code stands on one line too")
        rect = code_text.get_global_rect().size
        _ok(rect.x > rect.y,
                "the undashed code reads across, not down (w %s, h %s)" % [rect.x, rect.y])

        # The flow's two buttons wear the page's own row grammar: one
        # height (46, the height the Connect/Disconnect row wears), full
        # width, the way onward solid green and the kindness hollow.
        var open_b: Button = flow.get_node("Actions/Open")
        var copy_b: Button = flow.get_node("Actions/Copy")
        _ok(open_b.size_flags_horizontal & Control.SIZE_EXPAND_FILL != 0,
                "the way to GitHub fills the row like its neighbours do")
        _ok(copy_b.size_flags_horizontal & Control.SIZE_EXPAND_FILL != 0,
                "the copy fills the row like its neighbours do")
        _is(int(open_b.custom_minimum_size.y), 46,
                "the way to GitHub stands the row's one height")
        _is(int(copy_b.custom_minimum_size.y), 46,
                "the copy stands the row's one height")
        var open_slab := open_b.get_theme_stylebox("normal") as StyleBoxFlat
        var copy_slab := copy_b.get_theme_stylebox("normal") as StyleBoxFlat
        _ok(open_slab != null and open_slab.bg_color == ThemeScript.GREEN,
                "the way onward wears the solid green slab")
        _ok(copy_slab == null or copy_slab.bg_color != ThemeScript.GREEN,
                "the kindness beside it stands hollow")

        settings.queue_free()
        await create_timer(0.1).timeout

        # The second photograph's law: a connected reader (sync on, the
        # token and the name already saved) must never read the flow's
        # words -- no empty code ticket under their name, no two buttons
        # answering a question nobody is asking. The flow belongs to a
        # sign-in that is running, not to a switch that is on.
        _write_connected_settings()
        var connected := SettingsScript.new()
        connected.name = "Settings"
        connected.set_anchors_preset(Control.PRESET_FULL_RECT)
        root.add_child(connected)
        if not connected.is_node_ready():
                await connected.ready
        # The stand-ins are the app's own scripts, not
        # fakes -- a refresh never reaches the network, it only reads the
        # settings the file above wrote. The http stand-in is a Node (the
        # others are RefCounted) -- it is kept and freed at the end, so the
        # engine's exit reads no leak.
        var http := HttpClientScript.new()
        var loaded = (load("res://scripts/data/settings.gd") as GDScript).load_settings()
        connected.setup(http, GitHubAuthScript.new(),
                loaded, DeckScript.new())
        await create_timer(0.3).timeout

        var box: Control = connected.get_node("Margin/Scroll/Wrap/Column/GitHub/Padding/Box")
        var flow_c: VBoxContainer = box.get_node("Flow")
        var state_c: RichTextLabel = box.get_node("State")
        _ok(state_c.text.contains("@mlibre"),
                "the page says who the reader is (got \"%s\")" % state_c.text)
        _ok(not flow_c.visible,
                "a connected reader reads no sign-in flow under their name")
        _ok((flow_c.get_node("Code/Pad/CodeText") as RichTextLabel).text.is_empty(),
                "no code was ever carried into the connected page")

        connected.queue_free()
        http.free()
        await create_timer(0.1).timeout
        _done()

func _done() -> void:
        if _failures > 0:
                print("device_code: %d FAILURE(S)" % _failures)
                quit(1)
        else:
                print("device_code: all checks passed")
                quit(0)

func _ok(condition: bool, what: String) -> void:
        if condition:
                print("  ok   %s" % what)
        else:
                _failures += 1
                print("  FAIL %s" % what)

func _is(got, want, what: String) -> void:
        _ok(str(got) == str(want), "%s (got %s, want %s)" % [what, str(got), str(want)])

func _fresh_install() -> void:
        _remove_tree("user://settings.json")

## The connected reader's own file: sync on, the account already known --
## the state the second photograph was taken in (the reader had connected
## before; the page opened saying so, and stood an empty ticket under it).
func _write_connected_settings() -> void:
        var file := FileAccess.open("user://settings.json", FileAccess.WRITE)
        file.store_string(JSON.stringify({
                "token": "a-token-for-the-test",
                "owner": "mlibre",
                "repo": "quran-tathbit",
                "setup_done": true,
                "auto_sync": true,
                "sync_enabled": true,
        }, "\t") + "\n")
        file.close()

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
