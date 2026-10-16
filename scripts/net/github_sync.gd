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
##   remote unchanged since last sync, local changed  -> send local
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
## What there is to send is sent as ONE commit: the files' blobs upload
## first, a handful at a time, and then a single tree, commit and ref update
## land them together. A first sync is one tidy commit in the repo's history
## -- not three hundred -- and the round trips that dominate its duration
## happen in parallel.
##
## The checksums are git blob checksums, the same values GitHub lists in a
## tree, so a file that matches the repo byte for byte is recognised as
## identical and skipped: a quiet sync moves nothing at all. The branch's
## own HEAD is kept in the manifest too, so a sync with nothing to say and
## an unmoved HEAD is git's "already up to date" -- two questions asked,
## no tree walked, no file fetched.
##
## Only the card layout is ever touched: deck.json, progress.json, and the
## numbered card folders. Godot's editor metadata (.import, .uid) is never
## deck content and never leaves the machine. Anything else in the repo
## belongs to the user. In a browser, media does not travel either: the web
## app streams its recitations from the site it was served from, so sync
## carries only the small text of the deck.

const API := "https://api.github.com"
const MANIFEST := "user://sync_manifest.json"
const RAW := "application/vnd.github.raw"
const JSON_MIME := "application/vnd.github+json"

## Blobs in flight at once. Six is the browser's own habit per host, and a
## polite number against GitHub's secondary limits on desktop.
const BLOB_WIDTH := 6

const MEDIA_EXTENSIONS := ["mp3", "ogg", "wav", "m4a", "png", "jpg", "jpeg", "webp", "svg"]

var http  # HttpClient (or anything with the same request/request_json shape)
var auth: GitHubAuthScript
var token := ""
var owner := ""
var repo := "quran-tathbit"

## Media rides sync on every platform but the web, where recitations stream
## from the site instead of being copied in. A var so tests can flip it.
var carry_media := not OS.has_feature("web")

var _branch := "main"
var _deck_path := ""

func _init(p_http, p_auth: GitHubAuthScript) -> void:
        http = p_http
        auth = p_auth

