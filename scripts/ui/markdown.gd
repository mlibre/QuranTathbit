class_name TathbitMarkdown
extends RefCounted

## Just enough markdown for cards: paragraphs split on blank lines, **bold**,
## *italic*, [links](https://...), and ![media](file) for the audio and
## pictures sitting next to the card's text. Anything else is left alone --
## a card shows the words its author wrote, not a browser.
##
## Parses once into blocks so the view can dress each kind of content the way
## it deserves without re-reading the text.

class Block:
        var kind := "text"  # "text" or "media"
        var text := ""  # markdown, with ** and * intact
        var media := ""  # file name, for media blocks
        var link := ""  # URL, when the paragraph is a lone link

        func _init(p_kind: String) -> void:
                kind = p_kind


static func parse(source: String) -> Array:
        var blocks: Array = []
        for paragraph in _paragraphs(source):
                var block: Block = _parse_paragraph(paragraph)
                if block != null:
                        blocks.append(block)
        return blocks


static func _paragraphs(source: String) -> Array:
        var out: Array = []
        var current := PackedStringArray()
        for line in source.replace("\r\n", "\n").split("\n"):
                if line.strip_edges().is_empty():
                        if current.size() > 0:
                                out.append("\n".join(current))
                                current = PackedStringArray()
                else:
                        current.append(line.strip_edges())
        if current.size() > 0:
                out.append("\n".join(current))
        return out


static func _parse_paragraph(paragraph: String) -> Block:
        # A paragraph that is a single media reference: ![name](file) alone.
        var solo_media := RegEx.create_from_string("^!\\[(?P<label>[^\\]]*)\\]\\((?P<file>[^)]+)\\)$")
        var found := solo_media.search(paragraph.strip_edges())
        if found != null:
                var block := Block.new("media")
                block.media = found.get_string("file").strip_edges()
                return block
        var text := paragraph
        var link := ""
        var solo_link := RegEx.create_from_string("^\\[(?P<label>[^\\]]*)\\]\\((?P<url>[^)]+)\\)$")
        found = solo_link.search(paragraph.strip_edges())
        if found != null:
                link = found.get_string("url")
                text = "[%s](%s)" % [found.get_string("label"), link]
        var out := Block.new("text")
        out.text = text
        out.link = link
        return out


## Strip the markdown marks for plain-text uses (counts, previews, the
## citation a card's footer carries): images and links leave only their
## words behind, and the marks vanish -- what remains is what a reader
## reads, not what a parser saw.
static func plain(source: String) -> String:
        var text := source
        text = _replace_images(text)
        text = _replace_links(text)
        text = text.replace("**", "").replace("*", "")
        return text.strip_edges()


static func _replace_links(text: String) -> String:
        var re := RegEx.create_from_string("\\[([^\\]]+)\\]\\(([^)]+)\\)")
        return re.sub(text, "$1", true)


static func _replace_images(text: String) -> String:
        var re := RegEx.create_from_string("!\\[([^\\]]*)\\]\\(([^)]+)\\)")
        return re.sub(text, "$1", true)
