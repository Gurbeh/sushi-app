#!/usr/bin/env python3
"""Move lib/oxplayer → lib/sushi and rename Oxplayer*/oxplayer_* → Sushi*/sushi_*."""
from __future__ import annotations

import os
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LIB = ROOT / "lib"
TEST = ROOT / "test"
OX = LIB / "oxplayer"
SUSHI = LIB / "sushi"
OX_TEST = TEST / "oxplayer"
SUSHI_TEST = TEST / "sushi"

# Basename collisions with existing lib/sushi files.
SPECIAL_BASENAMES = {
    "ox_item_flags.dart": "sushi_catalog_item_flags.dart",
    "ox_item_flags.g.dart": "sushi_catalog_item_flags.g.dart",
}


def rename_basename(name: str) -> str:
    if name in SPECIAL_BASENAMES:
        return SPECIAL_BASENAMES[name]
    if name.startswith("oxplayer_"):
        return "sushi_" + name[len("oxplayer_") :]
    if name.startswith("ox_"):
        return "sushi_" + name[len("ox_") :]
    return name


def dest_relpath(rel: Path) -> Path:
    parts = list(rel.parts)
    # drop leading nothing; rel is relative to oxplayer/
    new_parts = []
    for p in parts[:-1]:
        if p == "oxplayer":
            new_parts.append("sushi")
        else:
            new_parts.append(p)
    new_parts.append(rename_basename(parts[-1]))
    return Path(*new_parts)


def move_tree(src_root: Path, dst_root: Path) -> list[tuple[Path, Path]]:
    moved: list[tuple[Path, Path]] = []
    if not src_root.is_dir():
        return moved
    for path in sorted(src_root.rglob("*")):
        if not path.is_file():
            continue
        # skip graphify junk
        if "graphify-out" in path.parts:
            continue
        rel = path.relative_to(src_root)
        dest = dst_root / dest_relpath(rel)
        dest.parent.mkdir(parents=True, exist_ok=True)
        if dest.exists():
            # Never overwrite existing sushi_* product files.
            print(f"SKIP exists: {dest.relative_to(ROOT)}")
            continue
        shutil.move(str(path), str(dest))
        moved.append((path, dest))
        print(f"MOVE {path.relative_to(ROOT)} -> {dest.relative_to(ROOT)}")
    return moved


# Text replacements applied to dart (and related) sources under lib/, test/, integration_test/, pigeons/
REPLACEMENTS: list[tuple[re.Pattern[str], str]] = [
    (re.compile(r"package:fladder/oxplayer/"), "package:fladder/sushi/"),
    # part directives for special rename
    (re.compile(r"part 'ox_item_flags\.g\.dart';"), "part 'sushi_catalog_item_flags.g.dart';"),
    (re.compile(r"ox_item_flags\.g\.dart"), "sushi_catalog_item_flags.g.dart"),
    (re.compile(r"ox_item_flags\.dart"), "sushi_catalog_item_flags.dart"),
    # path-style filenames in imports already covered by package replace + basename moves
    # Class / symbol renames (order matters: longer first)
    (re.compile(r"Oxplayer"), "Sushi"),
    (re.compile(r"oxplayer"), "sushi"),
    # Ox* product prefixes (avoid OxSemver already gone; avoid matching words mid-token after Oxplayer→Sushi)
    (re.compile(r"\bOxTdlib"), "SushiTdlib"),
    (re.compile(r"\bOxPlayback"), "SushiPlayback"),
    (re.compile(r"\bOxHome"), "SushiHome"),
    (re.compile(r"\bOxPoster"), "SushiPoster"),
    (re.compile(r"\bOxDetail"), "SushiDetail"),
    (re.compile(r"\bOxFavorites"), "SushiFavorites"),
    (re.compile(r"\bOxItemFlags"), "SushiCatalogItemFlags"),
    (re.compile(r"\bOxItem"), "SushiItem"),
    (re.compile(r"\bOxMedia"), "SushiMedia"),
    (re.compile(r"\bOxUpdate"), "SushiUpdate"),
    (re.compile(r"\bOxGitHub"), "SushiGitHub"),
    (re.compile(r"\bOxSubtitle"), "SushiSubtitle"),
    (re.compile(r"\bOxSeries"), "SushiSeries"),
    (re.compile(r"\bOxSeason"), "SushiSeason"),
    (re.compile(r"\bOxEpisode"), "SushiEpisode"),
    (re.compile(r"\bOxLibrary"), "SushiLibrary"),
    (re.compile(r"\bOxBoxset"), "SushiBoxset"),
    (re.compile(r"\bOxLabeled"), "SushiLabeled"),
    (re.compile(r"\bOxIran"), "SushiIran"),
    (re.compile(r"\bOxPlayer"), "SushiPlayer"),
    (re.compile(r"\bOxSplash"), "SushiSplash"),
    (re.compile(r"\bOxStaged"), "SushiStaged"),
    (re.compile(r"\bOxRouting"), "SushiRouting"),
    (re.compile(r"\bOxTelegram"), "SushiTelegram"),
    (re.compile(r"\bOxOptional"), "SushiOptional"),
    (re.compile(r"\bOxSemver"), "SushiSemver"),
    (re.compile(r"\bOxWatch"), "SushiWatch"),
    (re.compile(r"\bOxDialog"), "SushiDialog"),
    (re.compile(r"\bkOx"), "kSushi"),
    (re.compile(r"\boxplay"), "sushiplay"),  # log tags like oxplayTdlibLogTag
    (re.compile(r"\bOXPLAY_"), "SUSHI_"),
    (re.compile(r"\bOX_STREAM\b"), "SUSHI_STREAM"),
    (re.compile(r"/ox-login"), "/sushi-login"),
    (re.compile(r"/ox-help"), "/sushi-help"),
]

