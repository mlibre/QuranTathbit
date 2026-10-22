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
##   both changed, differently                       -> the reader is asked which
##                                                     copy stands; the one they
##                                                     name hard-forces the other
##                                                     (progress.json never asks --
##                                                     it merges card by card)
##
## progress.json merges card by card: the entry with more reviews wins, the
## later answer breaks ties -- and a deliberate reset (a defer, a suspend)
## is judged by its moment, newer than anything older whatever the review
## count says. Two devices can study offline and both keep their work when
## they meet. It also goes out when local study moved it past the bytes the
## repo last saw -- one device studying, then syncing, is the common case,
## and it must reach the other machines.
##
## What there is to send is sent as ONE commit: the files' blobs upload
## first and then a single tree, commit and ref update land them together.
## A first sync is one tidy commit in the repo's history -- not three
## hundred. Every request flies alone, one at a time, start to finish: a
## parallel flight races the very files it carries -- the reader studies
## while a sync runs, and a batch's answer can land over a save that flew
## beneath it -- so the engine never asks the network for two things at
## once, and never moves two files in one breath.
##
## This machine's word goes first: the push lands before a single pull
## flies, so the reader's own work reaches the repo at the first
## opportunity, and the repo's word is only taken afterwards. A pull can
## be retried; a lost answer cannot be.
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
## The other road a retry may take: the same bytes, off the repo's raw
## shelf -- a different host and a different door, for the link that will
## not open one way and opens another.
const RAW_HOST := "https://raw.githubusercontent.com"
const MANIFEST := "user://sync_manifest.json"
const RAW := "application/vnd.github.raw"
const JSON_MIME := "application/vnd.github+json"

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
var _alternate_fetch := false  # this run's downloads take the raw shelf, not the API's contents door

func _init(p_http, p_auth: GitHubAuthScript) -> void:
        http = p_http
        auth = p_auth

