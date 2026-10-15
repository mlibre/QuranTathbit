class_name GitHubSync
extends RefCounted
const SettingsScript := preload("res://scripts/data/settings.gd")
const DeckScript := preload("res://scripts/data/deck.gd")
const GitHubAuthScript := preload("res://scripts/net/github_auth.gd")

## The deck's bridge between machines: the deck lives in the user's own
## private GitHub repository as the same folders and files it is on disk, so
## a phone, a laptop and a browser all read and write exactly what a person
## would see at github.com.
##
## Sync is a three-way merge per file, keyed on the last-synced checksum kept
## in user://sync_manifest.json:
##
##   remote unchanged since last sync, local changed  -> push local
##   local unchanged since last sync, remote changed  -> pull remote
##   both changed                                     -> local wins (cards)
##                                                     -> per-card merge (progress)
##
## progress.json merges card by card: the entry with more reviews wins, the
## later answer breaks ties. Two devices can study offline and both keep
## their work when they meet. It also goes out when local study moved it past
## the bytes the repo last saw -- one device studying, then syncing, is the
## common case, and it must reach the other machines.
##
## The checksums are git blob checksums, the same values GitHub lists in a
## tree, so a file that matches the repo byte for byte is recognised as
## identical and skipped: a quiet sync moves nothing at all.
##
## Only the card layout is ever touched: deck.json, progress.json, and the
## numbered card folders. Anything else in the repo belongs to the user.

const API := "https://api.github.com"
const MANIFEST := "user://sync_manifest.json"
const RAW := "application/vnd.github.raw"
const JSON_MIME := "application/vnd.github+json"

var http  # HttpClient (or anything with the same request/request_json shape)
var auth: GitHubAuthScript
var token := ""
var owner := ""
var repo := "quran-tathbit"

var _branch := "main"
var _deck_path := ""

func _init(p_http, p_auth: GitHubAuthScript) -> void:
        http = p_http
        auth = p_auth

## Run one full sync. on_progress(text, done, total) is called as it goes.
## Returns {ok, message, pushed, pulled, merged} or {ok: false, error}.
func sync(deck_path: String, on_progress: Callable = Callable()) -> Dictionary:
        _deck_path = deck_path
        var settings = SettingsScript.load_settings()
        token = settings.token
        repo = settings.repo if not settings.repo.strip_edges().is_empty() else repo
        if token.strip_edges().is_empty():
                return {"ok": false, "error": "no_token"}

        var me: Dictionary = await _get_json("/user")
        if not _ok(me):
                return {"ok": false, "error": "auth_failed", "code": int(me.get("code", 0))}
        owner = str((me.body_json as Dictionary).get("login", ""))
        if owner.is_empty():
                return {"ok": false, "error": "auth_failed"}

        var repo_state: Dictionary = await _ensure_repo()
        if not bool(repo_state.get("ok", false)):
                return {"ok": false, "error": str(repo_state.get("error", "repo_failed"))}
        _branch = str(repo_state.get("branch", "main"))

        var tree: Dictionary = await _get_json(
                "/repos/%s/%s/git/trees/%s?recursive=1" % [owner, repo, _branch]
        )
        if not _ok(tree):
                return {"ok": false, "error": "tree_failed", "code": int(tree.get("code", 0))}
        var remote := _tree_shas(tree.body_json)

        # Remember where we started, so a mid-run failure does not lie later.
        var manifest := _load_manifest()
        var local := _local_files(deck_path)
        var plan := _plan(local, remote, manifest)
        var total: int = plan.size()
        _report(on_progress, "syncing", 0, total)

        var pushed := 0
        var pulled := 0
        var index := 0
        var failed: Array = []
        for step in plan:
                index += 1
                match str(step.action):
                        "pull":
                                if await _pull_file(deck_path, str(step.path)):
                                        pulled += 1
                                else:
                                        failed.append(str(step.path))
                        "push":
                                if await _push_file(deck_path, str(step.path), remote):
                                        pushed += 1
                                else:
                                        failed.append(str(step.path))
                        "delete":
                                if await _delete_file(str(step.path), remote):
                                        pushed += 1
                                else:
                                        failed.append(str(step.path))
                _report(on_progress, "syncing", index, total)

        # progress.json is merged card by card, never bulk-overwritten.
        var merge := await _merge_progress(deck_path, remote, manifest)
        var progress_failed := false
        if bool(merge.get("changed", false)):
                if await _push_file(deck_path, "progress.json", remote):
                        pushed += 1
                else:
                        progress_failed = true

        # Everything that now agrees, locally and remotely, is the new baseline.
        # Anything that failed to transfer stays out, so the next run retries it.
        var after := _local_files(deck_path)
        var fresh : Dictionary = {}
        for path in after.keys():
                if failed.has(path) or (path == "progress.json" and progress_failed):
                        continue
                fresh[path] = after[path]
        _save_manifest(fresh)

        return {
                "ok": failed.is_empty() and not progress_failed,
                "pushed": pushed,
                "pulled": pulled,
                "merged": int(merge.get("merged", 0)),
                "failed": failed,
        }

