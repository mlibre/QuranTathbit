extends SceneTree
const SyncScript := preload("res://scripts/net/github_sync.gd")
const AuthScript := preload("res://scripts/net/github_auth.gd")

## Sync is the promise the app makes: two devices can study offline and
## both keep their work. These tests drive the sync engine against a fake HTTP
## client that behaves like the slice of GitHub's API the app uses -- user,
## repo, ref, tree, blob, commit -- and check the three-way merge, file by
## file, the progress merge card by card, that everything a sync sends lands
## as one commit, that a failed transfer is retried on the next run instead
## of being silently forgotten, and that Godot's editor metadata and (on the
## web) media never travel.

const DECK := "user://test_sync_deck"

const API := "https://api.github.com"

var _failures := 0

func _init() -> void:
        await _test_first_push_pulls_nothing()
        await _test_second_device_pulls()
        await _test_local_edit_wins()
        await _test_progress_merges()
        await _test_local_progress_pushes()
        await _test_pace_travels_with_progress()
        await _test_quiet_sync_transfers_nothing()
        await _test_quiet_sync_asks_for_nothing()
        await _test_failed_push_retries()
        await _test_ref_conflict_retries()
        await _test_head_short_circuit()
        await _test_foreign_files_are_left_alone()
        await _test_shared_deck_arrives()
        await _test_editor_metadata_never_travels()
        await _test_web_skips_media()
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
        var blobs := {}  # blob sha -> bytes, exactly what the blobs API holds
        var commits := 0
        var head := "head-0"  # the ref the branch points at, one truth for every answer
        var tree_gets := 0  # full tree walks, the thing a settled sync never makes
        var fail_blobs := false  # every blob POST answers 500
        var ref_conflicts := 0  # the first ref updates answer 409
        var blob_posts := 0  # uploads, even the ones that fail
        var tree_posts := 0
        var commit_posts := 0
        var content_gets := 0  # file downloads, progress included

        func _init() -> void:
                files["README.md"] = {"sha": _content_sha("hello".to_utf8_buffer()), "content": "hello".to_utf8_buffer()}

        ## Speaks the small slice of the GitHub API the app uses.
        func request(method: String, url: String, _headers: Dictionary, body: PackedByteArray) -> Dictionary:
                var path := _content_path(url)
                if url.ends_with("/user"):
                        return _json(200, {"login": "tester"})
                if url.ends_with("/user/repos"):
                        return _json(201, {"default_branch": "main"})
                if method == "GET" and url.contains("/git/ref/heads/"):
                        return _json(200, {"object": {"sha": head}})
                if method == "POST" and url.ends_with("/git/blobs"):
                        blob_posts += 1
                        if fail_blobs:
                                return _json(500, {})
                        var payload: Variant = JSON.parse_string(body.get_string_from_utf8())
                        if typeof(payload) != TYPE_DICTIONARY:
                                return _json(400, {})
                        var content := Marshalls.base64_to_raw(str((payload as Dictionary).get("content", "")))
                        var sha := _content_sha(content)
                        blobs[sha] = content
                        return _json(201, {"sha": sha})
                if method == "POST" and url.ends_with("/git/trees"):
                        tree_posts += 1
                        return _make_tree(body)
                if method == "POST" and url.ends_with("/git/commits"):
                        commit_posts += 1
                        commits += 1
                        head = "head-%d" % commits
                        return _json(201, {"sha": head})
                if method == "PATCH" and url.contains("/git/refs/heads/"):
                        if ref_conflicts > 0:
                                ref_conflicts -= 1
                                return _json(409, {})
                        return _json(200, {"object": {"sha": head}})
                if method == "GET" and url.contains("/git/trees/"):
                        tree_gets += 1
                        var tree := []
                        for p in files.keys():
                                tree.append({"path": p, "sha": files[p].sha, "type": "blob"})
                        return _json(200, {"sha": "tree-listed", "tree": tree})
                if method == "GET" and url.contains("/repos/") and path.is_empty():
                        return _json(200, {"default_branch": "main"})
                if method == "GET" and not path.is_empty():
                        content_gets += 1
                        if not files.has(path):
                                return _json(404, {})
                        return _raw(200, files[path].content)
                return _json(404, {})

        ## Another device pushed: the file changes and the branch moves,
        ## together, the way a real commit does both at once.
        func commit_change(path: String, content: String) -> void:
                commits += 1
                head = "head-%d" % commits
                files[path] = {
                        "sha": _content_sha(content.to_utf8_buffer()),
                        "content": content.to_utf8_buffer(),
                }

        ## One tree carries everything a sync says: new blobs land, entries with
        ## a null sha vanish, and everything else -- the user's own files -- keeps
        ## its place, which is what base_tree means.
        func _make_tree(body: PackedByteArray) -> Dictionary:
                var payload: Variant = JSON.parse_string(body.get_string_from_utf8())
                if typeof(payload) != TYPE_DICTIONARY:
                        return _json(400, {})
                for entry in (payload as Dictionary).get("tree", []):
                        if typeof(entry) != TYPE_DICTIONARY:
                                continue
                        var entry_path := str((entry as Dictionary).get("path", ""))
                        if (entry as Dictionary).get("sha", null) == null:
                                files.erase(entry_path)
                                continue
                        var sha := str((entry as Dictionary).get("sha", ""))
                        if blobs.has(sha):
                                files[entry_path] = {"sha": sha, "content": blobs[sha]}
                return _json(201, {"sha": "tree-%d" % (commits + 1)})

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

        ## The checksums a real GitHub lists: git blob checksums of the content.
        static func _content_sha(content: PackedByteArray) -> String:
                var head := ("blob %d" % content.size()).to_utf8_buffer()
                head.append(0)
                var h := HashingContext.new()
                h.start(HashingContext.HASH_SHA1)
                h.update(head)
                h.update(content)
                return h.finish().hex_encode()

