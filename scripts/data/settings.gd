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
## Whether the deck's GitHub life is on at all. Off is the newborn state --
## a reader who has never asked for sync has no token, no repo and no sync
## door on the home page, and the deck simply lives on this device. Turning
## it on in Settings is what raises the door and opens the account rows
## beside it, so nothing of GitHub stands in front of a reader who never
## wanted it. A copy of the app that already carried a token when this
## switch arrived wakes with it on (see load_settings): nobody asked to be
## disconnected by an update.
var sync_enabled := false
var volume := 1.0  # recitation loudness, 0 (silent) to 1 (full); remembered between visits
## How many unseen cards a day offers. Anki's deck default (20 a day) is the
## starting point, not a law: a reader pacing their own memorisation chooses
## their own number in Settings, and the scheduler asks this before it fills
## the day's queue. The choice travels with the deck's own progress.json, so
## every device the deck reaches paces itself the same -- this copy is the
## device's working memory of it, adopted from the deck at boot.
var new_per_day := SchedulerScript.NEW_PER_DAY
## The face the verses themselves wear, wherever scripture is shown: one of
## theme.gd's AYAH_FACES ("amiri_quran", "amiri", "noto_naskh"). Empty
## means no choice has been made, and the default mushaf cut stands. Like
## the day's pace, the choice travels with the deck's own progress.json,
## so every device the deck reaches dresses its verses the same -- this
## copy is the device's working memory of it, adopted from the deck at boot.
var ayah_font := ""
## The tongue the app's own chrome speaks ("en", "fa", "ar" -- i18n.gd's
## LANGS). The verses and their Persian translation are the deck's content
## and never change; this dresses only menus, buttons and messages. It
## travels with the deck the same way, and stays empty until the reader
## answers the app's first question (or picks one in Settings).
var ui_lang := ""
## Two ways to size the app for the eyes in front of it, chosen in Settings.
## The interface scale multiplies the window's own content scale (everything
## grows together, the layout re-flows); the font scale multiplies only the
## words (theme.gd's fs()). Both are this device's own comfort -- a desk and
## a phone read at different distances -- so unlike the pace, the face and
## the tongue they stay here and never travel with the deck. 1.0 is the
## size the app has always been.
var ui_scale := 1.0
var font_scale := 1.0


static func load_settings():
        var s = (load("res://scripts/data/settings.gd") as GDScript).new()
        if not FileAccess.file_exists(PATH):
                return s
        var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
        if typeof(data) != TYPE_DICTIONARY:
                push_warning("Settings: %s unreadable; using defaults" % PATH)
                return s
        for key in ["token", "owner", "repo", "deck_folder", "last_sync", "setup_done", "auto_sync", "sync_enabled", "volume", "new_per_day", "ayah_font", "ui_lang", "ui_scale", "font_scale"]:
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
        # The switch arrived after the token did: a file written by an older
        # version says nothing about it, and a reader who already keeps their
        # deck on GitHub never asked to wake up disconnected. Their token is
        # the answer -- the switch wakes on with it.
        if not data.has("sync_enabled"):
                s.sync_enabled = s.has_token()
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
                                "sync_enabled": sync_enabled,
                                "volume": volume,
                                "new_per_day": new_per_day,
                                "ayah_font": ayah_font,
                                "ui_lang": ui_lang,
                                "ui_scale": ui_scale,
                                "font_scale": font_scale,
                        },
                        "\t"
                )
                + "\n"
        )
        file.close()
        return true


func has_token() -> bool:
        return not token.strip_edges().is_empty()
