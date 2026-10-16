extends SceneTree
const DeckScript := preload("res://scripts/data/deck.gd")
const DeckZipScript := preload("res://scripts/data/deck_zip.gd")
const SchedulerScript := preload("res://scripts/data/scheduler.gd")

## The deck as one file: this suite builds small decks on disk, packs them
## into zips, and joins them back into other decks -- holding the engine to
## the same laws the sync engine keeps. Progress merges card by card (the
## better-informed entry wins), the travelling choices merge by their own
## moments, content files land only where a deck lacks them, editor
## metadata never travels, and a file that is not this app's backup is
## refused by name, not adopted by guesswork.

const ROOT := "user://test_zip_deck"
const OTHER := "user://test_zip_other"
const OUT := "user://test_zip_out"

var _failures := 0

func _init() -> void:
        _teardown()
        _write_deck(ROOT, ["001", "002"])
        _test_destination_dirs()
        _test_export()
        _test_find_backups()
        _test_fresh_arrival()
        _test_merge_precedence()
        _test_choices_by_moment()
        _test_additive_content()
        _test_wrapped_zip()
        _test_own_export_is_neutral()
        _test_refuses_what_it_is_not()
        _test_zip_slip()
        _teardown()
        if _failures > 0:
                print("zip: %d FAILURE(S)" % _failures)
                quit(1)
        else:
                print("zip: all checks passed")
                quit(0)

func _ok(condition: bool, what: String) -> void:
        if not condition:
                _failures += 1
                print("  FAIL: %s" % what)

func _is(got: Variant, expected: Variant, what: String) -> void:
        if got != expected:
                _failures += 1
                print("  FAIL: %s — got %s, expected %s" % [what, str(got), str(expected)])

# --- fixtures ---------------------------------------------------------------------

## A small deck with a studied card, a resting card, the travelling
## choices, and the metadata files a real deck folder collects -- so the
## export has something to refuse and the import has something to carry.
func _write_deck(where: String, ids: Array, progress: Dictionary = {}, choices: Dictionary = {}) -> void:
        DirAccess.make_dir_recursive_absolute(where)
        var file := FileAccess.open(where.path_join("deck.json"), FileAccess.WRITE)
        file.store_string(JSON.stringify({"format": 1, "name": "Test", "cards": ids}))
        file.close()
        for id in ids:
                var folder := where.path_join(id)
                DirAccess.make_dir_recursive_absolute(folder)
                _write(folder.path_join("front.md"), "Question %s" % id)
                _write(folder.path_join("back.md"), "Answer %s\n\n![rec.mp3](rec.mp3)" % id)
                _write(folder.path_join("rec.mp3"), "not really audio %s" % id)
                # The sidecars a real deck folder gathers around its media.
                _write(folder.path_join("rec.mp3.import"), "editor metadata")
                _write(folder.path_join("rec.mp3.uid"), "editor metadata")
        var doc: Dictionary = {"format": 1, "cards": progress}
        for key in choices.keys():
                doc[key] = choices[key]["value"]
                doc[key + "_mod"] = int(choices[key]["mod"])
        if not progress.is_empty() or not choices.is_empty():
                _write(where.path_join("progress.json"), JSON.stringify(doc, "\t") + "\n")

func _write(path: String, text: String) -> void:
        var file := FileAccess.open(path, FileAccess.WRITE)
        file.store_string(text)
        file.close()

## A card's state, in the shape the scheduler writes, with only the fields
## this suite's story needs said out loud.
func _state(reps: int, mod: int, status := "review") -> Dictionary:
        var state := SchedulerScript.new_state()
        state["status"] = status
        state["reps"] = reps
        state["mod"] = mod
        return state

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

func _teardown() -> void:
        for path in [ROOT, OTHER, OUT]:
                _remove_tree(path)
        _remove_tree("user://backups")
        _remove_tree(OUT.path_join("../evil.txt"))

func _entries_of(zip_path: String) -> Array:
        var reader := ZIPReader.new()
        var err := reader.open(zip_path)
        if err != OK:
                return []
        var files: Array = []
        for entry in reader.get_files():
                if not entry.ends_with("/"):
                        files.append(entry)
        reader.close()
        return files

