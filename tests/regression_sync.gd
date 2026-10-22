extends SceneTree
const SyncScript := preload("res://scripts/net/github_sync.gd")
const AuthScript := preload("res://scripts/net/github_auth.gd")

## Sync is the promise the app makes: two devices can study offline and
## both keep their work. These tests drive the sync engine against a fake HTTP
## client that behaves like the slice of GitHub's API the app uses -- user,
## repo, ref, tree, blob, commit -- and check the three-way merge, file by
## file, the progress merge card by card, that everything a sync sends lands
## as one commit, that a failed transfer is retried on the next run instead
## of being silently forgotten, that Godot's editor metadata and (on the
## web) media never travel, that a dropped signin is the network's failure
## and not the token's, and that a download the API's door would not serve
## lands by the raw shelf when the run takes the other road.

const DECK := "user://test_sync_deck"

const API := "https://api.github.com"

var _failures := 0

func _init() -> void:
        await _test_first_push_pulls_nothing()
        await _test_second_device_pulls()
        await _test_local_edit_wins()
        await _test_progress_merges()
        await _test_defer_survives_the_merge()
        await _test_local_progress_pushes()
        await _test_pace_travels_with_progress()
        await _test_quiet_sync_transfers_nothing()
        await _test_quiet_sync_asks_for_nothing()
        await _test_failed_push_retries()
        await _test_failed_download_retries_the_other_road()
        await _test_signin_blip_is_the_network_not_the_token()
        await _test_ref_conflict_retries()
        await _test_head_short_circuit()
        await _test_foreign_files_are_left_alone()
        await _test_shared_deck_arrives()
        await _test_editor_metadata_never_travels()
        await _test_web_skips_media()
        await _test_conflict_asks_and_local_hard_forces()
        await _test_conflict_remote_hard_forces()
        await _test_conflict_declined_replaces_nothing()
        await _test_mid_fetch_answer_survives()
        await _test_push_lands_before_pull()
        await _test_answer_after_upload_still_pushes()
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
        var fail_contents := false  # every API contents GET answers as a link that never opened
        var fail_user := 0  # the first N signins answer as a link that never opened
        var refuse_user := 0  # the first N signins answer 401, the token's own refusal
        var raw_gets := 0  # downloads off the raw shelf, the other road
        var ref_conflicts := 0  # the first ref updates answer 409
        var blob_posts := 0  # uploads, even the ones that fail
        var tree_posts := 0
        var commit_posts := 0
        var content_gets := 0  # file downloads, progress included
        var order: Array = []  # every ask in the order it flew: "METHOD url"
        var on_contents_get: Callable = Callable()  # the test's own hand inside a file fetch
        var on_ref_patch: Callable = Callable()  # the test's own hand inside the commit's landing

        func _init() -> void:
                files["README.md"] = {"sha": _content_sha("hello".to_utf8_buffer()), "content": "hello".to_utf8_buffer()}

        ## Speaks the small slice of the GitHub API the app uses.
        func request(method: String, url: String, _headers: Dictionary, body: PackedByteArray) -> Dictionary:
                order.append("%s %s" % [method, url])
                var path := _content_path(url)
                if url.ends_with("/user"):
                        if refuse_user > 0:
                                refuse_user -= 1
                                return _json(401, {"message": "Bad credentials"})
                        if fail_user > 0:
                                fail_user -= 1
                                return _dead()
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
                        if on_ref_patch.is_valid():
                                on_ref_patch.call()
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
                if method == "GET" and url.begins_with("https://raw.githubusercontent.com/"):
                        # The raw shelf: owner/repo/branch, then the file -- the
                        # same bytes the contents door serves, by another door.
                        raw_gets += 1
                        var parts := url.substr("https://raw.githubusercontent.com/".length()).split("/")
                        var raw_path := ("/".join(parts.slice(3))).uri_decode()
                        if not files.has(raw_path):
                                return _json(404, {})
                        return _raw(200, files[raw_path].content)
                if method == "GET" and not path.is_empty():
                        content_gets += 1
                        if fail_contents:
                                return _dead()
                        if on_contents_get.is_valid():
                                on_contents_get.call(path)
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

        ## A link that never opened: no status, no code -- the shape a
        ## dropped connection leaves behind, where no answer ever came.
        static func _dead() -> Dictionary:
                return {"status": false, "code": 0, "headers": {}, "body": PackedByteArray()}

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
## There is deliberately no batch shape here -- the engine asks for one
## thing at a time, and a client that could fly many would let that law
## drift back in unnoticed.
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
        # The card is edited here and there at once, and nobody is asked:
        # the quiet scripted default is this machine's copy.
        _write(DECK.path_join("001/front.md"), "Q1 edited here")
        fake.commit_change("001/front.md", "Q1 edited there")
        var result: Dictionary = await sync.sync(DECK)
        _ok(bool(result.get("ok", false)), "a conflicting sync completes")
        _is(_read(DECK.path_join("001/front.md")), "Q1 edited here", "the local edit stands when nobody is asked")
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

