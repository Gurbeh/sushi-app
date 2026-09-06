#!/usr/bin/env python3
"""Restore ARB UTF-8: take pre-rename good files, apply oxplayer→sushi key renames."""
from __future__ import annotations

import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GOOD_REV = "9cbc580"


def git_show(rev: str, path: str) -> bytes:
    return subprocess.check_output(["git", "show", f"{rev}:{path}"], cwd=ROOT)


def rename_keys(text: str) -> str:
    # Key renames from oxplayer* / ox* product strings → sushi*
    replacements = [
        (r"\boxplayer", "sushi"),
        (r"\bOxplayer", "Sushi"),
        (r"\bOXPlayer", "Sushi"),
        (r"\boxPlayer", "sushi"),
    ]
    for pat, rep in replacements:
        text = re.sub(pat, rep, text)
    # Avoid double sushi_sushi
    text = text.replace("sushi_sushi", "sushi")
    text = text.replace("SushiSushi", "Sushi")
    return text


def main() -> None:
    for rel in ("lib/l10n/app_en.arb", "lib/l10n/app_fa.arb"):
        raw = git_show(GOOD_REV, rel)
        text = raw.decode("utf-8")
        fixed = rename_keys(text)
        # Ensure still valid utf-8 roundtrip
        out = fixed.encode("utf-8")
        out.decode("utf-8")
        path = ROOT / rel
        path.write_bytes(out)
        print(f"wrote {rel} ({len(out)} bytes)")

    # Sanity: HEAD-broken cp1252 vs our keys
    for rel in ("lib/l10n/app_en.arb", "lib/l10n/app_fa.arb"):
        text = (ROOT / rel).read_text(encoding="utf-8")
        ox = len(re.findall(r"oxplayer|Oxplayer|OXPlayer", text, re.I))
        sushi = len(re.findall(r"sushi[A-Z]|\"sushi", text))
        print(f"{rel}: ox-ish={ox} sushi-ish={sushi}")


if __name__ == "__main__":
    main()
