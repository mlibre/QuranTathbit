extends SceneTree
const DeckScript := preload("res://scripts/data/deck.gd")
const SchedulerScript := preload("res://scripts/data/scheduler.gd")
const HomeScript := preload("res://scripts/ui/home.gd")
const StudyScript := preload("res://scripts/ui/study.gd")
const SettingsScript := preload("res://scripts/ui/settings_screen.gd")
const ThemeScript := preload("res://scripts/ui/theme.gd")

## The day's offer, spent or set to reviews alone, still leaves a deck with
## unseen cards: the caught-up home page offers to take one more new card
## into a session. The offer stands only while an unseen card remains,
## never offers back a card the reader deferred or suspended today, and the
## session it opens holds exactly that one card. The same file holds the
## merge law to one place -- the deck itself tells both doors that merge a
## progress document how states compare and which choices travel -- and
## holds the settings page's font segments to the height their own faces
## ask for, so no preview can outgrow the box that offers it.

var _failures := 0

func _init() -> void:
        _test_first_fresh()
        await _test_home_offer()
        await _test_session_opens()
        await _test_browse_counts()
        _test_merge_law_one_place()
        await _test_segment_heights()

        if _failures > 0:
                print("extra card: %d FAILURE(S)" % _failures)
                quit(1)
        else:
                print("extra card: all checks passed")
                quit(0)

func _ok(condition: bool, what: String) -> void:
        if not condition:
                _failures += 1
                print("  FAIL: %s" % what)

func _is(got: Variant, expected: Variant, what: String) -> void:
        if got != expected:
                _failures += 1
                print("  FAIL: %s (got %s, expected %s)" % [what, str(got), str(expected)])

# --- the first card a larger offer would bring --------------------------------------

func _test_first_fresh() -> void:
        var now := 1700000000
        var deck = _scratch_deck("first_fresh")
        _ok(deck != null, "the scratch deck loads")
        if deck == null:
                return
        _is(SchedulerScript.first_fresh(deck, now).id, "001", "a fresh deck's first card is its first")
        # The queue's own rule, read past the cap: pace 0 offers nothing,
        # yet the first unseen card is still the first unseen card.
        _is(SchedulerScript.queue(deck, now, 0).size(), 0, "a pace of 0 offers nothing")
        _is(SchedulerScript.first_fresh(deck, now).id, "001", "the first fresh card ignores the cap")

        deck.cards[0].state = SchedulerScript.deferred_state(now)
        _is(SchedulerScript.first_fresh(deck, now).id, "002", "a card deferred today is never offered back today")
        deck.cards[1].state = SchedulerScript.suspended_state(now)
        _is(SchedulerScript.first_fresh(deck, now).id, "003", "a suspended card is not the day's to offer")
        deck.cards[2].state = SchedulerScript.apply(SchedulerScript.id_seed("003"), deck.cards[2].state, "good", now)
        _ok(deck.cards[2].state["status"] == "learning", "the third card is under way (guard)")
        _is(SchedulerScript.first_fresh(deck, now), null, "a deck with nothing unseen offers nothing")

        # Tomorrow the deferred card is new again, and the offer returns.
        var tomorrow := now + 86400
        _is(SchedulerScript.first_fresh(deck, tomorrow).id, "001", "tomorrow the deferred card is first again")

# --- the offer on the caught-up page -------------------------------------------------

