class_name Deck
extends RefCounted
const CardScript := preload("res://scripts/data/card.gd")
const SchedulerScript := preload("res://scripts/data/scheduler.gd")

## A deck is a folder. The app has exactly one, and it looks like this:
##
##     quran/
##       deck.json            {"format": 1, "name": "Quran", "cards": ["001", ...]}
##       001/
##         front.md           the question
##         back.md            the answer
##         001001.mp3         media referenced from the markdown
##       002/
##         ...
##
## front.md and back.md hold plain markdown; media is any other file in the
## card folder, referenced as ![name](name) and resolved next to the markdown.
## Progress lives in progress.json beside deck.json -- one entry per card id,
## so two devices that reviewed different cards merge cleanly. The reader's
## own pace rides the same file: how many new cards a day offers, and when
## that choice was last made, so it reaches every device the deck does.
##
## Decks load from res://assets (the bundled deck, copied into place on first
## run) and from user:// (the synced, writable copy). Saving writes only
## progress.json; the cards themselves belong to the deck's author.

const FORMAT := 1
const PROGRESS := "progress.json"
const DECK_META := "deck.json"

var name := ""
var folder := ""
var source := ""  # where the deck's content comes from, when it says
var cards: Array[CardScript] = []
var progress_path := ""
var dirty := false
## The reader's own pace: how many unseen cards a day offers. -1 while the
## progress file has never said one -- the very first save stamps this
## device's setting into the file and it becomes the deck's own number.
var new_per_day := -1
var new_per_day_mod := 0  # when the pace was last chosen, unix seconds
## The face the verses wear (theme.gd's AYAH_FACES keys) and the tongue the
## app's own chrome speaks (i18n.gd's LANGS). Both travel with the deck the
## way the pace does: empty while the progress file has never said one, and
## stamped with the moment of the choice so a later choice can win the
## merge, the way a later answer breaks a card's tie.
var ayah_font := ""
var ayah_font_mod := 0
var ui_lang := ""
var ui_lang_mod := 0

static func load(path: String):
        var deck = (load("res://scripts/data/deck.gd") as GDScript).new()
        deck.folder = path
        var meta_path := path.path_join(DECK_META)
        if not FileAccess.file_exists(meta_path):
                push_error("Deck.load: no %s in %s" % [DECK_META, path])
                return null
        var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
        if typeof(meta) != TYPE_DICTIONARY or int((meta as Dictionary).get("format", 0)) != FORMAT:
                push_error("Deck.load: %s is not a deck this app understands" % meta_path)
                return null
        deck.name = str((meta as Dictionary).get("name", "Deck"))
        deck.source = str((meta as Dictionary).get("source", ""))
        deck.progress_path = path.path_join(PROGRESS)

        # Cards are the numbered folders on disk. deck.json may list them -- but
        # a deck shared from another machine can arrive with folders this list
        # has never seen, so the folders are the truth and the list is the order.
        var ids: Array = []
        for entry in DirAccess.get_directories_at(path):
                if entry.is_valid_int():
                        ids.append(entry)
        ids.sort()
        if not ids.is_empty():
                var listed: Array = (meta as Dictionary).get("cards", [])
                if not listed.is_empty():
                        var ordered: Array = []
                        for id in listed:
                                if ids.has(str(id)):
                                        ordered.append(str(id))
                        for id in ids:
                                if not ordered.has(id):
                                        ordered.append(id)
                        ids = ordered
        for id in ids:
                var card := _load_card(path, str(id))
                if card == null:
                        return null
                deck.cards.append(card)
        if deck.cards.is_empty():
                push_error("Deck.load: %s has no cards" % path)
                return null

        deck._load_progress()
        return deck

static func _load_card(deck_path: String, id: String) -> CardScript:
        var folder := deck_path.path_join(id)
        var card := CardScript.new(id, folder)
        var front_path := folder.path_join("front.md")
        var back_path := folder.path_join("back.md")
        if not FileAccess.file_exists(front_path) or not FileAccess.file_exists(back_path):
                push_error("Deck: card %s is missing front.md or back.md" % id)
                return null
        card.front = FileAccess.get_file_as_string(front_path)
        card.back = FileAccess.get_file_as_string(back_path)
        for entry in DirAccess.get_files_at(folder):
                # Godot's .import and .uid sidecars are editor metadata, not
                # media a card can reference or sync can carry.
                if entry.get_extension() in ["md", "import", "uid"] or entry == ".gdignore":
                        continue
                card.media[entry] = folder.path_join(entry)
        return card

