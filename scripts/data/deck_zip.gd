class_name DeckZip
extends RefCounted
const DeckScript := preload("res://scripts/data/deck.gd")

## The deck as one file. A backup packs everything a reader would grieve to
## lose -- deck.json, every card's front and back and media, and the whole
## of progress.json, the file that carries both the learning and the
## travelling choices (pace, verse face, tongue) -- into a single zip a
## person can keep anywhere a file goes. The app's own settings never ride
## along: they are this device's, and the token among them is a secret.
##
## Bringing one back JOINS rather than replaces, by the same rules sync
## speaks: progress merges card by card (the entry with more reviews wins,
## the later answer breaks ties, and a deliberate reset -- a defer, a
## suspend -- is judged by its moment, newer than anything older whatever
## the review count says), the travelling choices merge by their own
## moments, and files land only where the deck lacks them -- a tie keeps the
## local word. Importing an old backup onto a deck that studied since can
## therefore never take a review away; importing onto a fresh install
## brings everything over in one move.
##
## Editor metadata (.import/.uid, Godot's and the desktop's) is never deck
## content and never travels, the same law the sync engine keeps.

## The choices that ride progress.json wherever it goes -- the same keys the
## sync engine merges, kept here so the two doors agree on what travels.
const CHOICE_KEYS := ["new_per_day", "ayah_font", "ui_lang"]

## Where a backup tries to land, in order: the shared Downloads folder
## (writable on a desktop; on a modern phone the OS declines and the write
## simply fails), then the app's own storage there, then the app's own
## corner of user:// -- which always works, everywhere. Empty answers are
## skipped (a machine may not name a Downloads folder at all), and the same
## path never appears twice.
static func destination_dirs() -> Array:
        var out: Array = []
        var seen: Dictionary = {}
        for shared in [true, false]:
                var dir := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS, shared)
                if dir.is_empty():
                        continue
                dir = dir.simplify_path()
                if seen.has(dir):
                        continue
                seen[dir] = true
                out.append({"path": dir, "shared": shared})
        if not seen.has("user://backups"):
                out.append({"path": "user://backups", "shared": false})
        return out


## The name a backup wears: the app, the deck, and the day -- so two
## exports on one day agree on one file (the later one is the fuller one),
## and no day's file eats another day's.
static func backup_name() -> String:
        return "qurantathbit-deck-%s.zip" % Time.get_date_string_from_system()


## Every backup this machine can see, newest first: each destination folder
## is read only if the OS lets it be read (a phone's shared storage often
## may not be), and each file answers with its own moment and size so the
## picker can say what it found without opening anything.
static func find_backups() -> Array:
        var out: Array = []
        for place in destination_dirs():
                _collect_zips(str(place["path"]), bool(place["shared"]), out)
        out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
                return float(a["mtime"]) > float(b["mtime"])
        )
        return out


static func _collect_zips(where: String, shared: bool, out: Array) -> void:
        var dir := DirAccess.open(where)
        if dir == null:
                return
        dir.list_dir_begin()
        var name := dir.get_next()
        while not name.is_empty():
                if not dir.current_is_dir() and name.get_extension().to_lower() == "zip":
                        var path := where.path_join(name)
                        var handle := FileAccess.open(path, FileAccess.READ)
                        if handle != null:
                                out.append({
                                        "path": path,
                                        "name": name,
                                        "mtime": FileAccess.get_modified_time(path),
                                        "bytes": handle.get_length(),
                                        "shared": shared,
                                })
                                handle.close()
                name = dir.get_next()
        dir.list_dir_end()


# --- export ----------------------------------------------------------------------


## Pack a deck folder into one zip. Every file under the folder rides along
## except the metadata that is not the deck's own; the walk is sorted so
## two exports of one deck tell the same story in the same order. Returns
## {ok, path, files, bytes} or {ok: false, error}.
static func export_deck(deck_path: String, target_path: String) -> Dictionary:
        if not FileAccess.file_exists(deck_path.path_join(DeckScript.DECK_META)):
                return {"ok": false, "error": "not_a_deck"}
        var rels: Array = []
        _collect(deck_path, "", rels)
        var packer := ZIPPacker.new()
        var err := packer.open(target_path, ZIPPacker.ZipAppend.APPEND_CREATE)
        if err != OK:
                return {"ok": false, "error": "cannot_write", "code": err}
        var written := 0
        for rel in rels:
                var data := FileAccess.get_file_as_bytes(deck_path.path_join(rel))
                err = packer.start_file(rel)
                if err != OK:
                        packer.close()
                        DirAccess.remove_absolute(target_path)
                        return {"ok": false, "error": "cannot_write", "code": err}
                packer.write_file(data)
                packer.close_file()
                written += 1
        err = packer.close()
        if err != OK:
                DirAccess.remove_absolute(target_path)
                return {"ok": false, "error": "cannot_write", "code": err}
        return {
                "ok": true,
                "path": target_path,
                "files": written,
                "bytes": FileAccess.get_file_as_bytes(target_path).size(),
        }