## Run one full sync. on_progress(phrase, done, total) is called as it goes,
## with a plain phrase ("signing in", "reading repo", "downloading",
## "uploading", "merging progress", "saving") and, when the size of the
## phase is known, how far through it is. Returns {ok, pushed, pulled,
## merged} or {ok: false, error}.
func sync(deck_path: String, on_progress: Callable = Callable()) -> Dictionary:
        _deck_path = deck_path
        var settings = SettingsScript.load_settings()
        token = settings.token
        repo = settings.repo if not settings.repo.strip_edges().is_empty() else repo
        if token.strip_edges().is_empty():
                return {"ok": false, "error": "no_token"}

        _report(on_progress, "signing in", 0, 0)
        var me: Dictionary = await _get_json("/user")
        if not _ok(me):
                return {"ok": false, "error": "auth_failed", "code": int(me.get("code", 0))}
        owner = str((me.body_json as Dictionary).get("login", ""))
        if owner.is_empty():
                return {"ok": false, "error": "auth_failed"}

        _report(on_progress, "reading repo", 0, 0)
        var repo_state: Dictionary = await _ensure_repo()
        if not bool(repo_state.get("ok", false)):
                return {"ok": false, "error": str(repo_state.get("error", "repo_failed"))}
        _branch = str(repo_state.get("branch", "main"))

        var head := await _head_sha()
        if head.is_empty():
                return {"ok": false, "error": "head_failed"}

        # Git's own first question: has the branch moved? When the deck has
        # nothing to say and HEAD is where the last sync left it, the tree
        # cannot have changed and the exchange is already over -- the same
        # way `git pull` answers "Already up to date" before touching a
        # single object.
        var manifest := _load_manifest()
        if head == str(manifest.get("_head", "")) and _nothing_to_say(deck_path, manifest):
                _report(on_progress, "in step", 0, 0)
                return {"ok": true, "pushed": 0, "pulled": 0, "merged": 0}

        var tree: Dictionary = await _get_json(
                "/repos/%s/%s/git/trees/%s?recursive=1" % [owner, repo, _branch]
        )
        if not _ok(tree):
                return {"ok": false, "error": "tree_failed", "code": int(tree.get("code", 0))}
        var base_tree := str((tree.body_json as Dictionary).get("sha", ""))
        var remote := _tree_shas(tree.body_json)

        # Remember where we started, so a mid-run failure does not lie later.
        var local := _local_files(deck_path)
        var plan := _plan(local, remote, manifest, carry_media)

        # Pulls are rare and small: each is one file this deck has never changed.
        # They fly six at a time, the way uploads do -- a first sync onto a new
        # device is a hundred files, and one round trip apiece is a hundred
        # waits for the same network.
        var pulls: Array = plan.filter(func(step: Dictionary) -> bool: return str(step.action) == "pull")
        var pulled := 0
        var failed: Array = []
        _report(on_progress, "downloading", 0, pulls.size())
        for start in range(0, pulls.size(), BLOB_WIDTH):
                var flight: Array = []
                for step in pulls.slice(start, start + BLOB_WIDTH):
                        flight.append(str(step.path))
                var responses: Array = await _fetch_files(flight)
                for i in flight.size():
                        if _write_pulled(deck_path, str(flight[i]), responses[i]):
                                pulled += 1
                        else:
                                failed.append(str(flight[i]))
                _report(on_progress, "downloading", minf(start + BLOB_WIDTH, pulls.size()), pulls.size())

        # progress.json is merged card by card, never bulk-overwritten, and the
        # merged file rides the same commit as everything else being sent.
        _report(on_progress, "merging progress", 0, 0)
        var merge := await _merge_progress(deck_path, remote, manifest)
        var progress_failed := merge.has("error")
        if progress_failed:
                push_error("GitHubSync: the progress merge failed (%s)" % str(merge.get("error")))

        var sends: Array = []  # local files the repo must receive
        for step in plan:
                if str(step.action) == "push" and FileAccess.file_exists(deck_path.path_join(str(step.path))):
                        sends.append(str(step.path))
        var deletes: Array = plan.filter(
                func(step: Dictionary) -> bool: return str(step.action) == "delete"
        ).map(func(step: Dictionary) -> String: return str(step.path))
        if bool(merge.get("changed", false)) and not progress_failed:
                sends.append("progress.json")

        var pushed := 0
        var settled_head := head
        if not (sends.is_empty() and deletes.is_empty()):
                _report(on_progress, "uploading", 0, sends.size())
                var blob_shas: Dictionary = await _create_blobs(deck_path, sends, on_progress)
                var missing := sends.filter(func(path: String) -> bool: return not blob_shas.has(path))
                if not missing.is_empty():
                        # Nothing has landed yet -- a failed blob means no commit -- so
                        # the next run simply tries again.
                        failed.append_array(missing)
                        _write_manifest(deck_path, failed, "progress.json" if progress_failed else "")
                        return {
                                "ok": false,
                                "error": "blob_failed",
                                "pushed": 0,
                                "pulled": pulled,
                                "merged": int(merge.get("merged", 0)),
                                "failed": failed,
                        }

                _report(on_progress, "saving", 0, 0)
                var landed := await _commit(blob_shas, sends, deletes, base_tree, head)
                if not landed.ok and str(landed.get("error", "")) == "ref_moved":
                        # Another machine synced mid-flight. Blobs are content addressed,
                        # so they are still good: look again and commit onto the new head.
                        var fresh_head := await _head_sha()
                        var fresh_tree: Dictionary = await _get_json(
                                "/repos/%s/%s/git/trees/%s?recursive=1" % [owner, repo, _branch]
                        )
                        if not fresh_head.is_empty() and _ok(fresh_tree):
                                landed = await _commit(
                                        blob_shas, sends, deletes,
                                        str((fresh_tree.body_json as Dictionary).get("sha", "")), fresh_head
                                )
                if not bool(landed.get("ok", false)):
                        return {
                                "ok": false,
                                "error": str(landed.get("error", "commit_failed")),
                                "code": int(landed.get("code", 0)),
                                "pushed": 0,
                                "pulled": pulled,
                                "merged": int(merge.get("merged", 0)),
                                "failed": failed,
                        }
                if landed.has("sha"):
                        settled_head = str(landed.sha)
                pushed = sends.size() + deletes.size()

        # Everything that now agrees, locally and remotely, is the new
        # baseline -- and the branch's own HEAD is remembered with it, so
        # the next quiet sync can answer "already up to date" from the
        # branch alone. Anything that failed to transfer stays out of both,
        # so the next run looks at the tree again and retries.
        var clean_finish: bool = failed.is_empty() and not progress_failed
        _write_manifest(
                deck_path, failed, "progress.json" if progress_failed else "",
                settled_head if clean_finish else ""
        )

        return {
                "ok": failed.is_empty() and not progress_failed,
                "pushed": pushed,
                "pulled": pulled,
                "merged": int(merge.get("merged", 0)),
                "failed": failed,
        }