## A defer or a suspend is a deliberate act, later than any answer before
## it -- and the merge must see that, or the card the reader put back
## returns with the very answers the defer was later than. The repo holds
## the card answered; the reader defers or suspends it here; the sync that
## follows must keep the reader's act, and the repo must carry it away.
## An answer that arrives from another device AFTER the act is newer
## learning, and wins -- the card returns to study, as it should.
func _test_defer_survives_the_merge() -> void:
        _write_deck({"001": ["Q1", "A1"], "002": ["Q2", "A2"]})
        var fake := FakeGitHub.new()
        var sync := _make_sync(fake)
        # Both cards were studied and pushed: the repo holds them answered.
        _write_progress({
                "001": {"status": "review", "ivl": 4, "ease": 2.5, "reps": 3, "lapses": 0, "mod": 1000, "due_day": 100, "step": 0, "relearning": false, "due_ts": 0},
                "002": {"status": "review", "ivl": 4, "ease": 2.5, "reps": 2, "lapses": 0, "mod": 1100, "due_day": 100, "step": 0, "relearning": false, "due_ts": 0},
        })
        await sync.sync(DECK)
        # The reader defers 001 and takes 002 out altogether -- both later
        # than anything the repo knows, both with nothing answered.
        _write_progress({
                "001": {"status": "new", "reps": 0, "mod": 5000, "defer_day": 60, "suspended": false},
                "002": {"status": "new", "reps": 0, "mod": 5100, "defer_day": 0, "suspended": true},
        })
        var result: Dictionary = await sync.sync(DECK)
        _ok(bool(result.get("ok", false)), "a sync after a defer and a suspend succeeds")
        var merged: Variant = JSON.parse_string(_read(DECK.path_join("progress.json")))
        var cards: Dictionary = (merged as Dictionary).cards
        _is(str(cards["001"].get("status", "")), "new", "the deferred card keeps its defer through the merge")
        _is(int(cards["001"].get("defer_day", 0)), 60, "the defer's day survives the merge")
        _is(int(cards["001"].get("reps", 0)), 0, "the deferred card's reset survives the merge")
        _ok(bool(cards["002"].get("suspended", false)), "the suspended card keeps its suspension through the merge")
        # The reader's acts reach the repo, so the next device honours them.
        if fake.files.has("progress.json"):
                var pushed: Variant = JSON.parse_string(fake.files["progress.json"].content.get_string_from_utf8())
                var pushed_cards: Dictionary = (pushed as Dictionary).get("cards", {})
                _is(str(pushed_cards["001"].get("status", "")), "new", "the defer is pushed to the repo")
                _ok(bool(pushed_cards["002"].get("suspended", false)), "the suspension is pushed to the repo")
        # An answer that arrives after the act is newer learning: the card
        # returns to study, and the later word wins.
        fake.commit_change("progress.json", (JSON.stringify({"format": 1, "cards": {
                "001": {"status": "review", "ivl": 4, "ease": 2.5, "reps": 3, "lapses": 0, "mod": 6000, "due_day": 100, "step": 0, "relearning": false, "due_ts": 0},
        }}) + "\n"))
        var later: Dictionary = await sync.sync(DECK)
        _ok(bool(later.get("ok", false)), "a sync against a later answer succeeds")
        var after: Variant = JSON.parse_string(_read(DECK.path_join("progress.json")))
        var after_cards: Dictionary = (after as Dictionary).cards
        _is(int(after_cards["001"].get("reps", 0)), 3, "an answer later than a defer returns the card to study")

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