# Do NOT touch these trees
SKIP_DIRS = {
    "go",
    "graphify-out",
    ".git",
    "build",
    ".dart_tool",
    "node_modules",
    "windows/oxtelegram",  # engine path kept
}


def should_skip(path: Path) -> bool:
    rel = path.relative_to(ROOT).as_posix()
    for skip in SKIP_DIRS:
        if rel == skip or rel.startswith(skip + "/"):
            return True
    # never rewrite go/oxtelegram contents
    if "oxtelegram" in path.parts and "go" in path.parts:
        return True
    return False


def rewrite_file(path: Path) -> bool:
    try:
        text = path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        return False
    orig = text
    for pat, repl in REPLACEMENTS:
        text = pat.sub(repl, text)
    # Fix accidental double-sushi from oxplayer_ already moved then replaced
    text = text.replace("sushi_sushi_", "sushi_")
    text = text.replace("SushiSushi", "Sushi")
    text = text.replace("package:fladder/sushi/sushi/", "package:fladder/sushi/")
    if text != orig:
        path.write_text(text, encoding="utf-8", newline="\n")
        return True
    return False


def main() -> None:
    print("=== move lib/oxplayer ===")
    move_tree(OX, SUSHI)
    print("=== move test/oxplayer ===")
    move_tree(OX_TEST, SUSHI_TEST)

    # Remove empty leftovers under oxplayer
    for root in (OX, OX_TEST):
        if root.is_dir():
            # remove empty dirs bottom-up; leave non-empty (skipped collisions)
            for dirpath, dirnames, filenames in os.walk(root, topdown=False):
                p = Path(dirpath)
                if "graphify-out" in p.parts:
                    shutil.rmtree(p, ignore_errors=True)
                    continue
                try:
                    if not any(p.iterdir()):
                        p.rmdir()
                        print(f"RMDIR {p.relative_to(ROOT)}")
                except OSError:
                    pass
            if root.is_dir() and not any(root.rglob("*")):
                shutil.rmtree(root, ignore_errors=True)

    print("=== rewrite sources ===")
    roots = [LIB, TEST, ROOT / "integration_test", ROOT / "pigeons"]
    changed = 0
    scanned = 0
    for base in roots:
        if not base.is_dir():
            continue
        for path in base.rglob("*"):
            if not path.is_file():
                continue
            if path.suffix not in {".dart", ".md", ".json", ".yaml", ".yml"}:
                continue
            if should_skip(path):
                continue
            scanned += 1
            if rewrite_file(path):
                changed += 1
                print(f"EDIT {path.relative_to(ROOT)}")
    print(f"done scanned={scanned} changed={changed}")


if __name__ == "__main__":
    main()
