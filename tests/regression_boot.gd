extends SceneTree
const DeckScript := preload("res://scripts/data/deck.gd")
const CardScript := preload("res://scripts/data/card.gd")
const SchedulerScript := preload("res://scripts/data/scheduler.gd")
const ThemeScript := preload("res://scripts/ui/theme.gd")

## The app must boot cold, on any machine, with no warm editor cache: the
## deck installs itself into user://, the home screen shows the deck's real
## numbers, and the study screen can render a real card -- front, answer
## buttons, back. This is the smallest journey a person takes, run headless
## exactly as a fresh install would run it.

var _failures := 0

func _init() -> void:
        # A fresh install: nothing in the user folder yet.
        _fresh_install()
        var main = (load("res://scripts/main.gd") as GDScript).new()
        # The scene file gives the root its full-rect anchors; match them here,
        # or every screen lays out at zero size and any check that reads real
        # geometry (a box holding its own words) measures a page that was
        # never laid out.
        main.set_anchors_preset(Control.PRESET_FULL_RECT)
        root.add_child(main)
        await main.ready
        # The home numbers count themselves in over half a second; read them
        # only once they have settled, or the check races the count.
        await create_timer(0.9).timeout

        var home: Control = main.get_node_or_null("Home")
        _ok(home != null, "the home screen is the first thing shown")
        if home == null:
                quit(1)
                return

        await _check_home_numbers(home)
        await _check_study_session(main)
        await _check_settings(main)
        await _check_browse(main)
        _check_settings_round_trip()
        _check_sync_retrying(main)

        if _failures > 0:
                print("boot: %d FAILURE(S)" % _failures)
                quit(1)
        else:
                print("boot: all checks passed")
                quit(0)

func _fresh_install() -> void:
        _remove_tree("user://decks")
        _remove_tree("user://settings.json")

func _ok(condition: bool, what: String) -> void:
        if not condition:
                _failures += 1
                print("  FAIL: %s" % what)

func _is(got: Variant, expected: Variant, what: String) -> void:
        if got != expected:
                _failures += 1
                print("  FAIL: %s — got %s, expected %s" % [what, str(got), str(expected)])

func _check_home_numbers(home: Control) -> void:
        var deck = load("res://scripts/data/deck.gd").load("user://decks/quran")
        _ok(deck != null, "the bundled deck installs itself on first run")
        if deck == null:
                return
        _is(deck.name, "Quran", "the deck is the Quran deck")
        _ok(deck.cards.size() == 99, "all 99 cards are there (got %d)" % deck.cards.size())

        var due: Label = home.get_node("Margin/Column/Stats/Due/Box/Value")
        var fresh: Label = home.get_node("Margin/Column/Stats/New/Box/Value")
        var learned: Label = home.get_node("Margin/Column/Stats/Learned/Box/Value")
        _is(due.text, "0", "nothing is due on a fresh install")
        _is(fresh.text, "20", "a day's new cards are offered")
        _is(learned.text, "0", "nothing is learned yet")

        var study: Button = home.get_node("Margin/Column/Study")
        _ok(not study.disabled, "study is ready")
        _ok(study.text == "Learn new cards", "the button names what the session is")

        # The settings corner once sat under a full-rect container added after
        # it, and no click could reach it. The engine's hit test -- deepest
        # topmost control, children in reverse order -- is the part that
        # decides who gets the click, so it is the part this walks by hand.
        var corner: Button = home.get_node("SettingsCorner")
        var at := corner.get_global_rect().get_center()
        _ok(_top_at(home, at) == corner, "the settings corner is on top of everything at its own centre")
        # The browsing door stands under the day's work.
        var browse_button: Button = home.get_node_or_null("Margin/Column/Browse")
        _ok(browse_button != null, "the library's door stands under the study button")
        # A turning sync mark stays inside its coin: the turn is about the
        # mark's own centre, and a mark that swings out of its button is the
        # mark that once left the outer circle.
        var sync_mark: ThemeScript.SyncMark = home.get_node("SyncCoin/Mark/SyncMark")
        sync_mark.set_working(true)
        await process_frame
        await process_frame
        _ok(
                absf(sync_mark.pivot_offset.x - sync_mark.size.x / 2.0) < 0.5
                        and absf(sync_mark.pivot_offset.y - sync_mark.size.y / 2.0) < 0.5,
                "the turning mark pivots at its own centre"
        )
        sync_mark.set_working(false)