# --- planning ------------------------------------------------------------------

## The plan says what each file needs: push, pull, or delete. progress.json
## never appears here -- the merge owns it.
static func _plan(local: Dictionary, remote: Dictionary, manifest: Dictionary) -> Array:
        var plan: Array = []
        for path in local.keys():
                if path == "progress.json":
                        continue
                var local_sha: String = local[path]
                var remote_sha: String = str(remote.get(path, ""))
                var synced_sha: String = str(manifest.get(path, ""))
                if remote_sha == local_sha:
                        continue  # already identical
                if remote_sha.is_empty():
                        plan.append({"action": "push", "path": path})  # not there yet
                elif synced_sha == local_sha:
                        plan.append({"action": "pull", "path": path})  # untouched here, changed there
                else:
                        plan.append({"action": "push", "path": path})  # changed here; local wins
        for path in remote.keys():
                if path == "progress.json" or local.has(path) or not _is_deck_path(path):
                        continue
                if manifest.has(path):
                        plan.append({"action": "delete", "path": path})  # removed here, still there
                else:
                        plan.append({"action": "pull", "path": path})  # a shared deck's new card
        return plan

static func _is_deck_path(path: String) -> bool:
        if path == "deck.json" or path == "progress.json":
                return true
        return path.split("/")[0].is_valid_int()

# --- repo and files ------------------------------------------------------------

func _ensure_repo() -> Dictionary:
        var existing: Dictionary = await _get_json("/repos/%s/%s" % [owner, repo])
        if int(existing.get("code", 0)) == 200:
                return {"ok": true, "branch": _default_branch(existing.body_json)}
        if int(existing.get("code", 0)) != 404:
                return {"ok": false, "error": "repo_lookup_failed"}
        var created: Dictionary = await _request_json(
                "POST", "/user/repos", {
                        "name": repo,
                        "private": true,
                        "auto_init": true,
                        "description": "My QuranTathbit deck: cards as folders and files.",
                }
        )
        if int(created.get("code", 0)) not in [201, 200]:
                # 422 means it exists under another case; the lookup settles it.
                if int(created.get("code", 0)) != 422:
                        return {"ok": false, "error": "repo_create_failed"}
        var again: Dictionary = await _get_json("/repos/%s/%s" % [owner, repo])
        if not _ok(again):
                return {"ok": false, "error": "repo_missing_after_create"}
        return {"ok": true, "branch": _default_branch(again.body_json)}

static func _default_branch(repo_json: Variant) -> String:
        if typeof(repo_json) != TYPE_DICTIONARY:
                return "main"
        return str((repo_json as Dictionary).get("default_branch", "main"))

func _pull_file(deck_path: String, path: String) -> bool:
        var target := deck_path.path_join(path)
        if not _is_safe_target(deck_path, target):
                push_error("GitHubSync: refusing to write outside the deck: %s" % path)
                return false
        var response: Dictionary = await _get_raw(
                "/repos/%s/%s/contents/%s" % [owner, repo, _encode_path(path)]
        )
        if int(response.get("code", 0)) != 200:
                push_error("GitHubSync: pull %s failed (%d)" % [path, int(response.get("code", 0))])
                return false
        var dir := target.get_base_dir()
        if not DirAccess.dir_exists_absolute(dir):
                var err := DirAccess.make_dir_recursive_absolute(dir)
                if err != OK:
                        push_error("GitHubSync: cannot create %s" % dir)
                        return false
        var file := FileAccess.open(target, FileAccess.WRITE)
        if file == null:
                push_error("GitHubSync: cannot write %s" % target)
                return false
        file.store_buffer(response.body)
        file.close()
        return true

