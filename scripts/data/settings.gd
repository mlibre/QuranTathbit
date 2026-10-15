class_name Settings
extends RefCounted

## The app's small memory: which GitHub account, which repo, when it last
## synced, and where the deck lives. One JSON file under user://, written
## rarely and read once at boot. The deck's learning progress is NOT here --
## that lives in the deck's own progress.json, where sync merges it.

const PATH := "user://settings.json"

var token := ""  # GitHub personal access token (or OAuth device-flow token)
var owner := ""  # GitHub login; filled in the first time we see it
var repo := "quran-tathbit"  # the private repo that holds the deck
var deck_folder := ""  # absolute path of the synced deck (user://decks/quran)
var last_sync := 0  # unix seconds
var setup_done := false


static func load_settings():
	var s = (load("res://scripts/data/settings.gd") as GDScript).new()
	if not FileAccess.file_exists(PATH):
		return s
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("Settings: %s unreadable; using defaults" % PATH)
		return s
	for key in ["token", "owner", "repo", "deck_folder", "last_sync", "setup_done"]:
		if data.has(key) and typeof(data[key]) == typeof(s.get(key)):
			s.set(key, data[key])
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
			},
			"\t"
		)
		+ "\n"
	)
	file.close()
	return true


func has_token() -> bool:
	return not token.strip_edges().is_empty()