## The engine's own hit test, walked by hand: deepest topmost control at a
## point, children in reverse order, honouring visibility and mouse_filter.
func _top_at(from: Control, at: Vector2) -> Control:
        var children := from.get_children()
        for i in range(children.size() - 1, -1, -1):
                var child := children[i]
                if child is not Control:
                        continue
                var c := child as Control
                if not c.visible or c.mouse_filter == Control.MOUSE_FILTER_IGNORE:
                        continue
                if not c.get_global_rect().has_point(at):
                        continue
                var deeper: Control = _top_at(c, at)
                if deeper != null:
                        return deeper
                return c
        return null

func _check_study_session(main: Node) -> void:
        main._start_session()
        await create_timer(0.4).timeout
        var study: Control = main.get_node_or_null("Study")
        _ok(study != null, "the session opens")
        if study == null:
                return

        var view = study.get_node("Margin/Column/Surface/Fill/CardPanel/Padding/View")
        _ok(view.get_child_count() >= 1, "the card's question is on screen")
        # The recitation's loudness lives in the header's free corner: a coin
        # beside the way back, and under it a rule the hand can drag.
        var volume_coin: Button = study.get_node_or_null("Margin/Column/TopBar/Right/Pair/Volume")
        _ok(volume_coin != null, "the volume coin sits in the header's corner")
        var volume_popup: Control = study.get_node_or_null("VolumePopup")
        _ok(volume_popup != null, "the volume's own page waits under the coin")
        if volume_coin != null:
                volume_coin.pressed.emit()
                await create_timer(0.1).timeout
                _ok(volume_popup != null and volume_popup.visible, "pressing the coin opens the volume's page")
                var slider: HSlider = volume_popup.get_node("Pad/Row/Slider")
                slider.value = 0.5
                await create_timer(0.7).timeout
                _is(study.volume, 0.5, "the rule sets the loudness it says")
                _ok(absf(study._player.volume_db - linear_to_db(0.5)) < 0.01, "the player obeys the rule")
                # The speaker in the page is the mute: one press for silence,
                # one press back for the loudness silence replaced.
                (volume_popup.get_node("Pad/Row/Mute") as Button).pressed.emit()
                await create_timer(0.2).timeout
                _is(study.volume, 0.0, "pressing the speaker mutes the recitation")
                (volume_popup.get_node("Pad/Row/Mute") as Button).pressed.emit()
                await create_timer(0.2).timeout
                _is(study.volume, 0.5, "pressing it again unmutes to what was")
                _is(
                        (volume_popup.get_node("Pad/Row/Readout") as Label).text,
                        "50%",
                        "the number says the loudness inline"
                )
                volume_coin.pressed.emit()
                await create_timer(0.1).timeout
                _ok(not volume_popup.visible, "pressing the coin again closes the page")

        study._reveal()
        await create_timer(0.4).timeout
        var answers: GridContainer = study.get_node("Margin/Column/Answers")
        _ok(answers.get_child_count() == 4, "four answers appear behind the reveal")
        var labels := []
        var waits := []
        for button in answers.get_children():
                labels.append(button.get_node("Center/Row/Stack/Word").text)
                waits.append(button.get_node("Center/Row/Stack/Wait").text)
        _ok(labels.any(func(l: String) -> bool: return l.begins_with("Again")), "one answer is Again")
        _ok(labels.any(func(l: String) -> bool: return l.begins_with("Good")), "one answer is Good")
        _ok(waits.all(func(w: String) -> bool: return not w.is_empty()), "every answer names its interval")
        # The answer side carries the question's own reference, small and gold,
        # so the verse is never read without knowing which one was asked for.
        var eyebrow := view.get_node_or_null("Body/Eyebrow")
        _ok(eyebrow != null and str(eyebrow.text).length() > 0, "the question rides along above the answer")
        # The verse wears the mushaf's own cut -- Amiri Quran, whose larger
        # harakat stay round at every size this app draws; Amiri's damma at
        # the shelf's small sizes read as a fatha's stroke, and a reader
        # learning the vowels read exactly that mistake off the page. And a
        # selection rests in the page's gold, never the engine's blue.
        # The verse breathes inside its own margin wrapper, so the page is
        # walked branch and all -- the first paragraph found is the verse.
        var paragraph: RichTextLabel = null
        for found in view.find_children("Paragraph", "RichTextLabel", true, false):
                paragraph = found
                break
        if paragraph != null:
                _ok(
                        str(paragraph.get_theme_font("normal_font").resource_path).ends_with(
                                "AmiriQuran-Regular.ttf"
                        ),
                        "the verse wears the mushaf cut (Amiri Quran)"
                )
                _is(
                        paragraph.get_theme_color("selection_color"),
                        ThemeScript.SELECT,
                        "a selection rests in the page's own gold"
                )
        # The back of the first card is Arabic plus Persian plus audio.
        var texts := []
        for child in view.get_node("Body").get_children():
                if child is RichTextLabel:
                        texts.append((child as RichTextLabel).text)
        var joined := "\n".join(texts)
        _ok(joined.length() > 20, "the answer shows real content")
        _ok(_audio_buttons(view).size() >= 2, "audio is offered as buttons beside the verses")
        # The card's citation is a footer at the page's foot: a gentle rule
        # and the source beneath it, not a paragraph in the verses' column.
        var footer := view.get_node_or_null("Footer")
        _ok(footer != null, "the source link stands at the card's foot")
        if footer != null:
                _ok(
                        (footer.get_node("Citation") as RichTextLabel).text.contains("quran.makarem.ir"),
                        "the footer carries the deck's source"
                )
        # Scripture leans when its author asked it to: the deck's italic marks
        # are honoured in every script, and the engine's forced tilt on the
        # Quranic face is the emphasis the stars always meant. Stripping them
        # instead made the bismillah's emphasis vanish, and the author noticed.
        var CardViewForType := load("res://scripts/ui/card_view.gd")
        _is(CardViewForType._bbcode("*بِسمِ اللهِ*", "arabic"), "[i]بِسمِ اللهِ[/i]", "an Arabic emphasis keeps its lean")
        _is(CardViewForType._bbcode("*a note*", "plain"), "[i]a note[/i]", "a Latin emphasis keeps its lean")
        _is(CardViewForType._bbcode("*بنام خداوند*", "persian"), "[i]بنام خداوند[/i]", "a Persian emphasis keeps its lean")
        # The verse's Persian voice stands beside its Arabic one: the
        # translation recitation, offered as its own pill, named for its
        # language and the verse it speaks.
        var audio := _audio_buttons(view)
        var persian_button: Button = null
        for pill in audio:
                if (pill.get_node("Center/Row/Label") as Label).text.begins_with("Persian"):
                        persian_button = pill
                        break
        _ok(persian_button != null, "the verse's Persian translation is offered beside it")
        if persian_button != null:
                _is(
                        persian_button.get_meta("idle_text", ""),
                        "Persian · 1:1",
                        "the translation's button names its language and verse"
                )
                persian_button.pressed.emit()
                await create_timer(0.25).timeout
                _is(
                        persian_button.get_node("Center/Row/Label").text,
                        "Listening…",
                        "pressing Persian speaks the translation"
                )
                study._view._on_audio_finished()
        # The recitation's button must hear the sound end: a verse that runs
        # out takes its button back to rest instead of saying "Listening…"
        # forever -- the very thing a finished signal is for.
        var listen_button: Button = null
        for pill in _audio_buttons(view):
                if "Listen" in (pill.get_node("Center/Row/Label") as Label).text:
                        listen_button = pill
                        break
        if listen_button != null:
                listen_button.pressed.emit()
                await create_timer(0.3).timeout
                _is(
                        listen_button.get_node("Center/Row/Label").text,
                        "Listening…",
                        "pressing Listen starts the recitation"
                )
                # A pill that flashes grey reads as broken: the button never
                # disables itself, not even while a browser fetch is afoot.
                _ok(not listen_button.disabled, "the recitation's button never wears the engine's grey")
                study._view._on_audio_finished()
                _is(
                        listen_button.get_node("Center/Row/Label").text,
                        listen_button.get_meta("idle_text", ""),
                        "the button rests the moment the sound runs out"
                )

        # The pencil: a card noticed mid-study is fixed mid-study. The
        # editor opens over the session, holds the keyboard, and saves back
        # to the very files the deck is.
        var edit_coin: Button = study.get_node_or_null("Margin/Column/TopBar/Right/Pair/Edit")
        _ok(edit_coin != null, "the pencil sits in the header's corner")
        if edit_coin != null:
                edit_coin.pressed.emit()
                await create_timer(0.3).timeout
                var editor: Control = study.get_node_or_null("Editor")
                _ok(editor != null, "the pencil opens the card's own page")
                if editor != null:
                        var front_field: Control = editor.get_node_or_null(
                                "Margin/Column/Scroll/Wrap/Content/Write/Front"
                        )
                        var back_field: Control = editor.get_node_or_null(
                                "Margin/Column/Scroll/Wrap/Content/Write/Back"
                        )
                        _ok(front_field != null and back_field != null, "the page carries the question and the answer")
                        if front_field != null and back_field != null:
                                var original: String = study._cards[0].front
                                _is(front_field.get_text(), original, "the editor opens with the card's own words")
                                # The page writes the way its words are read: the mirror's
                                # lines stand flush right, and the input engine beneath them
                                # resolves each line's own direction.
                                var lines: VBoxContainer = front_field.get_node_or_null("Lines")
                                _ok(lines != null and lines.get_child_count() >= 1, "the field lays its words out in lines")
                                if lines != null and lines.get_child_count() > 0:
                                        var mirror_line: RichTextLabel = lines.get_child(0)
                                        _ok(
                                                mirror_line.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT,
                                                "the writing runs flush right, the way Arabic is read"
                                        )
                                var source: TextEdit = front_field.get_node_or_null("Source")
                                _ok(
                                        source != null and source.text_direction == Control.TEXT_DIRECTION_AUTO,
                                        "the input engine reads each line's own direction"
                                )
                                front_field.set_text(original + "\nedited on the spot")
                                (editor.get_node("Margin/Column/Footer/Actions/Save") as Button).pressed.emit()
                                await create_timer(0.4).timeout
                                _ok(study.get_node_or_null("Editor") == null, "saving closes the editor")
                                _is(
                                        FileAccess.get_file_as_string("user://decks/quran/001/front.md"),
                                        original + "\nedited on the spot\n",
                                        "the edit lands in the card's own file"
                                )
                                _is(study._cards[0].front, original + "\nedited on the spot", "the card in memory carries the edit")
                                _ok(main._deck_edited, "the deck knows an edit waits for the repo")
                                # The suite leaves the deck as it found it.
                                var restore := FileAccess.open("user://decks/quran/001/front.md", FileAccess.WRITE)
                                restore.store_string(original + "\n")
                                restore.close()
                                study._cards[0].front = original
                                main._deck_edited = false
                                # The page asks before it lets the work go: a dirty page
                                # shows its guard, and discarding leaves the file untouched.
                                edit_coin.pressed.emit()
                                await create_timer(0.3).timeout
                                editor = study.get_node_or_null("Editor")
                                if editor != null:
                                        front_field = editor.get_node_or_null(
                                                "Margin/Column/Scroll/Wrap/Content/Write/Front"
                                        )
                                        if front_field != null:
                                                front_field.set_text(original + "\nthrown away")
                                                (editor.get_node("Margin/Column/TopBar/Back") as Button).pressed.emit()
                                                await create_timer(0.2).timeout
                                                _ok(
                                                        editor.get_node_or_null("Margin/Column/Footer/Guard") != null
                                                                and editor.get_node("Margin/Column/Footer/Guard").visible,
                                                        "leaving with unwritten words asks first"
                                                )
                                                (editor.get_node("Margin/Column/Footer/Guard/Discard") as Button).pressed.emit()
                                                await create_timer(0.4).timeout
                                                _ok(study.get_node_or_null("Editor") == null, "discarding closes the page")
                                                _is(
                                                        FileAccess.get_file_as_string("user://decks/quran/001/front.md"),
                                                        original + "\n",
                                                        "discarding writes nothing"
                                                )
                                # A page only opened and only closed is not an
                                # edit: the card's files end with the newline
                                # every text file carries, and the guard that
                                # compares them must read both sides the same
                                # way -- nothing was asked, nothing was kept.
                                edit_coin.pressed.emit()
                                await create_timer(0.3).timeout
                                editor = study.get_node_or_null("Editor")
                                if editor != null:
                                        (editor.get_node("Margin/Column/TopBar/Back") as Button).pressed.emit()
                                        await create_timer(0.25).timeout
                                        _ok(
                                                study.get_node_or_null("Editor") == null,
                                                "closing an untouched page asks nothing"
                                        )
                                # The page's other way of standing: the card as its reader
                                # will see it, both sides laid out whole.
                                edit_coin.pressed.emit()
                                await create_timer(0.3).timeout
                                editor = study.get_node_or_null("Editor")
                                if editor != null:
                                        (editor.get_node("Margin/Column/Footer/Actions/Mode/Row/Read") as Button).pressed.emit()
                                        await create_timer(0.3).timeout
                                        var read_col: VBoxContainer = editor.get_node_or_null(
                                                "Margin/Column/Scroll/Wrap/Content/Read"
                                        )
                                        _ok(
                                                read_col != null and read_col.get_child_count() == 2,
                                                "the read mode lays out both sides of the card"
                                        )
                                        editor.queue_free()

        # Answer the card and check the state moves.
        study._answer("good")
        await create_timer(0.3).timeout
        var deck = load("res://scripts/data/deck.gd").load("user://decks/quran")
        var studied: CardScript = deck.cards[0]
        _is(studied.state.status, "learning", "the answered card is learning")
        _is(studied.state.reps, 1, "the review is recorded")
        _is(studied.state.step, 1, "the card moved to the next step")

        study.closed.emit()
        await create_timer(0.4).timeout
        _ok(main.get_node_or_null("Home") != null, "closing the session returns home")

