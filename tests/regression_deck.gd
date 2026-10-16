extends SceneTree
const DeckScript := preload("res://scripts/data/deck.gd")
const CardScript := preload("res://scripts/data/card.gd")
const SchedulerScript := preload("res://scripts/data/scheduler.gd")

## The deck is folders and files: this suite builds a small deck on disk,
## reads it back, studies a card, saves, reloads, and checks the progress
## round-trips -- including a hand-corrupted progress file, which must be
## repaired rather than crash the app.

const ROOT := "user://test_deck"

var _failures := 0

func _init() -> void:
        _teardown()
        _write_deck()
        _test_load()
        _test_progress_round_trip()
        _test_progress_bytes_are_stable()
        _test_pace_round_trip()
        _test_choice_round_trip()
        _test_broken_progress()
        _test_script_classification()
        _teardown()
        if _failures > 0:
                print("deck: %d FAILURE(S)" % _failures)
                quit(1)
        else:
                print("deck: all checks passed")
                quit(0)

func _ok(condition: bool, what: String) -> void:
        if not condition:
                _failures += 1
                print("  FAIL: %s" % what)

func _is(got: Variant, expected: Variant, what: String) -> void:
        if got != expected:
                _failures += 1
                print("  FAIL: %s — got %s, expected %s" % [what, str(got), str(expected)])

func _write_deck() -> void:
        DirAccess.make_dir_recursive_absolute(ROOT)
        FileAccess.open(ROOT.path_join("deck.json"), FileAccess.WRITE).store_string(
                JSON.stringify({"format": 1, "name": "Test", "cards": ["001", "002"]})
        )
        for id in ["001", "002"]:
                var folder := ROOT.path_join(id)
                DirAccess.make_dir_recursive_absolute(folder)
                _write(folder.path_join("front.md"), "Question %s" % id)
                _write(folder.path_join("back.md"), "Answer %s\n\n![rec.mp3](rec.mp3)" % id)
                _write(folder.path_join("rec.mp3"), "not really audio")

func _write(path: String, text: String) -> void:
        var file := FileAccess.open(path, FileAccess.WRITE)
        file.store_string(text)
        file.close()

func _test_load() -> void:
        var deck: DeckScript = DeckScript.load(ROOT)
        _ok(deck != null, "a well-formed deck loads")
        if deck == null:
                return
        _is(deck.name, "Test", "the deck name comes from deck.json")
        _is(deck.cards.size(), 2, "both cards load")
        _is(deck.cards[0].id, "001", "cards keep their folder order")
        _is(deck.cards[0].front, "Question 001", "front.md is the question")
        _ok(deck.cards[0].back.contains("Answer 001"), "back.md is the answer")
        _ok(deck.cards[0].media.has("rec.mp3"), "media is indexed by name")
        _is(deck.cards[0].media_path("rec.mp3"), ROOT.path_join("001").path_join("rec.mp3"), "media resolves next to the markdown")
        _is(deck.cards[0].state.status, "new", "a card starts new")

        # A deck without deck.json is refused, not silently emptied.
        DirAccess.make_dir_recursive_absolute("user://test_empty")
        _ok(DeckScript.load("user://test_empty") == null, "a deck with no deck.json fails loudly")
        _write("user://test_empty".path_join("deck.json"), '{"format": 99}')
        _ok(DeckScript.load("user://test_empty") == null, "an unknown deck format fails loudly")
        DirAccess.remove_absolute("user://test_empty".path_join("deck.json"))
        DirAccess.remove_absolute("user://test_empty")

func _test_progress_round_trip() -> void:
        var deck: DeckScript = DeckScript.load(ROOT)
        var now := 1792000000
        deck.answer(deck.cards[0], "good", now)
        _ok(deck.dirty, "answering marks the deck dirty")
        _ok(deck.save_progress(), "progress saves")
        var reloaded: DeckScript = DeckScript.load(ROOT)
        _is(reloaded.cards[0].state.status, "learning", "the answered card keeps its state")
        _is(reloaded.cards[0].state.reps, 1, "the review is counted")
        _is(reloaded.cards[1].state.status, "new", "the untouched card stays new")
        # Untouched cards stay out of the file entirely.
        var raw := FileAccess.get_file_as_string(ROOT.path_join("progress.json"))
        _ok(not raw.contains("\"002\""), "untouched cards are not written to progress.json")

## A progress file that changes its own bytes between one save and the
## next -- with no study in between -- is a file that cannot be compared,
## and sync compares bytes: JSON reads every int back as a float, so a
## reload-and-save used to rewrite "reps": 1 as "reps": 1.0 and announce
## a change that was only formatting. The deck writes whole floats back
## as the ints they were; save, load, save again: identical bytes.
func _test_progress_bytes_are_stable() -> void:
        var deck: DeckScript = DeckScript.load(ROOT)
        deck.answer(deck.cards[0], "good", 1792000100)
        _ok(deck.save_progress(), "progress saves")
        var first := FileAccess.get_file_as_bytes(ROOT.path_join("progress.json"))
        var reloaded: DeckScript = DeckScript.load(ROOT)
        _ok(reloaded.save_progress(), "progress saves again after a reload")
        var second := FileAccess.get_file_as_bytes(ROOT.path_join("progress.json"))
        _is(second, first, "progress bytes do not change on a reload without study")
        var raw := FileAccess.get_file_as_string(ROOT.path_join("progress.json"))
        _ok(not raw.contains(".0"), "whole numbers are written as ints, never as floats")
        _ok(raw.contains("\"ease\": 2.5"), "a true fraction keeps its decimals")

