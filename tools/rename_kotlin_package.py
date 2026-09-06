#!/usr/bin/env python3
"""Move Android Kotlin package app.oxplayer → app.sushi and rewrite package decls."""
from __future__ import annotations

import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

MOVES = [
    (
        ROOT / "android/app/src/main/kotlin/app/oxplayer",
        ROOT / "android/app/src/main/kotlin/app/sushi",
    ),
    (
        ROOT / "android/app/src/direct/kotlin/app/oxplayer",
        ROOT / "android/app/src/direct/kotlin/app/sushi",
    ),
    (
        ROOT / "android/app/src/debug/kotlin/app/oxplayer",
        ROOT / "android/app/src/debug/kotlin/app/sushi",
    ),
    (
        ROOT / "android/app/src/profile/kotlin/app/oxplayer",
        ROOT / "android/app/src/profile/kotlin/app/sushi",
    ),
    (
        ROOT / "android/ox_tdlib_bridge/src/main/kotlin/app/oxplayer",
        ROOT / "android/ox_tdlib_bridge/src/main/kotlin/app/sushi",
    ),
]

TEXT_GLOBS = [
    ROOT / "android",
    ROOT / "pigeons",
    ROOT / "lib",
]

PACKAGE_RE = re.compile(r"\bapp\.oxplayer\b")
IMPORT_OX = re.compile(r"\bapp/oxplayer\b")


def move_tree(src: Path, dst: Path) -> None:
    if not src.is_dir():
        print(f"SKIP missing {src.relative_to(ROOT)}")
        return
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.exists():
        # merge: move files individually
        for path in src.rglob("*"):
            if path.is_file():
                rel = path.relative_to(src)
                target = dst / rel
                target.parent.mkdir(parents=True, exist_ok=True)
                if target.exists():
                    target.unlink()
                shutil.move(str(path), str(target))
                print(f"MOVE {path.relative_to(ROOT)} -> {target.relative_to(ROOT)}")
        shutil.rmtree(src, ignore_errors=True)
    else:
        shutil.move(str(src), str(dst))
        print(f"MOVE TREE {src.relative_to(ROOT)} -> {dst.relative_to(ROOT)}")


def rewrite_file(path: Path) -> bool:
    try:
        text = path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        return False
    orig = text
    text = PACKAGE_RE.sub("app.sushi", text)
    text = IMPORT_OX.sub("app/sushi", text)
    # namespace leftovers in XML / comments
    text = text.replace("app.oxplayer", "app.sushi")
    if text != orig:
        path.write_text(text, encoding="utf-8", newline="\n")
        return True
    return False


def main() -> None:
    for src, dst in MOVES:
        move_tree(src, dst)

    # Remove empty oxplayer dirs
    for leftover in ROOT.glob("android/**/app/oxplayer"):
        if leftover.is_dir():
            shutil.rmtree(leftover, ignore_errors=True)
            print(f"RMDIR {leftover.relative_to(ROOT)}")

    exts = {".kt", ".kts", ".xml", ".gradle", ".dart", ".md", ".properties"}
    changed = 0
    for base in TEXT_GLOBS:
        if not base.exists():
            continue
        for path in base.rglob("*"):
            if not path.is_file() or path.suffix.lower() not in exts:
                continue
            if "oxtelegram" in path.parts and "go" in str(path):
                continue
            if rewrite_file(path):
                changed += 1
                print(f"EDIT {path.relative_to(ROOT)}")
    print(f"rewrote {changed} files")


if __name__ == "__main__":
    main()
