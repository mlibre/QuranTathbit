extends SceneTree

## Live proof of the sync engine against GitHub's real servers, run with a
## classic token from the environment (never written anywhere):
##
##   1. whoami -- the token works.
##   2. A scratch repo is created (QURAN_TATHBIT_LIVE_REPO, private,
##      auto-initialized) -- exactly what the app does on a first sync.
##   3. The bundled deck syncs into it: one commit, blobs in batches.
##   4. The repo's tree is read back: every deck file landed, and no
##      editor metadata (.import) rode along.
##   5. A second sync is quiet: nothing pushes, nothing pulls, no commit.
##   6. The scratch repo is deleted (QURAN_TATHBIT_LIVE_CLEANUP=1 to allow
##      it), leaving the account as it was found.
##
## Run:
##   QURAN_TATHBIT_LIVE_TOKEN=ghp_... QURAN_TATHBIT_LIVE_CLEANUP=1 \
##     timeout 600 godot --headless --path . --script tools/live_sync_check.gd
## Prints LIVE_SYNC_OK and exits 0 when every check passes.

const SyncScript := preload("res://scripts/net/github_sync.gd")
const HttpClientScript := preload("res://scripts/net/http_client.gd")
const SettingsScript := preload("res://scripts/data/settings.gd")

const API := "https://api.github.com"
const BUNDLED_DECK := "res://assets/decks/quran"
const SCRATCH_DECK := "user://live_check_deck"
const CARD_COUNT := 99


func _init() -> void:
	var token := OS.get_environment("QURAN_TATHBIT_LIVE_TOKEN").strip_edges()
	if token.is_empty():
		print("FAIL: set QURAN_TATHBIT_LIVE_TOKEN to a classic token with repo scope")
		quit(1)
		return
	var repo := OS.get_environment("QURAN_TATHBIT_LIVE_REPO").strip_edges()
	if repo.is_empty():
		repo = "quran-tathbit-smoke"

	var http = HttpClientScript.new()
	root.add_child(http)
	await process_frame

	# The engine reads the token from settings; the test's scratch deck keeps
	# it away from the real one under user://decks.
	var settings = SettingsScript.load_settings()
	settings.token = token
	settings.repo = repo
	settings.owner = ""
	settings.save()
	_copy_deck()

	var sync := SyncScript.new(http, SyncScript._new_auth())
	sync.token = token
	sync.repo = repo

	# 1. Who the token belongs to, and clean up any earlier scratch repo.
	var me: Dictionary = await http.request_json.call(
		"GET", API + "/user", {"User-Agent": "QuranTathbit", "Authorization": "Bearer " + token}, null
	)
	if int(me.get("code", 0)) != 200:
		print("FAIL: /user answered ", me.get("code", 0))
		quit(1)
		return
	var login := str(JSON.parse_string(me.body.get_string_from_utf8()).login)
	print("whoami OK: @", login)
	if not await _delete_repo(http, token, login, repo, false):
		print("FAIL: could not clear the way for the scratch repo")
		quit(1)
		return

	# 2-3. A first sync creates the repo and carries the whole deck.
	var started := Time.get_ticks_msec()
	var first: Dictionary = await sync.sync(SCRATCH_DECK)
	var took := (Time.get_ticks_msec() - started) / 1000.0
	if not bool(first.get("ok", false)):
		print("FAIL: the first sync failed: ", first)
		await _delete_repo(http, token, login, repo, true)
		quit(1)
		return
	print("first sync OK: ", first.pushed, " files pushed in ", took, "s (", first.pulled, " pulled)")
	if int(first.pushed) < CARD_COUNT * 2 + 2:
		print("FAIL: expected at least the deck's ", CARD_COUNT * 2 + 2, " text files to be pushed")
		await _delete_repo(http, token, login, repo, true)
		quit(1)
		return

	# 4. What the repo actually holds now.
	var tree: Dictionary = await http.request_json.call(
		"GET",
		API + "/repos/%s/%s/git/trees/main?recursive=1" % [login, repo],
		{"User-Agent": "QuranTathbit", "Authorization": "Bearer " + token},
		null
	)
	var entries: Array = JSON.parse_string(tree.body.get_string_from_utf8()).tree
	var paths: Array = []
	for entry in entries:
		if str(entry.type) == "blob":
			paths.append(str(entry.path))
	var junk := paths.filter(func(p: String) -> bool: return p.ends_with(".import") or p.ends_with(".uid"))
	if not junk.is_empty():
		print("FAIL: editor metadata reached the repo: ", junk.slice(0, 3))
		await _delete_repo(http, token, login, repo, true)
		quit(1)
		return
	if not paths.has("deck.json") or not paths.has("001/front.md") or not paths.has("099/back.md"):
		print("FAIL: the repo is missing deck files; it holds ", paths.size(), " files")
		await _delete_repo(http, token, login, repo, true)
		quit(1)
		return
	var commits: Dictionary = await http.request_json.call(
		"GET",
		API + "/repos/%s/%s/commits?per_page=100" % [login, repo],
		{"User-Agent": "QuranTathbit", "Authorization": "Bearer " + token},
		null
	)
	var commit_list: Array = JSON.parse_string(commits.body.get_string_from_utf8())
	print("repo tree OK: ", paths.size(), " files, ", commit_list.size() - 1, " sync commit(s)")

	# 5. The second sync must be quiet.
	var second: Dictionary = await sync.sync(SCRATCH_DECK)
	if not bool(second.get("ok", false)) or int(second.pushed) != 0 or int(second.pulled) != 0:
		print("FAIL: the second sync was not quiet: ", second)
		await _delete_repo(http, token, login, repo, true)
		quit(1)
		return
	print("quiet sync OK: nothing moved")

	# 6. Leave the account as it was found.
	if not await _delete_repo(http, token, login, repo, true):
		print("NOTE: the scratch repo ", repo, " could not be deleted; remove it by hand")
		quit(1)
		return
	print("scratch repo deleted")
	print("LIVE_SYNC_OK")
	quit(0)


## The auth object the engine expects; its client id is only for the device
## flow, which this check never starts.
static func _new_auth():
	return load("res://scripts/net/github_auth.gd").new()


func _copy_deck() -> void:
	_remove_tree(SCRATCH_DECK)
	_copy(BUNDLED_DECK, SCRATCH_DECK)


func _copy(from: String, to: String) -> void:
	DirAccess.make_dir_recursive_absolute(to)
	for entry in DirAccess.get_files_at(from):
		if entry.get_extension() in ["import", "uid"]:
			continue
		var file := FileAccess.open(to.path_join(entry), FileAccess.WRITE)
		file.store_buffer(FileAccess.get_file_as_bytes(from.path_join(entry)))
		file.close()
	for entry in DirAccess.get_directories_at(from):
		_copy(from.path_join(entry), to.path_join(entry))


func _delete_repo(http, token: String, owner: String, repo: String, required: bool) -> bool:
	var response: Dictionary = await http.request.call(
		"DELETE",
		API + "/repos/%s/%s" % [owner, repo],
		{"User-Agent": "QuranTathbit", "Authorization": "Bearer " + token},
		PackedByteArray()
	)
	var code := int(response.get("code", 0))
	if code == 204 or code == 404:
		return true
	if not required and code in [403, 404]:
		return true  # nothing to clear, or no permission -- the create will tell
	if required and OS.get_environment("QURAN_TATHBIT_LIVE_CLEANUP") != "1":
		print("NOTE: cleanup skipped (QURAN_TATHBIT_LIVE_CLEANUP is not 1); repo ", repo, " remains")
		return true
	push_error("delete repo answered %d" % code)
	return false


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
