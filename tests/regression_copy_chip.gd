extends SceneTree
const CopyChipScript := preload("res://scripts/ui/copy_chip.gd")

## The copy a selection is owed, proven end to end. The report: on Android
## a chosen text offered no way to be carried away -- no system copy
## toolbar stands over ink the app draws itself, no keyboard hangs over a
## verse, and the engine's own label menu waits for a right-click a finger
## never makes. Here the pill stands over the very label holding the
## choice, the words arrive on the clipboard, the beat that follows says
## so, and the choice is let go. The pill leaves with the selection, a
## freed label never holds it, and a second choice made during the beat is
## answered with the same copy.

var _failures := 0

func _init() -> void:
        _fresh_install()
        var main = (load("res://scripts/main.gd") as GDScript).new()
        main.set_anchors_preset(Control.PRESET_FULL_RECT)
        root.add_child(main)
        await main.ready
        await create_timer(0.4).timeout

        var chip: CopyChipScript = main._copy_chip
        _ok(chip != null, "the app stands with its copy pill")
        if chip == null:
                _done()
                return
        _ok(not chip.visible, "the pill is nowhere at rest")

        await _check_copy_lifecycle(main, chip)
        _check_leaves_with_the_selection(chip)
        await _check_prunes_the_dead(chip)
        await _check_second_choice_during_the_beat(chip)

        _done()

func _done() -> void:
        if _failures > 0:
                print("copy_chip: %d FAILURE(S)" % _failures)
                quit(1)
        else:
                print("copy_chip: all checks passed")
                quit(0)

func _fresh_install() -> void:
        _remove_tree("user://decks")
        _remove_tree("user://settings.json")

## One whole life of a copy: the choice stands, the pill stands over it,
## the press carries the words and says so, the beat ends, and both the
## choice and the pill are let go.
func _check_copy_lifecycle(main, chip: CopyChipScript) -> void:
        var label := _stage_label("المتنُ المُختار", Vector2(100.0, 300.0))
        CopyChipScript.watch(label)
        await create_timer(0.2).timeout

        label.select_all()
        await create_timer(0.2).timeout
        _ok(chip.visible, "a choice brings the pill")
        _ok(chip.text == "Copy", "the pill offers the copy")
        # Over the label's own head: the pill's foot stands above the
        # label's crown, and its middle stands on the label's middle.
        _ok(
                chip.position.y + chip.size.y <= label.get_global_rect().position.y + 0.5,
                "the pill stands over the choice, not on it"
        )
        _ok(
                absf((chip.position.x + chip.size.x * 0.5) - label.get_global_rect().get_center().x)
                        <= 2.0,
                "the pill centres on the choice"
        )

        # A GDScript lambda captures its locals by value, so the words the
        # pill carries are collected through a box the lambda can reach.
        var heard := [""]
        chip.copied.connect(func(text: String) -> void: heard[0] = text)
        chip._copy()
        _is(heard[0], "المتنُ المُختار", "the chosen words are carried away")
        _ok(chip.text == "Copied", "the pill says the copy has landed")
        await create_timer(0.2).timeout
        _ok(chip.visible, "the beat that follows a copy keeps its place")

        await create_timer(1.2).timeout
        _ok(label.get_selection_from() < 0, "the choice is let go after the beat")
        await create_timer(0.2).timeout
        _ok(not chip.visible, "the pill leaves with the choice")
        label.free()

## A choice that goes without a copy takes the pill with it.
func _check_leaves_with_the_selection(chip: CopyChipScript) -> void:
        var label := _stage_label("واژه‌های گذرا", Vector2(80.0, 500.0))
        CopyChipScript.watch(label)
        label.select_all()
        chip._process(0.0)
        _ok(chip.visible, "a second choice brings the pill again")
        label.deselect()
        chip._process(0.0)
        _ok(not chip.visible, "the pill leaves when the choice leaves")
        label.free()

## A label that leaves the tree never holds the pill: the watch list is
## pruned by the pill's own next look.
func _check_prunes_the_dead(chip: CopyChipScript) -> void:
        var label := _stage_label("واژه‌های رفته", Vector2(60.0, 200.0))
        CopyChipScript.watch(label)
        label.select_all()
        label.free()
        await create_timer(0.15).timeout
        chip._process(0.0)
        var dead := 0
        for entry in CopyChipScript._watched:
                if not is_instance_valid(entry):
                        dead += 1
        _is(dead, 0, "a freed label is pruned from the watch")
        _ok(not chip.visible, "a freed label never shows the pill")

## A choice made while a copy's beat still plays: the first choice goes
## the way a hand moving to new words ends one choice and begins another,
## the pill follows the newer choice, answers it with the same copy, and
## the older beat's goodbye never steals the newer one's words.
func _check_second_choice_during_the_beat(chip: CopyChipScript) -> void:
        var first := _stage_label("واژه‌های یکم", Vector2(120.0, 250.0))
        var second := _stage_label("واژه‌های دوم", Vector2(120.0, 550.0))
        CopyChipScript.watch(first)
        CopyChipScript.watch(second)
        first.select_all()
        chip._process(0.0)
        var heard := [""]
        chip.copied.connect(func(text: String) -> void: heard[0] = text)
        chip._copy()
        _is(heard[0], "واژه‌های یکم", "the first choice is carried")
        # The beat is playing; the first choice goes and a second arrives.
        first.deselect()
        second.select_all()
        chip._process(0.0)
        _ok(chip.visible, "the pill stands over the second choice")
        chip._copy()
        _is(heard[0], "واژه‌های دوم", "the second choice is carried through the beat")
        await create_timer(1.4).timeout
        chip._process(0.0)
        _ok(not chip.visible, "the pill leaves after the second beat")
        first.free()
        second.free()

## A label on the stage, placed and sized by hand so the pill's geometry
## is measured against a known rect.
func _stage_label(words: String, at: Vector2) -> RichTextLabel:
        var label := RichTextLabel.new()
        label.text = words
        label.selection_enabled = true
        label.position = at
        label.size = Vector2(220.0, 60.0)
        root.add_child(label)
        return label

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
