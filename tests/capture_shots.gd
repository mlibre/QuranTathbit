extends SceneTree

## Visual QA: drive the real app through its first session on a fresh install
## and save a PNG at each step, so tools/shot_qa.py can read what a person
## would see. Run it on a display -- Xvfb is enough; headless mode cannot
## render, so it cannot carry this one.
##
##     godot --path . --script tests/capture_shots.gd -- /tmp/shots
##     python3 tools/shot_qa.py /tmp/shots
##
## The out directory defaults to /tmp/shots; name another after -- to put the
## PNGs somewhere else. The install is wiped first, so the shots are always of
## the same first run.

const MainScript := preload("res://scripts/main.gd")
const DeckZipScript := preload("res://scripts/data/deck_zip.gd")

const SHOTS := 32

var _out := "/tmp/shots"
var _saved := 0

func _init() -> void:
        var args := OS.get_cmdline_user_args()
        if args.size() > 0:
                _out = args[0]
        DirAccess.make_dir_recursive_absolute(_out)
        _fresh_install()

        var main = (load("res://scripts/main.gd") as GDScript).new()
        # The scene file gives the root its full-rect anchors; match it here,
        # or every screen lays out at zero size and the shots lie.
        main.set_anchors_preset(Control.PRESET_FULL_RECT)
        root.add_child(main)
        await main.ready
        await create_timer(0.8).timeout

        # The app's very first question: which tongue its own words speak.
        # A frame of the question, then the answer this film reads in.
        await _shot("language")
        var picker: Control = main.get_node_or_null("LanguagePicker")
        if picker != null:
                (picker.get_node("Centre/Card/Pad/Box/Languages/Langen") as Button).pressed.emit()
                await create_timer(0.6).timeout

        await _shot("home")
        main._start_session()
        await create_timer(0.8).timeout
        await _shot("study_front")
        var study: Control = main.get_node("Study")
        study._reveal()
        await create_timer(0.9).timeout
        await _shot("study_back")
        study._answer("good")
        await create_timer(0.7).timeout
        await _shot("study_next")
        study._answer("easy")
        await create_timer(0.7).timeout
        await _shot("study_two")
        # The recitation's own control, open under its coin: the popover is
        # part of the page a person sees, so the film keeps a frame of it --
        # said at a middling loudness, so the frame shows the ribbon partway
        # down the rule and the fill rising from the foot to meet it, not
        # only a full page.
        study._rig.apply(0.6)
        study._rig.toggle()
        await create_timer(0.5).timeout
        await _shot("volume")
        study._rig.toggle()
        await create_timer(0.3).timeout
        # The verses' own hand, asked for where they are read: the alif coin
        # opens the faces, each sampled in the hand it offers.
        study._toggle_font_popup()
        await create_timer(0.5).timeout
        await _shot("font")
        study._toggle_font_popup()
        await create_timer(0.3).timeout
        # The pencil: a card noticed mid-study is fixed mid-study, on the
        # card's own page over the session.
        study._open_editor()
        await create_timer(0.8).timeout
        await _shot("editor")
        if study.get_node_or_null("Editor") != null:
                (study.get_node("Editor") as Control).queue_free()
                await create_timer(0.3).timeout
        study.closed.emit()
        await create_timer(0.7).timeout
        main._on_settings_pressed()
        await create_timer(0.8).timeout
        await _shot("settings")
        var settings_screen: Control = main.get_node("Settings")
        var scroll: ScrollContainer = settings_screen.get_node("Margin/Scroll")
        # The deck as one file: the backup card, and over it the page of
        # found backups -- offered with a real row, made by a real export
        # into the app's own corner (the capture machine names no Downloads
        # folder, so the app's corner is where backups land here).
        var backup: Control = settings_screen.get_node_or_null("Margin/Scroll/Wrap/Column/Backup")
        if backup != null:
                DirAccess.make_dir_recursive_absolute("user://backups")
                var packed: Dictionary = DeckZipScript.export_deck(
                        "user://decks/quran", "user://backups".path_join("capture-deck.zip")
                )
                if bool(packed.get("ok", false)):
                        scroll.scroll_vertical = int(
                                maxf(0.0, backup.get_global_rect().position.y - scroll.get_global_rect().position.y)
                        )
                        await create_timer(0.5).timeout
                        await _shot("backup")
                        var import_button: Button = settings_screen.get_node_or_null(
                                "Margin/Scroll/Wrap/Column/Backup/Padding/Box/Buttons/Import"
                        )
                        if import_button != null:
                                import_button.pressed.emit()
                                await create_timer(0.6).timeout
                                await _shot("backup_picker")
                                var backup_page: Control = settings_screen.get_node_or_null("BackupPicker")
                                if backup_page != null:
                                        var cancel: Button = backup_page.get_node_or_null("Centre/Card/Pad/Box/Cancel")
                                        if cancel != null:
                                                cancel.pressed.emit()
                                await create_timer(0.4).timeout
                        DirAccess.remove_absolute("user://backups".path_join("capture-deck.zip"))
        # The reading card: the verses' face and the app's tongue, offered as
        # what they are -- a basmala drawn in each hand, a language named in
        # its own script.
        var reading: Control = settings_screen.get_node_or_null("Margin/Scroll/Wrap/Column/Reading")
        if reading != null:
                scroll.scroll_vertical = int(
                        maxf(0.0, reading.get_global_rect().position.y - scroll.get_global_rect().position.y)
                )
                await create_timer(0.5).timeout
                await _shot("reading")
        # The display card: the two sizes a reader sizes the app by, as
        # steppers of the same shape the pace already speaks, their values
        # said in percentages in the reader's own digits.
        var display: Control = settings_screen.get_node_or_null("Margin/Scroll/Wrap/Column/Display")
        if display != null:
                scroll.scroll_vertical = int(
                        maxf(0.0, display.get_global_rect().position.y - scroll.get_global_rect().position.y)
                )
                await create_timer(0.5).timeout
                await _shot("display_card")
                # The whole interface, one step larger; then the words, a step
                # larger still inside it -- the page rebuilt in its own new
                # size, the window re-flowed under the new factor.
                var ui_more: Button = settings_screen.get_node_or_null(
                        "Margin/Scroll/Wrap/Column/Display/Padding/Box/UiScale/Stepper/StepMore"
                )
                if ui_more != null:
                        ui_more.pressed.emit()
                        await create_timer(0.4).timeout
                var text_more: Button = settings_screen.get_node_or_null(
                        "Margin/Scroll/Wrap/Column/Display/Padding/Box/TextScale/Stepper/StepMore"
                )
                if text_more != null:
                        text_more.pressed.emit()
                        await create_timer(0.6).timeout
                        await _shot("display_stepped")
        main.get_node("Settings").closed.emit()
        await create_timer(0.6).timeout
        # Home again, wearing the two sizes: every card and margin a step
        # larger, the words a step larger still inside them.
        await _shot("home_scaled")
        # And back to the size the app has always been, before the rest of
        # the film reads on at it: the settings page has already gone, so
        # the choice is said the way its handler says it, without the page.
        main._settings.ui_scale = 1.0
        main._settings.font_scale = 1.0
        main._settings.save()
        (load("res://scripts/ui/theme.gd") as GDScript).set_ui_scale(1.0)
        (load("res://scripts/ui/theme.gd") as GDScript).set_font_scale(1.0)
        await create_timer(0.3).timeout
        # The standing home was built at the larger size, so it is said again
        # the way every page is: rebuilt in the size now worn.
        main._apply_language("en")
        await create_timer(0.8).timeout
        await _shot("home_again")
        # The library: the deck as a book, a row opening its own page.
        main._on_browse_pressed()
        await create_timer(1.4).timeout
        await _shot("browse")
        var browse: Control = main.get_node("Browse")
        var list: VBoxContainer = browse.get_node("Margin/Column/Scroll/Wrap/Column")
        var first_entry: VBoxContainer = null
        for child in list.get_children():
                if child.name.begins_with("Entry"):
                        first_entry = child
                        break
        if first_entry != null:
                (first_entry.get_node("Row") as Button).pressed.emit()
                await create_timer(0.7).timeout
                await _shot("browse_open")
        # The shelf answers its search field: an address finds its card.
        var search: LineEdit = browse.get_node_or_null("Margin/Column/Search")
        if search != null:
                search.text = "2:93"
                browse._on_search_changed("2:93")
                await create_timer(0.8).timeout
                await _shot("browse_search")
                search.text = ""
                browse._on_search_changed("")
                await create_timer(0.4).timeout
        # The deck's own extension: Al-Baqarah 94-145, text-only. A card
        # without recitation audio offers no Listen buttons, carries the
        # mushaf's own section mark where the source has it, and still names
        # its source at the page's foot -- this frame keeps one of them open
        # on the shelf (2:106, the hizb mark and all).
        search.text = "2:106"
        browse._on_search_changed("2:106")
        await create_timer(0.8).timeout
        var extension_entry: VBoxContainer = null
        for child in list.get_children():
                if child.name.begins_with("Entry"):
                        extension_entry = child
                        break
        if extension_entry != null:
                (extension_entry.get_node("Row") as Button).pressed.emit()
                await create_timer(0.7).timeout
                await _shot("extension_card")
        search.text = ""
        browse._on_search_changed("")
        await create_timer(0.4).timeout
        browse.closed.emit()
        await create_timer(0.6).timeout
        await _shot("home_third")
        # The app said again in the reader's own tongue: the same home page,
        # the same verses, only the chrome translated -- and its numbers in
        # the tongue's own script, a session's count included.
        main._apply_language("fa")
        await create_timer(0.8).timeout
        await _shot("home_fa")
        # The corner's own words, raised by the engine on a hover: a tooltip
        # that arrives in the engine's default face arrives in no language at
        # all -- this frame keeps the one the app now raises, in Vazirmatn.
        var corner_fa: Button = main.get_node_or_null("Home/SettingsCorner")
        if corner_fa != null:
                Input.warp_mouse(corner_fa.get_global_rect().get_center())
                await create_timer(1.4).timeout
                await _shot("tooltip_fa")
                Input.warp_mouse(Vector2(10, 700))
                await create_timer(0.3).timeout
        main._start_session()
        await create_timer(0.8).timeout
        await _shot("study_fa")
        var study_fa: Control = main.get_node_or_null("Study")
        if study_fa != null:
                study_fa._reveal()
                await create_timer(0.9).timeout
                await _shot("study_fa_back")
                # The recitation's own page, said in Persian: the quiet name
                # and the large figure centered, the ribbon hanging from the
                # rod and the fill rising from the foot -- said at a middling
                # loudness, so the frame shows the fill's own direction.
                study_fa._rig.apply(0.6)
                study_fa._rig.toggle()
                await create_timer(0.5).timeout
                await _shot("volume_fa")
                study_fa._rig.toggle()
                await create_timer(0.3).timeout
                # The card's own page, said in Persian: the boxes named at the
                # right edge, the ayeh set in the verses' own hand, and no
                # phantom blank line under the reference.
                study_fa._open_editor()
                await create_timer(0.8).timeout
                await _shot("editor_fa")
                var editor_fa: Control = study_fa.get_node_or_null("Editor")
                if editor_fa != null:
                        editor_fa.queue_free()
                        await create_timer(0.3).timeout
                study_fa.closed.emit()
                await create_timer(0.7).timeout
        # The settings page said in Persian: laid out from the right, the
        # whole page -- titles, labels, fields, the way back -- reading the
        # way its words do.
        main._on_settings_pressed()
        await create_timer(0.8).timeout
        await _shot("settings_fa")
        var settings_fa: Control = main.get_node_or_null("Settings")
        if settings_fa != null:
                # The cards the reader named live below the fold: the backup's
                # own words and the source's line, both of which once stood at
                # the left edge of a right-reading page.
                var scroll_fa: ScrollContainer = settings_fa.get_node("Margin/Scroll")
                for card_name in ["Backup", "DataSource"]:
                        var card_fa: Control = settings_fa.get_node_or_null(
                                "Margin/Scroll/Wrap/Column/" + card_name
                        )
                        if card_fa != null:
                                scroll_fa.scroll_vertical = int(
                                        maxf(0.0, card_fa.get_global_rect().position.y - scroll_fa.get_global_rect().position.y)
                                )
                                await create_timer(0.5).timeout
                                await _shot("settings_fa_" + card_name.to_lower())
                settings_fa.closed.emit()
                await create_timer(0.6).timeout
        # The library in Persian: the shelf's pills and counts carry the
        # tongue's own digits too.
        main._on_browse_pressed()
        await create_timer(1.4).timeout
        await _shot("browse_fa")
        var browse_fa: Control = main.get_node_or_null("Browse")
        if browse_fa != null:
                browse_fa.closed.emit()
                await create_timer(0.6).timeout
        main._apply_language("en")
        await create_timer(0.5).timeout

        print("captures: %d of %d shot(s) in %s" % [_saved, SHOTS, _out])
        quit(0 if _saved >= SHOTS else 1)

func _shot(name: String) -> void:
        await process_frame
        await process_frame
        var image := root.get_viewport().get_texture().get_image()
        if image.save_png(_out.path_join(name + ".png")) == OK:
                _saved += 1
                print("shot: %s" % name)

func _fresh_install() -> void:
        _remove_tree("user://decks")
        _remove_tree("user://settings.json")
        _remove_tree("user://sync_manifest.json")

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