func _check_settings(main: Node) -> void:
        main._on_settings_pressed()
        await create_timer(0.4).timeout
        var settings: Control = main.get_node_or_null("Settings")
        _ok(settings != null, "settings opens")
        if settings == null:
                return
        # The path is walked with a guard, not a bare get_node: a stale path
        # once errored silently here and the suite called the broken check a
        # pass, because a runtime error aborts the function, not the run.
        var state: RichTextLabel = settings.get_node_or_null("Margin/Scroll/Wrap/Column/GitHub/Padding/Box/State")
        _ok(state != null, "the GitHub section stands where it is built")
        if state != null:
                _ok(state.text.length() > 0, "the GitHub section says where things stand")
        var token: LineEdit = settings.get_node_or_null("Margin/Scroll/Wrap/Column/GitHub/Padding/Box/Token")
        _ok(token != null, "the token field stands in its own row")
        # Paste is no longer a button: in a browser the page hands the app its
        # own paste events, so Ctrl+V works in the field itself and a finger
        # pastes by holding it. The two doors that remain are seeing and
        # saving -- and the old button must not come back by accident.
        var paste: Button = settings.get_node_or_null("Margin/Scroll/Wrap/Column/GitHub/Padding/Box/TokenRow/PasteToken")
        _ok(paste == null, "no paste button: paste happens in the field itself")
        var shown: Button = settings.get_node_or_null("Margin/Scroll/Wrap/Column/GitHub/Padding/Box/TokenRow/ShowToken")
        _ok(shown != null, "the show button stands under the token field")
        var saved: Button = settings.get_node_or_null("Margin/Scroll/Wrap/Column/GitHub/Padding/Box/TokenRow/SaveToken")
        _ok(saved != null, "the save button stands beside it")
        var card_title: Label = settings.get_node_or_null("Margin/Scroll/Wrap/Column/GitHub/Padding/Box/CardTitle")
        _ok(card_title != null and card_title.text.length() > 0, "the GitHub card carries its own title inside it")
        # The quiet promise is a row of its own with a switch, not a caption
        # with a dot after it: a first-time reader sees the choice they have.
        var auto_row: Button = settings.get_node_or_null("Margin/Scroll/Wrap/Column/GitHub/Padding/Box/AutoRow")
        _ok(auto_row != null, "the auto-sync promise stands as its own row")
        if auto_row != null:
                _ok(auto_row.has_node("AutoPad/AutoLine/Switch"), "the promise row carries a switch")
                _ok(auto_row.text.is_empty(), "the row's words live in it, not on it")
                auto_row.set_pressed_no_signal(true)
                auto_row.toggled.emit(true)
                _ok(main._settings.auto_sync, "the row keeps the promise it says")
        # The day's offer is the reader's own: the stepper stands in the deck's
        # card, a press moves the number and writes the file, and the counts
        # that reach home answer it.
        var step_value: Label = settings.get_node_or_null(
                "Margin/Scroll/Wrap/Column/DeckInfo/Padding/Box/NewPerDay/Chip/StepValue"
        )
        _ok(step_value != null, "the day's new-card offer stands in the deck's card")
        if step_value != null:
                _is(int(step_value.text), main._settings.new_per_day, "the chip says the setting's number")
                var step_more: Button = settings.get_node_or_null(
                        "Margin/Scroll/Wrap/Column/DeckInfo/Padding/Box/NewPerDay/StepMore"
                )
                if step_more != null:
                        step_more.pressed.emit()
                        _is(main._settings.new_per_day, 21, "a press on more offers one more card a day")
                        _is(int(step_value.text), 21, "the chip follows the setting")
                var step_less: Button = settings.get_node_or_null(
                        "Margin/Scroll/Wrap/Column/DeckInfo/Padding/Box/NewPerDay/StepLess"
                )
                if step_less != null:
                        step_less.pressed.emit()
                        _is(main._settings.new_per_day, 20, "a press on less offers one fewer")
        # The home page answers the offer the same hour it changes: counts
        # carry the cap, and a smaller day is a smaller new count.
        var counts_now: Dictionary = SchedulerScript.counts(main._deck, int(Time.get_unix_time_from_system()), 3)
        _is(counts_now.new, 3, "a day that offers three brings three new cards")
        _is(counts_now.new_per_day, 3, "the counts carry the day's own offer")
        settings.closed.emit()
        await create_timer(0.4).timeout
        _ok(main.get_node_or_null("Home") != null, "closing settings returns home")