# --- the places a backup lives -------------------------------------------------------

func _test_destination_dirs() -> void:
        var dirs := DeckZipScript.destination_dirs()
        _ok(dirs.size() >= 1, "there is always somewhere a backup can land")
        var seen: Dictionary = {}
        for place in dirs:
                var path := str(place["path"])
                _ok(not path.is_empty(), "no candidate is ever an empty path")
                _ok(not seen.has(path), "no candidate is named twice")
                seen[path] = true
        _is(str(dirs[dirs.size() - 1]["path"]), "user://backups",
                "the app's own corner is the last resort, always there")

func _test_export() -> void:
        DirAccess.make_dir_recursive_absolute(OUT)
        _write_deck(ROOT, ["001", "002"], {"001": _state(1, 1790000100)}, {})
        var target := OUT.path_join("plain.zip")
        var result: Dictionary = DeckZipScript.export_deck(ROOT, target)
        _ok(bool(result.get("ok", false)), "a healthy deck exports")
        _ok(int(result.get("files", 0)) == 8, "both cards' words, their media, the deck and its progress ride along (got %d)" % int(result.get("files", 0)))
        var files := _entries_of(target)
        _ok(files.has("deck.json"), "the deck's own word for itself rides")
        _ok(files.has("progress.json"), "the progress rides")
        _ok(files.has("001/front.md"), "a card's question rides")
        _ok(files.has("002/rec.mp3"), "a card's media rides")
        for entry in files:
                _ok(not DeckZipScript._is_junk_path(entry),
                        "editor metadata never rides (%s)" % entry)
        var broken: Dictionary = DeckZipScript.export_deck("user://test_zip_missing", target)
        _ok(not bool(broken.get("ok", false)), "exporting a folder that is not a deck refuses")
        _is(str(broken.get("error", "")), "not_a_deck", "and says why")

func _test_find_backups() -> void:
        DirAccess.make_dir_recursive_absolute("user://backups")
        _write("user://backups".path_join("qurantathbit-deck-2026-01-01.zip"), "one")
        _write("user://backups".path_join("older.zip"), "two")
        _write("user://backups".path_join("notes.txt"), "not a zip")
        var found: Array = DeckZipScript.find_backups()
        var names: Array = []
        for entry in found:
                names.append(str(entry["name"]))
                _ok(str(entry["path"]).ends_with(".zip"), "only zips are offered")
                _ok(typeof(entry["mtime"]) == TYPE_FLOAT or typeof(entry["mtime"]) == TYPE_INT,
                        "each file answers with its own moment")
        _ok(names.has("qurantathbit-deck-2026-01-01.zip"), "the app's own backup is found")
        _ok(names.has("older.zip"), "a renamed backup is still offered")
        _ok(not names.has("notes.txt"), "a text file is not a backup")
        for entry in found:
                DirAccess.remove_absolute(str(entry["path"]))

# --- the joins -----------------------------------------------------------------------

## The new-device story: a deck that holds nothing of its own receives a
## whole backup, and everything arrives -- the name, the cards, the
## learning, the choices.
func _test_fresh_arrival() -> void:
        var progress := {"001": _state(4, 1790000100), "002": _state(1, 1790000200)}
        var choices := {
                "new_per_day": {"value": 7, "mod": 1790000050},
                "ayah_font": {"value": "amiri", "mod": 1790000060},
        }
        _write_deck(ROOT, ["001", "002"], progress, choices)
        DirAccess.make_dir_recursive_absolute(OUT)
        var target := OUT.path_join("fresh.zip")
        _ok(bool(DeckZipScript.export_deck(ROOT, target).get("ok", false)), "the deck packs")

        _write_deck(OTHER, ["001", "002"])  # a twin with no history of its own
        var result: Dictionary = DeckZipScript.import_deck(OTHER, target)
        _ok(bool(result.get("ok", false)), "a backup joins a fresh deck")
        _is(int(result.get("merged", 0)), 2, "both cards' learning arrives")
        _is(int(result.get("cards_new", 0)), 0, "no cards are new to a twin deck")
        var deck: DeckScript = DeckScript.load(OTHER)
        _ok(deck != null, "the joined deck still loads")
        if deck == null:
                return
        _is(deck.name, "Test", "the deck's own name survives the trip")
        _is(deck.cards.size(), 2, "both cards survive the trip")
        _is(deck.cards[0].state.reps, 4, "the learning survives the trip")
        _is(deck.new_per_day, 7, "the day's pace travels with it")
        _is(deck.ayah_font, "amiri", "the verses' face travels with it")