func _load_progress() -> void:
        if not FileAccess.file_exists(progress_path):
                return
        var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(progress_path))
        if typeof(data) != TYPE_DICTIONARY:
                push_warning("Deck: progress.json unreadable; starting fresh")
                return
        var entries: Dictionary = (data as Dictionary).get("cards", {})
        var pace: Variant = (data as Dictionary).get("new_per_day", null)
        if typeof(pace) == TYPE_INT or typeof(pace) == TYPE_FLOAT:
                new_per_day = int(pace)
                var mod: Variant = (data as Dictionary).get("new_per_day_mod", 0)
                new_per_day_mod = int(mod) if (
                        typeof(mod) == TYPE_INT or typeof(mod) == TYPE_FLOAT
                ) else 0
        ayah_font = _str_choice(data as Dictionary, "ayah_font", ayah_font)
        ayah_font_mod = _int_choice(data as Dictionary, "ayah_font_mod", ayah_font_mod)
        ui_lang = _str_choice(data as Dictionary, "ui_lang", ui_lang)
        ui_lang_mod = _int_choice(data as Dictionary, "ui_lang_mod", ui_lang_mod)
        for card in cards:
                var saved: Variant = entries.get(card.id)
                if typeof(saved) != TYPE_DICTIONARY:
                        continue
                # Trust the file's keys, but repair the ones the scheduler needs.
                var state := SchedulerScript.new_state()
                for key in state.keys():
                        if (saved as Dictionary).has(key):
                                state[key] = (saved as Dictionary)[key]
                if (saved as Dictionary).has("relearning"):
                        state["relearning"] = bool((saved as Dictionary).relearning)
                card.state = state


func save_progress() -> bool:
        var entries: Dictionary = {}
        for card in cards:
                var state: Dictionary = card.state
                # Untouched cards stay out of the file -- but a defer is a
                # touch the deck must remember: the card is new and unanswer,
                # yet its day is spoken for until tomorrow carries it back.
                if (
                        state["status"] == "new"
                        and int(state.get("reps", 0)) == 0
                        and int(state.get("defer_day", 0)) == 0
                ):
                        continue
                entries[card.id] = canonical_state(state)
        var file := FileAccess.open(progress_path, FileAccess.WRITE)
        if file == null:
                push_error("Deck.save_progress: cannot write %s (%s)" % [progress_path, error_string(FileAccess.get_open_error())])
                return false
        var doc := {"format": FORMAT, "cards": entries}
        if new_per_day >= 0:
                doc["new_per_day"] = new_per_day
                doc["new_per_day_mod"] = new_per_day_mod
        if not ayah_font.is_empty():
                doc["ayah_font"] = ayah_font
                doc["ayah_font_mod"] = ayah_font_mod
        if not ui_lang.is_empty():
                doc["ui_lang"] = ui_lang
                doc["ui_lang_mod"] = ui_lang_mod
        file.store_string(JSON.stringify(doc, "\t") + "\n")
        file.close()
        dirty = false
        return true


## A string choice read honestly: a hand-edited progress file can carry a
## number where a word belongs, and a number dressed as the font's key
## would dress every verse in a face that does not exist.
static func _str_choice(data: Dictionary, key: String, fallback: String) -> String:
        var value: Variant = data.get(key, null)
        return str(value) if typeof(value) == TYPE_STRING else fallback


## An int choice read honestly, the same tolerance for JSON's floats.
static func _int_choice(data: Dictionary, key: String, fallback: int) -> int:
        var value: Variant = data.get(key, null)
        if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
                return int(value)
        return fallback


## JSON reads every number back as a float, so a file saved, loaded and
## saved again would rewrite "reps": 3 as "reps": 3.0 -- the same learning,
## different bytes. Sync compares bytes, so the deck would announce a change
## that is only formatting, again and again. Whole floats go back to ints
## before anything is written; an ease of 2.5 stays exactly what it is.
static func canonical_state(state: Dictionary) -> Dictionary:
        var out := {}
        for key in state.keys():
                var value: Variant = state[key]
                if (
                        typeof(value) == TYPE_FLOAT
                        and float(value) == roundf(float(value))
                        and absf(float(value)) < 9007199254740992.0
                ):
                        out[key] = int(float(value))
                else:
                        out[key] = value
        return out

func answer(card: CardScript, button: String, now: int) -> void:
        card.state = SchedulerScript.apply(SchedulerScript.id_seed(card.id), card.state, button, now)
        dirty = true


## A card the reader put back in the initial basket for the rest of the day:
## not an answer, nothing learned and nothing scheduled -- only the day's
## own stamp, which the queue and the counts both pass over until tomorrow
## returns the card as new.
func defer(card: CardScript, now: int) -> void:
        card.state = SchedulerScript.deferred_state(now)
        dirty = true