## The library: every card in the deck, grouped by surah, each row opening
## its own verses and recitations in place. The search field keeps the
## shelf to the cards that answer it -- by reference, by the verses' own
## words, or by a verse's address, in whatever digits the hand prefers.
## Nothing here schedules; reading, listening and the pencil are all it
## does.
func _check_browse(main: Node) -> void:
        main._on_browse_pressed()
        await create_timer(0.5).timeout
        var browse: Control = main.get_node_or_null("Browse")
        _ok(browse != null, "the library opens")
        if browse == null:
                return
        var deck = load("res://scripts/data/deck.gd").load("user://decks/quran")
        # The path is walked with a guard, not a bare get_node: a stale path
        # errors silently and the suite calls the broken check a pass.
        var column: VBoxContainer = browse.get_node_or_null("Margin/Column/Scroll/Wrap/Column")
        if column == null:
                _ok(false, "the library's column stands where it is built")
                browse.closed.emit()
                await create_timer(0.3).timeout
                return
        var rows := 0
        var headers := 0
        for child in column.get_children():
                if child.name.begins_with("Entry"):
                        rows += 1
                elif child.name.begins_with("Header"):
                        headers += 1
        _is(rows, deck.cards.size(), "every card has its row in the library")
        _ok(headers >= 2, "the cards are gathered under their surahs' names")
        # The chapter's opening: no thread under the name -- a partial green
        # line reads as a line that failed to render -- and how many rest in
        # review is said in the count's own words, never as a broken-looking
        # rule.
        var last_header: VBoxContainer = null
        for child in column.get_children():
                if child.name.begins_with("Header"):
                        last_header = child
        if last_header != null:
                browse._set_header_count(column, 7, 2)
                var folio: Label = last_header.get_node_or_null("Line/Count")
                _ok(
                        folio != null and folio.text == "7 cards · 2 in review",
                        "the chapter's count says in words how many rest in review"
                )
                _ok(
                        last_header.get_node_or_null("Rule") == null,
                        "the chapter opens without a half-rendered thread"
                )
        # The search field: a verse's address finds its card, in the hand's
        # own digits, and the shelf keeps only what answers.
        var search: LineEdit = browse.get_node_or_null("Margin/Column/Search")
        _ok(search != null, "the library carries a search field")
        if search != null:
                search.text = "2:93"
                browse._on_search_changed("2:93")
                await create_timer(0.4).timeout
                var matched := 0
                for child in column.get_children():
                        if child.name.begins_with("Entry"):
                                matched += 1
                _is(matched, 1, "an address finds exactly its card (got %d)" % matched)
                _ok(
                        (browse.get_node("Margin/Column/Summary") as Label).text.begins_with("1 of "),
                        "the shelf says how many answered"
                )
                # Persian digits ask the same question.
                browse._on_search_changed("۲:۹۳")
                await create_timer(0.4).timeout
                matched = 0
                for child in column.get_children():
                        if child.name.begins_with("Entry"):
                                matched += 1
                _is(matched, 1, "Persian digits ask the same question (got %d)" % matched)
                # A question nothing answers says so, quietly.
                browse._on_search_changed("nothing matches this")
                await create_timer(0.4).timeout
                _ok(browse.get_node_or_null("Margin/Column/Scroll/Wrap/Column/Empty") != null, "an empty search says so")
                browse._on_search_changed("")
                await create_timer(0.4).timeout
                rows = 0
                for child in column.get_children():
                        if child.name.begins_with("Entry"):
                                rows += 1
                _is(rows, deck.cards.size(), "a cleared search brings the shelf back")
        # A row opens its card in place: the verses, the recitations, the
        # citation at the foot -- and only one row is open at a time.
        var first_entry: VBoxContainer = null
        for child in column.get_children():
                if child.name.begins_with("Entry"):
                        first_entry = child
                        break
        _ok(first_entry != null, "the library's first card stands in its row")
        if first_entry == null:
                browse.closed.emit()
                await create_timer(0.3).timeout
                return
        # The shelf's own scripture: the row's preview is the verse itself in
        # the mushaf cut, flush right the way the verse is read, at a size
        # its vowels survive -- the one place the app drew Amiri's harakat
        # small enough to misread.
        var preview: Label = first_entry.get_node_or_null("Row/Pad/Line/Words/Preview")
        if preview != null:
                _is(
                        preview.get_theme_font_size("font_size"),
                        26,
                        "the shelf's verse preview reads at the mushaf's size"
                )
                _ok(
                        str(preview.get_theme_font("font").resource_path).ends_with("AmiriQuran-Regular.ttf"),
                        "the shelf's preview wears the mushaf cut"
                )
                _ok(
                        preview.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT,
                        "the verse stands flush right, the edge it is read from"
                )
        # The row's own box holds its whole line of words: the standing at
        # the left, the address and the pointer at the right, all inside the
        # rounded box the row wears while its page is open -- none of it
        # hanging under the row's floor into the next verse.
        var open_row: Button = first_entry.get_node("Row") as Button
        var row_pad: MarginContainer = first_entry.get_node("Row/Pad") as MarginContainer
        var meta_box: Control = first_entry.get_node_or_null("Row/Pad/Line/Words/Meta")
        if meta_box != null and row_pad != null:
                _ok(
                        open_row.get_global_rect().encloses(meta_box.get_global_rect()),
                        "the row's box holds its standing and its pointer inside it"
                )
                _ok(
                        open_row.get_global_rect().size.y >= row_pad.get_combined_minimum_size().y - 0.5,
                        "the row stands as tall as its own words"
                )
        var ref_label: Label = first_entry.get_node_or_null("Row/Pad/Line/Words/Meta/Ref")
        if ref_label != null:
                _ok(
                        ref_label.get_combined_minimum_size().x > 10.0,
                        "the row carries its address in gold, not clipped to nothing"
                )
        (first_entry.get_node("Row") as Button).pressed.emit()
        await create_timer(0.4).timeout
        var detail: VBoxContainer = first_entry.get_node("Detail")
        _ok(detail.visible, "a pressed row opens its card beneath it")
        var disclose = first_entry.get_node_or_null("Row/Pad/Line/Words/Meta/Disclose")
        if disclose != null:
                _ok(disclose.open, "the pointer turns into what it opened")
        var view = detail.get_node("Card/Pad/Page/View")
        _ok(view.get_node("Body").get_child_count() >= 2, "the open card shows its verses")
        _ok(view.get_node_or_null("Footer") != null, "the open card carries its citation at the foot")
        var persian_rows := 0
        for pill in _audio_buttons(view):
                if (pill.get_node("Center/Row/Label") as Label).text.begins_with("Persian"):
                        persian_rows += 1
        _ok(persian_rows >= 1, "the open card offers its Persian translation")
        var pencil: Button = detail.get_node_or_null("Card/Pad/Page/Edit")
        _ok(pencil != null, "the open card carries the pencil at its foot")
        if pencil != null:
                _ok(
                        detail.get_node("Card").get_global_rect().encloses(pencil.get_global_rect()),
                        "the pencil lives inside the card, not on the desk below it"
                )
        var second_entry: VBoxContainer = null
        for child in column.get_children():
                if child != first_entry and child.name.begins_with("Entry"):
                        second_entry = child
                        break
        if second_entry != null:
                (second_entry.get_node("Row") as Button).pressed.emit()
                await create_timer(0.3).timeout
                _ok(not detail.visible, "opening one row folds the last one away")
        # The shelf's other question: the pills that keep one thread of the
        # story -- what is due, what has never been started, what rests.
        var filters: HFlowContainer = browse.get_node_or_null("Margin/Column/Filters")
        _ok(filters != null and filters.get_child_count() == 4, "the shelf carries its four pills")
        if filters != null and filters.get_child_count() == 4:
                var due_pill: Button = filters.get_node_or_null("PillDue")
                _ok(due_pill != null, "the due pill stands with its count")
                if due_pill != null:
                        due_pill.pressed.emit()
                        await create_timer(0.4).timeout
                        var due_rows := 0
                        for child in column.get_children():
                                if child.name.begins_with("Entry"):
                                        due_rows += 1
                        _is(due_rows, 0, "a fresh deck has nothing due today (got %d)" % due_rows)
                        _ok(
                                browse.get_node_or_null("Margin/Column/Scroll/Wrap/Column/Empty") != null,
                                "an empty due list says so, warmly"
                        )
                        due_pill = filters.get_node_or_null("PillDue")
                        if due_pill != null:
                                due_pill.pressed.emit()
                        await create_timer(0.4).timeout
                        var back_rows := 0
                        for child in column.get_children():
                                if child.name.begins_with("Entry"):
                                        back_rows += 1
                        _is(back_rows, deck.cards.size(), "a pressed-again pill brings the whole shelf back")
        # The running head: a surah's title that stays while its cards scroll.
        _ok(browse.get_node_or_null("Sticky") != null, "the running head rides above the shelf")
        var sticky: PanelContainer = browse.get_node_or_null("Sticky")
        if sticky != null:
                _ok(not sticky.visible, "the running head rests while the shelf is at its top")
                (browse.get_node("Margin/Column/Scroll") as ScrollContainer).scroll_vertical = 900
                await create_timer(0.3).timeout
                _ok(sticky.visible, "scrolling into a surah's cards raises its running head")
                _ok(
                        sticky.get_node("Row/Name").text.length() > 0,
                        "the running head names the chapter it stands over"
                )
        browse.closed.emit()
        await create_timer(0.4).timeout
        _ok(main.get_node_or_null("Home") != null, "leaving the library returns home")


