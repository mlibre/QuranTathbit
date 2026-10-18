extends SceneTree
const DeckScript := preload("res://scripts/data/deck.gd")
const CardScript := preload("res://scripts/data/card.gd")
const SchedulerScript := preload("res://scripts/data/scheduler.gd")
const DeckZipScript := preload("res://scripts/data/deck_zip.gd")
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
        await _check_language_picker(main)
        await _check_study_session(main)
        _check_own_digits()
        await _check_settings(main)
        await _check_browse(main)
        await _check_marks_and_rtl(main)
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

## The numbers a tongue says in its own script: Persian and Arabic readers
## meet ۱۰۰ and ١٠٠, never a Latin digit standing among their own words, and
## a wait is said in words -- ۱ روز, not 1d. English keeps the arithmetic
## it has always read.
func _check_own_digits() -> void:
        var i18n := load("res://scripts/ui/i18n.gd")
        i18n.set_lang("fa")
        _is(i18n.num("100"), "۱۰۰", "a Persian page says a hundred in Persian")
        _is(i18n.num("1.5"), "۱٫۵", "a half keeps its own separator")
        _is(i18n.num("50%"), "۵۰٪", "a percent keeps its own sign")
        _is(i18n.num("2:1"), "۲:۱", "a colon is never a separator")
        _is(i18n.num("end. Then"), "end. Then", "a sentence's own full stop is never a separator")
        _is(i18n.wait(86400), "۱ روز", "a day's wait is said in Persian words")
        _is(i18n.wait(600), "۱۰ دقیقه", "ten minutes likewise")
        _is(i18n.wait(30), "۳۰ ثانیه", "seconds likewise")
        _is(i18n.wait(129600), "۱٫۵ روز", "a day and a half likewise")
        _is(i18n.f("%d cards", [7]), "۷ کارت", "a whole line carries its own digits")
        i18n.set_lang("ar")
        _is(i18n.num(42), "٤٢", "an Arabic page says forty-two in Arabic")
        _is(i18n.wait(86400), "١ يوم", "a day's wait is said in Arabic words")
        i18n.set_lang("en")
        _is(i18n.num("100"), "100", "English reads its numbers as it always has")
        _is(i18n.wait(86400), "1d", "and its waits in Anki's own arithmetic")

func _ok(condition: bool, what: String) -> void:
        if not condition:
                _failures += 1
                print("  FAIL: %s" % what)

## A face row, found by the choice it carries rather than the words its
## name was built from -- "amiri_quran" capitalizes with a space in it,
## and a path built by hand would break on exactly that.
func _face_row_by_choice(popup: Control, key: String) -> Button:
        var rows: VBoxContainer = popup.get_node_or_null("Sheet/Pad/Column/Faces")
        if rows == null:
                return null
        for child in rows.get_children():
                var button := child as Button
                if button != null and str(button.get_meta("choice", "")) == key:
                        return button
        return null

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
        _ok(deck.cards.size() == 151, "all 151 cards are there (got %d)" % deck.cards.size())

        var due: Label = home.get_node("Margin/Column/Stats/Due/Box/Value")
        var fresh: Label = home.get_node("Margin/Column/Stats/New/Box/Value")
        var learned: Label = home.get_node("Margin/Column/Stats/Learned/Box/Value")
        _is(due.text, "0", "nothing is due on a fresh install")
        _is(fresh.text, "2", "a day's new cards are offered")
        _is(learned.text, "0", "nothing is learned yet")

        var study: Button = home.get_node("Margin/Column/Study")
        _ok(not study.disabled, "study is ready")
        _ok(study.text == "Learn new cards", "the button names what the session is")

        # The deck's own account is not said on the card at all any more:
        # the reader found the one lonely box it lived in bad to look at, so
        # it left with the box -- the pills below own the day's numbers, and
        # the card between owns the day's one news, standing as its hero.
        _ok(
                home.get_node_or_null("Margin/Column/DeckCard/Pad/Box/Caption") == null,
                "the deck card no longer says its account as a line of prose"
        )
        _ok(
                home.get_node_or_null("Margin/Column/DeckCard/Pad/Box/Chips") == null,
                "the total-card box is gone from the middle card entirely"
        )
        _ok(
                home.get_node_or_null("Margin/Column/DeckCard/Pad/Box/Ornament") != null,
                "the card wears the deck's own ornament between its name and its news"
        )
        var next_up: Label = home.get_node_or_null("Margin/Column/DeckCard/Pad/Box/NextUp")
        if next_up != null:
                _ok(next_up.visible and not next_up.text.is_empty(), "the day's news stands on the card")
                var hero_script := ThemeScript.reference_script(next_up.text)
                _is(
                        next_up.get_theme_font_size("font_size"),
                        ThemeScript.fs(30 if hero_script == "arabic" else (22 if hero_script == "persian" else 16)),
                        "the day's news is the card's hero, at the hero's own measure"
                )
        var deck_title: Label = home.get_node_or_null("Margin/Column/DeckCard/Pad/Box/Title")
        if deck_title != null:
                _is(
                        deck_title.get_theme_font_size("font_size"),
                        ThemeScript.fs(22),
                        "the deck's name is calm furniture at one quiet measure"
                )

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


