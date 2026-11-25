#!/usr/bin/env python3
"""Build the Telegram Web wrapper for each supported Ubuntu Touch framework."""

import argparse
import json
from pathlib import Path
from shutil import copytree
from subprocess import run
from tempfile import TemporaryDirectory


RELEASES = {
    "16.04": ("ubuntu-sdk-16.04.8", 16.04),
    "20.04": ("ubuntu-sdk-20.04", 20.04),
    "24.04-1.x": ("ubuntu-touch-24.04-1.x", 2404.1),
    "24.04-2.x": ("ubuntu-touch-24.04-2.x", 2404.2),
}
APP_ID = "telegram-web.touchwrapper"
VERSION = "1.0.0"


def write_json(path, content):
    path.write_text(json.dumps(content, indent=2) + "\n", encoding="utf-8")


def build(release, source, output):
    framework, policy_version = RELEASES[release]
    version = f"{VERSION}+ut{release.removesuffix('.x').replace('-', '.')}"
    manifest = {
        "name": APP_ID,
        "version": version,
        "title": "Telegram Web",
        "description": "Unofficial launcher for Telegram Web on Ubuntu Touch",
        "maintainer": "Telegram Web Wrapper <maintainer@example.invalid>",
        "architecture": "all",
        "framework": framework,
        "hooks": {
            "telegram-web": {
                "apparmor": "telegram-web.apparmor",
                "desktop": "telegram-web.desktop",
            },
        },
    }
    apparmor = {
        "template": "ubuntu-webapp",
        "policy_groups": [
            "audio",
            "content_exchange",
            "content_exchange_source",
            "networking",
            "webview",
        ],
        "policy_version": policy_version,
    }

    with TemporaryDirectory(prefix="telegram-web-") as temp_dir:
        staging = Path(temp_dir) / "app"
        copytree(source, staging)
        if release == "16.04":
            launcher = staging / "telegram-web.desktop"
            desktop_entry = launcher.read_text(encoding="utf-8")
            launcher.write_text(
                desktop_entry.replace("X-Lomiri-Touch=", "X-Ubuntu-Touch="),
                encoding="utf-8",
            )
        write_json(staging / "manifest.json", manifest)
        write_json(staging / "telegram-web.apparmor", apparmor)
        run(["click", "build", str(staging)], cwd=output, check=True)


def main():
    project = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("release", nargs="*", help=", ".join(RELEASES))
    parser.add_argument("--output", type=Path, default=project / "dist")
    args = parser.parse_args()

    for release in args.release:
        if release not in RELEASES:
            parser.error(f"unsupported Ubuntu Touch release: {release}")

    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    for release in dict.fromkeys(args.release or RELEASES):
        build(release, project / "app", output)


if __name__ == "__main__":
    main()