func _write_manifest(deck_path: String, failed: Array, progress_failed_path: String, settled_head := "") -> void:
        var after := _local_files(deck_path)
        var fresh: Dictionary = {}
        for path in after.keys():
                if failed.has(path) or (path == progress_failed_path and not progress_failed_path.is_empty()):
                        continue
                # A machine that does not carry media must not remember it as
                # agreed: the manifest is what "already synced" means, and a
                # browser never agreed about files it cannot hold. Recording
                # them anyway let a later desktop sync believe the repo had
                # media it had never received.
                if not carry_media and _is_media(path):
                        continue
                fresh[path] = after[path]
        # The branch this agreement was reached against, for the next run's
        # first question. An empty head -- a run that did not finish clean --
        # forces the next run to look at the tree instead of trusting it.
        if not settled_head.is_empty():
                fresh["_head"] = settled_head
        _save_manifest(fresh)

# --- planning ------------------------------------------------------------------

## Does this deck have anything to say to the repo? Every deck file agrees
## with the last sync's record of it, nothing the last sync knew has been
## deleted since, and the progress file has not moved -- the deck and the
## baseline are one, and only the branch's word is needed to finish.
func _nothing_to_say(deck_path: String, manifest: Dictionary) -> bool:
        if _progress_needs_push(deck_path.path_join("progress.json"), manifest):
                return false
        var local := _local_files(deck_path)
        for path in local.keys():
                if path == "progress.json" or _is_editor_metadata(path):
                        continue
                if not carry_media and _is_media(path):
                        continue
                if str(manifest.get(path, "")) != str(local[path]):
                        return false
        for path in manifest.keys():
                if str(path) == "_head" or path == "progress.json":
                        continue
                if not carry_media and _is_media(str(path)):
                        continue  # a file this machine does not carry is not a deletion
                if not local.has(str(path)):
                        return false  # removed here; the repo should hear
        return true

## The plan says what each file needs: send, pull, or delete. progress.json
## never appears here -- the merge owns it.
static func _plan(local: Dictionary, remote: Dictionary, manifest: Dictionary, carry: bool) -> Array:
        var plan: Array = []
        for path in local.keys():
                if path == "progress.json" or _is_editor_metadata(path):
                        continue
                if not carry and _is_media(path):
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
                # Editor metadata is junk wherever it appears -- never pulled into a
                # fresh deck, and deleted when an older sync put it there.
                if _is_editor_metadata(path):
                        if manifest.has(path):
                                plan.append({"action": "delete", "path": path})
                        continue
                if not carry and _is_media(path):
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

static func _is_media(path: String) -> bool:
        return path.get_extension().to_lower() in MEDIA_EXTENSIONS

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

## The commit the branch points at, as the parent of the one this sync makes.
func _head_sha() -> String:
        var head: Dictionary = await _get_json(
                "/repos/%s/%s/git/ref/heads/%s" % [owner, repo, _branch]
        )
        if not _ok(head) or typeof(head.body_json) != TYPE_DICTIONARY:
                return ""
        return str(((head.body_json as Dictionary).get("object", {}) as Dictionary).get("sha", ""))