## The reader's own pace rides the progress file, where sync carries it to
## every device the deck reaches: a deck whose file never said one says
## none (-1), a chosen one round-trips with its moment, and nonsense never
## passes for a number.
func _test_pace_round_trip() -> void:
        var deck: DeckScript = DeckScript.load(ROOT)
        _is(deck.new_per_day, -1, "a deck whose progress never said a pace says none")
        deck.new_per_day = 12
        deck.new_per_day_mod = 1792000200
        _ok(deck.save_progress(), "progress saves with the pace")
        var reloaded: DeckScript = DeckScript.load(ROOT)
        _is(reloaded.new_per_day, 12, "the chosen pace rides the progress file")
        _is(reloaded.new_per_day_mod, 1792000200, "and so does the moment it was chosen")
        var raw := FileAccess.get_file_as_string(ROOT.path_join("progress.json"))
        _ok(raw.contains("\"new_per_day\": 12"), "the pace is written where sync reads it")
        _write(ROOT.path_join("progress.json"), JSON.stringify({
                "format": 1, "cards": {}, "new_per_day": "twenty",
        }) + "\n")
        var broken: DeckScript = DeckScript.load(ROOT)
        _is(broken.new_per_day, -1, "a pace that is not a number is not a pace")

## The face the verses wear and the tongue the app speaks ride the progress
## file beside the pace, and read with the same honesty: a chosen word
## round-trips with its moment, a value of the wrong shape is not a choice,
## and a file that never said either says nothing.
func _test_choice_round_trip() -> void:
        var deck: DeckScript = DeckScript.load(ROOT)
        _is(deck.ayah_font, "", "a deck whose progress never said a face says none")
        _is(deck.ui_lang, "", "a deck whose progress never said a tongue says none")
        deck.ayah_font = "noto_naskh"
        deck.ayah_font_mod = 1792000300
        deck.ui_lang = "fa"
        deck.ui_lang_mod = 1792000301
        _ok(deck.save_progress(), "progress saves with the choices")
        var reloaded: DeckScript = DeckScript.load(ROOT)
        _is(reloaded.ayah_font, "noto_naskh", "the chosen face rides the progress file")
        _is(reloaded.ayah_font_mod, 1792000300, "and so does the moment it was chosen")
        _is(reloaded.ui_lang, "fa", "the chosen tongue rides the progress file")
        _is(reloaded.ui_lang_mod, 1792000301, "with its own moment beside it")
        var raw := FileAccess.get_file_as_string(ROOT.path_join("progress.json"))
        _ok(raw.contains("\"ayah_font\": \"noto_naskh\""), "the face is written where sync reads it")
        _ok(raw.contains("\"ui_lang\": \"fa\""), "the tongue is written where sync reads it")
        _write(ROOT.path_join("progress.json"), JSON.stringify({
                "format": 1, "cards": {}, "ayah_font": 12, "ui_lang": true,
        }) + "\n")
        var broken: DeckScript = DeckScript.load(ROOT)
        _is(broken.ayah_font, "", "a face that is not a word is not a face")
        _is(broken.ui_lang, "", "a tongue that is not a word is not a tongue")

func _test_broken_progress() -> void:
        _write(ROOT.path_join("progress.json"), "{ not json at all")
        var deck: DeckScript = DeckScript.load(ROOT)
        _ok(deck != null, "a broken progress file does not stop the deck")
        if deck != null:
                _is(deck.cards[0].state.status, "new", "a broken progress file starts the card fresh")
        # A progress entry with missing keys is repaired, not fatal.
        _write(ROOT.path_join("progress.json"), JSON.stringify({"format": 1, "cards": {"001": {"status": "review"}}}))
        var repaired: DeckScript = DeckScript.load(ROOT)
        _is(repaired.cards[0].state.status, "review", "a partial entry keeps what it has")
        _is(repaired.cards[0].state.ease, SchedulerScript.INITIAL_EASE, "a missing ease is repaired")
        _is(repaired.cards[0].state.ivl, 0, "a missing interval is repaired")

## Which typeface a line is dressed in is decided by its script, and the
## tell between a verse and its translation was once wrong three times in
## the real deck: a bare Persian line with no Persian-only letter read as
## Arabic, and wore Amiri at scripture's size. These are the lines that
## decided it.
func _test_script_classification() -> void:
        var theme := load("res://scripts/ui/theme.gd")
        # A vocalised verse: the mushaf's own voice.
        _is(theme.script_of("بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ"), "arabic",
                "a vocalised verse is Arabic")
        # A bare line with no tell either way: in this deck, a translation.
        _is(theme.script_of("بنام خداوند بخشنده مهربان"), "persian",
                "a bare shared-script line is the Persian translation")
        # A Persian letter settles it, even with Arabic words in the line.
        _is(theme.script_of("حمد و سپاس مخصوص خداوندى است که پروردگار جهانیان است"), "persian",
                "a line with Persian letters is Persian")
        _is(theme.script_of("سورة البقرة و می‌شود"), "persian",
                "Persian letters win over Arabic ones in the same line")
        # References are Arabic by construction, whatever their letters carry.
        _is(theme.reference_script("قريش - ۱"), "arabic",
                "a reference without a script tell is Arabic")
        _is(theme.reference_script("الفاتحة - ۱،۲"), "arabic",
                "a reference with Arabic letters is Arabic")
        _is(theme.reference_script("001001.mp3"), "plain",
                "a Latin reference is plain")
        _is(theme.script_of("001001.mp3"), "plain",
                "a Latin body line is plain")

func _teardown() -> void:
        _remove_tree(ROOT)

func _remove_tree(path: String) -> void:
        if DirAccess.dir_exists_absolute(path):
                for entry in DirAccess.get_files_at(path):
                        DirAccess.remove_absolute(path.path_join(entry))
                for entry in DirAccess.get_directories_at(path):
                        _remove_tree(path.path_join(entry))
                DirAccess.remove_absolute(path)
