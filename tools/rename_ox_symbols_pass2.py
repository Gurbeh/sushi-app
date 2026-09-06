#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent.parent
roots = [ROOT / "lib", ROOT / "test", ROOT / "integration_test", ROOT / "pigeons"]

PROTECT = re.compile(r"oxtelegram|liboxtelegram|go/oxtelegram|ox_stream_|ox_auth_", re.I)
OX_CLASS = re.compile(r"\bOx([A-Z][A-Za-z0-9_]*)")
OX_FUNC = re.compile(r"\box([A-Z][A-Za-z0-9_]*)")

changed_files = 0
for base in roots:
    if not base.is_dir():
        continue
    for path in base.rglob("*.dart"):
        text = path.read_text(encoding="utf-8")
        lines = text.splitlines(keepends=True)
        out = []
        file_changed = False
        for line in lines:
            if PROTECT.search(line):
                out.append(line)
                continue
            new = OX_CLASS.sub(r"Sushi\1", line)
            new = OX_FUNC.sub(r"sushi\1", new)
            if new != line:
                file_changed = True
            out.append(new)
        if file_changed:
            path.write_text("".join(out), encoding="utf-8", newline="\n")
            changed_files += 1
            print("EDIT", path.relative_to(ROOT))

print("changed_files", changed_files)

old = ROOT / "integration_test" / "oxplayer_playback_e2e_test.dart"
new = ROOT / "integration_test" / "sushi_playback_e2e_test.dart"
if old.exists():
    old.rename(new)
    print("RENAME", old.name, "->", new.name)
