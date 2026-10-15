extends SceneTree
const SyncScript := preload("res://scripts/net/github_sync.gd")
const AuthScript := preload("res://scripts/net/github_auth.gd")

## Sync is the promise the app makes: two devices can study offline and
## both keep their work. These tests drive the sync engine against a fake HTTP
## client that behaves like the slice of GitHub's API the app uses, and
## check the three-way merge, file by file, the progress merge card by card,
## and that a failed transfer is retried on the next run instead of being
## silently forgotten.

const DECK := "user://test_sync_deck"

const API := "https://api.github.com"

var _failures := 0

func _init() -> void:
	await _test_first_push_pulls_nothing()
	await _test_second_device_pulls()
	await _test_local_edit_wins()
	await _test_progress_merges()
	await _test_failed_push_retries()
	await _test_foreign_files_are_left_alone()
	await _test_shared_deck_arrives()
	_teardown()
	if _failures > 0:
		print("sync: %d FAILURE(S)" % _failures)
		quit(1)
	else:
		print("sync: all checks passed")
		quit(0)

func _ok(condition: bool, what: String) -> void:
	if not condition:
		_failures += 1
		print("  FAIL: %s" % what)

func _is(got: Variant, expected: Variant, what: String) -> void:
	if got != expected:
		_failures += 1
		print("  FAIL: %s — got %s, expected %s" % [what, str(got), str(expected)])

# --- a GitHub stand-in ----------------------------------------------------------

class FakeGitHub:
	extends RefCounted

	var files := {}  # path -> {"sha": ..., "content": bytes}
	var fails := []  # paths whose PUT must fail

	func _init() -> void:
		files["README.md"] = {"sha": "readme", "content": "hello".to_utf8_buffer()}

	## Speaks the small slice of the GitHub API the app uses.
	func request(method: String, url: String, _headers: Dictionary, body: PackedByteArray) -> Dictionary:
		var path := _content_path(url)
		if url.ends_with("/user"):
			return _json(200, {"login": "tester"})
		if url.ends_with("/user/repos"):
			return _json(201, {"default_branch": "main"})
		if url.contains("/git/trees/"):
			var tree := []
			for p in files.keys():
				tree.append({"path": p, "sha": files[p].sha, "type": "blob"})
			return _json(200, {"tree": tree})
		if method == "GET" and url.contains("/repos/") and path.is_empty():
			return _json(200, {"default_branch": "main"})
		if method == "GET" and not path.is_empty():
			if not files.has(path):
				return _json(404, {})
			return _raw(200, files[path].content)
		if method == "PUT" and not path.is_empty():
			if path in fails:
				return _json(409, {})
			var payload: Variant = JSON.parse_string(body.get_string_from_utf8())
			if typeof(payload) != TYPE_DICTIONARY:
				return _json(400, {})
			files[path] = {
				"sha": _content_sha(),
				"content": Marshalls.base64_to_raw(str((payload as Dictionary).get("content", ""))),
			}
			return _json(201, {})
		if method == "DELETE" and not path.is_empty():
			var del: Variant = JSON.parse_string(body.get_string_from_utf8())
			if not files.has(path):
				return _json(404, {})
			if typeof(del) == TYPE_DICTIONARY and str((del as Dictionary).get("sha", "")) != str(files[path].sha):
				return _json(409, {})
			files.erase(path)
			return _json(200, {})
		return _json(404, {})

	func _content_path(url: String) -> String:
		var marker := "/contents/"
		var at := url.find(marker)
		if at < 0:
			return ""
		return url.substr(at + marker.length()).uri_decode()

	static func _json(code: int, data: Variant) -> Dictionary:
		return {"status": true, "code": code, "headers": {}, "body": JSON.stringify(data).to_utf8_buffer()}

	static func _raw(code: int, content: PackedByteArray) -> Dictionary:
		return {"status": true, "code": code, "headers": {}, "body": content}

	static func _content_sha() -> String:
		return "sha%d" % (randi() % 100000)

## The client the sync engine sees: the same two methods, backed by the fake.
class FakeHttp:
	extends RefCounted

	var request: Callable
	var request_json: Callable

# --- fixtures -------------------------------------------------------------------