## Fetch many files at once: one batch, as many answers, in the same order.
func _fetch_files(paths: Array) -> Array:
        var batch: Array = []
        for path in paths:
                var headers := _auth_headers()
                headers["Accept"] = RAW
                batch.append({
                        "method": "GET",
                        "url": API + "/repos/%s/%s/contents/%s" % [owner, repo, _encode_path(str(path))],
                        "headers": headers,
                        "body": PackedByteArray(),
                })
        return await _request_many(batch)

## One fetched file, written home: inside the deck, nowhere else, with its
## folders made if the file is new to this machine.
func _write_pulled(deck_path: String, path: String, response: Dictionary) -> bool:
        var target := deck_path.path_join(path)
        if not _is_safe_target(deck_path, target):
                push_error("GitHubSync: refusing to write outside the deck: %s" % path)
                return false
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

## Upload every file's blob, a few at a time. Returns {path: blob sha}; a
## path missing from the answer failed and must be retried next sync.
func _create_blobs(deck_path: String, sends: Array, on_progress: Callable) -> Dictionary:
        var shas: Dictionary = {}
        var done := 0
        for start in range(0, sends.size(), BLOB_WIDTH):
                var flight: Array = sends.slice(start, start + BLOB_WIDTH)
                var batch: Array = []
                for path in flight:
                        var bytes := FileAccess.get_file_as_bytes(deck_path.path_join(path))
                        var headers := _auth_headers()
                        headers["Accept"] = JSON_MIME
                        headers["Content-Type"] = "application/json"
                        batch.append({
                                "method": "POST",
                                "url": API + "/repos/%s/%s/git/blobs" % [owner, repo],
                                "headers": headers,
                                "body": JSON.stringify(
                                        {"content": Marshalls.raw_to_base64(bytes), "encoding": "base64"}
                                ).to_utf8_buffer(),
                        })
                var responses: Array = await _request_many(batch)
                for i in responses.size():
                        var path: String = flight[i]
                        var body: Variant = _parse_json(responses[i].body)
                        if int(responses[i].get("code", 0)) == 201 and typeof(body) == TYPE_DICTIONARY and (body as Dictionary).has("sha"):
                                shas[path] = str((body as Dictionary).sha)
                        else:
                                push_error(
                                        "GitHubSync: blob %s failed (%d)" % [path, int(responses[i].get("code", 0))]
                                )
                        done += 1
                _report(on_progress, "uploading", done, sends.size())
        return shas

## One tree, one commit, one ref update: everything this sync has to say,
## said at once. Returns {ok: true} or {ok: false, error, code}; a 409 from
## the ref update is reported as "ref_moved" so the caller can retry onto
## whatever head landed meanwhile.
func _commit(blob_shas: Dictionary, sends: Array, deletes: Array, base_tree: String, head: String) -> Dictionary:
        var entries: Array = []
        for path in sends:
                entries.append({
                        "path": path,
                        "mode": "100644",
                        "type": "blob",
                        "sha": str(blob_shas.get(path, "")),
                })
        for path in deletes:
                entries.append({"path": path, "mode": "100644", "type": "blob", "sha": null})
        if entries.is_empty():
                return {"ok": true}

        var tree_payload := {"tree": entries}
        if not base_tree.is_empty():
                tree_payload["base_tree"] = base_tree
        var made_tree: Dictionary = await _request_json(
                "POST", "/repos/%s/%s/git/trees" % [owner, repo], tree_payload
        )
        var tree_body: Variant = _parse_json(made_tree.body)
        if int(made_tree.get("code", 0)) not in [200, 201] or typeof(tree_body) != TYPE_DICTIONARY:
                return {"ok": false, "error": "tree_failed", "code": int(made_tree.get("code", 0))}
        var new_tree := str((tree_body as Dictionary).get("sha", ""))

        var made_commit: Dictionary = await _request_json(
                "POST",
                "/repos/%s/%s/git/commits" % [owner, repo],
                {"message": _commit_message(sends, deletes), "tree": new_tree, "parents": [head]}
        )
        var commit_body: Variant = _parse_json(made_commit.body)
        if int(made_commit.get("code", 0)) not in [200, 201] or typeof(commit_body) != TYPE_DICTIONARY:
                return {"ok": false, "error": "commit_failed", "code": int(made_commit.get("code", 0))}
        var commit_sha := str((commit_body as Dictionary).get("sha", ""))

        var moved: Dictionary = await _request_json(
                "PATCH",
                "/repos/%s/%s/git/refs/heads/%s" % [owner, repo, _branch],
                {"sha": commit_sha, "force": false}
        )
        if int(moved.get("code", 0)) != 200:
                var error := "ref_failed"
                if int(moved.get("code", 0)) == 409:
                        error = "ref_moved"
                return {"ok": false, "error": error, "code": int(moved.get("code", 0))}
        return {"ok": true, "sha": commit_sha}