## The client the sync engine sees: the same methods, backed by the fake.
class FakeHttp:
        extends RefCounted

        var request: Callable
        var request_json: Callable

        ## The engine batches its downloads; the fake answers a batch as a
        ## run of asks, in order, exactly what the batch promises.
        func request_many(batch: Array) -> Array:
                var out: Array = []
                out.resize(batch.size())
                for i in batch.size():
                        var spec: Dictionary = batch[i]
                        out[i] = request.call(str(spec["method"]), str(spec["url"]), spec["headers"], spec["body"])
                return out

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

func _write_bytes(path: String, data: PackedByteArray) -> void:
        var file := FileAccess.open(path, FileAccess.WRITE)
        file.store_buffer(data)
        file.close()

func _write_progress(entries: Dictionary) -> void:
        _write(DECK.path_join("progress.json"), JSON.stringify({"format": 1, "cards": entries}) + "\n")

## A whole progress document, pace included -- the file as the app itself
## writes it, not just its cards.
func _write_progress_doc(doc: Dictionary) -> void:
        _write(DECK.path_join("progress.json"), JSON.stringify(doc) + "\n")

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
        _is(fake.commits, 1, "a first sync is one commit, not one per file (got %d)" % fake.commits)
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
        fake.commit_change("001/front.md", "Q1 edited there")
        var result: Dictionary = await sync.sync(DECK)
        _ok(bool(result.get("ok", false)), "a conflicting sync completes")
        _is(_read(DECK.path_join("001/front.md")), "Q1 edited here", "the local edit wins a content conflict")
        # And an untouched file follows the remote.
        fake.commit_change("001/back.md", "A1 edited there")
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
        fake.commit_change("progress.json", (JSON.stringify({"format": 1, "cards": {
                "001": {"status": "review", "ivl": 10, "ease": 2.5, "reps": 9, "lapses": 1, "mod": 2000, "due_day": 100, "step": 0, "relearning": false, "due_ts": 0},
        }}) + "\n"))
        var result: Dictionary = await sync.sync(DECK)
        _ok(bool(result.get("ok", false)), "a progress sync completes")
        _is(result.merged, 1, "one card's progress merges in (got %d)" % result.merged)
        var merged: Variant = JSON.parse_string(_read(DECK.path_join("progress.json")))
        var cards: Dictionary = (merged as Dictionary).cards
        _is(cards["001"].reps, 9, "the deeper study wins the merge")
        _is(cards["002"].reps, 1, "the local study the remote never saw is kept")

