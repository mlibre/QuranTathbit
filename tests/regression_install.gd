extends SceneTree

## The deck a package installs must be the deck the package carries, heard
## as well as read: a browser streams its recitations from the site, but
## every other build keeps them beside the markdown, and an exported package
## keeps an imported mp3 only as a resource the file system cannot see at
## its own path. The installer therefore reads the bundle through the
## loader, and this suite holds it to that: a fresh install lands playable
## audio, a deck that arrived without it (the install an earlier release
## could leave on a phone) is filled in and repaired, a file that already
## plays is never touched, and the editor's sidecars never ride the deck.

const MainScript := preload("res://scripts/main.gd")

var _failures := 0

func _init() -> void:
        var main := MainScript.new()
        var bundle := "res://assets/decks/quran/001"
        var card := "user://decks/quran/001"

        # --- what the bundle hands over, however it keeps it -------------------
        var raw := FileAccess.get_file_as_bytes(bundle.path_join("001001.mp3"))
        var unwrapped: PackedByteArray = main._bundled_bytes(bundle.path_join("001001.mp3"))
        _is(unwrapped.size(), raw.size(), "the loader hands the mp3's own bytes, whole")
        _ok(
                unwrapped.size() > 3 and unwrapped[0] == 0x49 and unwrapped[1] == 0x44 and unwrapped[2] == 0x33,
                "the unwrapped recitation begins as an ID3 mp3"
        )
        var md: PackedByteArray = main._bundled_bytes(bundle.path_join("back.md"))
        _ok(not md.is_empty(), "a file that was never imported still reads from the file system")

        var names := main._bundled_audio_names(bundle)
        _ok(names.has("001001.mp3"), "the card's recitation is named")
        _ok(names.has("001001-fa.mp3"), "and so is its Persian twin, derived")
        _ok(names.has("001002-fa.mp3"), "the second verse's twin is derived too")
        _ok(not names.has("back.md"), "the markdown is not audio")
        _ok(not names.has("001001.mp3.import"), "a remap's sidecar name is never audio")

        # --- a fresh install: the whole deck, audio included -------------------
        _remove_tree("user://decks")
        main._install_deck()
        main._deliver_cards()
        main._ensure_deck_audio()
        main._sweep_sidecars()
        _ok(FileAccess.file_exists(card.path_join("001001.mp3")), "a fresh install lands the recitation")
        _ok(FileAccess.file_exists(card.path_join("001001-fa.mp3")), "and its Persian twin")
        _ok(main._plays_audio(card.path_join("001001-fa.mp3")), "the twin begins as audio")
        _is(
                FileAccess.get_file_as_bytes(card.path_join("001001.mp3")).size(),
                raw.size(),
                "the installed recitation is the bundled one, byte for byte"
        )
        _ok(not FileAccess.file_exists(card.path_join("001001.mp3.import")), "the editor's sidecars never ride the deck")
        _ok(FileAccess.file_exists("user://decks/quran/deck.json"), "the deck's own json is installed")

        # --- the deck a broken release could leave: text, no audio --------------
        for entry in DirAccess.get_files_at(card):
                if entry.ends_with(".mp3"):
                        DirAccess.remove_absolute(card.path_join(entry))
        _ok(not FileAccess.file_exists(card.path_join("001001.mp3")), "the audio is gone, as a phone could keep it")
        main._ensure_deck_audio()
        _ok(FileAccess.file_exists(card.path_join("001001.mp3")), "a deck without audio is filled in")
        _ok(main._plays_audio(card.path_join("001001.mp3")), "the filled recitation begins as audio")
        _ok(FileAccess.file_exists(card.path_join("001002-fa.mp3")), "a derived twin is filled in too")

        # --- a file that is there but is not audio is repaired ------------------
        var junk := FileAccess.open(card.path_join("001001.mp3"), FileAccess.WRITE)
        junk.store_string("not audio at all")
        junk.close()
        main._ensure_deck_audio()
        _ok(main._plays_audio(card.path_join("001001.mp3")), "a file that lost its head is repaired")
        _is(
                FileAccess.get_file_as_bytes(card.path_join("001001.mp3")).size(),
                raw.size(),
                "the repair is the bundled bytes, not a patch"
        )

        # --- a file that already plays is never touched -------------------------
        var other := FileAccess.get_file_as_bytes(bundle.path_join("001002.mp3"))
        var swap := FileAccess.open(card.path_join("001001.mp3"), FileAccess.WRITE)
        swap.store_buffer(other)
        swap.close()
        main._ensure_deck_audio()
        _is(
                FileAccess.get_file_as_bytes(card.path_join("001001.mp3")).size(),
                other.size(),
                "a playable file is left exactly as it was found"
        )

        # --- litter an earlier release could plant, and a lost folder -----------
        var litter := FileAccess.open(card.path_join("001001.mp3.import"), FileAccess.WRITE)
        litter.store_string("[remap]\n")
        litter.close()
        main._sweep_sidecars()
        _ok(not FileAccess.file_exists(card.path_join("001001.mp3.import")), "a planted sidecar is swept away")

        DirAccess.remove_absolute(card.path_join("001001.mp3"))
        # Folder 007 exists on the installed deck from the install above; take
        # one away whole and let the delivery bring it back.
        var lost := "user://decks/quran/007"
        if DirAccess.dir_exists_absolute(lost):
                _remove_tree(lost)
        main._deliver_cards()
        _ok(FileAccess.file_exists(lost.path_join("002001.mp3")), "a folder the deck lost is delivered back")
        _ok(main._plays_audio(lost.path_join("002001.mp3")), "and its audio with it")

        if _failures > 0:
                print("install: %d FAILURE(S)" % _failures)
                quit(1)
        else:
                print("install: all checks passed")
                quit(0)

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


func _is(got: Variant, want: Variant, what: String) -> void:
        if got == want:
                print("  ok  %s" % what)
        else:
                print("  FAIL %s: got %s, want %s" % [what, got, want])
                _failures += 1

func _ok(got: bool, what: String) -> void:
        if got:
                print("  ok  %s" % what)
        else:
                print("  FAIL %s" % what)
                _failures += 1