## Run one full sync. on_progress(phrase, done, total) is called as it goes,
## with a plain phrase ("signing in", "reading repo", "merging progress",
## "uploading", "saving", "downloading") and, when the size of the phase is
## known, how far through it is.
##
## The order is the promise: progress merges first, this machine's push
## lands second, and the repo's pulls fly last -- the reader's own word
## always reaches the repo before the repo's word is taken, because a pull
## can be retried and a lost answer cannot be. Every request flies alone.
##
## A file both sides changed since the last sync is not the engine's to
## settle: on_conflict(paths) is asked which copy stands, and its word hard
## forces the other away -- "local" sends this machine's bytes over the
## repo's, "remote" pulls the repo's bytes over this machine's. Any other
## answer abandons the run before a single file moves, so nothing is ever
## replaced without the reader naming it. Without a callable the historic
## quiet default stands: this machine's copy (a scripted sync is never
## asked a question it cannot answer). Returns {ok, pushed, pulled, merged}
## or {ok: false, error, conflicts?} -- "auth_failed" is the token's own
## refusal, "network" a link that never answered, and both are told apart
## so only the network is asked again.
##
## alternate_fetch takes the other road for this run's downloads -- the
## raw shelf instead of the API's contents door -- which is what a retry
## wears: the same bytes by a different way.
func sync(
        deck_path: String,
        on_progress: Callable = Callable(),
        on_conflict: Callable = Callable(),
        alternate_fetch := false
) -> Dictionary:
        _deck_path = deck_path
        _alternate_fetch = alternate_fetch
        var settings = SettingsScript.load_settings()
        token = settings.token
        repo = settings.repo if not settings.repo.strip_edges().is_empty() else repo
        if token.strip_edges().is_empty():
                return {"ok": false, "error": "no_token"}

        _report(on_progress, "signing in", 0, 0)
        var me: Dictionary = await _get_json("/user")
        if not _ok(me):
                # A 401 is the token's own word about itself, and no asking
                # again changes it. Anything else -- no answer at all, a
                # timeout, a link that broke mid-flight -- is the network's
                # word, and the network is asked again.
                if bool(me.get("status", false)) and int(me.get("code", 0)) == 401:
                        return {"ok": false, "error": "auth_failed", "code": 401}
                return {"ok": false, "error": "network", "code": int(me.get("code", 0))}
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

        # A file this machine changed and the repo changed too, each unseen by
        # the other, is a conflict -- and a conflict is the reader's to settle,
        # never the engine's. The question is asked before anything moves, so
        # an answer names what is replaced and an abandonment replaces
        # nothing at all: the deck and the repo both stand exactly as they
        # stood, and the next sync asks again.
        var conflicts: Array = plan.filter(
                func(step: Dictionary) -> bool: return str(step.action) == "conflict"
        )
        if not conflicts.is_empty():
                var verdict := "local"
                if on_conflict.is_valid():
                        verdict = str(
                                await on_conflict.call(
                                        conflicts.map(
                                                func(step: Dictionary) -> String: return str(step.path)
                                        )
                                )
                        )
                if verdict == "remote":
                        for step in conflicts:
                                step.action = "pull"
                elif verdict == "local":
                        for step in conflicts:
                                step.action = "push"
                else:
                        return {
                                "ok": false,
                                "error": "conflict_declined",
                                "conflicts": conflicts.map(
                                        func(step: Dictionary) -> String: return str(step.path)
                                ),
                                "pushed": 0,
                                "pulled": 0,
                                "merged": 0,
                        }

        # progress.json is merged card by card, never bulk-overwritten, and the
        # merged file rides the same commit as everything else being sent.
        # The merge reads the local file only AFTER the remote copy is in
        # hand, so an answer that lands while the fetch flies is already in
        # the file when the merge reads it -- the write can never overwrite a
        # save it did not see.
        _report(on_progress, "merging progress", 0, 0)
        var merge := await _merge_progress(deck_path, remote, manifest)
        var progress_failed := merge.has("error")
        if progress_failed:
                push_error("GitHubSync: the progress merge failed (%s)" % str(merge.get("error")))

        var failed: Array = []  # transfers that did not land; the next run retries them

        var sends: Array = []  # local files the repo must receive
        for step in plan:
                if str(step.action) == "push" and FileAccess.file_exists(deck_path.path_join(str(step.path))):
                        sends.append(str(step.path))
        var deletes: Array = plan.filter(
                func(step: Dictionary) -> bool: return str(step.action) == "delete"
        ).map(func(step: Dictionary) -> String: return str(step.path))
        if bool(merge.get("changed", false)) and not progress_failed:
                sends.append("progress.json")

        # This machine's word goes first: the blobs, the tree, the commit and
        # the ref all land before a single pull flies, so whatever the reader
        # has already said is safe in the repo even when the run dies halfway
        # -- a pull can be retried, a lost answer cannot be.
        var pushed := 0
        var settled_head := head
        var commit_failed := false
        var landed_sends: Dictionary = {}  # the blobs that truly reached the repo
        var blob_shas: Dictionary = {}
        if not (sends.is_empty() and deletes.is_empty()):
                _report(on_progress, "uploading", 0, sends.size())
                blob_shas = await _create_blobs(deck_path, sends, on_progress)
                var missing := sends.filter(func(path: String) -> bool: return not blob_shas.has(path))
                if not missing.is_empty():
                        # Nothing has landed yet -- a failed blob means no commit -- so
                        # the next run simply tries again.
                        failed.append_array(missing)
                else:
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
                                        if bool(landed.get("ok", false)):
                                                # The repo the retry landed against is a different
                                                # tree than the run planned against: the manifest
                                                # must speak of the one the commit really sits on.
                                                remote = _tree_shas(fresh_tree.body_json)
                        if not bool(landed.get("ok", false)):
                                commit_failed = true
                        else:
                                if landed.has("sha"):
                                        settled_head = str(landed.sha)
                                pushed = sends.size() + deletes.size()
                                landed_sends = blob_shas

        # The repo's word arrives after this machine's was said: each pull is
        # one file this deck has never changed, fetched alone, written home,
        # counted -- the next one waits for this one to land. A push that
        # failed does not stop the pulls: what the repo holds is this deck's
        # to receive whatever became of its own sending.
        var pulls: Array = plan.filter(func(step: Dictionary) -> bool: return str(step.action) == "pull")
        var pulled := 0
        var pull_done := 0
        _report(on_progress, "downloading", 0, pulls.size())
        for step in pulls:
                var response: Dictionary = await _fetch_file(str(step.path))
                if _write_pulled(deck_path, str(step.path), response):
                        pulled += 1
                else:
                        failed.append(str(step.path))
                pull_done += 1
                _report(on_progress, "downloading", pull_done, pulls.size())

        # Everything the repo now holds is the new baseline -- the bytes that
        # actually flew, never a re-reading of the disk, which may have moved
        # beneath the run (a reader answering while the commit flew). A
        # baseline that flattered the disk could name an answer the repo
        # never received as "already agreed", and the next sync would say
        # "in step" forever. Anything that failed to transfer stays out of
        # both, so the next run looks at the tree again and retries.
        var clean_finish: bool = failed.is_empty() and not progress_failed and not commit_failed
        if not commit_failed:
                _write_manifest(
                        remote, landed_sends,
                        deletes, failed, "progress.json" if progress_failed else "",
                        settled_head if clean_finish else ""
                )

        return {
                "ok": failed.is_empty() and not progress_failed and not commit_failed,
                "pushed": pushed,
                "pulled": pulled,
                "merged": int(merge.get("merged", 0)),
                "failed": failed,
        }

