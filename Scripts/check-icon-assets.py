#!/usr/bin/env python3
"""Verify both the native icon source and its shipped macOS resource wiring.

The previous ICNS-only package passed size checks but acquired a second plate
on Tahoe. Requiring the compiled icon stack prevents that packaging regression.
"""
import argparse
import json
from pathlib import Path
import platform
import plistlib
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def require(condition, message):
    if not condition:
        raise SystemExit("Icon asset check failed: " + message)


def check_source():
    document = ROOT / "Configuration/Arcora.icon"
    config = json.loads((document / "icon.json").read_text())
    layers = [layer for group in config["groups"] for layer in group["layers"]]
    artwork = [layer for layer in layers if layer.get("image-name") == "ArcoraIcon.png"]
    require(len(artwork) == 1, "expected one Arcora artwork layer")
    image = document / "Assets/ArcoraIcon.png"
    master = ROOT / "Sources/Arcora/Resources/Brand/ArcoraIcon.png"
    require(not image.is_symlink() and not master.is_symlink(), "artwork must be regular files")
    data = image.read_bytes()
    require(data == master.read_bytes(), "native artwork and in-app master have diverged")
    require(data[:8] == b"\x89PNG\r\n\x1a\n" and data[12:16] == b"IHDR", "master is not a PNG")
    width, height = struct.unpack(">II", data[16:24])
    require(width == height and 1024 <= width <= 4096, "invalid master dimensions")
    # The existing master includes legacy padding. At its native point size,
    # it covers the 1024 pt system canvas; normalizing it first would inset it.
    position = artwork[0].get("position", {})
    scale = position.get("scale", 1)
    require(isinstance(scale, (int, float)) and 1.18 <= width * scale / 1024 <= 1.30,
            "artwork no longer covers the system canvas; inspect native padding")
    require(position.get("translation-in-points", [0, 0]) == [0, 0], "artwork must stay centered")
    require(artwork[0].get("glass") is False, "do not reapply glass to pre-rendered artwork")
    require("fill" in config, "native background fill is missing")
    info = plistlib.loads((ROOT / "Configuration/Info.plist").read_bytes())
    require(info.get("CFBundleIconName") == "Arcora", "source Info.plist lacks the native icon name")
    require(info.get("CFBundleIconFile") == "Arcora", "source Info.plist lacks the legacy fallback")


def check_app(app):
    require(platform.system() == "Darwin" and int(platform.mac_ver()[0].split(".")[0] or 0) >= 26,
            "native icon stack inspection requires macOS 26+ CoreUI; older assetutil cannot decode the stacks")
    resources = app / "Contents/Resources"
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    require(info.get("CFBundleIconName") == "Arcora", "app lacks CFBundleIconName=Arcora")
    require(info.get("CFBundleIconFile") == "Arcora", "app lacks CFBundleIconFile=Arcora")
    for name in ("Assets.car", "Arcora.icns"):
        path = resources / name
        require(path.is_file() and not path.is_symlink() and path.stat().st_size > 0,
                "missing compiled resource: " + name)
    assets = json.loads(subprocess.check_output(["xcrun", "assetutil", "--info", str(resources / "Assets.car")]))
    stacks = [item for item in assets if item.get("AssetType") == "IconImageStack" and item.get("Name") == "Arcora"]
    appearances = {item.get("Appearance") for item in stacks}
    require({"NSAppearanceNameAqua", "NSAppearanceNameDarkAqua", "ISAppearanceTintable"} <= appearances,
            "missing native Default, Dark, or Mono icon stack")
    require(all(item.get("CanvasWidth") == 1024 and item.get("CanvasHeight") == 1024 for item in stacks),
            "native icon canvas must be 1024 pt")
    require(any(item.get("AssetType") == "MultiSized Image" and item.get("Name") == "Arcora" for item in assets),
            "catalog lacks its legacy multi-size fallback")
    require(assets[0].get("Platform") == "macosx" and assets[0].get("PlatformVersion") == "14.0",
            "icon deployment target no longer matches macOS 14")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", nargs="?", type=Path, help="also inspect the compiled app bundle")
    args = parser.parse_args()
    check_source()
    if args.app:
        check_app(args.app)
        print("PASS: native icon wiring, 3 appearance stacks, 1024 pt canvas, and macOS 14 fallback")
    else:
        print("PASS: native icon source, full-canvas layout, and shared artwork")


if __name__ == "__main__":
    main()
