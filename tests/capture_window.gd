extends SceneTree

## Visual QA at any window size: the same first-session journey as
## capture_shots.gd, driven inside a window the caller names -- a phone's
## 390x844 or the desktop's own 1280x800 -- with the layout invariants
## asserted along the way, because a phone screen is where a desktop canvas
## hides: the stretch mode can pin the design width at the desktop's base
## resolution and quietly draw the whole desktop UI at a third of its size.
## Run it on a display -- Xvfb is enough; headless mode cannot resize
## windows, so it cannot carry this one.
##
##     godot --path . --script tests/capture_window.gd -- 390x844 /tmp/shots-phone
##     godot --path . --script tests/capture_window.gd -- 1280x800 /tmp/shots-desk
##
## The window size is the first argument (default 390x844), the out
## directory the second (default /tmp/shots-window). The window must be
## asked for before the first frame runs: under a bare X server the canvas
## follows a programmatic resize only while the tree is still starting up,
## and never afterwards, so a mid-run resize would test nothing. The
## install is wiped first, so the shots are always of the same first run.
## The invariants know which shape they are in: narrower than 620 design
## units is a hand, wider is a desk.

const SHOTS := 5

var _window := Vector2i(390, 844)
var _phone := true
var _out := "/tmp/shots-window"
var _saved := 0
var _failures := 0
var _main: Control

func _init() -> void:
        var args := OS.get_cmdline_user_args()
        if args.size() > 0 and "x" in args[0]:
                var parts := args[0].split("x")
                _window = Vector2i(int(parts[0]), int(parts[1]))
        if args.size() > 1:
                _out = args[1]
        _phone = _window.x < 620
        # Before anything else -- before a single frame: the one moment a
        # programmatic resize is guaranteed to reach the canvas.
        DisplayServer.window_set_size(_window)
        DirAccess.make_dir_recursive_absolute(_out)
        _fresh_install()
        await create_timer(0.4).timeout

        var main: Control = (load("res://scripts/main.gd") as GDScript).new()
        _main = main
        main.set_anchors_preset(Control.PRESET_FULL_RECT)
        root.add_child(main)
        # After the tree has run frames, _ready fires inside add_child itself,
        # and awaiting a signal that already fired would stand still forever --
        # so the await waits only when there is actually something to wait for.
        if not main.is_node_ready():
                await main.ready
        await create_timer(0.8).timeout

        _check_canvas()
        var home: Control = main.get_node("Home")
        _check_touch_reach(home)

        await _shot("window_home")
        main._start_session()
        await create_timer(0.8).timeout
        _check_card_fits()
        await _shot("window_front")
        var study: Control = main.get_node("Study")
        study._reveal()
        await create_timer(0.9).timeout
        _check_answers()
        await _shot("window_back")
        study._answer("good")
        await create_timer(0.7).timeout
        await _shot("window_next")
        study.closed.emit()
        await create_timer(0.7).timeout
        main._on_settings_pressed()
        await create_timer(0.8).timeout
        _check_settings_fit()
        await _shot("window_settings")

        print("captures: %d of %d shot(s) at %dx%d in %s" % [_saved, SHOTS, _window.x, _window.y, _out])
        if _failures > 0:
                print("window %dx%d: %d FAILURE(S)" % [_window.x, _window.y, _failures])
        quit(0 if _failures == 0 and _saved >= SHOTS else 1)

# --- the invariants -------------------------------------------------------------

## The one number that decides whether a phone gets a phone UI: the design
## canvas the stretch mode hands the app (the visible rect, in design units
## -- the window's own size is physical pixels, not what the layout lays out
## against). A window narrower than the base resolution's aspect must still
## receive a canvas of the base's own width, not the desktop's -- 1280-wide
## design units in a 390px window is the whole desktop drawn at a third of
## its size. A window at the desktop's own shape keeps the desktop canvas
## exactly.
func _check_canvas() -> void:
        var canvas := root.get_visible_rect().size
        if _phone:
                _ok(canvas.x <= 470.0,
                        "a phone window gets a phone canvas (got %s)" % canvas)
                _ok(canvas.y >= 800.0,
                        "a phone canvas is at least the base height (got %s)" % canvas)
        else:
                _ok(canvas == Vector2(_window),
                        "a desktop window keeps its own canvas (got %s, window %s)" % [canvas, _window])

