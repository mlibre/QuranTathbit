extends SceneTree
const DeckScript := preload("res://scripts/data/deck.gd")
const SchedulerScript := preload("res://scripts/data/scheduler.gd")
const ThemeScript := preload("res://scripts/ui/theme.gd")

## The library's two steps, held where the reader saw them: the shelf of
## surahs opens first -- one card a chapter, wearing its name, the mushaf's
## own number said by the chapter's own addresses, a ring carrying the
## share of its cards resting in review, a gold dot when the day asks
## something of it -- and the chapter's card opens the chapter's own page
## of verse rows, the rows the library has always read. The ring and the
## count are the chapter's own facts, gathered from the whole chapter, not
## from the question that surfaced it. The way back runs the page's own
## order: out of the chapter to its shelf, out of the library to home --
## by the back button, by Esc, and by the phone's back key alike.

var _failures := 0

func _init() -> void:
        await _test_shelf_of_surahs()
        await _test_chapter_page()
        await _test_the_way_back()
        await _test_questions_narrow_the_shelf()
        await _test_keyboard_walks_both_steps()

        if _failures > 0:
                print("library: %d FAILURE(S)" % _failures)
                quit(1)
        else:
                print("library: all checks passed")
                quit(0)


func _ok(condition: bool, what: String) -> void:
        if condition:
                print("  ok  %s" % what)
        else:
                _failures += 1
                print("  FAIL  %s" % what)


func _is(got: Variant, want: Variant, what: String) -> void:
        if got == want:
                print("  ok  %s" % what)
        else:
                _failures += 1
                print("  FAIL  %s -- got %s, want %s" % [what, got, want])


## Two chapters with known standings: Alpha holds four cards -- one
## resting in review, one learning step due now, one learning step still
## waiting, one never begun -- so its ring says a quarter and its corner
## carries the day's gold dot; Beta holds two, both resting, so its ring
## is full and it says nothing about today.
func _library_deck() -> Dictionary:
        var now := int(Time.get_unix_time_from_system())
        var today := SchedulerScript.today(now)
        var base := "user://scratch_library/shelf"
        _remove_tree("user://scratch_library")
        DirAccess.make_dir_recursive_absolute(base)
        var ids := ["001", "002", "003", "004", "005", "006"]
        var meta := FileAccess.open(base.path_join("deck.json"), FileAccess.WRITE)
        meta.store_string(JSON.stringify({"format": 1, "name": "Shelf", "cards": ids}) + "\n")
        meta.close()
        var states := {
                "001": {"status": "review", "reps": 3, "lapses": 0, "ivl": 20, "due_day": today + 30, "due_ts": 0, "mod": now},
                "002": {"status": "learning", "reps": 1, "lapses": 0, "ivl": 0, "due_day": 0, "due_ts": now - 60, "mod": now},
                "003": {"status": "learning", "reps": 1, "lapses": 0, "ivl": 0, "due_day": 0, "due_ts": now + 3600, "mod": now},
                "005": {"status": "review", "reps": 2, "lapses": 0, "ivl": 10, "due_day": today + 12, "due_ts": 0, "mod": now},
                "006": {"status": "review", "reps": 2, "lapses": 0, "ivl": 10, "due_day": today + 12, "due_ts": 0, "mod": now},
        }
        for i in ids.size():
                var id: String = ids[i]
                var folder := base.path_join(id)
                DirAccess.make_dir_recursive_absolute(folder)
                var chapter := "Alpha"
                var media := 1000 + i + 1
                if i >= 4:
                        chapter = "Beta"
                        media = 2000 + i - 3
                var front := FileAccess.open(folder.path_join("front.md"), FileAccess.WRITE)
                front.store_string("%s - %d\n" % [chapter, i + 1])
                front.close()
                var back := FileAccess.open(folder.path_join("back.md"), FileAccess.WRITE)
                back.store_string(
                        "the verse of card %s\n\n![%06d.mp3](%06d.mp3)\n" % [id, media, media]
                )
                back.close()
        var deck = DeckScript.load(base)
        if deck == null:
                return {"deck": null, "now": now}
        for id in states:
                for card in deck.cards:
                        if card.id == id:
                                card.state = states[id]
        return {"deck": deck, "now": now}