## The reader's own travelling choices -- the day's pace, the face the
## verses wear, the tongue the app speaks -- ride the progress file through
## every door they have: chosen here, they reach the repo; chosen later on
## another device, they arrive here; chosen earlier there, they never
## overwrite the newer word this deck already holds. Later wins, per
## choice: a newer tongue and an older face can arrive in one file, and
## each is judged on its own moment.
func _test_pace_travels_with_progress() -> void:
        _write_deck({"001": ["Q1", "A1"]})
        var fake := FakeGitHub.new()
        var sync := _make_sync(fake)
        await sync.sync(DECK)
        _write_progress_doc({
                "format": 1, "cards": {}, "new_per_day": 12, "new_per_day_mod": 5000,
                "ayah_font": "noto_naskh", "ayah_font_mod": 5001,
                "ui_lang": "fa", "ui_lang_mod": 5002,
        })
        var result: Dictionary = await sync.sync(DECK)
        _ok(bool(result.get("ok", false)), "a sync after a choice succeeds (%s)" % str(result.get("error", "")))
        var arrived: Variant = JSON.parse_string(fake.files["progress.json"].content.get_string_from_utf8())
        _ok(
                typeof(arrived) == TYPE_DICTIONARY and int((arrived as Dictionary).get("new_per_day", -1)) == 12,
                "the chosen pace reaches the repo"
        )
        _ok(
                typeof(arrived) == TYPE_DICTIONARY
                        and str((arrived as Dictionary).get("ayah_font", "")) == "noto_naskh",
                "the chosen face reaches the repo"
        )
        _ok(
                typeof(arrived) == TYPE_DICTIONARY
                        and str((arrived as Dictionary).get("ui_lang", "")) == "fa",
                "the chosen tongue reaches the repo"
        )
        # Another device chooses later; its word arrives here.
        fake.commit_change(
                "progress.json",
                JSON.stringify({
                        "format": 1, "cards": {}, "new_per_day": 30, "new_per_day_mod": 9000,
                        "ayah_font": "amiri", "ayah_font_mod": 9001,
                        "ui_lang": "ar", "ui_lang_mod": 9002,
                }) + "\n"
        )
        var later: Dictionary = await sync.sync(DECK)
        _ok(bool(later.get("ok", false)), "a sync with a later remote choice succeeds")
        var local: Variant = JSON.parse_string(_read(DECK.path_join("progress.json")))
        _is(int((local as Dictionary).get("new_per_day", -1)), 30, "the later pace becomes this device's own")
        _is(str((local as Dictionary).get("ayah_font", "")), "amiri", "the later face becomes this device's own")
        _is(str((local as Dictionary).get("ui_lang", "")), "ar", "the later tongue becomes this device's own")
        # An older remote choice never wins -- per choice, so a file can
        # carry an older tongue and a newer face at once.
        fake.commit_change(
                "progress.json",
                JSON.stringify({
                        "format": 1, "cards": {}, "new_per_day": 5, "new_per_day_mod": 7000,
                        "ayah_font": "amiri_quran", "ayah_font_mod": 7001,
                        "ui_lang": "fa", "ui_lang_mod": 9500,
                }) + "\n"
        )
        var older: Dictionary = await sync.sync(DECK)
        _ok(bool(older.get("ok", false)), "a sync with an older remote choice succeeds")
        var kept: Variant = JSON.parse_string(_read(DECK.path_join("progress.json")))
        _is(int((kept as Dictionary).get("new_per_day", -1)), 30, "the newer local pace is kept")
        _is(str((kept as Dictionary).get("ayah_font", "")), "amiri", "the newer local face is kept")
        _is(str((kept as Dictionary).get("ui_lang", "")), "fa", "a newer remote tongue wins its own choice")

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

