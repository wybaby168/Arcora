#!/usr/bin/env python3
"""Verify that source or packaged Finder Services declare all supported actions."""
import argparse
import json
from pathlib import Path
import plistlib
import re

root=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument("app",nargs="?",type=Path)
args=parser.parse_args()
folder=args.app/"Contents" if args.app else root/"Configuration"
resources=folder/"Resources" if args.app else folder
info=plistlib.loads((folder/"Info.plist").read_bytes())
expected={"zip":"Arcora — Quick ZIP","7z":"Arcora — Quick 7z","rar":"Arcora — Quick RAR","custom":"Arcora — Custom Compression…"}
if info["CFBundleIdentifier"] in ("app.arcora.desktop.rar-evaluation","app.arcora.desktop.rar-codec-evaluation"):
    prefix="Arcora Personal" if info.get("ArcoraRARLocalEvaluation") is True else "Arcora RAR Test"
    expected={action:title.replace("Arcora —",prefix+" —",1) for action,title in expected.items()}
services=info.get("NSServices",[])
assert len(services)==len(expected),"Every action must be advertised exactly once"
assert {service.get("NSUserData") for service in services}==set(expected),"Missing/unknown service action"
for service in services:
    assert service["NSMenuItem"]["default"]==expected[service["NSUserData"]]
    assert service["NSMessage"]=="compressFiles"
    assert service.get("NSPortName")==info["CFBundleName"],"The service port must match the app's registered name"
    assert service.get("NSRequiredContext")=={},"Explicit file-selection context required"
    assert "public.item" in service.get("NSSendFileTypes",[]),"Regular files and folders must both match"
    assert service.get("NSRestricted") is True,"Do not let sandboxed clients use file processing to escape their sandbox"
keys=set(expected.values())|{"Arcora could not accept this file selection. Open Arcora and try again."}
for language in ("en","zh-Hans","ja"):
    values={}
    for line in (resources/(language+".lproj")/"ServicesMenu.strings").read_text().splitlines():
        if not line.strip() or line.startswith("//"):continue
        match=re.fullmatch(r'("(?:[^"\\]|\\.)*")\s*=\s*("(?:[^"\\]|\\.)*");',line)
        assert match,"Invalid service localization line"
        key,value=map(json.loads,match.groups())
        assert key not in values and value,"Duplicate or empty service translation"
        values[key]=value
    assert set(values)==keys,"Missing service translations: "+language
print("PASS: 4 Finder file/folder services; matching dispatch actions and 3 complete menu translations")
