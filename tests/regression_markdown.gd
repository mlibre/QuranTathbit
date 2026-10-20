extends SceneTree
const MarkdownScript := preload("res://scripts/ui/markdown.gd")
const ThemeScript := preload("res://scripts/ui/theme.gd")

## The card renderer reads exactly what cards contain: paragraphs split on
## blank lines, a lone media reference, bold and italic, links, and the
## plain-text form used for previews. Anything the deck's author wrote must
## survive the round trip -- words unchanged, media found.

var _failures := 0

func _init() -> void:
        _test_paragraphs()
        _test_marks()
        _test_links_and_media()
        _test_script_detection()
        if _failures > 0:
                print("markdown: %d FAILURE(S)" % _failures)
                quit(1)
        else:
                print("markdown: all checks passed")
                quit(0)

func _ok(condition: bool, what: String) -> void:
        if not condition:
                _failures += 1
                print("  FAIL: %s" % what)

func _is(got: Variant, expected: Variant, what: String) -> void:
        if got != expected:
                _failures += 1
                print("  FAIL: %s — got %s, expected %s" % [what, str(got), str(expected)])

func _test_paragraphs() -> void:
        var blocks: Array = MarkdownScript.parse("one\n\ntwo\n\nthree")
        _is(blocks.size(), 3, "blank lines split paragraphs")
        _is(blocks[0].text, "one", "paragraph text is kept verbatim")
        _is(blocks[0].kind, "text", "a plain paragraph is text")

        var single: Array = MarkdownScript.parse("just one line")
        _is(single.size(), 1, "a single line is one paragraph")

        var spacing: Array = MarkdownScript.parse("  padded  \n\n  second  ")
        _is(spacing[0].text, "padded", "surrounding space is trimmed")

func _test_marks() -> void:
        var blocks: Array = MarkdownScript.parse("**bold** and *soft*")
        _is(blocks.size(), 1, "marks do not split paragraphs")
        var text: String = blocks[0].text
        _ok(text.contains("**bold**"), "bold marks survive parsing")
        _ok(text.contains("*soft*"), "italic marks survive parsing")
        _is(MarkdownScript.plain("**bold** and *soft*"), "bold and soft", "the plain form drops the marks")

        # The first line that says anything -- the reference a card asks with,
        # wherever a page names a card. One law for home, the shelf and the
        # editor, so a card is called the same thing everywhere.
        _is(MarkdownScript.first_plain_line("\n\n   \nسورة الفاتحة - ۱\nmore"), "سورة الفاتحة - ۱", "blank and empty lines are passed over")
        _is(MarkdownScript.first_plain_line("**Al-Fātiḥah** - 1"), "Al-Fātiḥah - 1", "marks are stripped, words kept")
        _is(MarkdownScript.first_plain_line(""), "", "a wordless text has no reference")
        _is(MarkdownScript.first_plain_line("a\r\nb"), "a", "a carriage return does not glue lines")

func _test_links_and_media() -> void:
        var blocks: Array = MarkdownScript.parse("![001001.mp3](001001.mp3)")
        _is(blocks.size(), 1, "a lone media reference is one block")
        _is(blocks[0].kind, "media", "a media reference is media")
        _is(blocks[0].media, "001001.mp3", "the media name is the file name")

        var mixed: Array = MarkdownScript.parse("verse\n\n![rec.mp3](rec.mp3)\n\ntranslation")
        _is(mixed.size(), 3, "media and text alternate")
        _is(mixed[1].kind, "media", "the middle block is the media")

        var linked: Array = MarkdownScript.parse("[quran.makarem.ir](https://quran.makarem.ir/#1:1)")
        _is(linked[0].link, "https://quran.makarem.ir/#1:1", "a lone link exposes its URL")
        # A card's footer shows the link's own words: the brackets and the
        # address are the parser's business, never the reader's.
        _is(
                MarkdownScript.plain(linked[0].text),
                "quran.makarem.ir",
                "the plain form of a link is its label, not its markdown"
        )

        var inline: Array = MarkdownScript.parse("see ![rec.mp3](rec.mp3) here")
        _is(inline[0].kind, "text", "media beside other words stays text")
        _ok(MarkdownScript.plain(inline[0].text).contains("rec.mp3") or MarkdownScript.plain(inline[0].text).contains("see"), "inline media keeps its surroundings")

func _test_script_detection() -> void:
        _is(ThemeScript.script_of("بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ"), "arabic", "Arabic script is detected")
        _is(ThemeScript.script_of("حمد و سپاس مخصوص خداوندى است که پروردگار جهانیان است"), "persian", "Persian script is detected")
        _is(ThemeScript.script_of("plain english words"), "plain", "Latin text is plain")
        _is(ThemeScript.script_of(""), "plain", "empty text is plain")
        _is(ThemeScript.script_of("123"), "plain", "digits alone are plain")