func _push_file(deck_path: String, path: String, remote: Dictionary) -> bool:
        var source := deck_path.path_join(path)
        if not FileAccess.file_exists(source):
                return true  # nothing local to send
        var bytes := FileAccess.get_file_as_bytes(source)
        var payload := {
                "message": "Tathbit: update %s" % path,
                "content": Marshalls.raw_to_base64(bytes),
                "branch": _branch,
        }
        if remote.has(path):
                payload["sha"] = remote[path]
        var response: Dictionary = await _request_json(
                "PUT", "/repos/%s/%s/contents/%s" % [owner, repo, _encode_path(path)], payload
        )
        if int(response.get("code", 0)) not in [200, 201]:
                push_error("GitHubSync: push %s failed (%d)" % [path, int(response.get("code", 0))])
                return false
        return true

func _delete_file(path: String, remote: Dictionary) -> bool:
        var sha := str(remote.get(path, ""))
        if sha.is_empty():
                return true
        var response: Dictionary = await _request_json(
                "DELETE",
                "/repos/%s/%s/contents/%s" % [owner, repo, _encode_path(path)],
                {"message": "Tathbit: remove %s" % path, "sha": sha, "branch": _branch}
        )
        return int(response.get("code", 0)) == 200

# --- progress merge ------------------------------------------------------------

## Card by card: more reviews wins, then the later answer. The file goes to
## the repo when the merge changed it or when local study moved it past the
## bytes the repo last saw.
func _merge_progress(deck_path: String, remote: Dictionary, manifest: Dictionary) -> Dictionary:
        var local_path := deck_path.path_join("progress.json")
        var mine := _read_progress(local_path)
        var remote_sha := str(remote.get("progress.json", ""))
        var theirs: Dictionary = {}
        if not remote_sha.is_empty():
                var fetched: Dictionary = await _get_raw(
                        "/repos/%s/%s/contents/%s" % [owner, repo, _encode_path("progress.json")]
                )
                if int(fetched.get("code", 0)) != 200:
                        return {"merged": 0, "changed": false, "error": "progress_pull_failed"}
                theirs = _progress_entries(fetched.body)
        var merged := 0
        for card_id in theirs.keys():
                var their_state: Dictionary = theirs[card_id]
                if not mine.has(card_id):
                        mine[card_id] = their_state
                        merged += 1
                elif _progress_rank(their_state) > _progress_rank(mine[card_id]):
                        mine[card_id] = their_state
                        merged += 1
        if not (merged > 0 or _progress_needs_push(local_path, manifest)):
                return {"merged": 0, "changed": false}
        if merged > 0:
                var file := FileAccess.open(local_path, FileAccess.WRITE)
                if file == null:
                        return {"merged": 0, "changed": false}
                file.store_string(JSON.stringify({"format": DeckScript.FORMAT, "cards": mine}, "\t") + "\n")
                file.close()
        return {"merged": merged, "changed": true}

## Is the local progress file ahead of the bytes the repo last saw? A missing
## baseline means it was never sent; a differing checksum means study moved it.
static func _progress_needs_push(local_path: String, manifest: Dictionary) -> bool:
        if not FileAccess.file_exists(local_path):
                return false
        var baseline := str(manifest.get("progress.json", ""))
        if baseline.is_empty():
                return true
        return _blob_sha(FileAccess.get_file_as_bytes(local_path)) != baseline

static func _progress_rank(state: Dictionary) -> Array:
        return [int(state.get("reps", 0)), int(state.get("mod", 0))]

static func _progress_entries(body: PackedByteArray) -> Dictionary:
        if body.is_empty():
                return {}
        var data: Variant = JSON.parse_string(body.get_string_from_utf8())
        if typeof(data) != TYPE_DICTIONARY:
                return {}
        var entries: Dictionary = data.get("cards", {})
        var clean: Dictionary = {}
        for card_id in entries.keys():
                if typeof(entries[card_id]) == TYPE_DICTIONARY:
                        clean[card_id] = entries[card_id]
        return clean

func _read_progress(path: String) -> Dictionary:
        if not FileAccess.file_exists(path):
                return {}
        var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
        if typeof(data) != TYPE_DICTIONARY:
                return {}
        var entries: Dictionary = data.get("cards", {})
        var clean: Dictionary = {}
        for card_id in entries.keys():
                if typeof(entries[card_id]) == TYPE_DICTIONARY:
                        clean[card_id] = entries[card_id]
        return clean

# --- inventories ---------------------------------------------------------------