## The last-synced checksums of one run, told from the repo's side: every
## deck file the tree listed, with this run's landed blobs pinned to the
## bytes that actually flew, the deletions gone, the failures absent, and
## the branch's HEAD remembered beside them. What the repo holds is what
## "already synced" means -- the disk's own word is never asked, because the
## disk can move while a run flies.
func _write_manifest(
        remote: Dictionary, sent: Dictionary, deletes: Array,
        failed: Array, progress_failed_path: String, settled_head := ""
) -> void:
        var fresh: Dictionary = {}
        for path in remote.keys():
                if not _is_deck_path(str(path)):
                        continue
                if deletes.has(path) or failed.has(path) or path == progress_failed_path:
                        continue
                # A machine that does not carry media must not remember it as
                # agreed: the manifest is what "already synced" means, and a
                # browser never agreed about files it cannot hold.
                if not carry_media and _is_media(str(path)):
                        continue
                fresh[str(path)] = str(sent.get(str(path), remote[path]))
        for path in sent.keys():
                if failed.has(path) or path == progress_failed_path:
                        continue
                if not carry_media and _is_media(str(path)):
                        continue
                fresh[str(path)] = str(sent[path])
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
                elif synced_sha == remote_sha:
                        plan.append({"action": "push", "path": path})  # changed here; the repo slept
                else:
                        plan.append({"action": "conflict", "path": path})  # changed in both places
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

## One fetched file, fetched alone: a single request, a single answer, the
## next one waiting for this one to land. The engine never asks the network
## for two things at once -- a parallel flight races the very files it
## carries. The usual road is the API's contents door; an alternate run
## takes the raw shelf instead -- a different host, a different door, the
## same bytes -- because a link that will not open one way sometimes opens
## another.
func _fetch_file(path: String) -> Dictionary:
        var headers := _auth_headers()
        headers["Accept"] = RAW
        return await http.request.call("GET", _download_url(path), headers, PackedByteArray())


## Where a file is fetched from this run: the API's contents door, or --
## when the run is itself a retry -- the raw shelf the same bytes sit on.
func _download_url(path: String) -> String:
        if _alternate_fetch:
                return "%s/%s/%s/%s/%s" % [RAW_HOST, owner, repo, _branch, _encode_path(path)]
        return "%s/repos/%s/%s/contents/%s" % [API, owner, repo, _encode_path(path)]

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