static func _commit_message(sends: Array, deletes: Array) -> String:
        if deletes.is_empty() and sends.size() == 1 and str(sends[0]) == "progress.json":
                return "Tathbit: update progress"
        if sends.size() + deletes.size() == 1:
                return "Tathbit: update %s" % [str(sends[0]) if sends.size() == 1 else str(deletes[0])]
        return "Tathbit: sync %d files" % (sends.size() + deletes.size())

# --- progress merge ------------------------------------------------------------

## Card by card: more reviews wins, then the later answer. The reader's own
## pace rides the same merge: the choice made later wins, the way a later
## answer breaks a card's tie. The file goes to the repo when the merge
## changed it or when local study moved it past the bytes the repo last saw.
func _merge_progress(deck_path: String, remote: Dictionary, manifest: Dictionary) -> Dictionary:
        var local_path := deck_path.path_join("progress.json")
        var remote_sha := str(remote.get("progress.json", ""))
        var baseline := str(manifest.get("progress.json", ""))
        # Both sides exactly as the last sync left them: there is nothing to
        # merge and nothing to send, and no reason to fetch the file at all.
        # Downloading it anyway made every sync look like a full round trip.
        if not remote_sha.is_empty() and remote_sha == baseline and not _progress_needs_push(local_path, manifest):
                return {"merged": 0, "changed": false}
        var mine := _read_progress(local_path)
        var pace := _read_pace(local_path)
        var theirs: Dictionary = {}
        var their_pace := {}
        if not remote_sha.is_empty():
                var fetched: Dictionary = await _get_raw(
                        "/repos/%s/%s/contents/%s" % [owner, repo, _encode_path("progress.json")]
                )
                if int(fetched.get("code", 0)) != 200:
                        return {"merged": 0, "changed": false, "error": "progress_pull_failed"}
                var remote_data: Variant = JSON.parse_string(fetched.body.get_string_from_utf8())
                if typeof(remote_data) == TYPE_DICTIONARY:
                        theirs = _progress_entries(fetched.body)
                        their_pace = _pace_of(remote_data)
        var merged := 0
        for card_id in theirs.keys():
                var their_state: Dictionary = theirs[card_id]
                if not mine.has(card_id):
                        mine[card_id] = their_state
                        merged += 1
                elif _progress_rank(their_state) > _progress_rank(mine[card_id]):
                        mine[card_id] = their_state
                        merged += 1
        if not their_pace.is_empty() and (
                pace.is_empty() or int(their_pace.get("mod", 0)) > int(pace.get("mod", 0))
        ):
                pace = their_pace
                merged += 1
        if not (merged > 0 or _progress_needs_push(local_path, manifest)):
                return {"merged": 0, "changed": false}
        if merged > 0:
                var file := FileAccess.open(local_path, FileAccess.WRITE)
                if file == null:
                        return {"merged": 0, "changed": false, "error": "progress_write_failed"}
                var clean := {}
                for card_id in mine.keys():
                        clean[card_id] = DeckScript.canonical_state(mine[card_id])
                var doc := {"format": DeckScript.FORMAT, "cards": clean}
                if not pace.is_empty():
                        doc["new_per_day"] = int(pace["value"])
                        doc["new_per_day_mod"] = int(pace["mod"])
                file.store_string(JSON.stringify(doc, "\t") + "\n")
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