## A download the API's contents door would not serve can land by the raw
## shelf instead: a run wearing alternate_fetch fetches the same files from
## raw.githubusercontent.com, and a link that is dead one way is alive the
## other -- the shape of the immediate retry the app asks itself.
func _test_failed_download_retries_the_other_road() -> void:
        _write_deck({"001": ["Q1", "A1"]})
        var fake := FakeGitHub.new()
        await _make_sync(fake).sync(DECK)  # this machine's word is already in the repo
        # A fresh device pulls; the API's contents door will not open for it.
        var target := "user://test_sync_alt_road"
        _remove_tree(target)
        DirAccess.make_dir_recursive_absolute(target)
        fake.fail_contents = true
        var broken: Dictionary = await _make_sync(fake).sync(target)
        _ok(not bool(broken.get("ok", false)), "a dead contents door fails the sync, loudly")
        _ok(fake.raw_gets == 0, "the usual road never touches the raw shelf")
        var contents_asked := fake.content_gets
        # The other road: the same run asked again, wearing alternate_fetch.
        var landed: Dictionary = await _make_sync(fake).sync(
                target, Callable(), Callable(), true
        )
        _ok(bool(landed.get("ok", false)), "the other road lands the same files (%s)" % str(landed.get("error", "")))
        _ok(fake.raw_gets >= 3, "the other road is the raw shelf (got %d raw fetches)" % fake.raw_gets)
        _is(
                fake.content_gets, contents_asked,
                "the alternate run asked the dead door nothing (api fetches %d -> %d)" % [contents_asked, fake.content_gets]
        )
        _ok(FileAccess.file_exists(target.path_join("001/front.md")), "the card arrives by the other road")
        _remove_tree(target)

## A signin that never got an answer is the network's failure, not the
## token's: only the token's own 401 says the token is wrong, and the two
## are told apart so the app asks the network again without sending the
## reader to Settings for a token that never did anything wrong.
func _test_signin_blip_is_the_network_not_the_token() -> void:
        _write_deck({"001": ["Q1", "A1"]})
        var fake := FakeGitHub.new()
        fake.fail_user = 1
        var blip: Dictionary = await _make_sync(fake).sync(DECK)
        _is(str(blip.get("error", "")), "network", "a dropped signin is the network's word")
        fake.refuse_user = 1
        var refused: Dictionary = await _make_sync(fake).sync(DECK)
        _is(str(refused.get("error", "")), "auth_failed", "a 401 is the token's own word")

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

## A file both sides changed is the reader's to settle, never the engine's:
## the engine asks, and the word it receives hard-forces one copy over the
## other. "local" stands for this machine's bytes -- pushed over the
## repo's -- and the ask names exactly the paths that conflicted.
func _test_conflict_asks_and_local_hard_forces() -> void:
        _write_deck({"001": ["Q1", "A1"], "002": ["Q2", "A2"]})
        var fake := FakeGitHub.new()
        var sync := _make_sync(fake)
        await sync.sync(DECK)
        _write(DECK.path_join("001/front.md"), "Q1 edited here")
        fake.commit_change("001/front.md", "Q1 edited there")
        var asked: Array = []
        # Lambdas capture locals by value, so the ask records itself into the
        # one shared array (in place, never reassigned) if the outer test is
        # to see it.
        var on_conflict := func(paths: Array) -> String:
                asked.assign(paths)
                return "local"
        var result: Dictionary = await sync.sync(DECK, Callable(), on_conflict)
        _ok(bool(result.get("ok", false)), "a local-verdict sync completes")
        _is(asked.size(), 1, "the conflict is asked about once")
        var first_asked := str(asked[0]) if asked.size() > 0 else ""
        _is(first_asked, "001/front.md", "the asked path is the conflicted card")
        _is(_read(DECK.path_join("001/front.md")), "Q1 edited here", "the device's copy stands here")
        _is(
                fake.files["001/front.md"].content.get_string_from_utf8(),
                "Q1 edited here",
                "the device's copy hard-forces the repo's"
        )

