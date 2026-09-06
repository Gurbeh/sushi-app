#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent.parent / "lib"

def fix(text: str) -> str:
    # Broken `\1sushi_foo.dart';` from bad regex replace of part/export
    text = re.sub(r"\\+1sushi_([\w.]+)", r"part 'sushi_\1", text)
    # package:fladder/sushi/.../ox_X -> sushi_X
    text = re.sub(r"(package:fladder/sushi/[\w/]*)ox_", r"\1sushi_", text)
    text = re.sub(r"part of 'ox_", "part of 'sushi_", text)
    # relative leftover ox_ in conditional exports
    text = re.sub(r"'ox_([\w.]+\\.dart)'", r"'sushi_\1'", text)
    return text

# Fix hls export file completely
hls = ROOT / "sushi" / "playback" / "sushi_hls_web_buffer_config.dart"
hls.write_text(
    "export 'sushi_hls_web_buffer_config_stub.dart'\n"
    "    if (dart.library.js_interop) 'sushi_hls_web_buffer_config_web.dart';\n",
    encoding="utf-8",
    newline="\n",
)
print("fixed hls export")

changed = 1
for path in ROOT.rglob("*.dart"):
    if path == hls:
        continue
    t = path.read_text(encoding="utf-8")
    n = fix(t)
    if n != t:
        path.write_text(n, encoding="utf-8", newline="\n")
        changed += 1
        print("EDIT", path.relative_to(ROOT.parent))

print("changed", changed)

# Spot-check remaining bad imports
bad = []
for path in (ROOT / "sushi").rglob("*.dart"):
    t = path.read_text(encoding="utf-8")
    if "\\1" in t or re.search(r"package:fladder/sushi/[\w/]*ox_", t) or "part of 'ox_" in t:
        bad.append(str(path.relative_to(ROOT.parent)))
print("still bad:", len(bad))
for b in bad[:30]:
    print(" ", b)