## The pace a parsed progress document carries, if it says one: how many new
## cards a day offers, and when that choice was made. An empty dictionary
## when the document is silent.
static func _pace_of(data: Dictionary) -> Dictionary:
        var out := {}
        var value: Variant = data.get("new_per_day", null)
        if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
                out["value"] = int(value)
                var mod: Variant = data.get("new_per_day_mod", 0)
                out["mod"] = int(mod) if (
                        typeof(mod) == TYPE_INT or typeof(mod) == TYPE_FLOAT
                ) else 0
        return out

func _read_pace(path: String) -> Dictionary:
        if not FileAccess.file_exists(path):
                return {}
        var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
        if typeof(data) != TYPE_DICTIONARY:
                return {}
        return _pace_of(data)

# --- inventories ---------------------------------------------------------------

static func _local_files(deck_path: String) -> Dictionary:
        var out: Dictionary = {}
        _collect(deck_path, "", out)
        return out

static func _collect(root: String, prefix: String, out: Dictionary) -> void:
        var dir: String = root if prefix.is_empty() else root.path_join(prefix)
        for entry in DirAccess.get_files_at(dir):
                if _is_editor_metadata(entry):
                        continue
                var rel: String = entry if prefix.is_empty() else prefix.path_join(entry)
                out[rel] = _blob_sha(FileAccess.get_file_as_bytes(dir.path_join(entry)))
        for entry in DirAccess.get_directories_at(dir):
                var rel: String = entry if prefix.is_empty() else prefix.path_join(entry)
                _collect(root, rel, out)

## Godot keeps .import and .uid files beside the assets it manages; they are
## editor metadata wherever the deck folder is copied, never deck content,
## and must not ride into the user's repository.
static func _is_editor_metadata(name: String) -> bool:
        return name.ends_with(".import") or name.ends_with(".uid") or name == ".gdignore"

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
        var out: Dictionary = {}
        if typeof(tree_json) != TYPE_DICTIONARY:
                return out
        for entry in (tree_json as Dictionary).get("tree", []):
                if typeof(entry) == TYPE_DICTIONARY and str(entry.get("type", "")) == "blob":
                        out[str(entry.get("path", ""))] = str(entry.get("sha", ""))
        return out

func _load_manifest() -> Dictionary:
        return manifest_for(_deck_path)

## The last-synced checksums of one deck, read without running a sync: Home
## asks "does anything wait?" and the answer is the record the last sync
## left behind -- one small file, no network.
static func manifest_for(deck_path: String) -> Dictionary:
        if not FileAccess.file_exists(MANIFEST):
                return {}
        var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
        if typeof(data) != TYPE_DICTIONARY:
                return {}
        # One manifest per deck folder: two folders syncing one repo must not
        # mistake each other's files for already-synced ones.
        var decks: Dictionary = (data as Dictionary).get("decks", {})
        var mine: Variant = decks.get(deck_path.simplify_path(), {})
        if typeof(mine) == TYPE_DICTIONARY:
                return mine as Dictionary
        return {}

## Does this deck hold study the repo has not seen? The progress file
## differs from the bytes the last sync left behind. A deck that has never
## synced is not waiting -- it has not begun.
static func progress_dirty(deck_path: String) -> bool:
        var path := deck_path.path_join("progress.json")
        if not FileAccess.file_exists(path):
                return false
        var baseline := str(manifest_for(deck_path).get("progress.json", ""))
        if baseline.is_empty():
                return false
        return _blob_sha(FileAccess.get_file_as_bytes(path)) != baseline

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

## A batch, when the client can fly many at once; one by one otherwise.
func _request_many(batch: Array) -> Array:
        if http != null and http.has_method("request_many"):
                return await http.request_many.call(batch)
        var out: Array = []
        for spec in batch:
                out.append(
                        await http.request.call(
                                str(spec["method"]), str(spec["url"]), spec["headers"], spec["body"]
                        )
                )
        return out

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