func _make_sync(fake: FakeGitHub) -> SyncScript:
	var http := FakeHttp.new()
	http.request = func(method: String, url: String, headers: Dictionary, body: PackedByteArray) -> Dictionary:
		return fake.request(method, url, headers, body)
	http.request_json = func(method: String, url: String, headers: Dictionary, payload: Variant) -> Dictionary:
		var body := PackedByteArray()
		if payload != null:
			body = JSON.stringify(payload).to_utf8_buffer()
		return fake.request(method, url, headers, body)
	var auth := AuthScript.new()
	var sync := SyncScript.new(http, auth)
	sync.token = "fake-token"
	return sync

func _write_deck(cards: Dictionary) -> void:
	_teardown()
	DirAccess.make_dir_recursive_absolute(DECK)
	FileAccess.open(DECK.path_join("deck.json"), FileAccess.WRITE).store_string(
		JSON.stringify({"format": 1, "name": "Quran", "cards": cards.keys()})
	)
	for id in cards.keys():
		var folder := DECK.path_join(id)
		DirAccess.make_dir_recursive_absolute(folder)
		_write(folder.path_join("front.md"), cards[id][0])
		_write(folder.path_join("back.md"), cards[id][1])

func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func _write_progress(entries: Dictionary) -> void:
	_write(DECK.path_join("progress.json"), JSON.stringify({"format": 1, "cards": entries}) + "\n")

func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path)

# --- the tests ------------------------------------------------------------------

func _test_first_push_pulls_nothing() -> void:
	_write_deck({"001": ["Q1", "A1"], "002": ["Q2", "A2"]})
	var fake := FakeGitHub.new()
	var result: Dictionary = await _make_sync(fake).sync(DECK)
	_ok(bool(result.get("ok", false)), "a first sync succeeds (%s)" % str(result.get("error", "")))
	_is(result.pushed, 5, "the deck and its cards are pushed (got %d)" % result.pushed)
	_is(result.pulled, 0, "nothing is pulled on a first sync")
	_ok(fake.files.has("deck.json"), "deck.json is in the repo")
	_ok(fake.files.has("001/front.md"), "the card front is in the repo")
	_ok(fake.files.has("002/back.md"), "the card back is in the repo")
	_ok(fake.files.has("README.md"), "the file the user keeps is untouched")

func _test_second_device_pulls() -> void:
	var fake := FakeGitHub.new()
	await _make_sync(fake).sync(DECK)
	# The other device pulls into a fresh folder.
	var target := "user://test_sync_pull"
	_remove_tree(target)
	DirAccess.make_dir_recursive_absolute(target)
	var result: Dictionary = await _make_sync(fake).sync(target)
	_ok(bool(result.get("ok", false)), "a second device syncs")
	_ok(result.pulled >= 4, "the second device pulls the deck (got %d)" % result.pulled)
	_ok(FileAccess.file_exists(target.path_join("001/front.md")), "the card arrives on the second device")
	_remove_tree(target)

func _test_local_edit_wins() -> void:
	_write_deck({"001": ["Q1", "A1"]})
	var fake := FakeGitHub.new()
	var sync := _make_sync(fake)
	await sync.sync(DECK)
	# The card is edited here and there at once.
	_write(DECK.path_join("001/front.md"), "Q1 edited here")
	fake.files["001/front.md"] = {"sha": "theirs", "content": "Q1 edited there".to_utf8_buffer()}
	var result: Dictionary = await sync.sync(DECK)
	_ok(bool(result.get("ok", false)), "a conflicting sync completes")
	_is(_read(DECK.path_join("001/front.md")), "Q1 edited here", "the local edit wins a content conflict")
	# And an untouched file follows the remote.
	fake.files["001/back.md"] = {"sha": "theirs2", "content": "A1 edited there".to_utf8_buffer()}
	await sync.sync(DECK)
	_is(_read(DECK.path_join("001/back.md")), "A1 edited there", "an untouched file follows the remote")