## "remote" stands for the repo's bytes: pulled over this machine's, and
## the repo keeps what it had.
func _test_conflict_remote_hard_forces() -> void:
        _write_deck({"001": ["Q1", "A1"]})
        var fake := FakeGitHub.new()
        var sync := _make_sync(fake)
        await sync.sync(DECK)
        _write(DECK.path_join("001/front.md"), "Q1 edited here")
        fake.commit_change("001/front.md", "Q1 edited there")
        var result: Dictionary = await sync.sync(DECK, Callable(), func(_paths: Array) -> String: return "remote")
        _ok(bool(result.get("ok", false)), "a remote-verdict sync completes")
        _is(_read(DECK.path_join("001/front.md")), "Q1 edited there", "the repo's copy hard-forces the device's")
        _is(
                fake.files["001/front.md"].content.get_string_from_utf8(),
                "Q1 edited there",
                "the repo keeps its own copy"
        )

## A question stood down from replaces nothing at all: the deck and the
## repo both stand exactly as they stood, the run says so, and the next
## sync asks again.
func _test_conflict_declined_replaces_nothing() -> void:
        _write_deck({"001": ["Q1", "A1"]})
        var fake := FakeGitHub.new()
        var sync := _make_sync(fake)
        await sync.sync(DECK)
        _write(DECK.path_join("001/front.md"), "Q1 edited here")
        fake.commit_change("001/front.md", "Q1 edited there")
        var declined: Dictionary = await sync.sync(DECK, Callable(), func(_paths: Array) -> String: return "")
        _ok(not bool(declined.get("ok", false)), "a declined conflict does not pass")
        _is(str(declined.get("error", "")), "conflict_declined", "the error names the standing-down")
        _is(_read(DECK.path_join("001/front.md")), "Q1 edited here", "the device's copy is untouched")
        _is(
                fake.files["001/front.md"].content.get_string_from_utf8(),
                "Q1 edited there",
                "the repo is untouched"
        )
        var asks: Array = []
        var on_conflict := func(_paths: Array) -> String:
                asks.append("asked")
                return "local"
        await sync.sync(DECK, Callable(), on_conflict)
        _is(asks.size(), 1, "the next sync asks again")

## The reader studies while a sync runs -- the merge's one fetch flies, and
## an answer saves to the very file the merge is about to judge. The merge
## must read the local file AFTER the fetch, so the write it makes is built
## from a copy that already saw the answer. The old order read first,
## fetched second, and wrote a merge that predated the answer: the answer
## vanished, and the card came back as new the next time the deck was read.
func _test_mid_fetch_answer_survives() -> void:
        _write_deck({"001": ["Q1", "A1"], "002": ["Q2", "A2"]})
        var fake := FakeGitHub.new()
        var sync := _make_sync(fake)
        await sync.sync(DECK)  # the baseline
        # The other device studied 002; the repo holds it.
        fake.commit_change("progress.json", (JSON.stringify({"format": 1, "cards": {
                "002": {"status": "review", "ivl": 1, "ease": 2.5, "reps": 1, "lapses": 0, "mod": 900, "due_day": 100, "step": 0, "relearning": false, "due_ts": 0},
        }}) + "\n"))
        # The reader answers 001 on this device while the merge's fetch flies:
        # the save lands on progress.json mid-flight, exactly the moment the
        # old merge used to overwrite it.
        fake.on_contents_get = func(path: String) -> void:
                if path != "progress.json":
                        return
                _write_progress({
                        "001": {"status": "review", "ivl": 4, "ease": 2.5, "reps": 1, "lapses": 0, "mod": 5000, "due_day": 100, "step": 0, "relearning": false, "due_ts": 0},
                })
        var result: Dictionary = await sync.sync(DECK)
        fake.on_contents_get = Callable()
        _ok(bool(result.get("ok", false)), "a sync whose reader answered mid-flight succeeds")
        var merged: Variant = JSON.parse_string(_read(DECK.path_join("progress.json")))
        var cards: Dictionary = (merged as Dictionary).cards
        _ok(cards.has("002"), "the other device's study arrives")
        _is(int(cards["001"].get("reps", 0)), 1, "the answer that landed mid-fetch survives")
        _is(int(cards["001"].get("mod", 0)), 5000, "the mid-fetch answer is the one kept, not an older shadow")

