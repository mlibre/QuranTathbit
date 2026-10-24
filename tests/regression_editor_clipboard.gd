extends SceneTree
const CardEditorScript := preload("res://scripts/ui/card_editor.gd")
const ThemeScript := preload("res://scripts/ui/theme.gd")

## The page's clipboard, proven end to end. The report: Ctrl+C and Ctrl+V
## did nothing on the edit-card page. The paste bridge knew only settings'
## LineEdit fields -- the editor writes in the app's own right-reading
## fields, whose input engine is a TextEdit, and the bridge let the paste
## fall on the floor. Here the page's paste lands in the field the reader
## is writing in: a verse keeps the shape the clipboard carried, a
## reference takes its first line, a selection steps aside, and a cut lets
## the chosen words go. The deck's own stray star is pinned too -- the
## patch that carries an old install across -- and the walk that tells the
## page "paper" or "working parts" for the browser's own menu.

var _failures := 0

func _init() -> void:
        _fresh_install()
        var main = (load("res://scripts/main.gd") as GDScript).new()
        main.set_anchors_preset(Control.PRESET_FULL_RECT)
        root.add_child(main)
        await main.ready
        await create_timer(0.4).timeout

        await _check_deck_patch(main)
        await _check_editor_paste(main)
        _check_line_edit(main)
        _check_menu_ground(main)

        if _failures > 0:
                print("editor_clipboard: %d FAILURE(S)" % _failures)
                quit(1)
        else:
                print("editor_clipboard: all checks passed")
                quit(0)

func _fresh_install() -> void:
        _remove_tree("user://decks")
        _remove_tree("user://settings.json")

## The basmala card's stray leading star: a fresh install never sees it
## (the bundled deck no longer carries it), an old install is carried
## across by the patch, and a card the reader has edited is theirs -- the
## patch will not touch it.
func _check_deck_patch(main) -> void:
        _ok(main._deck != null and main._deck.cards.size() > 6, "the deck is standing")
        if main._deck == null or main._deck.cards.size() <= 6:
                return
        var card = main._deck.cards[6]
        _ok(card.front.strip_edges() == "البقرة - ۱", "the seventh card is the basmala card")
        _ok(not card.back.begins_with("*"), "the basmala no longer opens with a stray star")
        _ok(
                card.back.contains("الرَّحیمِ * الم") and card.back.contains("مهربان* الم"),
                "the stars the author kept stay kept"
        )
        var patch: Dictionary = main.DECK_PATCHES[0]
        var target := "user://decks/quran".path_join(str(patch["path"]))
        var file := FileAccess.open(target, FileAccess.WRITE)
        file.store_string(str(patch["was"]))
        file.close()
        main._patch_deck()
        _is(
                FileAccess.get_file_as_string(target),
                str(patch["now"]),
                "an old install's stray star is patched away"
        )
        file = FileAccess.open(target, FileAccess.WRITE)
        file.store_string(str(patch["was"]) + "\nan author's own line\n")
        file.close()
        main._patch_deck()
        _is(
                FileAccess.get_file_as_string(target),
                str(patch["was"]) + "\nan author's own line\n",
                "a card the reader edited is theirs, not ours"
        )
        file = FileAccess.open(target, FileAccess.WRITE)
        file.store_string(str(patch["now"]))
        file.close()

## The exact report: a paste into the editor's fields. The page hands the
## text to the app; the field the reader is writing in answers.
func _check_editor_paste(main) -> void:
        var card = main._deck.cards[6]
        var editor = CardEditorScript.new(card, 1.0)
        root.add_child(editor)
        await create_timer(0.2).timeout

        # The question is a one-line reference; the field holds focus from
        # the page's own opening, and a multi-line clipboard gives it its
        # first line alone.
        main._on_web_paste(["سورهٔ تازه\nخطِ دوم\n"])
        _ok(
                editor._front.get_text().ends_with("سورهٔ تازه"),
                "a reference takes the clipboard's first line"
        )
        _ok(
                not editor._front.get_text().contains("خطِ دوم"),
                "a reference never takes the clipboard's second line"
        )

        # The answer is a verse: the shape the clipboard carried is the
        # shape that lands.
        editor._back.take_focus()
        main._on_web_paste(["آیهٔ نخست\nآیهٔ دوم\n"])
        _ok(
                editor._back.get_text().contains("آیهٔ نخست\nآیهٔ دوم"),
                "a verse keeps the shape the clipboard carried"
        )

        # The chosen words step aside for what arrives.
        var back_source := editor._back.get_node("Source") as TextEdit
        back_source.select_all()
        main._on_web_paste(["متنِ جایگزین"])
        _is(
                editor._back.get_text().strip_edges(),
                "متنِ جایگزین",
                "the chosen words step aside for what arrives"
        )

        # A cut's other half: the words simply go.
        var before: String = editor._back.get_text()
        back_source.select(0, 0, 0, 4)
        main._on_web_cut([])
        _is(
                editor._back.get_text().length(),
                before.length() - 4,
                "a cut lets the chosen words go"
        )
        editor.visible = false