func _test_home_offer() -> void:
        # The page reads the wall's own clock (a defer is only "today" by
        # the real today), so the states are staged on the real now.
        var now := int(Time.get_unix_time_from_system())
        var deck = _scratch_deck("home_offer")
        if deck == null:
                _ok(false, "the scratch deck loads")
                return
        var home := HomeScript.new()
        home.name = "HomeOffer"
        home.set_anchors_preset(Control.PRESET_FULL_RECT)
        root.add_child(home)
        if not home.is_node_ready():
                await home.ready

        # Reviews alone, nothing started: the day says it is done while the
        # deck holds three unseen cards -- the offer stands.
        home.setup(deck, SchedulerScript.counts(deck, now, 0), "", "off")
        var study: Button = home.get_node("Margin/Column/Study")
        var extra: Button = home.get_node("Margin/Column/ExtraNew")
        _is(study.disabled, true, "a day of reviews alone rests the study button")
        _is(extra.visible, true, "the offer stands while an unseen card remains")
        _is(home._next_fresh_card().id, "001", "the offer points at the first unseen card")

        # The reader's own word about today: a deferred card is not offered
        # back by the button either.
        deck.cards[0].state = SchedulerScript.deferred_state(now)
        home.setup(deck, SchedulerScript.counts(deck, now, 0), "", "off")
        _is(extra.visible, true, "the offer still stands for the cards after the deferred one")
        _is(home._next_fresh_card().id, "002", "the offer skips the card deferred today")

        # Nothing left to take: the offer goes away with its reason.
        deck.cards[1].state = SchedulerScript.suspended_state(now)
        deck.cards[2].state = SchedulerScript.apply(SchedulerScript.id_seed("003"), deck.cards[2].state, "good", now)
        home.setup(deck, SchedulerScript.counts(deck, now, 0), "", "off")
        _is(extra.visible, false, "no unseen card, no offer")

        # A day with waiting work is the day's own button's business.
        deck.cards[2].state["due_ts"] = now - 10
        home.setup(deck, SchedulerScript.counts(deck, now, 0), "", "off")
        _is(study.disabled, false, "a card waiting is the study button's business")
        _is(extra.visible, false, "the offer stands only on a caught-up day")

        home.queue_free()
        await process_frame

# --- the session the offer opens ------------------------------------------------------

func _test_session_opens() -> void:
        _fresh_install()
        var main = (load("res://scripts/main.gd") as GDScript).new()
        main.set_anchors_preset(Control.PRESET_FULL_RECT)
        root.add_child(main)
        # A tree that has already processed frames fires a synchronous
        # _ready inside add_child -- awaiting an already-spent signal would
        # stand still forever, so the signal is awaited only if it has not
        # yet come.
        if not main.is_node_ready():
                await main.ready
        await create_timer(0.9).timeout
        var picker: Control = main.get_node_or_null("LanguagePicker")
        if picker != null:
                (picker.get_node("Centre/Card/Pad/Box/Languages/Langen") as Button).pressed.emit()
                await create_timer(0.6).timeout
        # Reviews alone on a fresh deck: the page is caught up, the offer
        # stands, and the button it offers opens a session of exactly one
        # card -- the card a larger offer would have brought first.
        main._settings.new_per_day = 0
        main._settings.save()
        main._refresh_home()
        var home: Control = main.get_node("Home")
        var extra: Button = home.get_node("Margin/Column/ExtraNew")
        _is(extra.visible, true, "the caught-up page offers one more new card")
        extra.pressed.emit()
        await create_timer(0.5).timeout
        var study: Control = main.get_node_or_null("Study")
        _ok(study != null, "the offer opens a session")
        if study != null:
                _is(study._cards.size(), 1, "the session holds exactly one card")
                _is(study._cards[0].id, "001", "the card is the deck's first unseen card")
                study.closed.emit()
                await create_timer(0.6).timeout

        # The one card, answered, is learned like any other: the day's
        # button goes back to resting, and the offer waits on the next
        # unseen card.
        _is(main.get_node_or_null("Home") != null, true, "the session returns home")
        main.queue_free()
        await process_frame

# --- the library's own account of the schedule -----------------------------------------