## This machine's word lands before the repo's is taken: a run with one of
## each must commit its push before it fetches its pull, so the reader's
## own work is safe in the repo even when the run dies between the two.
func _test_push_lands_before_pull() -> void:
        _write_deck({"001": ["Q1", "A1"]})
        var fake := FakeGitHub.new()
        var sync := _make_sync(fake)
        await sync.sync(DECK)
        fake.order.clear()
        # This machine edits the back; the other machine edits the front.
        _write(DECK.path_join("001/back.md"), "A1 edited here")
        fake.commit_change("001/front.md", "Q1 edited there")
        var result: Dictionary = await sync.sync(DECK)
        _ok(bool(result.get("ok", false)), "a sync with a push and a pull completes")
        _is(int(result.pushed), 1, "one file goes out (got %d)" % int(result.pushed))
        _is(int(result.pulled), 1, "one file comes in (got %d)" % int(result.pulled))
        var patch_at := -1
        var pull_at := -1
        for i in fake.order.size():
                var ask := str(fake.order[i])
                if ask.contains("PATCH") and ask.contains("/git/refs/heads/"):
                        patch_at = i  # the LAST patch is this run's own commit
                if ask.contains("GET") and ask.contains("/contents/001/front.md"):
                        pull_at = i
        _ok(patch_at >= 0 and pull_at >= 0, "the commit and the pull both flew")
        _ok(
                patch_at >= 0 and pull_at >= 0 and patch_at < pull_at,
                "the push lands before the pull (commit at %d, pull at %d)" % [patch_at, pull_at]
        )

## An answer that lands while the commit itself flies must still reach the
## repo on the next run. The manifest's baseline is the bytes that actually
## flew -- never a re-reading of the disk -- so the newer local file stays
## "waiting" and the next sync carries it, instead of the baseline lying
## that the repo already holds an answer it never received.
func _test_answer_after_upload_still_pushes() -> void:
        _write_deck({"001": ["Q1", "A1"]})
        var fake := FakeGitHub.new()
        var sync := _make_sync(fake)
        await sync.sync(DECK)  # the baseline
        # This device studies; the sync will carry it.
        _write_progress({
                "001": {"status": "review", "ivl": 4, "ease": 2.5, "reps": 1, "lapses": 0, "mod": 6000, "due_day": 100, "step": 0, "relearning": false, "due_ts": 0},
        })
        # And while the commit lands, the reader answers again -- a newer
        # save on the very file the run is pushing.
        fake.on_ref_patch = func() -> void:
                _write_progress({
                        "001": {"status": "review", "ivl": 5, "ease": 2.5, "reps": 2, "lapses": 0, "mod": 7000, "due_day": 100, "step": 0, "relearning": false, "due_ts": 0},
                })
        var first: Dictionary = await sync.sync(DECK)
        fake.on_ref_patch = Callable()
        _ok(bool(first.get("ok", false)), "the sync whose reader answered mid-commit succeeds")
        _ok(SyncScript.progress_dirty(DECK), "the answer that landed mid-commit is still waiting")
        var second: Dictionary = await _make_sync(fake).sync(DECK)
        _ok(bool(second.get("ok", false)), "the next sync carries the waiting answer")
        var remote_text := str(fake.files["progress.json"].content.get_string_from_utf8())
        _ok(remote_text.contains("7000"), "the answer reaches the repo (repo holds %s)" % remote_text)

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