## A sync the network interrupted is retried on the app's own, each retry
## a resume; a token the repo refuses is not retried at all, because that
## failure does not heal with time.
func _check_sync_retrying(main: Node) -> void:
        _ok(main._sync_retryable("head_failed"), "a network failure is worth retrying")
        _ok(main._sync_retryable("blob_failed"), "a failed upload is worth retrying")
        _ok(not main._sync_retryable("no_token"), "a missing token is not retried")
        _ok(not main._sync_retryable("auth_failed"), "a refused token is not retried")
        main._sync_attempts = 0
        _ok(
                main._maybe_schedule_sync_retry(true, {"ok": false, "error": "head_failed"}),
                "a quiet failure schedules its own retry"
        )
        _ok(main._sync_retrying, "the app says it will try again")
        _is(main._sync_attempts, 1, "the first retry is the first retry")
        main._settings.token = "for-the-line"
        _ok(
                main._sync_line().contains("try again"),
                "the home line says the app will try again by itself"
        )
        main._settings.token = ""
        _ok(
                not main._maybe_schedule_sync_retry(true, {"ok": false, "error": "auth_failed"}),
                "a refused token schedules nothing"
        )
        _ok(
                not main._maybe_schedule_sync_retry(false, {"ok": false, "error": "head_failed"}),
                "a hand-pressed sync is not retried behind the hand's back"
        )
        main._sync_retrying = false
        main._sync_attempts = 0
        main._sync_generation += 1  # cancels the pending timer's run


