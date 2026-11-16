#!/usr/bin/env python3
"""Render the 1024 AppIcon master; actool generates the remaining sizes."""
import json
import os
import shutil
import subprocess
import sys
import tempfile

BACKGROUND = "#F1EBE5"


def fail(message):
    print(message, file=sys.stderr)
    sys.exit(1)


def run(command):
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        fail(f"Failed: {' '.join(command)}\n{result.stderr.strip()}")
    return result


def generate_icons(source_path, iconset_dir):
    if not os.path.exists(source_path):
        fail(f"Source image not found: {source_path}")

    contents_path = os.path.join(iconset_dir, "Contents.json")
    if not os.path.exists(contents_path):
        fail(f"Contents.json not found: {contents_path}")
    with open(contents_path, "r", encoding="utf-8") as handle:
        images = json.load(handle).get("images", [])
    if not any(item.get("platform") == "ios" and item.get("size") == "1024x1024" for item in images):
        fail("AppIcon.appiconset must use the single 1024x1024 iOS icon")

    target = os.path.join(iconset_dir, "AppIcon-1024.png")
    helper = os.path.join(os.path.dirname(os.path.abspath(__file__)), "opaque_png.swift")
    with tempfile.TemporaryDirectory(prefix="trolltask-icon-") as directory:
        alpha_png = os.path.join(directory, "alpha.png")
        master_png = os.path.join(directory, "master.png")
        run(["sips", "-s", "format", "png", "-z", "1024", "1024", source_path, "--out", alpha_png])
        run(["xcrun", "swift", helper, alpha_png, master_png, BACKGROUND])
        shutil.copyfile(master_png, target)

    probe = run(["sips", "-g", "hasAlpha", target]).stdout
    if "hasAlpha: yes" in probe:
        fail(f"{target} still has an alpha channel")
    print(f"Rendered {target}")


if __name__ == "__main__":
    source = sys.argv[1] if len(sys.argv) > 1 else "Resources/AppIcon-source.svg"
    destination = sys.argv[2] if len(sys.argv) > 2 else "Resources/Assets.xcassets/AppIcon.appiconset"
    generate_icons(source, destination)