func _test_browse_counts() -> void:
        var now := int(Time.get_unix_time_from_system())
        var deck = _scratch_deck("browse_counts")
        if deck == null:
                _ok(false, "the scratch deck loads")
                return
        deck.cards[1].state = SchedulerScript.suspended_state(now)
        var browse = (load("res://scripts/ui/browse.gd") as GDScript).new()
        browse.name = "BrowseCounts"
        browse.set_anchors_preset(Control.PRESET_FULL_RECT)
        root.add_child(browse)
        if not browse.is_node_ready():
                await browse.ready
        browse.setup(deck, 1.0)
        await create_timer(0.3).timeout
        # The pills agree with the home page: a card out of the schedule for
        # good is not waiting to be learned, whatever its status says.
        var pills: HFlowContainer = browse.get_node("Margin/Column/Filters")
        var said := {}
        for child in pills.get_children():
                said[child.name] = (child as Button).text
        _is(said.get("PillAll", "").ends_with("3"), true, "the whole shelf counts every page")
        _is(said.get("PillNew", "").ends_with("2"), true, "a suspended card is not waiting to be learned")
        # And the thread the new pill keeps passes it over too.
        browse._filter = "new"
        _ok(browse._filter_matches(deck.cards[0]), "an unseen card answers the new filter")
        _ok(not browse._filter_matches(deck.cards[1]), "a suspended card does not answer the new filter")
        browse._filter = "all"
        _ok(browse._filter_matches(deck.cards[1]), "the whole shelf still counts the suspended page")
        browse.queue_free()
        await process_frame

# --- the merge law, told once ----------------------------------------------------------

func _test_merge_law_one_place() -> void:
        var answered := {"reps": 5, "mod": 500}
        var deferred := {"reps": 0, "mod": 900}
        var later := {"reps": 6, "mod": 1200}
        _ok(DeckScript.state_beats(deferred, answered), "a deliberate reset outranks an older answer")
        _ok(not DeckScript.state_beats(answered, deferred), "an older answer does not outrank a newer reset")
        _ok(DeckScript.state_beats(later, deferred), "a newer answer outranks an older reset")
        _ok(DeckScript.state_beats({"reps": 2, "mod": 50}, {"reps": 1, "mod": 900}), "between two answers, more reviews wins")

        # Noise never travels: a value of the wrong shape is not a choice,
        # through either door -- the sync engine's merge and the backup's
        # import read this one law.
        var noise := DeckScript.choices_of({
                "new_per_day": "many", "new_per_day_mod": 5,
                "ayah_font": 7, "ayah_font_mod": 6,
        })
        _is(noise.size(), 0, "a wrong-shaped value is not a travelling choice")
        var honest := DeckScript.choices_of({
                "new_per_day": 3, "new_per_day_mod": 5,
                "ayah_font": "amiri", "ayah_font_mod": 6,
        })
        _is(honest.size(), 2, "a well-shaped choice travels")
        _is(int(honest["new_per_day"]["mod"]), 5, "the choice's own moment rides with it")

        var entries := DeckScript.entries_of({"cards": {"001": {"reps": 1}, "junk": 5}})
        _is(entries.size(), 1, "a hand-edited entry that is not a card's state never merges")
        _ok(entries.has("001"), "the honest entry survives the cleaning")

# --- the segments a face is offered in --------------------------------------------------

