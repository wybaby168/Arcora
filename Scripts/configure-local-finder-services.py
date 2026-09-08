#!/usr/bin/env python3
"""Give locally generated RAR variants distinct Services identities and titles."""
import json
from pathlib import Path
import plistlib
import re
import sys

app = Path(sys.argv[1])
info_path = app / "Contents/Info.plist"
info = plistlib.loads(info_path.read_bytes())
assert info["CFBundleIdentifier"] in {
    "app.arcora.desktop.rar-evaluation", "app.arcora.desktop.rar-codec-evaluation"
}, "Only generated private RAR builds may be relabelled"
personal = info.get("ArcoraRARLocalEvaluation") is True
prefix = "Arcora Personal" if personal else "Arcora RAR Test"
translations = {"en": prefix, "zh-Hans": "Arcora 个人版" if personal else "Arcora RAR 测试版",
                "ja": "Arcora 個人用" if personal else "Arcora RAR テスト版"}
for service in info["NSServices"]:
    service["NSPortName"] = info["CFBundleName"]
    service["NSMenuItem"]["default"] = service["NSMenuItem"]["default"].replace("Arcora —", prefix + " —", 1)
info_path.write_bytes(plistlib.dumps(info, sort_keys=False))
for language, localized_prefix in translations.items():
    path = app / "Contents/Resources" / (language + ".lproj") / "ServicesMenu.strings"
    lines = []
    for line in path.read_text().splitlines():
        if not line.strip() or line.startswith("//"):
            lines.append(line)
            continue
        match = re.fullmatch(r'("(?:[^"\\]|\\.)*")\s*=\s*("(?:[^"\\]|\\.)*");', line)
        assert match, "Unexpected localization syntax"
        key, value = map(json.loads, match.groups())
        key = key.replace("Arcora —", prefix + " —", 1)
        value = value.replace("Arcora —", localized_prefix + " —", 1)
        lines.append(json.dumps(key, ensure_ascii=False) + " = " + json.dumps(value, ensure_ascii=False) + ";")
    path.write_text("\n".join(lines) + "\n")