## The app's very first question, asked exactly once: a fresh install has
## never answered for its tongue, so the picker stands over the home page
## until a language is chosen -- and the choice is remembered on the device,
## carried with the deck, and never asked again on any device the deck
## reaches.
func _check_language_picker(main: Node) -> void:
        var picker: Control = main.get_node_or_null("LanguagePicker")
        _ok(picker != null, "a first run offers the app's language")
        if picker == null:
                return
        _ok(
                picker.get_node_or_null("Centre/Card/Pad/Box/Languages/Langen") != null,
                "each language is named in its own script"
        )
        (picker.get_node("Centre/Card/Pad/Box/Languages/Langen") as Button).pressed.emit()
        await create_timer(0.6).timeout
        _ok(main.get_node_or_null("LanguagePicker") == null, "the picker leaves once answered")
        _ok(main.get_node_or_null("Home") != null, "home stands beneath, said in the tongue chosen")
        var remembered: Variant = JSON.parse_string(
                FileAccess.get_file_as_string("user://settings.json")
        )
        _ok(
                typeof(remembered) == TYPE_DICTIONARY
                        and str((remembered as Dictionary).get("ui_lang", "")) == "en",
                "the choice is remembered on this device"
        )
        var carried: Variant = JSON.parse_string(
                FileAccess.get_file_as_string("user://decks/quran/progress.json")
        )
        _ok(
                typeof(carried) == TYPE_DICTIONARY
                        and str((carried as Dictionary).get("ui_lang", "")) == "en",
                "the choice is carried with the deck"
        )


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
                # The page hangs from its coin: never past the window's edge,
                # a breath below it, its roof pointing up at it -- the peak is
                # the anchor, so a narrow window may slide the page sideways
                # and the page still reads as the coin's own.
                var coin_rect := volume_coin.get_global_rect()
                var page_rect := volume_popup.get_global_rect()
                var window_w := study.get_global_rect().size.x
                _ok(
                        absf(page_rect.position.y - (coin_rect.end.y + 8.0)) < 2.0,
                        "the volume's page hangs a breath below its coin"
                )
                _ok(
                        page_rect.position.x >= 11.0 and page_rect.end.x <= window_w - 11.0,
                        "the page never runs past the window's edge"
                )
                var caret: Control = volume_popup.get_node_or_null("Caret")
                _ok(
                        caret != null
                                and absf(
                                        page_rect.position.x + caret.position.x + 8.0
                                                - coin_rect.get_center().x
                                ) < 3.0,
                        "the page's roof points up at its coin"
                )
                _ok(
                        volume_popup.get_node_or_null("Sheet/Pad/Column/Title") != null,
                        "the page says what it is for before it asks for a number"
                )
                # The page centers on its one number: the quiet name above,
                # the live figure large beneath it, and under both the mute
                # anchoring one rule the width of the page -- the way every
                # volume rule the reader has ever dragged behaves, the box
                # the reader twice called wrong being neither.
                var readout: Label = volume_popup.get_node_or_null("Sheet/Pad/Column/Readout")
                _ok(
                        readout != null and readout.text.length() > 0,
                        "the figure stands centered, the page's own hero"
                )
                _ok(
                        readout != null
                                and absf(
                                        (readout.get_global_rect().get_center().x
                                        - volume_popup.get_global_rect().get_center().x)
                                ) < 2.0,
                        "the figure stands at the page's own centre"
                )
                var slider: HSlider = volume_popup.get_node("Sheet/Pad/Column/Band/Slider")
                slider.value = 0.5
                await create_timer(0.7).timeout
                _is(study.volume, 0.5, "the rule sets the loudness it says")
                _ok(absf(study._player.volume_db - linear_to_db(0.5)) < 0.01, "the player obeys the rule")
                # The rule a thumb actually wants: everything the band holds
                # after the mute, which is the width of the page.
                _ok(
                        slider.size.x >= 240.0,
                        "the rule runs the width of the page, wide enough for a thumb"
                )
                _ok(
                        volume_popup.get_node_or_null("Sheet/Pad/Column/Band/Mute") != null,
                        "the mute anchors the rule at the reading's start"
                )
                # The speaker in the band is the mute: one press for silence,
                # one press back for the loudness silence replaced.
                (volume_popup.get_node("Sheet/Pad/Column/Band/Mute") as Button).pressed.emit()
                await create_timer(0.2).timeout
                _is(study.volume, 0.0, "pressing the speaker mutes the recitation")
                (volume_popup.get_node("Sheet/Pad/Column/Band/Mute") as Button).pressed.emit()
                await create_timer(0.2).timeout
                _is(study.volume, 0.5, "pressing it again unmutes to what was")
                _is(
                        (volume_popup.get_node("Sheet/Pad/Column/Readout") as Label).text,
                        "50%",
                        "the figure says the loudness from the page's own centre"
                )
                # The loud mark keeps its promise: one press, and the rule
                # holds everything it can.
                (volume_popup.get_node("Sheet/Pad/Column/Band/Loud") as Button).pressed.emit()
                await create_timer(0.2).timeout
                _is(study.volume, 1.0, "pressing the loud mark fills the rule")
                _is(
                        (volume_popup.get_node("Sheet/Pad/Column/Readout") as Label).text,
                        "100%",
                        "the figure says a full rule in its own round way"
                )
                volume_coin.pressed.emit()
                await create_timer(0.1).timeout
                _ok(not volume_popup.visible, "pressing the coin again closes the page")

        # The verses' own hand can be chosen where they are read: a third coin
        # in the corner opens the faces, a choice re-says the card in the new
        # hand at once, and the deck carries the choice as it carries every
        # travelling one.
        var font_coin: Button = study.get_node_or_null("Margin/Column/TopBar/Right/Pair/Font")
        _ok(font_coin != null, "the alif coin sits between the pencil and the speaker")
        var font_popup: Control = study.get_node_or_null("FontPopup")
        _ok(font_popup != null, "the faces' own page waits under the coin")
        if font_coin != null and font_popup != null:
                font_coin.pressed.emit()
                await create_timer(0.1).timeout
                _ok(font_popup.visible, "pressing the alif opens the faces")
                _ok(volume_popup == null or not volume_popup.visible, "opening the faces closes the volume's page")
                var face_rows := font_popup.get_node_or_null("Sheet/Pad/Column/Faces")
                _ok(face_rows != null and face_rows.get_child_count() == 3, "each face is a row of its own")
                var amiri_row := _face_row_by_choice(font_popup, "amiri")
                if amiri_row != null:
                        amiri_row.pressed.emit()
                        await create_timer(0.3).timeout
                        _ok(not font_popup.visible, "a choice folds the page away")
                        _is(ThemeScript.ayah_face_key(), "amiri", "the chosen face is worn from this breath on")
                        var carried_face: Variant = JSON.parse_string(
                                FileAccess.get_file_as_string("user://decks/quran/progress.json")
                        )
                        _ok(
                                typeof(carried_face) == TYPE_DICTIONARY
                                        and str((carried_face as Dictionary).get("ayah_font", "")) == "amiri",
                                "the choice is stamped into the deck's own file"
                        )
                        var resaid: RichTextLabel = null
                        for found in view.find_children("Paragraph", "RichTextLabel", true, false):
                                resaid = found
                                break
                        _ok(
                                resaid != null
                                        and str(resaid.get_theme_font("normal_font").resource_path).ends_with(
                                                "Amiri-Regular.ttf"
                                        ),
                                "the standing card re-says its words in the new hand"
                        )
                # Back to the mushaf's own cut, the way the reader found it.
                font_coin.pressed.emit()
                await create_timer(0.1).timeout
                var quran_row := _face_row_by_choice(font_popup, "amiri_quran")
                if quran_row != null:
                        quran_row.pressed.emit()
                        await create_timer(0.2).timeout
                        _is(ThemeScript.ayah_face_key(), "amiri_quran", "the mushaf's cut returns")

        # A tongue says its numbers in its own script: the session's count
        # in Persian reads ۱ از ۹۹, the answer buttons name their waits in
        # Persian words with the word and the wait centred on one axis, and
        # the recitation's button says only what it does -- the verse's own
        # address is already said by the page, twice.
        var i18n := load("res://scripts/ui/i18n.gd")
        i18n.set_lang("fa")
        study._show_front()
        await create_timer(0.1).timeout
        var fa_progress: Label = study.get_node("Margin/Column/TopBar/Progress")
        _ok(
                fa_progress.text.contains("از") and not fa_progress.text.contains("1"),
                "the session's count is said in Persian words and digits"
        )
        study._reveal()
        await create_timer(0.4).timeout
        var fa_waits := []
        var centered_pairs := true
        for button in study.get_node("Margin/Column/Answers").get_children():
                fa_waits.append(button.get_node("Center/Row/Stack/Wait").text)
                var word_label: Label = button.get_node("Center/Row/Stack/Word")
                var wait_label: Label = button.get_node("Center/Row/Stack/Wait")
                if (
                        word_label.horizontal_alignment != HORIZONTAL_ALIGNMENT_CENTER
                        or wait_label.horizontal_alignment != HORIZONTAL_ALIGNMENT_CENTER
                ):
                        centered_pairs = false
        _ok(
                fa_waits.any(func(w: String) -> bool: return w.contains("دقیقه")),
                "the answer buttons name their waits in Persian words"
        )
        _ok(centered_pairs, "each grade's word and wait stand centred on one axis")
        var audio_meta := ""
        for found in view.find_children("*", "Button", true, false):
                # The engine sanitizes node names: "Audio:001003.mp3" is
                # born as "Audio_001003_mp3".
                if str(found.name).begins_with("Audio"):
                        audio_meta = str(found.get_meta("idle_text", ""))
                        break
        _is(audio_meta, "شنیدن", "the recitation's button says only what it does")
        i18n.set_lang("en")
        study._show_front()
        await create_timer(0.1).timeout

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
        if eyebrow != null:
                _is(
                        eyebrow.get_theme_font_size("normal_font_size"),
                        17,
                        "the eyebrow stands a breath larger above the answer"
                )
                _ok(
                        str(eyebrow.get_theme_font("normal_font").resource_path).ends_with(
                                "AmiriQuran-Regular.ttf"
                        ),
                        "the eyebrow wears the face the verses wear"
                )
        # The session's card takes its own measure, a touch wider than the
        # library's page: a verse and its translation breathe on one line.
        var card_panel: PanelContainer = study.get_node_or_null("Margin/Column/Surface/Fill/CardPanel")
        if card_panel != null:
                var expected := maxf(minf(study.size.x - 48.0, 800.0), 280.0)
                _is(
                        int(round(card_panel.custom_minimum_size.x)),
                        int(round(expected)),
                        "the session's card takes its own wider measure"
                )
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
                        "Persian",
                        "the translation's button names its language, and nothing more"
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
                                _is(
                                        front_field.get_text(),
                                        original.strip_edges(),
                                        "the editor opens with the card's own words"
                                )
                                # The file on disk ends with a newline; the field's
                                # words do not. A phantom blank line under every
                                # reference was the newline showing through.
                                _ok(
                                        not front_field.get_text().ends_with("\n")
                                                and not back_field.get_text().ends_with("\n"),
                                        "no phantom blank line rides in from the file's trailing newline"
                                )
                                # The question is a reference, and a reference is
                                # Arabic by construction: the field writes in the
                                # verses' own hand, the same face the card reads in.
                                _ok(
                                        front_field.face() == ThemeScript.editor_face_for("arabic"),
                                        "the question field writes in the verses' own hand"
                                )
                                _ok(
                                        back_field.face() == ThemeScript.editor_face(),
                                        "the answer field writes in the verses' own hand"
                                )
                                _ok(
                                        back_field.face().has_char(0x067E),
                                        "the answer field's hand still draws پ, by its book twin if it must"
                                )
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
                                front_field.set_text(original.strip_edges() + "\nedited on the spot")
                                (editor.get_node("Margin/Column/Footer/Actions/Save") as Button).pressed.emit()
                                await create_timer(0.4).timeout
                                _ok(study.get_node_or_null("Editor") == null, "saving closes the editor")
                                _is(
                                        FileAccess.get_file_as_string("user://decks/quran/001/front.md"),
                                        original.strip_edges() + "\nedited on the spot\n",
                                        "the edit lands in the card's own file"
                                )
                                _is(study._cards[0].front, original.strip_edges() + "\nedited on the spot", "the card in memory carries the edit")
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
        # A card's own name is the word a reader hunts for, so it stands one
        # breath larger than the captions beneath it.
        if card_title != null:
                _is(card_title.get_theme_font_size("font_size"), ThemeScript.fs(13), "a card title stands one breath larger than its captions")
        # The token field stands alone -- its lecture left with it -- but the
        # repo field kept its own words: the reader asked for them aligned
        # to the reading, not gone, and an English page stands them at the
        # left, as English reads (a RichTextLabel's LEFT is its visual left
        # under a plain LTR root).
        var token_hint: RichTextLabel = settings.get_node_or_null("Margin/Scroll/Wrap/Column/GitHub/Padding/Box/TokenHint")
        _ok(token_hint == null, "no hint line stands under the token field")
        var repo_hint: RichTextLabel = settings.get_node_or_null("Margin/Scroll/Wrap/Column/GitHub/Padding/Box/RepoHint")
        _ok(repo_hint != null and repo_hint.text.length() > 0, "the repo field keeps its own words under it")
        _ok(
                repo_hint != null and repo_hint.horizontal_alignment == HORIZONTAL_ALIGNMENT_LEFT,
                "the English repo hint stands at the left, as English reads"
        )
        var i18n := load("res://scripts/ui/i18n.gd")
        _ok(
                not i18n.STRINGS.has("From github.com/settings/tokens — needs the repo scope. Stays on this device."),
                "the token hint's words left the app's table with the line that said them"
        )
        _ok(
                i18n.STRINGS.has("Where your deck lives on GitHub — created on first sync if it does not exist."),
                "the repo hint's words stay in the app's table with the line that says them"
        )
        _ok(
                not i18n.STRINGS.has("In the browser, recitations stream from this site while you study."),
                "the browser's recitation note left the source card with the line that said it"
        )
        # The explainer under a choice that shows itself was saying what the
        # choice already says: the font's and the tongue's captions are gone,
        # and the source card's button went with the link that already opens.
        _ok(
                not i18n.STRINGS.has("The face the verses are read in, wherever scripture is shown. Carried with your deck."),
                "the font card's explainer left the app's table with the line that said it"
        )
        _ok(
                not i18n.STRINGS.has("Menus and messages only — the verses and their translations stay as they are. Carried with your deck."),
                "the tongue card's explainer left the app's table with the line that said it"
        )
        _ok(
                not i18n.STRINGS.has("Open quran.makarem.ir"),
                "the source card's open button left the app's table with the button that said it"
        )
        var open_coin: Control = settings.get_node_or_null("Margin/Scroll/Wrap/Column/DataSource/Padding/Box/Open")
        _ok(open_coin == null, "the source card carries its link and no button beside it")
        var source_en: RichTextLabel = settings.get_node_or_null("Margin/Scroll/Wrap/Column/DataSource/Padding/Box/What")
        _ok(
                source_en != null and source_en.horizontal_alignment == HORIZONTAL_ALIGNMENT_LEFT,
                "the English source line stands at the left, as English reads"
        )
        # The deck's card speaks in words, not paths: user://decks/quran is
        # the machine's own address for the deck, and no reader needs it.
        var folder_line: Control = settings.get_node_or_null(
                "Margin/Scroll/Wrap/Column/DeckInfo/Padding/Box/Folder"
        )
        _ok(folder_line == null, "the deck's card no longer shows its raw storage path")
        # The deck's name line and its storage note are gone entirely: the
        # card that holds the day's pace offers the pace, not a lecture on
        # folders -- the name is already on the home page it came from.
        var deck_line: RichTextLabel = settings.get_node_or_null(
                "Margin/Scroll/Wrap/Column/DeckInfo/Padding/Box/Name"
        )
        _ok(deck_line == null, "the deck's card no longer repeats its name and folder story")
        var deck_note: RichTextLabel = settings.get_node_or_null(
                "Margin/Scroll/Wrap/Column/DeckInfo/Padding/Box/Note"
        )
        _ok(deck_note == null, "the folder note is gone with it")
        var pace_title: Label = settings.get_node_or_null(
                "Margin/Scroll/Wrap/Column/DeckInfo/Padding/Box/CardTitle"
        )
        _ok(
                pace_title != null and pace_title.text.length() > 0,
                "the pace card carries its own running title"
        )
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
                        _is(main._settings.new_per_day, 3, "a press on more offers one more card a day")
                        _is(int(step_value.text), 3, "the chip follows the setting")
                var step_less: Button = settings.get_node_or_null(
                        "Margin/Scroll/Wrap/Column/DeckInfo/Padding/Box/NewPerDay/StepLess"
                )
                if step_less != null:
                        step_less.pressed.emit()
                        _is(main._settings.new_per_day, 2, "a press on less offers one fewer")
                # The choice is the deck's own to carry: the pace lands in the
                # progress file, where sync reads it to every other device.
                var paced: Variant = JSON.parse_string(
                        FileAccess.get_file_as_string("user://decks/quran/progress.json")
                )
                _ok(
                        typeof(paced) == TYPE_DICTIONARY
                                and int((paced as Dictionary).get("new_per_day", -1)) == 2,
                        "a chosen pace is stamped into the deck's own progress file"
                )
        # The deck as one file: the backup card stands in Settings, the two
        # doors out of it are wired, and the whole journey -- the real deck
        # packed, joined back, its picker pressed -- runs against the real
        # user deck, all inside the app's own storage (a test never writes
        # into a person's real Downloads folder).
        var backup_card: Control = settings.get_node_or_null("Margin/Scroll/Wrap/Column/Backup")
        _ok(backup_card != null, "the backup card stands beside the deck's own")
        var export_button: Button = settings.get_node_or_null(
                "Margin/Scroll/Wrap/Column/Backup/Padding/Box/Buttons/Export"
        )
        var import_button: Button = settings.get_node_or_null(
                "Margin/Scroll/Wrap/Column/Backup/Padding/Box/Buttons/Import"
        )
        _ok(export_button != null and export_button.text == "Export", "the way out is offered in words")
        _ok(import_button != null and import_button.text == "Import", "and the way back beside it")
        if export_button != null:
                var wired := false
                for link in export_button.pressed.get_connections():
                        if str(link["callable"]).contains("_on_export_pressed"):
                                wired = true
                _ok(wired, "the way out is wired to the packer")
        var roundtrip := "user://backups".path_join("boot-roundtrip.zip")
        DirAccess.make_dir_recursive_absolute("user://backups")
        var packed: Dictionary = DeckZipScript.export_deck("user://decks/quran", roundtrip)
        _ok(bool(packed.get("ok", false)), "the real deck packs into one file")
        _ok(
                int(packed.get("files", 0)) >= 390,
                "every card's words and media ride along (got %d)" % int(packed.get("files", 0))
        )
        var archive := ZIPReader.new()
        var opened := archive.open(roundtrip)
        _ok(opened == OK, "the file is a zip a reader can open")
        if opened == OK:
                _ok(archive.file_exists("deck.json"), "the deck's own word rides")
                _ok(archive.file_exists("progress.json"), "the learning rides")
                _ok(archive.file_exists("001/front.md"), "the cards ride")
                archive.close()
        var before_progress := FileAccess.get_file_as_bytes("user://decks/quran/progress.json")
        var joined: Dictionary = DeckZipScript.import_deck("user://decks/quran", roundtrip)
        _ok(bool(joined.get("ok", false)), "and joins back into the same deck")
        _is(int(joined.get("merged", 0)), 0, "a deck meeting its own backup moves no learning")
        _is(int(joined.get("added", 0)), 0, "and adds no files")
        _ok(
                before_progress == FileAccess.get_file_as_bytes("user://decks/quran/progress.json"),
                "an unmoved progress file is not even rewritten"
        )
        # The way back runs through the picker: a press on Import stands the
        # page of found backups over Settings, a press on a row joins it, and
        # the note under the buttons says what arrived -- nothing, here.
        if import_button != null:
                import_button.pressed.emit()
                await create_timer(0.3).timeout
                var picker: Control = settings.get_node_or_null("BackupPicker")
                _ok(picker != null, "the way in opens the page of found backups")
                if picker != null:
                        var row: Button = picker.get_node_or_null("Centre/Card/Pad/Box/Rows/Row0")
                        _ok(row != null, "the backup this test made is offered as a row")
                        if row != null:
                                row.pressed.emit()
                                await create_timer(0.4).timeout
                                var note: RichTextLabel = settings.get_node_or_null(
                                        "Margin/Scroll/Wrap/Column/Backup/Padding/Box/BackupNote"
                                )
                                _ok(
                                        note != null and note.text == "This deck already holds everything the backup has.",
                                        "the note says what arrived, in the reader's own words"
                                )
                                _is(main._deck.cards.size(), 151, "the deck re-reads whole after the join")
                        _ok(settings.get_node_or_null("BackupPicker") == null, "the page puts itself away")
                import_button.pressed.emit()
                await create_timer(0.3).timeout
                var picker_again: Control = settings.get_node_or_null("BackupPicker")
                if picker_again != null:
                        var cancel: Button = picker_again.get_node_or_null("Centre/Card/Pad/Box/Cancel")
                        _ok(cancel != null, "the page can be put away by hand too")
                        if cancel != null:
                                cancel.pressed.emit()
                                await create_timer(0.3).timeout
                                _ok(
                                        settings.get_node_or_null("BackupPicker") == null,
                                        "cancel puts the page away"
                                )
        DirAccess.remove_absolute(roundtrip)
        # The reading card: the verses' own face and the app's own tongue,
        # both the reader's to choose, both shown as what they are, and both
        # carried with the deck the way the pace is.
        var faces: HBoxContainer = settings.get_node_or_null(
                "Margin/Scroll/Wrap/Column/Reading/Padding/Box/AyahFaces"
        )
        _ok(
                faces != null and faces.get_child_count() == 3,
                "the reading card offers every face the verses can wear"
        )
        # The choice says itself: a face named beside its own basmala needs
        # no explainer under it, and neither does a tongue named in its own
        # script -- the reading card carries its choices and no captions.
        var reading_box: VBoxContainer = settings.get_node_or_null(
                "Margin/Scroll/Wrap/Column/Reading/Padding/Box"
        )
        if reading_box != null:
                var captions := 0
                for child in reading_box.get_children():
                        if child is RichTextLabel:
                                captions += 1
                _is(captions, 0, "the reading card shows its choices without explaining them")
        if faces != null and faces.get_child_count() == 3:
                var sample := (faces.get_child(2).get_node("Pad/Stack/Sample") as Label)
                _ok(
                        str(sample.get_theme_font("font").resource_path).ends_with(
                                "NotoNaskhArabic-Regular.ttf"
                        ),
                        "each face is judged by its own drawing of the basmala"
                )
                (faces.get_child(2) as Button).pressed.emit()
                _is(main._settings.ayah_font, "noto_naskh", "a chosen face is remembered")
                _is(ThemeScript.ayah_face_key(), "noto_naskh", "the theme wears the chosen face at once")
                var stamped: Variant = JSON.parse_string(
                        FileAccess.get_file_as_string("user://decks/quran/progress.json")
                )
                _ok(
                        typeof(stamped) == TYPE_DICTIONARY
                                and str((stamped as Dictionary).get("ayah_font", "")) == "noto_naskh",
                        "the chosen face is stamped into the deck's own progress file"
                )
                (faces.get_child(0) as Button).pressed.emit()
                _is(ThemeScript.ayah_face_key(), "amiri_quran", "the mushaf cut returns")
        var langs: HBoxContainer = settings.get_node_or_null(
                "Margin/Scroll/Wrap/Column/Reading/Padding/Box/AppLanguages"
        )
        _ok(
                langs != null and langs.get_child_count() == 3,
                "the reading card offers every tongue the app speaks"
        )
        if langs != null and langs.get_child_count() == 3:
                (langs.get_child(1) as Button).pressed.emit()
                await create_timer(0.3).timeout
                var said: Label = settings.get_node_or_null("Margin/Scroll/Wrap/Column/TopBar/Title")
                _ok(said != null and said.text == "تنظیمات", "the page is said again in the tongue chosen")
                _is(main._settings.ui_lang, "fa", "the tongue is remembered")
                var langs_again: HBoxContainer = settings.get_node_or_null(
                        "Margin/Scroll/Wrap/Column/Reading/Padding/Box/AppLanguages"
                )
                if langs_again != null and langs_again.get_child_count() == 3:
                        (langs_again.get_child(0) as Button).pressed.emit()
                        await create_timer(0.3).timeout
                        var said_again: Label = settings.get_node_or_null(
                                "Margin/Scroll/Wrap/Column/TopBar/Title"
                        )
                        _ok(
                                said_again != null and said_again.text == "Settings",
                                "the page returns to English when English is chosen"
                        )
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
        # The shelf says what a card means, not only what it says: every row
        # carries its verse's Persian as a second quiet line under the Arabic,
        # flush right the way the verse is read, its tail trimmed with an
        # ellipsis rather than cut mid-letter.
        var carrying := 0
        for child in column.get_children():
                if not child.name.begins_with("Entry"):
                        continue
                var translation: Label = child.get_node_or_null("Row/Pad/Line/Words/Translation")
                if translation == null:
                        continue
                if not translation.text.is_empty():
                        carrying += 1
                _ok(
                        translation.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT
                                and translation.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS,
                        "a row's Persian stands at the reading's edge, trimmed with an ellipsis"
                )
        _ok(carrying >= rows - 2, "the rows carry their Persian under the verse (got %d of %d)" % [carrying, rows])
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
                        27,
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
        # A pill sizes itself by its own words, so the words must carry their
        # own air: a pill whose text stands on the edge of its shape reads as
        # text escaping the button it belongs to. The margin belongs to the
        # stylebox, so the pill's own least width says it is there.
        if filters != null:
                for pill in filters.get_children():
                        var face := (pill as Button).get_theme_font("font")
                        var size := (pill as Button).get_theme_font_size("font_size")
                        var words := face.get_string_size(
                                (pill as Button).text, HORIZONTAL_ALIGNMENT_LEFT, -1, size
                        ).x if face != null else 0.0
                        _ok(
                                (pill as Button).get_combined_minimum_size().x >= words + 20.0,
                                "%s keeps air on both sides of its words" % (pill as Button).name
                        )
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