## A thumb must be able to reach everything the page offers: the study
## button, the dock at the page's foot and the corner's sleeping update
## coin sit inside the canvas, and the dock's doors are on top of
## everything at their own centres, where a tap lands.
func _check_touch_reach(home: Control) -> void:
        var window := root.get_visible_rect()
        var study: Control = home.get_node("Margin/Column/Study")
        _ok(window.grow(1.0).encloses(study.get_global_rect()),
                "the study button is inside the window (%s in %s)" % [study.get_global_rect(), window])
        var dock: Control = home.get_node("Dock")
        _ok(window.grow(1.0).encloses(dock.get_global_rect()),
                "the dock is inside the window (%s in %s)" % [dock.get_global_rect(), window])
        for item_name in ["Home", "Study", "Library", "Settings"]:
                var item: Button = home.get_node("Dock/Pad/Row/" + item_name)
                # A door that is not standing holds no centre to tap: every
                # nav door stands on every page, and the reach check asks
                # only of the doors present.
                if not item.visible:
                        continue
                _ok(window.encloses(item.get_global_rect()),
                        "the dock's %s door is inside the window (%s)" % [item_name, item.get_global_rect()])
                var at := item.get_global_rect().get_center()
                _ok(_top_at(home, at) == item,
                        "the dock's %s door is on top of everything at its own centre" % item_name)
        var update_coin: Button = home.get_node("UpdateCoin")
        _ok(window.encloses(update_coin.get_global_rect()),
                "the update coin is inside the window (%s)" % update_coin.get_global_rect())
        var sync_coin: Button = home.get_node("SyncCoin")
        if sync_coin.visible:
                _ok(window.encloses(sync_coin.get_global_rect()),
                        "the sync coin is inside the window (%s)" % sync_coin.get_global_rect())
        _ok(
                home.get_node_or_null("Margin/Column/SyncLine") == null,
                "the page itself says nothing of sync -- the corner's sync coin is the whole story"
        )
        if sync_coin.visible:
                _ok(
                        sync_coin.tooltip_text.length() > 0,
                        "the sync state says itself in the coin's own words"
                )

## The card never asks a window for more room than it has.
func _check_card_fits() -> void:
        var study: Control = _main.get_node_or_null("Study")
        if study == null:
                _ok(false, "the study screen is standing")
                return
        var card: Control = study.get_node("Margin/Column/Surface/Fill/CardPanel")
        _ok(card.get_global_rect().size.x <= root.get_visible_rect().size.x + 1.0,
                "the card fits the window's width (%s in %s)" % [
                        card.get_global_rect().size.x, root.get_visible_rect().size.x
                ])

## Two answer buttons to a row in a hand, four on a desk, each a whole
## thumb tall, every one of them inside the window.
func _check_answers() -> void:
        var study: Control = _main.get_node("Study")
        var grid: GridContainer = study.get_node("Margin/Column/Answers")
        var want := 2 if _phone else 4
        _ok(grid.columns == want,
                "answers sit %d to a row in this window (got %d)" % [want, grid.columns])
        var window := root.get_visible_rect()
        for button in grid.get_children():
                _ok(window.grow(1.0).encloses((button as Control).get_global_rect()),
                        "every answer button is inside the window")
                _ok((button as Control).custom_minimum_size.y >= 60.0,
                        "answer buttons are a thumb tall (%s)" % (button as Control).custom_minimum_size)

## Settings' capped column still fits the window edge to edge.
func _check_settings_fit() -> void:
        var screen: Control = _main.get_node("Settings")
        var column: Control = screen.get_node("Margin/Scroll/Wrap/Column")
        _ok(column.custom_minimum_size.x <= root.get_visible_rect().size.x,
                "the settings column fits the window (wants %s, window %s)" % [
                        column.custom_minimum_size.x, root.get_visible_rect().size.x
                ])

# --- the harness ----------------------------------------------------------------

func _ok(condition: bool, what: String) -> void:
        if not condition:
                _failures += 1
                print("  FAIL: %s" % what)

## The engine's own hit test, walked by hand: deepest topmost control at a
## point, children in reverse order, honouring visibility and mouse_filter.
func _top_at(from: Control, at: Vector2) -> Control:
        var children := from.get_children()
        for i in range(children.size() - 1, -1, -1):
                var child := children[i]
                if child is not Control:
                        continue
                var c := child as Control
                if not c.visible or c.mouse_filter == Control.MOUSE_FILTER_IGNORE:
                        continue
                if not c.get_global_rect().has_point(at):
                        continue
                var deeper: Control = _top_at(c, at)
                if deeper != null:
                        return deeper
                return c
        return null

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
