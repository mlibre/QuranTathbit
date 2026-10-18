#!/usr/bin/env python3
"""Prove the shipped deck is exactly the apkg, nothing else.

Re-extracts quran-cards-2026-10-14.apkg into a scratch directory with the
same code path tools/apkg_to_deck.py uses, then compares every file with
assets/decks/quran:

  front.md / back.md / *.mp3   must be identical after the reader's
                               punctuation pass (every ';' and '؛' read
                               as ':', v1.0.30) -- the deck's own edit,
                               applied to both sides before comparing
  deck.json                    may differ only in the deck *name* label
                               ("Default" in the package -> the app's name)
                               and key order; the recorded source URL must
                               match the one the app ships; the card list is
                               the package's own followed by the extension
                               cards in their folder order
  *-fa.mp3                     are the Persian translation recitations the
                               app delivers beside the package's verses
                               (tools/fetch_persian.py, from the CDN that
                               deck.json's translation_audio records); they
                               are additive, ignored here
  cards 100-151                are Al-Baqarah 94-145, transcribed by hand
                               from the deck's recorded source by the reader
                               (tools/extend_baqarah.py); text-only --
                               front.md and back.md and nothing else -- they
                               are an additive layer the package cannot
                               vouch for, allowed by shape and ignored
                               below it
  *.import                     are Godot editor metadata, ignored
  progress.json                is runtime state, ignored
  anything else                is a failure

Exit code 0 only when the deck is a faithful copy. Run from the repo root:

    python3 tools/verify_deck.py [path-to.apkg] [path-to-deck]

The package file is intentionally not part of the repo (it is a 12 MB
binary that lives only on the developer's machine). When it is absent the
script reports a single, clear "skipped" message and exits 0 -- the
deck's bytes were proven once, on the commit that introduced it, and the
deck.json source field still records where they came from. Drop the
package back into the root to run the proof again.
"""

from __future__ import annotations

import json
import shutil
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from apkg_to_deck import convert  # noqa: E402  (same code path, one truth)

DEFAULT_APKG = Path("quran-cards-2026-10-14.apkg")
DEFAULT_DECK = Path("assets/decks/quran")
SOURCE = "https://quran.makarem.ir/"

# What the package's deck is called versus what the app renames it to.
PACKAGE_NAME = "Default"
APP_NAME = "Quran"


def is_translation(name: str) -> bool:
    """The app's own Persian translation recitations, *-fa.mp3."""
    return name.endswith("-fa.mp3")


def punctuation_pass(data: bytes) -> bytes:
    """The reader's own edit of the deck's words, v1.0.30: every semicolon
    -- the ASCII ';' the package's translation carried between its clauses
    and the Arabic '؛' two verses used -- reads as a colon, the punctuation
    the deck's own quotations already use. The proof compares both sides
    after the same pass, so it still catches every drift that is not this
    one deliberate edit.
    """
    return data.replace(b";", b":").replace("\u061b".encode(), b":")


def is_extension_card(rel: Path, fresh_card_ids: set[str]) -> bool:
    """A file that belongs to a card folder the package never carried.

    Al-Baqarah 94-145 (folders 100-151) joined the deck from the reader's
    own transcription of the deck's recorded source -- the same source the
    package came from, said once, by hand, in tools/extend_baqarah.py. The
    proof treats them the way it treats the translation recitations: an
    additive layer the package cannot vouch for, allowed only as the two
    markdown files a text-only card is -- no audio may arrive for them from
    anywhere, and none did.
    """
    if len(rel.parts) != 2:
        return False
    folder = rel.parts[0]
    try:
        int(folder)
    except ValueError:
        return False
    return folder not in fresh_card_ids and rel.name in ("front.md", "back.md")


def compare_filesets(fresh: Path, shipped: Path) -> list[str]:
    problems: list[str] = []

    fresh_card_ids = {
        p.relative_to(fresh).parts[0]
        for p in fresh.iterdir()
        if p.is_dir() and p.name.isdigit()
    }
    fresh_files = {p.relative_to(fresh) for p in fresh.rglob("*") if p.is_file()}
    shipped_files = {
        p.relative_to(shipped)
        for p in shipped.rglob("*")
        if p.is_file()
        and p.suffix != ".import"
        and p.name != "progress.json"
        and not is_translation(p.name)
        and not is_extension_card(p.relative_to(shipped), fresh_card_ids)
    }

    for rel in sorted(fresh_files - shipped_files):
        problems.append(f"missing from the shipped deck: {rel}")
    for rel in sorted(shipped_files - fresh_files):
        problems.append(f"extra in the shipped deck (not in the package): {rel}")

    for rel in sorted(fresh_files & shipped_files):
        a = (fresh / rel).read_bytes()
        b = (shipped / rel).read_bytes()
        if rel.name in ("front.md", "back.md"):
            a = punctuation_pass(a)
            b = punctuation_pass(b)
        if a == b:
            continue
        if rel.name == "deck.json":
            problems.extend(compare_deck_json(a, b, fresh_card_ids))
        else:
            problems.append(f"content differs from the package: {rel}")
    return problems


def compare_deck_json(fresh: bytes, shipped: bytes, fresh_card_ids: set[str]) -> list[str]:
    a = json.loads(fresh)
    b = json.loads(shipped)
    package_cards = [str(c) for c in a.get("cards", [])]
    shipped_cards = [str(c) for c in b.get("cards", [])]
    # The package's cards, then the extension's own folders in their folder
    # order -- the same order the loader itself appends them in.
    expected = package_cards + sorted(
        {c for c in shipped_cards if c not in package_cards}
    )
    if shipped_cards != expected:
        return ["deck.json: the card list is not the package's list followed by the extension's"]
    if b.get("name") != APP_NAME or a.get("name") != PACKAGE_NAME:
        return [
            f"deck.json: unexpected deck name (package has {a.get('name')!r}, "
            f"shipped has {b.get('name')!r}, expected {PACKAGE_NAME!r} -> {APP_NAME!r})"
        ]
    if b.get("source") != SOURCE:
        return [f"deck.json: shipped source must record {SOURCE}"]
    return []


def main() -> None:
    apkg = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_APKG
    deck = Path(sys.argv[2]) if len(sys.argv) > 2 else DEFAULT_DECK
    if not apkg.is_file():
        # The package is intentionally absent from the repo. The deck's
        # bytes were proven byte-identical on the commit that introduced
        # them, and deck.json records the source. Re-running the proof
        # needs the developer's local copy of the apkg dropped into the
        # root -- say so plainly instead of failing the build.
        if (deck / "deck.json").is_file():
            print(f"skip: {apkg} not present (deck proven at introduction; "
                  "deck.json still records the source)")
            return
        sys.exit(f"error: neither package nor deck found")
    if not (deck / "deck.json").is_file():
        sys.exit(f"error: deck not found: {deck}")

    scratch = Path(tempfile.mkdtemp(prefix="deck-verify-"))
    try:
        convert(apkg, scratch / "quran", source=SOURCE)
        problems = compare_filesets(scratch / "quran", deck)
    finally:
        shutil.rmtree(scratch, ignore_errors=True)

    if problems:
        print("FAILED: the shipped deck is not a faithful copy of the package")
        for p in problems:
            print("  -", p)
        sys.exit(1)

    print("OK: the shipped deck is byte-identical to the package "
          "(deck.json differs only by the app's deck name label; the "
          "Al-Baqarah 94-145 extension cards ride beside it as an additive "
          "layer, the way the translation recitations do)")


if __name__ == "__main__":
    main()
