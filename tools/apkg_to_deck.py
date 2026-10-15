#!/usr/bin/env python3
"""Convert an Anki .apkg deck into the folder-and-files deck this app reads.

The app never parses Anki databases: a deck is a folder of cards, a card is a
folder of markdown plus its media. This tool runs once (or whenever a deck is
refreshed) and writes that layout:

    <out>/
      deck.json                 {"format": 1, "name": ..., "cards": [...]}
      001/
        front.md
        back.md
        001001.mp3              media referenced from the markdown
      002/
        ...

Usage:
    python3 tools/apkg_to_deck.py DECK.apkg assets/decks/quran

Reads `collection.anki2` when it holds real data (legacy exports, schema < 18);
otherwise decompresses `collection.anki21b` (zstd), which is what modern Anki
ships. Anki's HTML fields are flattened to markdown so the app's renderer can
dress each kind of text the way it deserves. Media files are copied by name;
a missing reference aborts the run instead of silently shipping a broken card.
"""

from __future__ import annotations

import json
import re
import shutil
import sqlite3
import sys
import zipfile
from pathlib import Path

HTML_DIV = re.compile(r"<div[^>]*>(.*?)</div>", re.S)
ANY_TAG = re.compile(r"<[^>]+>")
ANCHOR = re.compile(r'<a[^>]+href="(?P<href>[^"]+)"[^>]*>(?P<label>.*?)</a>', re.S)
SOUND = re.compile(r"\[sound:(?P<name>.+?)\]")

ESCAPES = [
    ("&nbsp;", " "),
    ("&amp;", "&"),
    ("&lt;", "<"),
    ("&gt;", ">"),
    ("&quot;", '"'),
    ("&#39;", "'"),
]


def zstd_decompress(data: bytes) -> bytes:
    """Decompress zstd bytes using the python module or the zstd CLI.

    Modern packages compress their media too (the zstd magic 28 b5 2f fd
    leads every such stream), so every blob goes through here before it is
    written into the deck.
    """
    if data[:4] != b"\x28\xb5\x2f\xfd":
        return data
    try:
        import io

        import zstandard
    except ImportError:
        cli = shutil.which("zstd")
        if not cli:
            sys.exit(
                "error: this package needs zstd. Install it with\n"
                "  python3 -m pip install zstandard\nor the `zstd` command line tool."
            )
        import subprocess

        return subprocess.run(
            [cli, "-d", "-c"], input=data, capture_output=True, check=True
        ).stdout
    import io

    return zstandard.ZstdDecompressor().stream_reader(io.BytesIO(data)).read()


def load_collection(zf: zipfile.ZipFile, workdir: Path) -> Path:
    """Return a path to a usable collection.anki2, decompressing when needed."""
    if "collection.anki2" in zf.namelist():
        candidate = workdir / "collection.anki2"
        candidate.write_bytes(zf.read("collection.anki2"))
        con = sqlite3.connect(candidate)
        try:
            notes = con.execute("select count(*) from notes").fetchone()[0]
            tables = {
                name
                for (name,) in con.execute(
                    "select name from sqlite_master where type='table'"
                )
            }
        finally:
            con.close()
        # Modern packages stub the legacy file with a "please update" note.
        if notes > 0 and ("notetypes" in tables or "models" in tables):
            return candidate
    if "collection.anki21b" not in zf.namelist():
        sys.exit("error: package has no collection to read")
    path = workdir / "collection.anki2"
    path.write_bytes(zstd_decompress(zf.read("collection.anki21b")))
    return path


def read_media_names(zf: zipfile.ZipFile, workdir: Path) -> list[str]:
    """Media names in zip-index order ('0', '1', ... -> '001001.mp3')."""
    if "media" not in zf.namelist():
        return []
    raw = zf.read("media")
    if raw[:4] == b"\x28\xb5\x2f\xfd":  # zstd magic: schema-18 protobuf index
        raw = zstd_decompress(raw)
        names = [
            m.group(1).decode()
            for m in re.finditer(rb"\n([\x20-\x7e]{4,}\.\w{2,4})", raw)
        ]
        if names:
            return names
        sys.exit("error: could not read the package's media index")
    mapping = json.loads(raw)
    return [mapping[key] for key in sorted(mapping, key=int)]


