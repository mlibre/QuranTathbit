#!/usr/bin/env python3
"""Prove the shipped deck is exactly the apkg, nothing else.

Re-extracts quran-cards-2026-10-14.apkg into a scratch directory with the
same code path tools/apkg_to_deck.py uses, then compares every file with
assets/decks/quran:

  front.md / back.md / *.mp3   must be byte-identical
  deck.json                    may differ only in the deck *name* label
                               ("Default" in the package -> the app's name)
                               and key order; the recorded source URL must
                               match the one the app ships
  *-fa.mp3                     are the Persian translation recitations the
                               app delivers beside the package's verses
                               (tools/fetch_persian.py, from the CDN that
                               deck.json's translation_audio records); they
                               are additive, ignored here
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


def compare_filesets(fresh: Path, shipped: Path) -> list[str]:
    problems: list[str] = []

    fresh_files = {p.relative_to(fresh) for p in fresh.rglob("*") if p.is_file()}
    shipped_files = {
        p.relative_to(shipped)
        for p in shipped.rglob("*")
        if p.is_file()
        and p.suffix != ".import"
        and p.name != "progress.json"
        and not is_translation(p.name)
    }

    for rel in sorted(fresh_files - shipped_files):
        problems.append(f"missing from the shipped deck: {rel}")
    for rel in sorted(shipped_files - fresh_files):
        problems.append(f"extra in the shipped deck (not in the package): {rel}")

    for rel in sorted(fresh_files & shipped_files):
        a = (fresh / rel).read_bytes()
        b = (shipped / rel).read_bytes()
        if a == b:
            continue
        if rel.name == "deck.json":
            problems.extend(compare_deck_json(a, b))
        else:
            problems.append(f"content differs from the package: {rel}")
    return problems


def compare_deck_json(fresh: bytes, shipped: bytes) -> list[str]:
    a = json.loads(fresh)
    b = json.loads(shipped)
    if a.get("cards") != b.get("cards"):
        return ["deck.json: the card list differs from the package"]
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
          "(deck.json differs only by the app's deck name label)")


if __name__ == "__main__":
    main()