static func _local_files(deck_path: String) -> Dictionary:
        var out : Dictionary = {}
        _collect(deck_path, "", out)
        return out

static func _collect(root: String, prefix: String, out: Dictionary) -> void:
        var dir: String = root if prefix.is_empty() else root.path_join(prefix)
        for entry in DirAccess.get_files_at(dir):
                var rel: String = entry if prefix.is_empty() else prefix.path_join(entry)
                out[rel] = _blob_sha(FileAccess.get_file_as_bytes(dir.path_join(entry)))
        for entry in DirAccess.get_directories_at(dir):
                var rel: String = entry if prefix.is_empty() else prefix.path_join(entry)
                _collect(root, rel, out)

## A git blob checksum -- the same value GitHub lists in a tree, so "already
## identical" can be told apart from "changed here" and unchanged files stop
## being re-sent on every sync.
static func _blob_sha(bytes: PackedByteArray) -> String:
        var head := ("blob %d" % bytes.size()).to_utf8_buffer()
        head.append(0)
        var h := HashingContext.new()
        h.start(HashingContext.HASH_SHA1)
        h.update(head)
        h.update(bytes)
        return h.finish().hex_encode()

func _tree_shas(tree_json: Variant) -> Dictionary:
        var out : Dictionary = {}
        if typeof(tree_json) != TYPE_DICTIONARY:
                return out
        for entry in (tree_json as Dictionary).get("tree", []):
                if typeof(entry) == TYPE_DICTIONARY and str(entry.get("type", "")) == "blob":
                        out[str(entry.get("path", ""))] = str(entry.get("sha", ""))
        return out

func _load_manifest() -> Dictionary:
        if not FileAccess.file_exists(MANIFEST):
                return {}
        var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
        if typeof(data) != TYPE_DICTIONARY:
                return {}
        # One manifest per deck folder: two folders syncing one repo must not
        # mistake each other's files for already-synced ones.
        var decks: Dictionary = (data as Dictionary).get("decks", {})
        var mine: Variant = decks.get(_deck_key(), {})
        if typeof(mine) == TYPE_DICTIONARY:
                return mine as Dictionary
        return {}

func _save_manifest(files: Dictionary) -> void:
        var data := {}
        if FileAccess.file_exists(MANIFEST):
                var existing: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
                if typeof(existing) == TYPE_DICTIONARY:
                        data = (existing as Dictionary).duplicate()
        var decks: Dictionary = data.get("decks", {})
        decks[_deck_key()] = files
        data["decks"] = decks
        var file := FileAccess.open(MANIFEST, FileAccess.WRITE)
        if file == null:
                return
        file.store_string(JSON.stringify(data, "\t") + "\n")
        file.close()

func _deck_key() -> String:
        return _deck_path.simplify_path()

# --- plumbing -------------------------------------------------------------------

func _ok(response: Dictionary) -> bool:
        return bool(response.get("status", false)) and int(response.get("code", 0)) == 200

func _get_json(path: String) -> Dictionary:
        var response: Dictionary = await _request_json("GET", path, null)
        response["body_json"] = _parse_json(response.body)
        return response

func _get_raw(path: String) -> Dictionary:
        var headers := _auth_headers()
        headers["Accept"] = RAW
        return await http.request.call("GET", API + path, headers, PackedByteArray())

func _request_json(method: String, path: String, payload: Variant) -> Dictionary:
        var headers := _auth_headers()
        headers["Accept"] = JSON_MIME
        return await http.request_json.call(method, API + path, headers, payload)

func _auth_headers() -> Dictionary:
        return {"Authorization": "Bearer " + token, "User-Agent": "QuranTathbit"}

static func _parse_json(body: PackedByteArray) -> Variant:
        if body.is_empty():
                return null
        return JSON.parse_string(body.get_string_from_utf8())

## Percent-encode each path segment, keeping the separators.
static func _encode_path(path: String) -> String:
        var parts := path.split("/")
        var encoded: PackedStringArray = PackedStringArray()
        for part in parts:
                encoded.append(part.uri_encode())
        return "/".join(encoded)

func _is_safe_target(deck_path: String, target: String) -> bool:
        var normalized := target.simplify_path()
        var root: String = deck_path.simplify_path()
        return normalized == root or normalized.begins_with(root + "/")

func _report(on_progress: Callable, text: String, done: int, total: int) -> void:
        if on_progress.is_valid():
                on_progress.call(text, done, total)