static func _collect(root: String, prefix: String, out: Array) -> void:
        var dir: String = root if prefix.is_empty() else root.path_join(prefix)
        var files: Array = DirAccess.get_files_at(dir)
        files.sort()
        for entry in files:
                if _is_junk_name(entry):
                        continue
                out.append(entry if prefix.is_empty() else prefix.path_join(entry))
        var folders: Array = DirAccess.get_directories_at(dir)
        folders.sort()
        for entry in folders:
                _collect(root, entry if prefix.is_empty() else prefix.path_join(entry), out)


# --- import ----------------------------------------------------------------------


## Join a backup's deck to the one on disk. Content files land only where
## the deck lacks them; progress merges card by card and the travelling
## choices by their own moments -- the same ranks and rules the sync engine
## applies, so every door into the deck agrees on what a merge means.
## A zip whose whole deck sits under one wrapping folder (the way many
## tools zip a folder rather than its contents) is understood too. Returns
## {ok, merged, choices, added, cards_new} or {ok: false, error}.
static func import_deck(deck_path: String, zip_path: String) -> Dictionary:
        var reader := ZIPReader.new()
        var err := reader.open(zip_path)
        if err != OK:
                return {"ok": false, "error": "unreadable"}
        var entries: PackedStringArray = reader.get_files()
        var prefix := ""
        if not entries.has("deck.json"):
                # The deck may stand under one wrapping folder -- "quran/"
                # -- the way a person zips a folder instead of its contents.
                # Exactly one such folder may speak for the deck; two is not
                # a deck wearing a coat, it is two decks.
                var wrappers: Dictionary = {}
                for entry in entries:
                        if entry.ends_with("/deck.json") and entry.count("/") == 1:
                                wrappers[entry.substr(0, entry.length() - "deck.json".length())] = true
                if wrappers.size() != 1:
                        reader.close()
                        return {"ok": false, "error": "not_a_deck"}
                prefix = str(wrappers.keys()[0])
        var meta: Variant = JSON.parse_string(reader.read_file(prefix + "deck.json").get_string_from_utf8())
        if typeof(meta) != TYPE_DICTIONARY or int((meta as Dictionary).get("format", 0)) != DeckScript.FORMAT:
                reader.close()
                return {"ok": false, "error": "not_a_deck"}

        var added := 0
        var new_cards: Dictionary = {}
        var progress_bytes := PackedByteArray()
        for entry in entries:
                if entry.ends_with("/"):
                        continue  # the archive's own folder lines, not files
                var rel := entry.substr(prefix.length())
                if rel.is_empty() or _is_junk_path(rel) or not _safe_rel(rel):
                        continue
                if rel == DeckScript.PROGRESS:
                        progress_bytes = reader.read_file(entry)
                        continue
                var target := deck_path.path_join(rel)
                if FileAccess.file_exists(target):
                        continue  # a tie keeps the local word
                var card_id := rel.get_slice("/", 0)
                if card_id.is_valid_int() and not DirAccess.dir_exists_absolute(deck_path.path_join(card_id)):
                        new_cards[card_id] = true
                if rel.contains("/"):
                        DirAccess.make_dir_recursive_absolute(deck_path.path_join(rel.get_base_dir()))
                var file := FileAccess.open(target, FileAccess.WRITE)
                if file == null:
                        push_error("DeckZip: cannot write %s" % target)
                        continue
                file.store_buffer(reader.read_file(entry))
                file.close()
                added += 1
        reader.close()

        var merged := _merge_progress(deck_path, progress_bytes)
        if not bool(merged.get("ok", false)):
                return merged
        return {
                "ok": true,
                "merged": int(merged.get("merged", 0)),
                "choices": int(merged.get("choices", 0)),
                "added": added,
                "cards_new": new_cards.size(),
        }