## The two-devices story: both studied apart, and the join keeps the
## better-informed word on every card -- more reviews wins, a later answer
## breaks a tie, and a card only one side ever touched simply arrives.
func _test_merge_precedence() -> void:
        _teardown()
        _write_deck(ROOT, ["001", "002", "003"],
                {"001": _state(5, 1790001000), "002": _state(2, 1790000100)},
                {})
        DirAccess.make_dir_recursive_absolute(OUT)
        var target := OUT.path_join("merge.zip")
        _ok(bool(DeckZipScript.export_deck(ROOT, target).get("ok", false)), "the fuller deck packs")

        _write_deck(OTHER, ["001", "002", "003"],
                {"001": _state(3, 1790009000), "002": _state(4, 1790009500), "003": _state(1, 1790009900)},
                {})
        var result: Dictionary = DeckZipScript.import_deck(OTHER, target)
        _ok(bool(result.get("ok", false)), "the join runs")
        _is(int(result.get("merged", 0)), 1, "only the card the backup knew better arrives (got %d)" % int(result.get("merged", 0)))
        var deck: DeckScript = DeckScript.load(OTHER)
        if deck == null:
                _ok(false, "the merged deck loads")
                return
        _is(deck.cards[0].state.reps, 5, "the backup's fuller history on 001 arrives")
        _is(deck.cards[1].state.reps, 4, "local's fuller history on 002 stays")
        _is(deck.cards[2].state.reps, 1, "a card the backup never met keeps local's word")

## The choices merge by their own moments, the way the sync engine merges
## them: a later choice wins wherever it was made, an earlier one does not
## undo a newer word here, and noise is not a choice at all.
func _test_choices_by_moment() -> void:
        _teardown()
        # ROOT is packed into the zip, so it carries the arriving choices;
        # OTHER is the importer, so it carries the standing ones.
        var arriving := {
                "new_per_day": {"value": 9, "mod": 1790008000},
                "ayah_font": {"value": "noto_naskh", "mod": 1790009000},
                "ui_lang": {"value": "ar", "mod": 1790009800},
        }
        _write_deck(ROOT, ["001"], {"001": _state(1, 1790000100)}, arriving)
        DirAccess.make_dir_recursive_absolute(OUT)
        var target := OUT.path_join("choices.zip")
        _ok(bool(DeckZipScript.export_deck(ROOT, target).get("ok", false)), "the deck packs")

        var standing := {
                "new_per_day": {"value": 20, "mod": 1790009500},
                "ayah_font": {"value": "amiri", "mod": 1790001000},
                "ui_lang": {"value": "fa", "mod": 1790000500},
        }
        _write_deck(OTHER, ["001"], {}, standing)
        var result: Dictionary = DeckZipScript.import_deck(OTHER, target)
        _ok(bool(result.get("ok", false)), "the join runs")
        _is(int(result.get("choices", 0)), 2, "only the later choices move (got %d)" % int(result.get("choices", 0)))
        var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OTHER.path_join("progress.json")))
        _is(int(doc["new_per_day"]), 20, "the local pace stands when it was said later")
        _is(str(doc["ayah_font"]), "noto_naskh", "the backup's later face arrives")
        _is(str(doc["ui_lang"]), "ar", "the backup's later tongue arrives")