func _test_segment_heights() -> void:
        # The mushaf cut's own line box is half again its font's size; the
        # height every segment shares must carry the tallest face's sample,
        # measured -- the fixed height once let its ink stand past the
        # border.
        var size19 := ThemeScript.fs(19)
        var tallest := 0
        for face in ThemeScript.AYAH_FACES:
                var f: Font = ThemeScript.ayah_face_for(str(face["key"]))
                var room := ThemeScript.ink_room(ThemeScript.BASMALA_SAMPLE, f, size19)
                tallest = maxi(tallest, ceili(f.get_height(size19)) + 2 * maxi(room.x, room.y))
        _is(ThemeScript.basmala_sample_height(), tallest, "the shared height is the tallest face's measured sample")
        _ok(tallest > size19, "the tallest sample is taller than its font size (the mushaf cut's box)")

        var settings := SettingsScript.new()
        settings.name = "SettingsHeights"
        settings.set_anchors_preset(Control.PRESET_FULL_RECT)
        root.add_child(settings)
        if not settings.is_node_ready():
                await settings.ready
        await process_frame
        await process_frame
        var row: HBoxContainer = settings.get_node_or_null("Margin/Scroll/Wrap/Column/Reading/Padding/Box/AyahFaces")
        _ok(row != null, "the reading card offers its faces")
        if row != null:
                var heights := []
                for child in row.get_children():
                        var button := child as Button
                        if button == null:
                                continue
                        heights.append(button.size.y)
                        # The box must hold what it offers: the segment is
                        # never shorter than the content laid inside it.
                        var pad: MarginContainer = button.get_node("Pad")
                        _ok(
                                button.size.y + 0.5 >= pad.get_combined_minimum_size().y,
                                "the %s segment holds its own name and sample" % button.name
                        )
                _is(heights.size(), ThemeScript.AYAH_FACES.size(), "every face is offered")
                if heights.size() == ThemeScript.AYAH_FACES.size():
                        _ok(
                                heights[0] == heights[1] and heights[1] == heights[2],
                                "the segments share one height"
                        )
        settings.queue_free()
        await process_frame

        # The session's popup judges the same choice; its rows answer the
        # same law, said by the same measure.
        var popup := StudyScript.new()._font_popup()
        var rows: VBoxContainer = popup.find_children("Faces", "VBoxContainer", true, false)[0] if popup.find_children("Faces", "VBoxContainer", true, false).size() > 0 else null
        _ok(rows != null, "the session's popup offers its faces")
        if rows != null:
                for child in rows.get_children():
                        var button := child as Button
                        if button == null:
                                continue
                        var sample: Label = button.get_node("Pad/Row/Sample")
                        _ok(
                                button.custom_minimum_size.y + 0.5 >= 12.0 + sample.custom_minimum_size.y,
                                "the %s row holds its own sample" % button.name
                        )
                        # Each sample carries its own face's measured room --
                        # the row height is shared, the room is the face's
                        # own. A face whose ink fits its font's box asks for
                        # no room of its own (give_label_room's own law), so
                        # only a face with room to carry is asked to carry it.
                        var key := str(button.get_meta("choice", ""))
                        var f: Font = ThemeScript.ayah_face_for(key)
                        var room := ThemeScript.ink_room(ThemeScript.BASMALA_SAMPLE, f, size19)
                        if maxi(room.x, room.y) > 0:
                                _ok(
                                        sample.custom_minimum_size.y >= ceili(f.get_height(size19)) + 2 * maxi(room.x, room.y),
                                        "the %s sample carries its own ink's room" % button.name
                                )

# --- the scratch deck ------------------------------------------------------------------

func _scratch_deck(name: String):
        var base := "user://scratch_extra_card".path_join(name)
        _remove_tree(base)
        DirAccess.make_dir_recursive_absolute(base)
        var ids := ["001", "002", "003"]
        var file := FileAccess.open(base.path_join("deck.json"), FileAccess.WRITE)
        file.store_string(JSON.stringify({"format": 1, "name": "Extra", "cards": ids}) + "\n")
        file.close()
        for id in ids:
                var folder := base.path_join(id)
                DirAccess.make_dir_recursive_absolute(folder)
                var front := FileAccess.open(folder.path_join("front.md"), FileAccess.WRITE)
                front.store_string("Sura of the test - %s\n" % id)
                front.close()
                var back := FileAccess.open(folder.path_join("back.md"), FileAccess.WRITE)
                back.store_string("the answer %s\n" % id)
                back.close()
        return DeckScript.load(base)

func _fresh_install() -> void:
        _remove_tree("user://decks")
        _remove_tree("user://settings.json")
        _remove_tree("user://sync_manifest.json")
        _remove_tree("user://scratch_extra_card")

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