## Upload every file's blob, one at a time: a single request, a single
## answer, the next file waiting for this one's sha. Returns {path: blob
## sha}; a path missing from the answer failed and must be retried next
## sync.
func _create_blobs(deck_path: String, sends: Array, on_progress: Callable) -> Dictionary:
        var shas: Dictionary = {}
        var done := 0
        for path in sends:
                var bytes := FileAccess.get_file_as_bytes(deck_path.path_join(path))
                var headers := _auth_headers()
                headers["Accept"] = JSON_MIME
                headers["Content-Type"] = "application/json"
                var response: Dictionary = await http.request.call(
                        "POST", API + "/repos/%s/%s/git/blobs" % [owner, repo], headers,
                        JSON.stringify(
                                {"content": Marshalls.raw_to_base64(bytes), "encoding": "base64"}
                        ).to_utf8_buffer()
                )
                var body: Variant = _parse_json(response.body)
                if int(response.get("code", 0)) == 201 and typeof(body) == TYPE_DICTIONARY and (body as Dictionary).has("sha"):
                        shas[str(path)] = str((body as Dictionary).sha)
                else:
                        push_error(
                                "GitHubSync: blob %s failed (%d)" % [path, int(response.get("code", 0))]
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

## Card by card: more reviews wins, then the later answer -- unless one
## side is a deliberate reset (a defer, a suspend: nothing answered, yet
## touched at a known moment), which is judged by its moment alone, newer
## than anything older and older than anything newer, whatever either
## side's review count says. The reader's own choices ride the same merge:
## the choice made later wins, the way a later answer breaks a card's tie.
## The file goes to the repo when the merge changed it or when local study
## moved it past the bytes the repo last saw.
##
## The remote copy is fetched FIRST and the local file read only afterwards
## -- the one wait in the merge sits before the read, never between the
## read and the write. A reader answers while the fetch flies (the merge
## runs under the whole app, and the app does not stop for it); the answer
## saves to the file mid-flight, and the merge's later read sees it, so the
## write can never overwrite a save it did not see. The old order read the
## file first and wrote a merge built from a copy that predated the answer
## -- the answer vanished, and the card returned as new.
func _merge_progress(deck_path: String, remote: Dictionary, manifest: Dictionary) -> Dictionary:
        var local_path := deck_path.path_join("progress.json")
        var remote_sha := str(remote.get("progress.json", ""))
        var baseline := str(manifest.get("progress.json", ""))
        # Both sides exactly as the last sync left them: there is nothing to
        # merge and nothing to send, and no reason to fetch the file at all.
        # Downloading it anyway made every sync look like a full round trip.
        if not remote_sha.is_empty() and remote_sha == baseline and not _progress_needs_push(local_path, manifest):
                return {"merged": 0, "changed": false}
        var theirs: Dictionary = {}
        var their_choices: Dictionary = {}
        if not remote_sha.is_empty():
                var fetched: Dictionary = await _get_raw("progress.json")
                if int(fetched.get("code", 0)) != 200:
                        return {"merged": 0, "changed": false, "error": "progress_pull_failed"}
                var remote_data: Variant = JSON.parse_string(fetched.body.get_string_from_utf8())
                if typeof(remote_data) == TYPE_DICTIONARY:
                        theirs = DeckScript.entries_of(remote_data)
                        their_choices = DeckScript.choices_of(remote_data)
        # The local word, read as late as the merge can read it -- after every
        # wait, so that read, merge and write are one breath: no answer can
        # land inside them, and none can be overwritten from outside them.
        var mine := _read_progress(local_path)
        var choices := _read_choices(local_path)
        var merged := 0
        for card_id in theirs.keys():
                var their_state: Dictionary = theirs[card_id]
                if not mine.has(card_id):
                        mine[card_id] = their_state
                        merged += 1
                elif DeckScript.state_beats(their_state, mine[card_id]):
                        mine[card_id] = their_state
                        merged += 1
        for key in DeckScript.CHOICE_KEYS:
                var their_choice: Dictionary = their_choices.get(key, {})
                if their_choice.is_empty():
                        continue
                var mine_choice: Dictionary = choices.get(key, {})
                if mine_choice.is_empty() or int(their_choice.get("mod", 0)) > int(mine_choice.get("mod", 0)):
                        choices[key] = their_choice
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
                for key in choices.keys():
                        var choice: Dictionary = choices[key]
                        doc[key] = choice["value"]
                        doc[key + "_mod"] = int(choice["mod"])
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

## The card entries and travelling choices a progress document carries are
## read by the deck's own law (DeckScript.entries_of / choices_of), told
## once for both doors that merge a deck -- this one and the backup's
## import -- so they can never disagree.
func _read_progress(path: String) -> Dictionary:
        if not FileAccess.file_exists(path):
                return {}
        var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
        if typeof(data) != TYPE_DICTIONARY:
                return {}
        return DeckScript.entries_of(data)

func _read_choices(path: String) -> Dictionary:
        if not FileAccess.file_exists(path):
                return {}
        var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
        if typeof(data) != TYPE_DICTIONARY:
                return {}
        return DeckScript.choices_of(data)

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
        return await http.request.call("GET", _download_url(path), headers, PackedByteArray())

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