## The whole word, whatever it wears: a verse's marks reach past the box its
## font declares, and any control that clips at that box drew them nowhere --
## the damma a reader lost on أُنزِلَ was exactly that. And a page whose tongue
## reads from the right is laid out from the right, so nothing is asked to
## stand at an edge it does not read from.
func _check_marks_and_rtl(main: Node) -> void:
        var i18n := load("res://scripts/ui/i18n.gd")
        var word := "أُنزِلَ"

        # The measurement itself: honest about every face, exact at any size.
        _is(ThemeScript.ink_room("", ThemeScript.ayah_face_for("amiri"), 26), Vector2i.ZERO,
                "an empty line asks for no room")
        var amiri_room := ThemeScript.ink_room(word, ThemeScript.ayah_face_for("amiri"), 26)
        _ok(amiri_room.x >= 5, "Amiri's damma over أُنزِلَ stands past its font's box (got %d px over)" % amiri_room.x)
        var quran_room := ThemeScript.ink_room(word, ThemeScript.ayah_face_for("amiri_quran"), 40)
        _is(quran_room.x, 0, "the mushaf cut carries its marks inside its own box")
        var vazir_room := ThemeScript.ink_room(word, ThemeScript.vazir(15), 15)
        _ok(vazir_room.x >= 2, "Vazirmatn's own marks stand past its box at the editor's size")

        # A verse paragraph carries the room inside itself, so the ink is
        # drawn whole: the label's own stylebox margins cover what the words
        # ask for in the face they are worn in.
        var CardViewForRoom := load("res://scripts/ui/card_view.gd")
        var player := AudioStreamPlayer.new()
        main.add_child(player)
        var view = CardViewForRoom.new(player)
        main.add_child(view)
        ThemeScript.set_ayah_face("amiri")
        var verse := FileAccess.get_file_as_string("res://assets/decks/quran/010/back.md")
        view.show_text(verse, "res://assets/decks/quran/010")
        await create_timer(0.2).timeout
        var verse_label: RichTextLabel = null
        for child in view.get_node("Body").get_children():
                # An Arabic verse breathes inside its own Room wrapper.
                var paragraph := child as RichTextLabel
                if paragraph == null and child.get_child_count() > 0:
                        paragraph = child.get_child(0) as RichTextLabel
                if paragraph != null and paragraph.name == "Paragraph" and paragraph.text.contains("نزِلَ"):
                        verse_label = paragraph
                        break
        _ok(verse_label != null, "the verse paragraph is on the page")
        if verse_label != null:
                var box: StyleBox = verse_label.get_theme_stylebox("normal")
                var room_40 := ThemeScript.ink_room(word, ThemeScript.ayah_face_for("amiri"), 40)
                _ok(
                        box != null and box.content_margin_top >= room_40.x,
                        "the verse label carries the room its damma asks for"
                )
        view.queue_free()
        player.queue_free()
        ThemeScript.set_ayah_face("amiri_quran")

        # The library's preview gives the same room as height around a
        # centred line, so a clipped Label cannot cut what it truncates.
        ThemeScript.set_ayah_face("amiri")
        main._on_browse_pressed()
        await create_timer(0.4).timeout
        var browse: Control = main.get_node_or_null("Browse")
        if browse != null:
                var found_room := false
                var column: VBoxContainer = browse.get_node_or_null("Margin/Column/Scroll/Wrap/Column")
                if column != null:
                        for entry in column.get_children():
                                var preview: Label = entry.get_node_or_null("Row/Pad/Line/Words/Preview")
                                if preview != null and preview.text.contains("نزِلَ"):
                                        var face: Font = ThemeScript.ayah_face_for("amiri")
                                        found_room = preview.get_combined_minimum_size().y > face.get_height(27)
                                        break
                _ok(found_room, "the shelf's preview stands taller than its font's own box for a tall stack")
                browse.closed.emit()
                await create_timer(0.2).timeout
        ThemeScript.set_ayah_face("amiri_quran")

        # The editor's mirror gives the room back out of its separation, so
        # the lines stay on the engine's own pitch however tall the words.
        var RtlFieldForPitch := load("res://scripts/ui/rtl_field.gd")
        var field = RtlFieldForPitch.new()
        field.set_anchors_preset(Control.PRESET_FULL_RECT)
        main.add_child(field)
        field.set_text("بِمَا أُنزِلَ إِلَيْكَ\nو آنچه بر تو نازل شده")
        await create_timer(0.3).timeout
        _ok(field._room > 0, "the mirror's lines ask for the room their marks need")
        var mirror: VBoxContainer = field.get_node_or_null("Lines")
        if mirror != null and mirror.get_child_count() >= 2:
                var first: Control = mirror.get_child(0)
                var second: Control = mirror.get_child(1)
                var pitch := second.position.y - first.position.y
                _is(roundf(pitch), roundf(field._editor.get_line_height()),
                        "the mirror's pitch stays the engine's own, room or no room")

        # The hand on the glass: the engine lays its lines flush left while
        # the mirror shows them flush right, so a raw click on the ink a
        # reader sees used to land at the line's very beginning -- every
        # time, wherever the finger pressed. The field answers the press
        # itself, sliding it back onto the engine's own words.
        var verse_line: String = field._editor.get_line(0)
        var verse_width: float = field._editor.get_line_width(0, 0)
        var verse_slide: float = maxf(field._editor.size.x - verse_width, 0.0)
        var verse_y: float = field._editor.get_rect_at_line_column(0, 0).position.y + field._editor.get_rect_at_line_column(0, 0).size.y * 0.5
        var press := func(where: Vector2) -> void:
                var event := InputEventMouseButton.new()
                event.button_index = MOUSE_BUTTON_LEFT
                event.pressed = true
                event.position = where
                field._on_editor_input(event)
        var release := func() -> void:
                var event := InputEventMouseButton.new()
                event.button_index = MOUSE_BUTTON_LEFT
                event.pressed = false
                event.position = Vector2(10, 10)
                field._on_editor_input(event)
        press.call(Vector2(field._editor.size.x - 1.0, verse_y))
        _is(field._editor.get_caret_column(), 0,
                "a press at the ink's right edge places the caret at the reading's start, not the press's habit")
        press.call(Vector2(verse_slide + 1.0, verse_y))
        _ok(field._editor.get_caret_column() >= verse_line.length() - 2,
                "a press at the ink's left edge places the caret at the line's far end")
        press.call(Vector2(verse_slide + verse_width * 0.5, verse_y))
        _ok(
                field._editor.get_caret_column() > 0 and field._editor.get_caret_column() < verse_line.length(),
                "a press inside the ink lands inside the line"
        )
        press.call(Vector2(field._editor.size.x - 1.0, verse_y + field._editor.get_line_height()))
        _is(field._editor.get_caret_line(), 1, "a press on the second line reaches the second line")
        # The second press takes the word under the finger, the third the line.
        release.call()
        press.call(Vector2(verse_slide + verse_width * 0.2, verse_y))
        release.call()
        await create_timer(0.02).timeout
        press.call(Vector2(verse_slide + verse_width * 0.2, verse_y))
        _ok(
                field._editor.has_selection() and field._editor.get_selected_text().length() > 0
                        and not field._editor.get_selected_text().contains(" "),
                "a second press takes the word under the finger, whole"
        )
        release.call()
        # The third press needs its own rhythm: the counter counts from the
        # last press, so a breath longer than a double press starts it over.
        await create_timer(0.6).timeout
        press.call(Vector2(verse_slide + verse_width * 0.2, verse_y))
        release.call()
        await create_timer(0.02).timeout
        press.call(Vector2(verse_slide + verse_width * 0.2, verse_y))
        release.call()
        await create_timer(0.02).timeout
        press.call(Vector2(verse_slide + verse_width * 0.2, verse_y))
        _is(field._editor.get_selected_text().length(), verse_line.length(),
                "a third press takes the whole line")
        release.call()
        # A press held and moving chooses, from where it began to where it is.
        press.call(Vector2(field._editor.size.x - 2.0, verse_y))
        var drag := InputEventMouseMotion.new()
        drag.position = Vector2(verse_slide + 4.0, verse_y)
        drag.button_mask = MOUSE_BUTTON_MASK_LEFT
        field._on_editor_input(drag)
        _ok(
                field._editor.has_selection() and field._editor.get_selected_text().length() >= verse_line.length() - 2,
                "a held press chooses across the line, from its beginning to its end"
        )
        release.call()
        field.queue_free()

        # A line that wraps is the case the slide was built for and the case
        # that broke it: the column a press at the row's far end returns is
        # the first column of the NEXT row, so every wrapped row but the last
        # was slid by its neighbour's width and the caret landed a handful of
        # words behind the finger -- the reader's "waaay back" on exactly
        # this sentence. The row is found by its own place on the page now,
        # so a press on any wrapped row lands inside that row.
        var wrap_field = RtlFieldForPitch.new()
        # The field is given a phone's own width, not the window's: the
        # reader's sentence wraps on the phone, and a field stretched across
        # a 1152px window would carry it on one row and prove nothing.
        wrap_field.position = Vector2(40, 60)
        wrap_field.size = Vector2(360, 260)
        main.add_child(wrap_field)
        wrap_field.set_face(ThemeScript.editor_face())
        wrap_field.set_text(
                "(همان) کسانى که به غیب [= حقایقى که از حس پوشیده و پنهان است] ایمان مى آورند و نماز را برپا مى دارند و از نعمتهایى که به آنان روزى داده ایم انفاق مى کنند"
        )
        await create_timer(0.4).timeout
        var wrap_editor: TextEdit = wrap_field._editor
        var wrap_parts := wrap_editor.get_line_wrapped_text(0)
        _ok(
                wrap_parts.size() >= 2,
                "the reader's own sentence wraps in the field, as it did on the phone"
        )
        if wrap_parts.size() >= 2:
                var wrap_press := func(where: Vector2) -> void:
                        var down := InputEventMouseButton.new()
                        down.button_index = MOUSE_BUTTON_LEFT
                        down.pressed = true
                        down.position = where
                        wrap_field._on_editor_input(down)
                        var up := InputEventMouseButton.new()
                        up.button_index = MOUSE_BUTTON_LEFT
                        up.pressed = false
                        up.position = where
                        wrap_field._on_editor_input(up)
                var wrap_tops: Array[float] = []
                var wrap_col := 0
                for w in wrap_parts.size():
                        wrap_tops.append(wrap_editor.get_rect_at_line_column(0, wrap_col).position.y)
                        wrap_col += wrap_parts[w].length()
                for w in wrap_parts.size() - 1:
                        var ink_w: float = wrap_editor.get_line_width(0, w)
                        var slide_w: float = maxf(wrap_editor.size.x - ink_w, 0.0)
                        var row_y: float = wrap_tops[w] + 20.0
                        # The row's own first column: everything this row holds.
                        var row_start := 0
                        for i in w:
                                row_start += wrap_parts[i].length()
                        var row_end: int = row_start + wrap_parts[w].length()
                        # The column a press at this x means: the one whose own
                        # caret rect stands nearest the pressed place, slid
                        # onto the engine's flush-left ink. The old bug slid
                        # every row by its neighbour's width, which stands
                        # out here as a handful of words of miss.
                        var nearest := func(press_x: float) -> int:
                                var ex: float = press_x - slide_w
                                var best := row_start
                                var best_d := 1.0e9
                                for col in range(row_start, row_end + 1):
                                        var r: Rect2 = wrap_editor.get_rect_at_line_column(0, col)
                                        var d: float = absf(r.position.x - ex)
                                        if d < best_d:
                                                best_d = d
                                                best = col
                                return best
                        # A press at the row's middle: the caret stands within
                        # a breath of the word the finger meant, not a
                        # handful of words away.
                        var mid_x: float = slide_w + ink_w * 0.5
                        wrap_press.call(Vector2(mid_x, row_y))
                        _ok(
                                absi(wrap_editor.get_caret_column() - nearest.call(mid_x)) <= 2,
                                "a press on wrapped row %d lands on the word the finger meant" % w
                        )
                        # A press at the row's reading start (the right edge):
                        # the caret stands at the row's first word, not the
                        # next row's.
                        wrap_press.call(Vector2(wrap_editor.size.x - 1.0, row_y))
                        _ok(
                                wrap_editor.get_caret_column() <= row_start + 1,
                                "a press at row %d's reading start takes that row's first word" % w
                        )
        wrap_field.queue_free()

        # The quiet promise says itself once; the line beneath it that
        # explained it again is gone.
        i18n.set_lang("en")
        _ok(not i18n.is_rtl(), "English reads from the left")
        i18n.set_lang("fa")
        _ok(i18n.is_rtl(), "Persian reads from the right")
        i18n.set_lang("ar")
        _ok(i18n.is_rtl(), "Arabic reads from the right")
        # A page said in Persian is laid out from the right: the root turns,
        # the titles and labels stand at the reading's edge, and the way back
        # points the way it goes. Said again in English, everything returns.
        # For Labels the alignment is LEFT on purpose in both tongues: under
        # an RTL layout the engine reads a Label's LEFT as the reading's
        # start (the right edge), so a RIGHT would stand a Persian title at
        # the LEFT margin -- the corner it was reported stuck in. A
        # RichTextLabel answers the other way -- its LEFT stays the visual
        # left edge whatever the layout reads, measured -- so its explanation
        # lines must be told RIGHT in so many words or they stand at the
        # wrong edge, the corner the reader next reported them stuck in.
        main._apply_language("fa")
        main._on_settings_pressed()
        await create_timer(0.5).timeout
        var settings_fa: Control = main.get_node_or_null("Settings")
        if settings_fa != null:
                _ok(settings_fa.layout_direction == Control.LAYOUT_DIRECTION_RTL,
                        "a Persian settings page is laid out from the right")
                var title_fa: Label = settings_fa.get_node_or_null("Margin/Scroll/Wrap/Column/GitHub/Padding/Box/CardTitle")
                _ok(title_fa != null and title_fa.horizontal_alignment == HORIZONTAL_ALIGNMENT_LEFT,
                        "a Persian card title stands at the right edge (LEFT is the reading's start under RTL)")
                var pace_label_fa: Label = settings_fa.get_node_or_null("Margin/Scroll/Wrap/Column/DeckInfo/Padding/Box/CardTitle")
                _ok(pace_label_fa != null and pace_label_fa.horizontal_alignment == HORIZONTAL_ALIGNMENT_LEFT,
                        "the Persian pace title stands at the right edge")
                if title_fa != null:
                        _is(title_fa.get_theme_font_size("font_size"), ThemeScript.fs(13),
                                "a Persian card title stands one breath larger too")
                var repo_field: LineEdit = settings_fa.get_node_or_null("Margin/Scroll/Wrap/Column/GitHub/Padding/Box/Repo")
                _ok(repo_field != null and repo_field.alignment == HORIZONTAL_ALIGNMENT_LEFT,
                        "a Persian page's field meets its reader at the reading's start")
                var repo_hint_fa: RichTextLabel = settings_fa.get_node_or_null("Margin/Scroll/Wrap/Column/GitHub/Padding/Box/RepoHint")
                _ok(
                        repo_hint_fa != null and repo_hint_fa.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT,
                        "the Persian repo hint stands at the reading's edge, not the visual left"
                )
                var state_fa: RichTextLabel = settings_fa.get_node_or_null("Margin/Scroll/Wrap/Column/GitHub/Padding/Box/State")
                _ok(
                        state_fa != null and state_fa.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT,
                        "the Persian account line (وصل شده به …) stands at the reading's edge"
                )
                _ok(settings_fa.get_node_or_null("Margin/Scroll/Wrap/Column/GitHub/Padding/Box/AutoRow/AutoPad/AutoLine/Words/Sub") == null,
                        "the quiet promise carries no explainer beneath it")
                var source_fa: RichTextLabel = settings_fa.get_node_or_null("Margin/Scroll/Wrap/Column/DataSource/Padding/Box/What")
                _ok(source_fa != null and source_fa.text.contains("می‌آیند") and not source_fa.text.contains("بی‌کم‌وکاست"),
                        "the Persian source line says its say and stops")
                _ok(source_fa != null and source_fa.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT,
                        "the Persian source line stands at the right edge (a RichTextLabel's LEFT stays the visual left)")
                var backup_caption_fa: RichTextLabel = settings_fa.get_node_or_null("Margin/Scroll/Wrap/Column/Backup/Padding/Box/Caption")
                _ok(backup_caption_fa != null and backup_caption_fa.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT,
                        "the Persian backup card's own words stand at the right edge")
                var backup_note_fa: RichTextLabel = settings_fa.get_node_or_null("Margin/Scroll/Wrap/Column/Backup/Padding/Box/BackupNote")
                _ok(backup_note_fa != null and backup_note_fa.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER,
                        "the backup note still says itself from the middle, both tongues")
                var back_fa: Button = settings_fa.get_node_or_null("Margin/Scroll/Wrap/Column/TopBar/Back")
                _ok(back_fa != null and back_fa.get_global_rect().position.x > settings_fa.get_global_rect().size.x / 2.0,
                        "the way back stands at the reading's start, the right")
                settings_fa.closed.emit()
                await create_timer(0.3).timeout
        # The library said in Persian asks its questions from the right: the
        # entry line's placeholder stands where the reading begins, and the
        # pills run همه first from the right hand, the way the questions
        # occur to a right-reading reader -- not washed up against the left
        # margin the way a left-reading page would put them.
        main._on_browse_pressed()
        await create_timer(0.6).timeout
        var browse_fa: Control = main.get_node_or_null("Browse")
        if browse_fa != null:
                var search_fa: LineEdit = browse_fa.get_node_or_null("Margin/Column/Search")
                _ok(
                        search_fa != null
                                and search_fa.text_direction == Control.TEXT_DIRECTION_RTL
                                and search_fa.alignment == HORIZONTAL_ALIGNMENT_RIGHT,
                        "the Persian entry line meets its reader at the reading's start"
                )
                var filters_fa: HFlowContainer = browse_fa.get_node_or_null("Margin/Column/Filters")
                if filters_fa != null and filters_fa.get_child_count() == 4:
                        _ok(
                                filters_fa.layout_direction == Control.LAYOUT_DIRECTION_RTL,
                                "the Persian pills are asked in the reading's own order"
                        )
                        var first_pill: Control = filters_fa.get_child(0)
                        var last_pill: Control = filters_fa.get_child(3)
                        _ok(
                                first_pill.get_global_rect().position.x
                                        > last_pill.get_global_rect().position.x,
                                "همه stands at the right hand and در مرور at the left"
                        )
                browse_fa.closed.emit()
                await create_timer(0.3).timeout
        # The editor said in Persian: the boxes are named at the right edge,
        # and both fields write in the verses' own hand -- the ayeh is never
        # set in the Persian face again.
        main._start_session()
        await create_timer(0.6).timeout
        var study_fa: Control = main.get_node_or_null("Study")
        if study_fa != null:
                study_fa._open_editor()
                await create_timer(0.5).timeout
                var editor_fa: Control = study_fa.get_node_or_null("Editor")
                _ok(editor_fa != null, "the pencil opens the card's own page in Persian too")
                if editor_fa != null:
                        var asked: Label = editor_fa.get_node_or_null("Margin/Column/Scroll/Wrap/Content/Write/QuestionCaption")
                        var answered: Label = editor_fa.get_node_or_null("Margin/Column/Scroll/Wrap/Content/Write/AnswerCaption")
                        _ok(
                                asked != null and asked.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT
                                        and answered != null and answered.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT,
                                "the Persian editor names its boxes at the right edge"
                        )
                        var front_fa: Control = editor_fa.get_node_or_null("Margin/Column/Scroll/Wrap/Content/Write/Front")
                        var back_fa_field: Control = editor_fa.get_node_or_null("Margin/Column/Scroll/Wrap/Content/Write/Back")
                        _ok(
                                front_fa != null and front_fa.face() == ThemeScript.editor_face_for("arabic")
                                        and back_fa_field != null and back_fa_field.face() == ThemeScript.editor_face(),
                                "the Persian editor writes scripture in the verses' own hand"
                        )
                if editor_fa != null:
                        editor_fa.queue_free()
                        await create_timer(0.2).timeout
                study_fa.closed.emit()
                await create_timer(0.5).timeout
        # The engine's own tooltips arrive in the app's own hand: the window's
        # theme carries a Vazirmatn TooltipLabel, so a Persian tooltip is
        # never a row of empty boxes in no language at all.
        var tooltip_font: Font = main.get_window().theme.get_font("font", "TooltipLabel")
        _ok(
                tooltip_font != null and str(tooltip_font.resource_path).ends_with("Vazirmatn-Regular.ttf"),
                "tooltips speak in a face that carries the reader's letters"
        )
        _is(i18n.t("Browse the cards"), "همهٔ کارت‌ها", "the library's door says all the cards")
        main._apply_language("en")
        main._on_settings_pressed()
        await create_timer(0.5).timeout
        var settings_en: Control = main.get_node_or_null("Settings")
        if settings_en != null:
                _ok(settings_en.layout_direction != Control.LAYOUT_DIRECTION_RTL,
                        "the English page returns to the left-reading layout")
                var title_en: Label = settings_en.get_node_or_null("Margin/Scroll/Wrap/Column/GitHub/Padding/Box/CardTitle")
                _ok(title_en != null and title_en.horizontal_alignment == HORIZONTAL_ALIGNMENT_LEFT,
                        "an English card title stands at the left edge")
                settings_en.closed.emit()
                await create_timer(0.3).timeout

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
