class_name Settings
extends RefCounted

## The app's small memory: which GitHub account, which repo, when it last
## synced, and where the deck lives. One JSON file under user://, written
## rarely and read once at boot. The deck's learning progress is NOT here --
## that lives in the deck's own progress.json, where sync merges it.

const PATH := "user://settings.json"
const SchedulerScript := preload("res://scripts/data/scheduler.gd")

var token := ""  # GitHub personal access token (or OAuth device-flow token)
var owner := ""  # GitHub login; filled in the first time we see it
var repo := "quran-tathbit"  # the private repo that holds the deck
var deck_folder := ""  # absolute path of the synced deck (user://decks/quran)
var last_sync := 0  # unix seconds
var setup_done := false
var auto_sync := true  # quiet sync after each session, and when the app opens
var volume := 1.0  # recitation loudness, 0 (silent) to 1 (full); remembered between visits
## How many unseen cards a day offers. Anki's deck default (20 a day) is the
## starting point, not a law: a reader pacing their own memorisation chooses
## their own number in Settings, and the scheduler asks this before it fills
## the day's queue. Per device, like volume -- it is how a person reads, not
## what they have read.
var new_per_day := SchedulerScript.NEW_PER_DAY


static func load_settings():
        var s = (load("res://scripts/data/settings.gd") as GDScript).new()
        if not FileAccess.file_exists(PATH):
                return s
        var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
        if typeof(data) != TYPE_DICTIONARY:
                push_warning("Settings: %s unreadable; using defaults" % PATH)
                return s
        for key in ["token", "owner", "repo", "deck_folder", "last_sync", "setup_done", "auto_sync", "volume", "new_per_day"]:
                if not data.has(key):
                        continue
                # JSON reads every number back as a float, and every saved int
                # as a float that happens to be whole. A strict typeof match
                # silently threw last_sync away on every load -- the app then
                # forgot it had ever synced, and said so.
                var value: Variant = data[key]
                var want: int = typeof(s.get(key))
                if typeof(value) == want:
                        s.set(key, value)
                elif want == TYPE_INT and typeof(value) == TYPE_FLOAT:
                        s.set(key, int(round(float(value))))
                elif want == TYPE_FLOAT and typeof(value) == TYPE_INT:
                        s.set(key, float(value))
                elif want == TYPE_BOOL and typeof(value) == TYPE_INT:
                        s.set(key, bool(value))
        return s


func save() -> bool:
        var file := FileAccess.open(PATH, FileAccess.WRITE)
        if file == null:
                push_error("Settings.save: cannot write %s" % PATH)
                return false
        file.store_string(
                JSON.stringify(
                        {
                                "token": token,
                                "owner": owner,
                                "repo": repo,
                                "deck_folder": deck_folder,
                                "last_sync": last_sync,
                                "setup_done": setup_done,
                                "auto_sync": auto_sync,
                                "volume": volume,
                                "new_per_day": new_per_day,
                        },
                        "\t"
                )
                + "\n"
        )
        file.close()
        return true


func has_token() -> bool:
        return not token.strip_edges().is_empty()