func _open_library(deck) -> Control:
        var browse = (load("res://scripts/ui/browse.gd") as GDScript).new()
        browse.name = "LibraryShelf"
        browse.set_anchors_preset(Control.PRESET_FULL_RECT)
        root.add_child(browse)
        if not browse.is_node_ready():
                await browse.ready
        browse.setup(deck, 1.0)
        await create_timer(0.4).timeout
        return browse


func _grid_of(browse: Control) -> GridContainer:
        return browse.get_node_or_null(
                "Margin/Column/Scroll/Wrap/Column/Shelf"
        ) as GridContainer


func _shelf_cards(browse: Control) -> Array:
        var grid := _grid_of(browse)
        var cards := []
        if grid != null:
                for child in grid.get_children():
                        if child.name.begins_with("SurahCard"):
                                cards.append(child)
        return cards


func _test_shelf_of_surahs() -> void:
        var made := _library_deck()
        var deck = made["deck"]
        if deck == null:
                _ok(false, "the library deck loads")
                return
        var browse: Control = await _open_library(deck)
        var cards := _shelf_cards(browse)
        _is(cards.size(), 2, "the shelf holds one card a chapter")
        if cards.size() != 2:
                browse.queue_free()
                await process_frame
                return
        var alpha: Button = cards[0]
        var beta: Button = cards[1]
        _is((alpha.get_node("Pad/Words/Name") as Label).text, "Alpha", "the card wears its chapter's name")
        _is((alpha.get_node("Pad/Words/Number") as Label).text, "Surah 1", "the mushaf's own number is said by the chapter's addresses")
        _is((alpha.get_node("Pad/Words/Count") as Label).text, "1 of 4 cards", "the ring's fraction is named in words")
        _is((alpha.get_node("Pad/Words/Ring") as ThemeScript.ProgressRing).percent, 25, "Alpha's ring carries a quarter of its cards")
        _ok(alpha.get_node_or_null("Due") != null, "a chapter the day asks something of wears the gold dot")
        _is((beta.get_node("Pad/Words/Number") as Label).text, "Surah 2", "Beta's number is its own")
        _is((beta.get_node("Pad/Words/Ring") as ThemeScript.ProgressRing).percent, 100, "Beta's ring is full")
        _ok(beta.get_node_or_null("Due") == null, "a chapter the day asks nothing of carries no dot")
        var summary: Label = browse.get_node("Margin/Column/Summary")
        _ok(not summary.visible, "the shelf at rest says no line the pills already said")
        browse.queue_free()
        await process_frame


func _test_chapter_page() -> void:
        var made := _library_deck()
        var deck = made["deck"]
        if deck == null:
                _ok(false, "the library deck loads for the chapter page")
                return
        var browse: Control = await _open_library(deck)
        var cards := _shelf_cards(browse)
        if cards.is_empty():
                _ok(false, "the shelf stands for the chapter's door")
                browse.queue_free()
                await process_frame
                return
        browse._open_surah_view("Alpha")
        await create_timer(0.1).timeout
        _is(
                (browse.get_node("Margin/Column/TopBar/Title") as Label).text,
                "Alpha",
                "the page's title carries the chapter's name"
        )
        _ok(
                _grid_of(browse) == null,
                "the shelf's grid stands down while a chapter's page stands"
        )
        var waited := 0.0
        var built := _entries_on(browse)
        while built < 4 and waited < 10.0:
                await create_timer(0.2).timeout
                waited += 0.2
                built = _entries_on(browse)
        _is(built, 4, "the chapter's page holds its own cards alone")
        _ok(
                browse.get_node_or_null("Margin/Column/Scroll/Wrap/Column/Tail") != null,
                "the chapter's page carries its tail"
        )
        var header: VBoxContainer = null
        var column: VBoxContainer = browse.get_node("Margin/Column/Scroll/Wrap/Column")
        for child in column.get_children():
                if child.name.begins_with("Header"):
                        header = child
        _ok(header != null, "the chapter's page opens with its own header")
        if header != null:
                var said: String = (header.get_node("Line/Count") as Label).text
                _ok(said.contains("4"), "the header counts the chapter's cards (%s)" % said)
        browse.queue_free()
        await process_frame