## Local study must reach the repo even when the remote never moved: that is
## the common case -- one device studies, then syncs.
func _test_local_progress_pushes() -> void:
        _write_deck({"001": ["Q1", "A1"]})
        var fake := FakeGitHub.new()
        var sync := _make_sync(fake)
        await sync.sync(DECK)
        # This device studies; the repo has never seen progress.
        _write_progress({
                "001": {"status": "review", "ivl": 4, "ease": 2.5, "reps": 5, "lapses": 0, "mod": 2000, "due_day": 100, "step": 0, "relearning": false, "due_ts": 0},
        })
        var result: Dictionary = await sync.sync(DECK)
        _ok(bool(result.get("ok", false)), "a sync after local study succeeds (%s)" % str(result.get("error", "")))
        _ok(fake.files.has("progress.json"), "the repo receives the local progress")
        if fake.files.has("progress.json"):
                var arrived: Variant = JSON.parse_string(fake.files["progress.json"].content.get_string_from_utf8())
                var state: Variant = {} if typeof(arrived) != TYPE_DICTIONARY else (arrived as Dictionary).get("cards", {}).get("001", {})
                _ok(typeof(state) == TYPE_DICTIONARY and int((state as Dictionary).get("reps", 0)) == 5, "the repo holds the studied card's progress")
        # More study on the same card: the repo follows the deeper work.
        _write_progress({
                "001": {"status": "review", "ivl": 6, "ease": 2.5, "reps": 7, "lapses": 0, "mod": 3000, "due_day": 100, "step": 0, "relearning": false, "due_ts": 0},
        })
        var again: Dictionary = await sync.sync(DECK)
        _ok(bool(again.get("ok", false)), "a second sync after more study succeeds")
        var remote_state: Variant = JSON.parse_string(fake.files["progress.json"].content.get_string_from_utf8())
        var state_after: Variant = {} if typeof(remote_state) != TYPE_DICTIONARY else (remote_state as Dictionary).get("cards", {}).get("001", {})
        _ok(typeof(state_after) == TYPE_DICTIONARY and int((state_after as Dictionary).get("reps", 0)) == 7, "the repo follows the deeper local study")

## The reader's own pace -- how many new cards a day offers -- rides the
## progress file through every door it has: chosen here, it reaches the repo;
## chosen later on another device, it arrives here; chosen earlier there, it
## never overwrites the newer word this deck already holds.
func _test_pace_travels_with_progress() -> void:
        _write_deck({"001": ["Q1", "A1"]})
        var fake := FakeGitHub.new()
        var sync := _make_sync(fake)
        await sync.sync(DECK)
        _write_progress_doc({"format": 1, "cards": {}, "new_per_day": 12, "new_per_day_mod": 5000})
        var result: Dictionary = await sync.sync(DECK)
        _ok(bool(result.get("ok", false)), "a sync after a pace choice succeeds (%s)" % str(result.get("error", "")))
        var arrived: Variant = JSON.parse_string(fake.files["progress.json"].content.get_string_from_utf8())
        _ok(
                typeof(arrived) == TYPE_DICTIONARY and int((arrived as Dictionary).get("new_per_day", -1)) == 12,
                "the chosen pace reaches the repo"
        )
        # Another device chooses a later pace; it arrives here.
        fake.commit_change(
                "progress.json",
                JSON.stringify({"format": 1, "cards": {}, "new_per_day": 30, "new_per_day_mod": 9000}) + "\n"
        )
        var later: Dictionary = await sync.sync(DECK)
        _ok(bool(later.get("ok", false)), "a sync with a later remote pace succeeds")
        var local: Variant = JSON.parse_string(_read(DECK.path_join("progress.json")))
        _is(int((local as Dictionary).get("new_per_day", -1)), 30, "the later pace becomes this device's own")
        # An older remote choice never wins.
        fake.commit_change(
                "progress.json",
                JSON.stringify({"format": 1, "cards": {}, "new_per_day": 5, "new_per_day_mod": 7000}) + "\n"
        )
        var older: Dictionary = await sync.sync(DECK)
        _ok(bool(older.get("ok", false)), "a sync with an older remote pace succeeds")
        var kept: Variant = JSON.parse_string(_read(DECK.path_join("progress.json")))
        _is(int((kept as Dictionary).get("new_per_day", -1)), 30, "the newer local pace is kept")

## A sync where nothing changed anywhere must move nothing: the checksums
## agree, so no file is sent and none is pulled, and no commit is made.
func _test_quiet_sync_transfers_nothing() -> void:
        _write_deck({"001": ["Q1", "A1"]})
        var fake := FakeGitHub.new()
        var sync := _make_sync(fake)
        await sync.sync(DECK)
        _write_progress({
                "001": {"status": "review", "ivl": 4, "ease": 2.5, "reps": 2, "lapses": 0, "mod": 1000, "due_day": 100, "step": 0, "relearning": false, "due_ts": 0},
        })
        await sync.sync(DECK)  # the progress reaches the repo once
        var commits_before := fake.commits
        var quiet: Dictionary = await sync.sync(DECK)
        _ok(bool(quiet.get("ok", false)), "a quiet sync succeeds")
        _is(quiet.pushed, 0, "a quiet sync pushes nothing (got %d)" % quiet.pushed)
        _is(quiet.pulled, 0, "a quiet sync pulls nothing (got %d)" % quiet.pulled)
        _is(fake.commits, commits_before, "a quiet sync commits nothing")