def html_to_blocks(field_html: str) -> list[str]:
    """Flatten one Anki HTML field into a list of markdown paragraphs."""
    blocks: list[str] = []
    for div in HTML_DIV.findall(field_html):
        div = ANCHOR.sub(
            lambda m: f"[{ANY_TAG.sub('', m.group('label')).strip()}]({m.group('href')})", div
        )
        for old, new in ESCAPES:
            div = div.replace(old, new)
        text = ANY_TAG.sub("", div).strip()
        if text:
            blocks.append(text)
    return blocks


def convert(apkg: Path, out_dir: Path) -> None:
    workdir = out_dir.parent / ".apkg_work"
    shutil.rmtree(workdir, ignore_errors=True)
    workdir.mkdir(parents=True)
    try:
        zf = zipfile.ZipFile(apkg)
        collection = load_collection(zf, workdir)
        media_names = read_media_names(zf, workdir)

        blobs: dict[str, bytes] = {}
        for index, name in enumerate(media_names):
            try:
                blobs[name] = zstd_decompress(zf.read(str(index)))
            except KeyError:
                sys.exit(f"error: package media {index} ({name}) is missing")

        con = sqlite3.connect(collection)
        con.row_factory = sqlite3.Row
        try:
            tables = {
                name
                for (name,) in con.execute(
                    "select name from sqlite_master where type='table'"
                )
            }
            if "decks" in tables:
                row = con.execute("select name from decks limit 1").fetchone()
                name = row[0] if row else "Deck"
            else:
                decks = json.loads(con.execute("select decks from col").fetchone()[0])
                name = next(iter(decks.values()))["name"] if decks else "Deck"
            notes = con.execute("select flds from notes order by id").fetchall()
        finally:
            con.close()
        if not notes:
            sys.exit("error: package has no notes")

        copied: set[str] = set()
        cards: list[str] = []
        for number, note in enumerate(notes, start=1):
            fields = note["flds"].split("\x1f")
            front = html_to_blocks(fields[0])
            if not front:
                sys.exit(f"error: note {number} has an empty front field")

            card_dir = out_dir / f"{number:03d}"
            card_dir.mkdir(parents=True, exist_ok=True)
            (card_dir / "front.md").write_text(
                "\n\n".join(front) + "\n", encoding="utf-8"
            )

            back_lines: list[str] = []
            for block in html_to_blocks(fields[1]):
                sounds = SOUND.findall(block)
                text = SOUND.sub("", block).strip()
                if text:
                    back_lines.append(text)
                for sound in sounds:
                    if sound not in blobs:
                        sys.exit(f"error: card {number} needs missing media {sound}")
                    (card_dir / sound).write_bytes(blobs[sound])
                    copied.add(sound)
                    back_lines.append(f"![{sound}]({sound})")
            if not back_lines:
                sys.exit(f"error: note {number} has an empty back field")
            (card_dir / "back.md").write_text(
                "\n\n".join(back_lines) + "\n", encoding="utf-8"
            )
            cards.append(f"{number:03d}")

        (out_dir / "deck.json").write_text(
            json.dumps({"format": 1, "name": name, "cards": cards}, ensure_ascii=False, indent=2)
            + "\n",
            encoding="utf-8",
        )
        unused = sorted(set(blobs) - copied)
        print(
            f"wrote {len(cards)} cards to {out_dir} "
            f"({len(copied)} media files, {len(unused)} unused)"
        )
        if unused:
            print("unused media:", ", ".join(unused))
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    convert(Path(sys.argv[1]), Path(sys.argv[2]))


if __name__ == "__main__":
    main()