## The app's own memory must survive its own handwriting: JSON writes
## every number as a float, and a loader that compared types strictly
## forgot the last sync forever -- the app said "not synced yet" on every
## open, and said it again after every sync, forever, on every platform.
func _check_settings_round_trip() -> void:
        var script: GDScript = load("res://scripts/data/settings.gd")
        var settings = script.new()
        settings.token = "round-trip"
        settings.last_sync = 1792000123
        settings.setup_done = true
        settings.auto_sync = false
        settings.volume = 0.35
        settings.new_per_day = 7
        _ok(settings.save(), "settings save")
        var back = script.load_settings()
        _is(back.token, "round-trip", "the token loads back")
        _is(back.last_sync, 1792000123, "the last sync time survives its own reload")
        _is(back.setup_done, true, "setup_done survives its own reload")
        _is(back.auto_sync, false, "a switched-off auto sync stays off")
        _is(back.volume, 0.35, "a chosen loudness survives its own reload")
        _is(back.new_per_day, 7, "a chosen pace survives its own reload")
        # A file written by any older version of the app carries its ints as
        # floats; those must heal into the ints they were meant as.
        var file := FileAccess.open("user://settings.json", FileAccess.WRITE)
        file.store_string("{\"last_sync\": 1792000456.0, \"token\": \"x\", \"repo\": \"r\"}\n")
        file.close()
        var healed = script.load_settings()
        _is(healed.last_sync, 1792000456, "a whole float reads back as the int it was saved as")

## The pills a card view offers, gathered from the flows they sit in: a
## verse's voices live side by side inside a flow, not directly on the page.
func _audio_buttons(view: Node) -> Array:
        var out: Array = []
        for child in view.get_node("Body").get_children():
                if child is HFlowContainer:
                        for pill in child.get_children():
                                if pill is Button and pill.has_node("Center/Row/Icon"):
                                        out.append(pill)
        return out

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