func _test_the_way_back() -> void:
        var made := _library_deck()
        var deck = made["deck"]
        if deck == null:
                _ok(false, "the library deck loads for the way back")
                return
        var browse: Control = await _open_library(deck)
        var left := {"gone": false}
        browse.closed.connect(func() -> void: left["gone"] = true)
        browse._open_surah_view("Beta")
        await create_timer(0.1).timeout
        # The back button, Esc and the phone's back key all take the same
        # first step: out of the chapter, onto the shelf -- and only the
        # second step leaves the library.
        browse._go_back()
        await create_timer(0.3).timeout
        _ok(_grid_of(browse) != null, "the back button returns to the shelf")
        _is(
                (browse.get_node("Margin/Column/TopBar/Title") as Label).text,
                "Browse",
                "the shelf's title is the library's again"
        )
        _ok(not left["gone"], "the first step back does not leave the library")
        browse._open_surah_view("Beta")
        await create_timer(0.1).timeout
        browse.request_back()
        await create_timer(0.3).timeout
        _ok(_grid_of(browse) != null, "the phone's back key returns to the shelf first")
        _ok(not left["gone"], "the key's first step keeps the library standing")
        browse.request_back()
        await create_timer(0.3).timeout
        _ok(left["gone"], "the key's second step leaves the library")
        browse.queue_free()
        await process_frame


func _test_questions_narrow_the_shelf() -> void:
        var made := _library_deck()
        var deck = made["deck"]
        if deck == null:
                _ok(false, "the library deck loads for the questions")
                return
        var browse: Control = await _open_library(deck)
        # A name asked by name: only that chapter's card stands.
        browse._on_search_changed("Beta")
        await create_timer(0.5).timeout
        var cards := _shelf_cards(browse)
        _is(cards.size(), 1, "a name asked by name narrows the shelf to its chapter")
        if cards.size() == 1:
                _is(
                        (cards[0].get_node("Pad/Words/Name") as Label).text,
                        "Beta",
                        "the chapter that answers is Beta"
                )
                var summary: Label = browse.get_node("Margin/Column/Summary")
                _ok(summary.visible, "a standing question is answered by a line")
        # The ring is the chapter's own fact: Beta narrowed to one card on
        # the shelf still wears the full ring its two resting cards earned.
        if cards.size() == 1:
                _is(
                        (cards[0].get_node("Pad/Words/Ring") as ThemeScript.ProgressRing).percent,
                        100,
                        "a narrowed shelf does not rewrite a chapter's standing"
                )
        browse._on_search_changed("")
        await create_timer(0.5).timeout
        _is(_shelf_cards(browse).size(), 2, "the question answered, the whole shelf returns")
        # The day's thread: only the chapter holding a due card stands.
        browse._filter = "due"
        browse._rebuild()
        await create_timer(0.4).timeout
        cards = _shelf_cards(browse)
        _is(cards.size(), 1, "the day's thread shows the chapter the day asks for")
        if cards.size() == 1:
                _is(
                        (cards[0].get_node("Pad/Words/Name") as Label).text,
                        "Alpha",
                        "the day asks for Alpha, where a learning step fell due"
                )
        browse._filter = "all"
        browse._rebuild()
        await create_timer(0.4).timeout
        _is(_shelf_cards(browse).size(), 2, "the whole story shows the whole shelf")
        browse.queue_free()
        await process_frame


func _test_keyboard_walks_both_steps() -> void:
        var made := _library_deck()
        var deck = made["deck"]
        if deck == null:
                _ok(false, "the library deck loads for the keyboard")
                return
        var browse: Control = await _open_library(deck)
        _is(browse._row_buttons().size(), 2, "the arrows walk the shelf's cards")
        browse._open_surah_view("Alpha")
        await create_timer(0.1).timeout
        var waited := 0.0
        while _entries_on(browse) < 4 and waited < 10.0:
                await create_timer(0.2).timeout
                waited += 0.2
        _is(browse._row_buttons().size(), 4, "the arrows walk the chapter's rows")
        browse.queue_free()
        await process_frame


func _entries_on(browse: Control) -> int:
        var column: VBoxContainer = browse.get_node_or_null(
                "Margin/Column/Scroll/Wrap/Column"
        )
        if column == null:
                return 0
        var count := 0
        for child in column.get_children():
                if child.name.begins_with("Entry"):
                        count += 1
        return count


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