## A quiet sync must not merely move nothing -- it must not even ask. The
## remote progress file used to be fetched on every run even when both
## sides matched the last sync's record of them, so every sync carried the
## shape of a full round trip: a status check should cost a handful of
## lookups, never a file.
func _test_quiet_sync_asks_for_nothing() -> void:
        _write_deck({"001": ["Q1", "A1"]})
        var fake := FakeGitHub.new()
        var sync := _make_sync(fake)
        await sync.sync(DECK)
        _write_progress({
                "001": {"status": "review", "ivl": 4, "ease": 2.5, "reps": 3, "lapses": 0, "mod": 1000, "due_day": 100, "step": 0, "relearning": false, "due_ts": 0},
        })
        await sync.sync(DECK)  # the progress reaches the repo once
        fake.blob_posts = 0
        fake.tree_posts = 0
        fake.commit_posts = 0
        fake.content_gets = 0
        var quiet: Dictionary = await sync.sync(DECK)
        _ok(bool(quiet.get("ok", false)), "a quiet sync succeeds")
        _is(fake.content_gets, 0, "a quiet sync fetches no file (got %d)" % fake.content_gets)
        _is(fake.blob_posts, 0, "a quiet sync uploads no blob (got %d)" % fake.blob_posts)
        _is(fake.tree_posts, 0, "a quiet sync posts no tree (got %d)" % fake.tree_posts)
        _is(fake.commit_posts, 0, "a quiet sync commits nothing (got %d)" % fake.commit_posts)
        # And the deck itself can answer the same question without the
        # network at all: this is the line Home shows between syncs.
        _ok(not SyncScript.progress_dirty(DECK), "a synced deck reports nothing waiting")
        _write_progress({
                "001": {"status": "review", "ivl": 8, "ease": 2.5, "reps": 4, "lapses": 0, "mod": 2000, "due_day": 100, "step": 0, "relearning": false, "due_ts": 0},
        })
        _ok(SyncScript.progress_dirty(DECK), "a studied deck reports answers waiting")

func _test_failed_push_retries() -> void:
        _write_deck({"001": ["Q1", "A1"]})
        var fake := FakeGitHub.new()
        var sync := _make_sync(fake)
        await sync.sync(DECK)
        # A card changes here; the upload of its blob fails.
        _write(DECK.path_join("001/front.md"), "Q1 changed")
        fake.fail_blobs = true
        var result: Dictionary = await sync.sync(DECK)
        _ok(not bool(result.get("ok", false)), "a failed transfer is reported, not swallowed")
        _is(
                fake.files["001/front.md"].content.get_string_from_utf8(), "Q1",
                "nothing landed while the upload failed"
        )
        # The next run must try the same file again, not assume it is synced.
        fake.fail_blobs = false
        var again: Dictionary = await sync.sync(DECK)
        _ok(bool(again.get("ok", false)), "the retry succeeds")
        _ok(again.pushed >= 1, "the failed file is pushed on the retry (got %d)" % again.pushed)
        _is(fake.files["001/front.md"].content.get_string_from_utf8(), "Q1 changed", "the retried file's content is the local one")

## Two machines syncing at once: the ref has moved by the time this one
## commits, GitHub answers 409, and the engine re-commits onto the new head.
func _test_ref_conflict_retries() -> void:
        _write_deck({"001": ["Q1", "A1"]})
        var fake := FakeGitHub.new()
        var sync := _make_sync(fake)
        await sync.sync(DECK)
        _write(DECK.path_join("001/front.md"), "Q1 raced")
        fake.ref_conflicts = 1
        var result: Dictionary = await sync.sync(DECK)
        _ok(bool(result.get("ok", false)), "a sync past a moved ref succeeds (%s)" % str(result.get("error", "")))
        _is(fake.files["001/front.md"].content.get_string_from_utf8(), "Q1 raced", "the raced edit lands after the retry")

