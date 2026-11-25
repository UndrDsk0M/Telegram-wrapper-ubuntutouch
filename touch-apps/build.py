#!/usr/bin/env python3
"""Build both Ubuntu Touch 16.04 Click packages."""
import argparse
import json
import os
from pathlib import Path
from shutil import copy2, copytree
from subprocess import run
from tempfile import TemporaryDirectory

APPS = {
    "pocket-player": ("Pocket Player", "Play local audio and video", ("audio", "content_exchange", "video")),
    "chatgpt-web": ("ChatGPT Web", "Launcher for the official ChatGPT website", ("networking", "webview")),
}
VERSION = "1.0.0"
PLAYER_VERSION = "1.1.0"


def build(source, output, app, architecture="all", codecs=None):
    title, description, policies = APPS[app]
    hooks = {"apparmor": "apparmor.json", "desktop": app + ".desktop"}
    if app == "pocket-player":
        hooks["content-hub"] = "content-hub.json"
    manifest = {
        "name": app + ".touchapps",
        "title": title,
        "description": description,
        "version": PLAYER_VERSION if codecs else VERSION,
        "maintainer": "Touch Apps <maintainer@example.invalid>",
        "framework": "ubuntu-sdk-16.04.8",
        "architecture": architecture,
        "hooks": {app: hooks},
    }
    profile = {"policy_groups": list(policies), "policy_version": 16.04}
    if app == "chatgpt-web":
        profile["template"] = "ubuntu-webapp"
    if codecs:
        profile["policy_groups"].append("networking")

    with TemporaryDirectory(prefix="touch-app-") as temp:
        tree = Path(temp) / app
        copytree(source / app, tree)
        if codecs:
            env = os.environ.copy()
            env.update(GOOS="linux", GOARCH="arm" if architecture == "armhf" else "arm64",
                       GOARM="7", CGO_ENABLED="0")
            run(["go", "build", "-buildvcs=false", "-trimpath", "-ldflags=-s -w",
                 "-o", str(tree / "pocket-player"), str(source / "media-engine" / "main.go")],
                cwd=source, env=env, check=True)
            copy2(codecs / ("ffmpeg-" + architecture), tree / "ffmpeg")
            for notice in sorted((source / "media-engine" / "licenses").glob("*")):
                copy2(notice, tree / notice.name)
            launcher = tree / "pocket-player.desktop"
            desktop = launcher.read_text(encoding="utf-8")
            launcher.write_text(desktop.replace("Exec=qmlscene PocketPlayer.qml", "Exec=./pocket-player"),
                                encoding="utf-8")
        for name, content in (("manifest.json", manifest), ("apparmor.json", profile)):
            (tree / name).write_text(json.dumps(content, indent=2) + "\n", encoding="utf-8")
        tree.chmod(0o755)
        for child in tree.iterdir():
            child.chmod(0o755 if child.name in ("pocket-player", "ffmpeg") else 0o644)
        run(["click", "build", str(tree)], cwd=output, check=True)
        filename = f"{manifest['name']}_{manifest['version']}_{architecture}.click"
        (output / filename).chmod(0o644)


def main():
    source = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=source / "dist")
    parser.add_argument("--player-codecs-dir", type=Path,
                        help="build Pocket Player with ffmpeg-armhf and ffmpeg-arm64 from this directory")
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    if args.player_codecs_dir:
        codecs = args.player_codecs_dir.resolve()
        for architecture in ("armhf", "arm64"):
            build(source, output, "pocket-player", architecture, codecs)
    else:
        for app in APPS:
            build(source, output, app)


if __name__ == "__main__":
    main()