## The settings fields keep their own half of the promise: one line for a
## selection, and the page told what a Ctrl+C would carry.
func _check_line_edit(main) -> void:
        var field := LineEdit.new()
        root.add_child(field)
        field.grab_focus()
        field.text = "توکنِ کهنه"
        field.select_all()
        main._on_web_paste(["ghp_fresh\nsecond line"])
        _is(field.text, "ghp_fresh", "a settings field takes one line for its selection")
        field.select(0, 4)
        main._on_web_cut([])
        _is(field.text, "fresh", "a settings field lets its cut go")

        # A bridge-delivered paste or cut speaks the field's own signal, the
        # way a keystroke does: the shelf's narrowing and the pills listen
        # to text_changed, so what the page hands over must narrow the shelf
        # the same typed letters do. An edit that says nothing leaves the
        # shelf wide while the field holds a question.
        var said := {"changed": 0}
        field.text_changed.connect(func(_t: String) -> void: said["changed"] += 1)
        field.text = "abXd".replace("X", "c")
        field.caret_column = 2
        var heard: int = said["changed"]
        main._on_web_paste(["X"])
        _is(field.text, "abXcd", "a web paste lands at the caret")
        _ok(said["changed"] > heard, "a web paste says text_changed")
        heard = said["changed"]
        field.select(1, 3)
        main._on_web_cut([])
        _is(field.text, "acd", "the web cut takes the chosen words")
        _ok(said["changed"] > heard, "a web cut says text_changed")

        # The keyboard's own cut -- the physical hand's Ctrl+X on a machine
        # -- speaks the same voice.
        heard = said["changed"]
        field.text = "word"
        field.select_all()
        ThemeScript._line_delete_selection(field)
        _is(field.text, "", "the keyboard's cut empties the field")
        _ok(said["changed"] > heard, "the keyboard's cut says text_changed")

        field.text = "abcd"
        field.select(0, 2)
        main._publish_clipboard()
        _is(main._clip_state, "1ab", "the page is told the words a Ctrl+C means")
        field.deselect()
        main._publish_clipboard()
        _is(main._clip_state, "1", "the page is told when the choosing ends")
        field.free()

## The walk that answers "paper or working parts" for the browser's own
## menu: a button is the app's ground, a writing field is, and the paper
## around them is not. Measured on a stage where nothing else stands, so
## the answer is the walk's own and not the page layout's.
func _check_menu_ground(main) -> void:
        var stage := Control.new()
        stage.set_anchors_preset(Control.PRESET_FULL_RECT)
        root.add_child(stage)
        for child in root.get_children():
                if child is Control and child != stage:
                        (child as Control).visible = false
        var button := Button.new()
        button.position = Vector2(100.0, 100.0)
        button.size = Vector2(120.0, 40.0)
        stage.add_child(button)
        var entry := LineEdit.new()
        entry.position = Vector2(300.0, 300.0)
        entry.size = Vector2(200.0, 36.0)
        stage.add_child(entry)
        _ok(main._interactive_under(root, Vector2(160.0, 120.0)), "a button is the app's own ground")
        _ok(main._interactive_under(root, Vector2(400.0, 318.0)), "a writing field is the app's own ground")
        _ok(
                not main._interactive_under(root, Vector2(600.0, 500.0)),
                "the paper around them is the browser's own"
        )

func _ok(condition: bool, what: String) -> void:
        if condition:
                print("  ok   %s" % what)
        else:
                _failures += 1
                print("  FAIL %s" % what)

func _is(got, want, what: String) -> void:
        _ok(str(got) == str(want), "%s (got %s, want %s)" % [what, str(got), str(want)])

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