## The learning and the choices, joined: their entries arrive where this
## deck lacks them or where they outrank what is here, and the merged file
## is written in the deck's own shape (canonical states, so a whole number
## never re-saves as a float) only when something actually moved.
static func _merge_progress(deck_path: String, their_bytes: PackedByteArray) -> Dictionary:
        if their_bytes.is_empty():
                return {"ok": true, "merged": 0, "choices": 0}
        var their_doc: Variant = JSON.parse_string(their_bytes.get_string_from_utf8())
        if typeof(their_doc) != TYPE_DICTIONARY:
                return {"ok": true, "merged": 0, "choices": 0}
        var path := deck_path.path_join(DeckScript.PROGRESS)
        var my_doc := _read_doc(path)
        var my_cards := _entries_of(my_doc)
        var their_cards := _entries_of(their_doc as Dictionary)
        var merged := 0
        for card_id in their_cards.keys():
                if not my_cards.has(card_id) or _state_beats(their_cards[card_id], my_cards[card_id]):
                        my_cards[card_id] = their_cards[card_id]
                        merged += 1
        var my_choices := _choices_of(my_doc)
        var their_choices := _choices_of(their_doc as Dictionary)
        var choices := 0
        for key in CHOICE_KEYS:
                var theirs: Dictionary = their_choices.get(key, {})
                if theirs.is_empty():
                        continue
                var mine: Dictionary = my_choices.get(key, {})
                if mine.is_empty() or int(theirs.get("mod", 0)) > int(mine.get("mod", 0)):
                        my_choices[key] = theirs
                        choices += 1
        if merged == 0 and choices == 0:
                return {"ok": true, "merged": 0, "choices": 0}
        var cards_out: Dictionary = {}
        for card_id in my_cards.keys():
                cards_out[card_id] = DeckScript.canonical_state(my_cards[card_id])
        var doc := {"format": DeckScript.FORMAT, "cards": cards_out}
        for key in my_choices.keys():
                var choice: Dictionary = my_choices[key]
                doc[key] = choice["value"]
                doc[key + "_mod"] = int(choice["mod"])
        var file := FileAccess.open(path, FileAccess.WRITE)
        if file == null:
                return {"ok": false, "error": "cannot_write"}
        file.store_string(JSON.stringify(doc, "\t") + "\n")
        file.close()
        return {"ok": true, "merged": merged, "choices": choices}


## A card's standing in the merge: how much was learned, then when it was
## last answered -- the same rank the sync engine compares by.
static func _rank(state: Dictionary) -> Array:
        return [int(state.get("reps", 0)), int(state.get("mod", 0))]


## Does one card state outrank another, by the sync engine's own rule? Two
## answered states compare by rank; a deliberate reset (a defer, a suspend:
## nothing answered, yet touched at a known moment) compares by its moment
## alone -- newer than anything older, older than anything newer, whatever
## either side's review count says. Without this, importing a backup made
## after a defer would hand the card back to the answers the defer was a
## deliberate act later than.
static func _state_beats(a: Dictionary, b: Dictionary) -> bool:
        var a_reset := int(a.get("reps", 0)) == 0 and int(a.get("mod", 0)) > 0
        var b_reset := int(b.get("reps", 0)) == 0 and int(b.get("mod", 0)) > 0
        if a_reset or b_reset:
                return int(a.get("mod", 0)) > int(b.get("mod", 0))
        return _rank(a) > _rank(b)


static func _read_doc(path: String) -> Dictionary:
        if not FileAccess.file_exists(path):
                return {}
        var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
        return data if typeof(data) == TYPE_DICTIONARY else {}


static func _entries_of(doc: Dictionary) -> Dictionary:
        var entries: Variant = doc.get("cards", {})
        var out: Dictionary = {}
        if typeof(entries) == TYPE_DICTIONARY:
                for card_id in (entries as Dictionary).keys():
                        if typeof((entries as Dictionary)[card_id]) == TYPE_DICTIONARY:
                                out[card_id] = (entries as Dictionary)[card_id]
        return out


## The choices a progress document carries, each with its value and the
## moment it was chosen. A value of the wrong shape (a hand-edited file, a
## number where a font's key belongs) is not a choice -- it is noise, and
## noise never travels.
static func _choices_of(doc: Dictionary) -> Dictionary:
        var out: Dictionary = {}
        for key in CHOICE_KEYS:
                var value: Variant = doc.get(key, null)
                if value == null:
                        continue
                if key == "new_per_day":
                        if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
                                continue
                elif typeof(value) != TYPE_STRING:
                        continue
                var mod: Variant = doc.get(key + "_mod", 0)
                out[key] = {
                        "value": value,
                        "mod": int(mod) if (typeof(mod) == TYPE_INT or typeof(mod) == TYPE_FLOAT) else 0,
                }
        return out


# --- the archive's own hygiene -----------------------------------------------------


## Godot's .import and .uid sidecars are editor metadata, never deck
## content; the desktop's .DS_Store and Thumbs.db and Apple's __MACOSX
## lines are a zipper's packing, not a file. None of them ride out or in.
static func _is_junk_name(name: String) -> bool:
        return (
                name.ends_with(".import")
                or name.ends_with(".uid")
                or name == ".gdignore"
                or name == ".DS_Store"
                or name == "Thumbs.db"
                or name == "__MACOSX"
        )


static func _is_junk_path(rel: String) -> bool:
        for part in rel.split("/"):
                if _is_junk_name(part):
                        return true
        return false


## A path an archive hands us is only a path if it stays inside the deck:
## no absolute address, no climb out with "..", no scheme, no empty floor.
## Anything else is not the deck's business (zip-slip), and is declined.
static func _safe_rel(rel: String) -> bool:
        if rel.is_absolute_path() or rel.begins_with("res://") or rel.begins_with("user://"):
                return false
        for part in rel.split("/"):
                if part.is_empty() or part == "..":
                        return false
        return true