## A join adds, never overwrites: a file the deck already has keeps its own
## word (the tie sync also keeps), a file the deck lacks arrives, and a
## whole card the deck never met joins as a card -- counted as one, not as
## three files.
func _test_additive_content() -> void:
        _teardown()
        _write_deck(ROOT, ["001", "002"],
                {"001": _state(1, 1790000100)},
                {"new_per_day": {"value": 5, "mod": 1790000050}})
        # The backup's 001 says something different from the local 001.
        _write(ROOT.path_join("001/front.md"), "Question 001 (edited on the other device)")
        DirAccess.make_dir_recursive_absolute(OUT)
        var target := OUT.path_join("additive.zip")
        _ok(bool(DeckZipScript.export_deck(ROOT, target).get("ok", false)), "the deck packs")

        _write_deck(OTHER, ["001", "002"])
        DirAccess.remove_absolute(OTHER.path_join("001/rec.mp3"))  # local lacks this one
        var result: Dictionary = DeckZipScript.import_deck(OTHER, target)
        _ok(bool(result.get("ok", false)), "the join runs")
        _is(int(result.get("cards_new", 0)), 0, "no unknown cards in this story")
        _is(FileAccess.get_file_as_string(OTHER.path_join("001/front.md")), "Question 001",
                "a file the deck already has keeps its own word")
        _ok(FileAccess.file_exists(OTHER.path_join("001/rec.mp3")),
                "a file the deck lacks arrives")

        # A whole card the deck never met.
        _teardown()
        DirAccess.make_dir_recursive_absolute(OUT)
        _write_deck(ROOT, ["001", "002", "003"], {}, {})
        _ok(bool(DeckZipScript.export_deck(ROOT, target).get("ok", false)), "the fuller deck packs")
        _write_deck(OTHER, ["001", "002"], {}, {})
        var joined: Dictionary = DeckZipScript.import_deck(OTHER, target)
        _is(int(joined.get("cards_new", 0)), 1, "one new card is counted once, not per file (got %d)" % int(joined.get("cards_new", 0)))
        var deck: DeckScript = DeckScript.load(OTHER)
        _ok(deck != null and deck.cards.size() == 3, "the deck now holds the card that arrived")

## A zip whose whole deck sits under one wrapping folder -- the way many
## tools zip a folder instead of its contents -- is understood, as long as
## exactly one folder speaks for the deck.
func _test_wrapped_zip() -> void:
        _teardown()
        _write_deck(ROOT, ["001"], {"001": _state(2, 1790000100)},
                {"ui_lang": {"value": "fa", "mod": 1790000050}})
        DirAccess.make_dir_recursive_absolute(OUT)
        var target := OUT.path_join("plain.zip")
        _ok(bool(DeckZipScript.export_deck(ROOT, target).get("ok", false)), "the deck packs")

        # The same archive, re-said under one wrapping folder.
        var wrapped := OUT.path_join("wrapped.zip")
        var reader := ZIPReader.new()
        reader.open(target)
        var packer := ZIPPacker.new()
        packer.open(wrapped, ZIPPacker.ZipAppend.APPEND_CREATE)
        for entry in reader.get_files():
                if entry.ends_with("/"):
                        continue
                packer.start_file("quran/" + entry)
                packer.write_file(reader.read_file(entry))
                packer.close_file()
        reader.close()
        packer.close()

        _write_deck(OTHER, ["001"], {}, {})
        var result: Dictionary = DeckZipScript.import_deck(OTHER, wrapped)
        _ok(bool(result.get("ok", false)), "a wrapped backup joins")
        _is(int(result.get("merged", 0)), 1, "and carries the same learning")
        var deck: DeckScript = DeckScript.load(OTHER)
        _ok(deck != null and deck.cards.size() == 1, "the wrapped deck still loads as one card")

## Importing a deck's own export changes nothing -- the join finds nothing
## to move, and the progress file is not even rewritten, because sync and
## every other byte-comparing eye read it after.
func _test_own_export_is_neutral() -> void:
        _teardown()
        var progress := {"001": _state(3, 1790000100), "002": _state(6, 1790000200)}
        _write_deck(ROOT, ["001", "002"], progress,
                {"ayah_font": {"value": "amiri_quran", "mod": 1790000050}})
        DirAccess.make_dir_recursive_absolute(OUT)
        var target := OUT.path_join("self.zip")
        _ok(bool(DeckZipScript.export_deck(ROOT, target).get("ok", false)), "the deck packs")
        var before := FileAccess.get_file_as_bytes(ROOT.path_join("progress.json"))
        var result: Dictionary = DeckZipScript.import_deck(ROOT, target)
        _ok(bool(result.get("ok", false)), "the join runs")
        _is(int(result.get("merged", 0)), 0, "nothing moves")
        _is(int(result.get("added", 0)), 0, "nothing is added")
        _is(int(result.get("choices", 0)), 0, "no choice moves")
        var after := FileAccess.get_file_as_bytes(ROOT.path_join("progress.json"))
        _ok(before == after, "an unmoved progress file is not even rewritten")

