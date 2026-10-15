extends SceneTree
const DeckScript := preload("res://scripts/data/deck.gd")
const CardScript := preload("res://scripts/data/card.gd")

## The app must boot cold, on any machine, with no warm editor cache: the
## deck installs itself into user://, the home screen shows the deck's real
## numbers, and the study screen can render a real card -- front, answer
## buttons, back. This is the smallest journey a person takes, run headless
## exactly as a fresh install would run it.

var _failures := 0

func _init() -> void:
        # A fresh install: nothing in the user folder yet.
        _fresh_install()
        var main = (load("res://scripts/main.gd") as GDScript).new()
        root.add_child(main)
        await main.ready
        # The home numbers count themselves in over half a second; read them
        # only once they have settled, or the check races the count.
        await create_timer(0.9).timeout

        var home: Control = main.get_node_or_null("Home")
        _ok(home != null, "the home screen is the first thing shown")
        if home == null:
                quit(1)
                return

        await _check_home_numbers(home)
        await _check_study_session(main)
        await _check_settings(main)

        if _failures > 0:
                print("boot: %d FAILURE(S)" % _failures)
                quit(1)
        else:
                print("boot: all checks passed")
                quit(0)

func _fresh_install() -> void:
        _remove_tree("user://decks")
        _remove_tree("user://settings.json")

func _ok(condition: bool, what: String) -> void:
        if not condition:
                _failures += 1
                print("  FAIL: %s" % what)

func _is(got: Variant, expected: Variant, what: String) -> void:
        if got != expected:
                _failures += 1
                print("  FAIL: %s — got %s, expected %s" % [what, str(got), str(expected)])

func _check_home_numbers(home: Control) -> void:
        var deck = load("res://scripts/data/deck.gd").load("user://decks/quran")
        _ok(deck != null, "the bundled deck installs itself on first run")
        if deck == null:
                return
        _is(deck.name, "Quran", "the deck is the Quran deck")
        _ok(deck.cards.size() == 99, "all 99 cards are there (got %d)" % deck.cards.size())

        var due: Label = home.get_node("Margin/Column/Stats/Due/Box/Value")
        var fresh: Label = home.get_node("Margin/Column/Stats/New/Box/Value")
        var learned: Label = home.get_node("Margin/Column/Stats/Learned/Box/Value")
        _is(due.text, "0", "nothing is due on a fresh install")
        _is(fresh.text, "20", "a day's new cards are offered")
        _is(learned.text, "0", "nothing is learned yet")

        var study: Button = home.get_node("Margin/Column/Study")
        _ok(not study.disabled, "study is ready")
        _ok(study.text == "Learn new cards", "the button names what the session is")

        # The settings corner once sat under a full-rect container added after
        # it, and no click could reach it. The engine's hit test -- deepest
        # topmost control, children in reverse order -- is the part that
        # decides who gets the click, so it is the part this walks by hand.
        var corner: Button = home.get_node("SettingsCorner")
        var at := corner.get_global_rect().get_center()
        _ok(_top_at(home, at) == corner, "the settings corner is on top of everything at its own centre")


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

func _check_study_session(main: Node) -> void:
        main._start_session()
        await create_timer(0.4).timeout
        var study: Control = main.get_node_or_null("Study")
        _ok(study != null, "the session opens")
        if study == null:
                return

        var view = study.get_node("Margin/Column/Surface/Fill/CardPanel/Padding/View")
        _ok(view.get_child_count() >= 1, "the card's question is on screen")

        study._reveal()
        await create_timer(0.4).timeout
        var answers: GridContainer = study.get_node("Margin/Column/Answers")
        _ok(answers.get_child_count() == 4, "four answers appear behind the reveal")
        var labels := []
        var waits := []
        for button in answers.get_children():
                labels.append(button.get_node("Center/Row/Stack/Word").text)
                waits.append(button.get_node("Center/Row/Stack/Wait").text)
        _ok(labels.any(func(l: String) -> bool: return l.begins_with("Again")), "one answer is Again")
        _ok(labels.any(func(l: String) -> bool: return l.begins_with("Good")), "one answer is Good")
        _ok(waits.all(func(w: String) -> bool: return not w.is_empty()), "every answer names its interval")
        # The answer side carries the question's own reference, small and gold,
        # so the verse is never read without knowing which one was asked for.
        var eyebrow := view.get_node_or_null("Eyebrow")
        _ok(eyebrow != null and str(eyebrow.text).length() > 0, "the question rides along above the answer")
        # The back of the first card is Arabic plus Persian plus audio.
        var texts := []
        for child in view.get_children():
                if child is RichTextLabel:
                        texts.append((child as RichTextLabel).text)
        var joined := "\n".join(texts)
        _ok(joined.length() > 20, "the answer shows real content")
        _ok(view.get_children().any(func(c: Node) -> bool:
                return c is Button and c.has_node("Center/Row/Icon") and "Listen" in c.get_node("Center/Row/Label").text
        ), "audio is offered as a button")

        # Answer the card and check the state moves.
        study._answer("good")
        await create_timer(0.3).timeout
        var deck = load("res://scripts/data/deck.gd").load("user://decks/quran")
        var studied: CardScript = deck.cards[0]
        _is(studied.state.status, "learning", "the answered card is learning")
        _is(studied.state.reps, 1, "the review is recorded")
        _is(studied.state.step, 1, "the card moved to the next step")

        study.closed.emit()
        await create_timer(0.4).timeout
        _ok(main.get_node_or_null("Home") != null, "closing the session returns home")

func _check_settings(main: Node) -> void:
        main._on_settings_pressed()
        await create_timer(0.4).timeout
        var settings: Control = main.get_node_or_null("Settings")
        _ok(settings != null, "settings opens")
        if settings == null:
                return
        var state: RichTextLabel = settings.get_node("Margin/Scroll/Column/GitHub/Padding/Box/State")
        _ok(state.text.length() > 0, "the GitHub section says where things stand")
        settings.closed.emit()
        await create_timer(0.4).timeout
        _ok(main.get_node_or_null("Home") != null, "closing settings returns home")

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