## Git's own shortcut: a sync with nothing to say against an unmoved
## branch asks its two questions and stops -- no tree walk, no file
## fetches. A moved branch or a local edit gets the full exchange.
func _test_head_short_circuit() -> void:
        _write_deck({"001": ["Q1", "A1"]})
        var fake := FakeGitHub.new()
        var sync := _make_sync(fake)
        await sync.sync(DECK)
        _write_progress({
                "001": {"status": "review", "ivl": 4, "ease": 2.5, "reps": 2, "lapses": 0, "mod": 1000, "due_day": 100, "step": 0, "relearning": false, "due_ts": 0},
        })
        await sync.sync(DECK)  # the progress lands once; the branch is remembered
        fake.tree_gets = 0
        fake.blob_posts = 0
        var in_step: Dictionary = await sync.sync(DECK)
        _ok(bool(in_step.get("ok", false)), "a settled sync against an unmoved branch succeeds")
        _is(fake.tree_gets, 0, "an unmoved branch is not even walked (got %d)" % fake.tree_gets)
        _is(fake.blob_posts, 0, "nothing is uploaded when there is nothing to say")
        # Another device pushes: the branch moves, and the sync looks again.
        fake.commit_change("001/back.md", "A1 from elsewhere")
        fake.tree_gets = 0
        var moved: Dictionary = await sync.sync(DECK)
        _ok(bool(moved.get("ok", false)), "a sync past a moved branch succeeds")
        _ok(fake.tree_gets >= 1, "a moved branch is walked again")
        _is(_read(DECK.path_join("001/back.md")), "A1 from elsewhere", "the local deck follows the branch")
        # A local edit speaks even against an unmoved branch.
        _write(DECK.path_join("001/front.md"), "Q1 changed here")
        fake.blob_posts = 0
        var speaking: Dictionary = await sync.sync(DECK)
        _ok(bool(speaking.get("ok", false)), "a sync with a local edit succeeds")
        _ok(fake.blob_posts >= 1, "a local edit is uploaded, whatever the branch says")

func _test_foreign_files_are_left_alone() -> void:
        _write_deck({"001": ["Q1", "A1"]})
        var fake := FakeGitHub.new()
        var sync := _make_sync(fake)
        await sync.sync(DECK)
        # The user's own repo files must never be touched.
        fake.commit_change("my-notes.md", "mine")
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

## Godot's .import and .uid sidecars are editor metadata: they must never
## reach the repo, and never be pulled into a fresh deck from a repo whose
## older syncs put them there.
func _test_editor_metadata_never_travels() -> void:
        _write_deck({"001": ["Q1", "A1"]})
        _write(DECK.path_join("001/verse.mp3.import"), "editor metadata")
        var fake := FakeGitHub.new()
        var sync := _make_sync(fake)
        var result: Dictionary = await sync.sync(DECK)
        _ok(bool(result.get("ok", false)), "a sync beside editor metadata succeeds")
        _ok(not fake.files.has("001/verse.mp3.import"), "editor metadata is never uploaded")
        # A fresh device meets a repo an older sync left metadata in.
        var stale := "user://test_sync_stale"
        _remove_tree(stale)
        DirAccess.make_dir_recursive_absolute(stale)
        fake.files["001/verse.mp3.import"] = {"sha": "junk", "content": "editor metadata".to_utf8_buffer()}
        var adopt: Dictionary = await _make_sync(fake).sync(stale)
        _ok(bool(adopt.get("ok", false)), "a fresh device syncs from a stale repo")
        _ok(not FileAccess.file_exists(stale.path_join("001/verse.mp3.import")), "editor metadata is not pulled")
        _remove_tree(stale)

## A browser streams its recitations from the site it was served from, so
## sync there carries the deck's text and never its media; the default on
## every other platform is to carry everything.
func _test_web_skips_media() -> void:
        _write_deck({"001": ["Q1", "A1"]})
        _write_bytes(DECK.path_join("001/verse.mp3"), "LOCALAUDIO".to_utf8_buffer())
        var fake := FakeGitHub.new()
        fake.files["002/remote.mp3"] = {
                "sha": FakeGitHub._content_sha("REMOTEAUDIO".to_utf8_buffer()),
                "content": "REMOTEAUDIO".to_utf8_buffer(),
        }
        var webby := _make_sync(fake)
        webby.carry_media = false
        var result: Dictionary = await webby.sync(DECK)
        _ok(bool(result.get("ok", false)), "a web-style sync succeeds")
        _ok(not fake.files.has("001/verse.mp3"), "a web sync uploads no media")
        _ok(not FileAccess.file_exists(DECK.path_join("002/remote.mp3")), "a web sync downloads no media")
        # The desktop default still carries everything.
        var plain: Dictionary = await _make_sync(fake).sync(DECK)
        _ok(bool(plain.get("ok", false)), "a desktop sync succeeds after the web one")
        _ok(fake.files.has("001/verse.mp3"), "a desktop sync uploads the media")

func _teardown() -> void:
        _remove_tree(DECK)
        _remove_tree("user://test_sync_pull")
        _remove_tree("user://test_sync_stale")
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