# --- the refusals ---------------------------------------------------------------------

func _test_refuses_what_it_is_not() -> void:
        _write_deck(ROOT, ["001"], {}, {})
        DirAccess.make_dir_recursive_absolute(OUT)

        # A zip that is not a deck at all.
        var stranger := OUT.path_join("stranger.zip")
        var packer := ZIPPacker.new()
        packer.open(stranger, ZIPPacker.ZipAppend.APPEND_CREATE)
        packer.start_file("letter.txt")
        packer.write_file("hello".to_utf8_buffer())
        packer.close_file()
        packer.close()
        _is(str(DeckZipScript.import_deck(ROOT, stranger).get("error", "")), "not_a_deck",
                "a zip with no deck.json is refused by name")

        # A deck from a future this app does not speak.
        var future := OUT.path_join("future.zip")
        packer = ZIPPacker.new()
        packer.open(future, ZIPPacker.ZipAppend.APPEND_CREATE)
        packer.start_file("deck.json")
        packer.write_file('{"format": 99}'.to_utf8_buffer())
        packer.close_file()
        packer.close()
        _is(str(DeckZipScript.import_deck(ROOT, future).get("error", "")), "not_a_deck",
                "an unknown deck format is refused by name")

        # Two folders each claiming to be the deck.
        var twins := OUT.path_join("twins.zip")
        packer = ZIPPacker.new()
        packer.open(twins, ZIPPacker.ZipAppend.APPEND_CREATE)
        for folder in ["a", "b"]:
                packer.start_file(folder + "/deck.json")
                packer.write_file('{"format": 1}'.to_utf8_buffer())
                packer.close_file()
        packer.close()
        _is(str(DeckZipScript.import_deck(ROOT, twins).get("error", "")), "not_a_deck",
                "two decks wearing one coat are refused")

        # Not a zip at all.
        var garbage := OUT.path_join("garbage.zip")
        _write(garbage, "this is not a zip file")
        _is(str(DeckZipScript.import_deck(ROOT, garbage).get("error", "")), "unreadable",
                "a file that is not an archive says so")

        # A missing file.
        _is(str(DeckZipScript.import_deck(ROOT, OUT.path_join("ghost.zip")).get("error", "")), "unreadable",
                "a file that is not there says so")

        # Nothing was written by any refusal.
        _ok(not FileAccess.file_exists(ROOT.path_join("letter.txt")),
                "a refused backup leaves nothing behind")

## A path an archive hands over is only a path if it stays inside the deck:
## a climb out with ".." is declined, and the deck never even notices.
func _test_zip_slip() -> void:
        _teardown()
        _write_deck(ROOT, ["001"], {}, {})
        DirAccess.make_dir_recursive_absolute(OUT)
        var target := OUT.path_join("slip.zip")
        var packer := ZIPPacker.new()
        packer.open(target, ZIPPacker.ZipAppend.APPEND_CREATE)
        packer.start_file("deck.json")
        packer.write_file('{"format": 1, "name": "Test", "cards": ["001"]}'.to_utf8_buffer())
        packer.close_file()
        packer.start_file("ok.txt")
        packer.write_file("fine".to_utf8_buffer())
        packer.close_file()
        packer.start_file("../evil.txt")
        packer.write_file("bad".to_utf8_buffer())
        packer.close_file()
        packer.close()
        var result: Dictionary = DeckZipScript.import_deck(ROOT, target)
        _ok(bool(result.get("ok", false)), "the join runs")
        _ok(FileAccess.file_exists(ROOT.path_join("ok.txt")), "an honest file lands")
        _ok(not FileAccess.file_exists(OUT.path_join("evil.txt")),
                "a climb out of the deck is declined")
        _ok(not FileAccess.file_exists("user://evil.txt"),
                "and reaches nowhere else either")
        DirAccess.remove_absolute(ROOT.path_join("ok.txt"))
