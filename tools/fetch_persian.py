#!/usr/bin/env python3
"""Fetch the Persian translation recitations for every verse in the deck.

The deck's cards reference their Arabic recitations by file name
(002001.mp3 = surah 2, verse 1). Makarem's site serves the Persian
translation of the same verses -- recited by Hojatollah Kabiri -- under the
same six-digit names in its own folder:

    https://cdn.makarem.ir/quransound/persian-kabiri/002001.mp3

Each verse's translation is saved beside the verse's own recitation as
{stem}-fa.mp3 (002001-fa.mp3), so a card's folder carries both voices and
the app can offer them side by side. No other source is used, by the
deck's own instruction; the URL template is recorded in deck.json under
"translation_audio".

Run from the repo root (idempotent; existing files are kept):

    python3 tools/fetch_persian.py [cdn-base] [deck-root]

Defaults:
    cdn-base  https://cdn.makarem.ir/quransound/persian-kabiri
    deck-root assets/decks/quran
"""

from __future__ import annotations

import sys
import time
import urllib.request
from pathlib import Path

DEFAULT_CDN = "https://cdn.makarem.ir/quransound/persian-kabiri"
DEFAULT_DECK = Path("assets/decks/quran")

# Six-digit stems (002001) are verses; anything else is not a verse
# recitation and has no translation twin on the CDN.
VERSE_NAME = "002001.mp3"


def verse_stems(deck: Path) -> list[tuple[Path, str]]:
    found: list[tuple[Path, str]] = []
    for folder in sorted(p for p in deck.iterdir() if p.is_dir() and p.name.isdigit()):
        for mp3 in sorted(folder.glob("*.mp3")):
            stem = mp3.stem
            if len(stem) == 6 and stem.isdigit():
                found.append((folder, stem))
    return found


def fetch(url: str, tries: int = 4) -> bytes:
    last: Exception | None = None
    for attempt in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "QuranTathbit/1.0"})
            with urllib.request.urlopen(req, timeout=30) as response:
                return response.read()
        except Exception as error:  # noqa: BLE001 -- the network has many moods
            last = error
            time.sleep(1.5 * (attempt + 1))
    raise RuntimeError(f"could not fetch {url}: {last}")


def main() -> None:
    cdn = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_CDN
    deck = Path(sys.argv[2]) if len(sys.argv) > 2 else DEFAULT_DECK
    if not (deck / "deck.json").is_file():
        sys.exit(f"error: no deck at {deck}")

    stems = verse_stems(deck)
    print(f"{len(stems)} verse recitation(s) found in {deck}")

    fetched = 0
    kept = 0
    failed: list[str] = []
    for folder, stem in stems:
        target = folder / f"{stem}-fa.mp3"
        if target.exists() and target.stat().st_size > 0:
            kept += 1
            continue
        url = f"{cdn}/{stem}.mp3"
        try:
            data = fetch(url)
        except RuntimeError as error:
            print(f"  FAIL {url}\n       {error}")
            failed.append(stem)
            continue
        if not data.startswith(b"ID3") and not data.startswith(b"\xff\xfb") and not data.startswith(b"\xff\xf3"):
            failed.append(stem)
            print(f"  FAIL {url} -- not an mp3 ({len(data)} bytes)")
            continue
        target.write_bytes(data)
        fetched += 1
        print(f"  {target.relative_to(deck)}  {len(data) // 1024} KB")

    print(f"done: {fetched} fetched, {kept} already present, {len(failed)} failed")
    if failed:
        sys.exit(f"error: {len(failed)} translation(s) missing: {', '.join(failed)}")


if __name__ == "__main__":
    main()