func _test_progress_merges() -> void:
	_write_deck({"001": ["Q1", "A1"], "002": ["Q2", "A2"]})
	var fake := FakeGitHub.new()
	var sync := _make_sync(fake)
	await sync.sync(DECK)
	# This device studied 001; the other studied 002 the moment before, and
	# studied 001 far harder after this device last looked.
	_write_progress({
		"001": {"status": "review", "ivl": 4, "ease": 2.5, "reps": 3, "lapses": 0, "mod": 1000, "due_day": 100, "step": 0, "relearning": false, "due_ts": 0},
		"002": {"status": "review", "ivl": 1, "ease": 2.5, "reps": 1, "lapses": 0, "mod": 900, "due_day": 100, "step": 0, "relearning": false, "due_ts": 0},
	})
	fake.files["progress.json"] = {
		"sha": "prog",
		"content": (JSON.stringify({"format": 1, "cards": {
			"001": {"status": "review", "ivl": 10, "ease": 2.5, "reps": 9, "lapses": 1, "mod": 2000, "due_day": 100, "step": 0, "relearning": false, "due_ts": 0},
		}}) + "\n").to_utf8_buffer(),
	}
	var result: Dictionary = await sync.sync(DECK)
	_ok(bool(result.get("ok", false)), "a progress sync completes")
	_is(result.merged, 1, "one card's progress merges in (got %d)" % result.merged)
	var merged: Variant = JSON.parse_string(_read(DECK.path_join("progress.json")))
	var cards: Dictionary = (merged as Dictionary).cards
	_is(cards["001"].reps, 9, "the deeper study wins the merge")
	_is(cards["002"].reps, 1, "the local study the remote never saw is kept")

func _test_failed_push_retries() -> void:
	_write_deck({"001": ["Q1", "A1"]})
	var fake := FakeGitHub.new()
	var sync := _make_sync(fake)
	await sync.sync(DECK)
	# A card changes here; the push fails.
	_write(DECK.path_join("001/front.md"), "Q1 changed")
	fake.fails.append("001/front.md")
	var result: Dictionary = await sync.sync(DECK)
	_ok(not bool(result.get("ok", false)), "a failed transfer is reported, not swallowed")
	# The next run must try the same file again, not assume it is synced.
	fake.fails.clear()
	var again: Dictionary = await sync.sync(DECK)
	_ok(bool(again.get("ok", false)), "the retry succeeds")
	_ok(again.pushed >= 1, "the failed file is pushed on the retry (got %d)" % again.pushed)

func _test_foreign_files_are_left_alone() -> void:
	_write_deck({"001": ["Q1", "A1"]})
	var fake := FakeGitHub.new()
	var sync := _make_sync(fake)
	await sync.sync(DECK)
	# The user's own repo files must never be touched.
	fake.files["my-notes.md"] = {"sha": "note", "content": "mine".to_utf8_buffer()}
	await sync.sync(DECK)
	_ok(fake.files.has("my-notes.md"), "a foreign file is left in the repo")
	_ok(not FileAccess.file_exists(DECK.path_join("my-notes.md")), "a foreign file is not pulled into the deck")

func _test_shared_deck_arrives() -> void:
	# Someone shares their deck: their repo has cards this deck has never seen.
	var fake := FakeGitHub.new()
	fake.files["deck.json"] = {
		"sha": "d",
		"content": JSON.stringify({"format": 1, "name": "Quran", "cards": ["001", "002"]}).to_utf8_buffer(),
	}
	fake.files["001/front.md"] = {"sha": "a", "content": "Shared Q1".to_utf8_buffer()}
	fake.files["001/back.md"] = {"sha": "b", "content": "Shared A1".to_utf8_buffer()}
	fake.files["002/front.md"] = {"sha": "c", "content": "Shared Q2".to_utf8_buffer()}
	fake.files["002/back.md"] = {"sha": "e", "content": "Shared A2".to_utf8_buffer()}
	_write_deck({"001": ["Q1", "A1"]})
	var result: Dictionary = await _make_sync(fake).sync(DECK)
	_ok(bool(result.get("ok", false)), "a shared deck syncs")
	_ok(result.pulled >= 2, "the new cards arrive (got %d)" % result.pulled)
	_is(_read(DECK.path_join("002/front.md")), "Shared Q2", "the shared card is adopted")

func _teardown() -> void:
	_remove_tree(DECK)
	_remove_tree("user://test_sync_pull")
	_remove_tree("user://sync_manifest.json")
	_file("user://settings.json").store_string(
		JSON.stringify(
			{"token": "fake-token", "owner": "", "repo": "quran-tathbit", "deck_folder": "", "last_sync": 0, "setup_done": false}
		)
		+ "\n"
	)

func _file(path: String) -> FileAccess:
	return FileAccess.open(path, FileAccess.WRITE)

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
