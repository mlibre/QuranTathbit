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
	_test_broken_progress()
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

func _teardown() -> void:
	_remove_tree(ROOT)

func _remove_tree(path: String) -> void:
	if DirAccess.dir_exists_absolute(path):
		for entry in DirAccess.get_files_at(path):
			DirAccess.remove_absolute(path.path_join(entry))
		for entry in DirAccess.get_directories_at(path):
			_remove_tree(path.path_join(entry))
		DirAccess.remove_absolute(path)
