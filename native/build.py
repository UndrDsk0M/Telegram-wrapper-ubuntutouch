#!/usr/bin/env python3
"""Build Sparrow Chat Click packages for Ubuntu Touch 16.04."""
import argparse
import json
import os
from pathlib import Path
from shutil import copy2, copytree
from subprocess import check_output, run
from tempfile import TemporaryDirectory

VERSION = "0.3.0"
ARCHITECTURES = {"armhf": "arm", "arm64": "arm64", "amd64": "amd64"}


def licenses(directory, project, env):
    directory.mkdir()
    go_root = Path(check_output(["go", "env", "GOROOT"], text=True, env=env).strip())
    copy2(go_root / "LICENSE", directory / "go-LICENSE")
    modules = check_output(
        ["go", "list", "-buildvcs=false", "-deps", "-f",
         "{{if .Module}}{{.Module.Path}} {{.Module.Dir}}{{end}}", "."],
        cwd=project, env=env, text=True,
    )
    for module in sorted(set(filter(None, modules.splitlines()))):
        name, source = module.split(" ", 1)
        if Path(source).resolve() == project:
            continue
        for notice in Path(source).iterdir():
            if notice.is_file() and notice.name.upper().startswith(("LICENSE", "COPYING", "NOTICE")):
                copy2(notice, directory / (name.replace("/", "_") + "-" + notice.name))


def build(project, output, architecture):
    env = os.environ.copy()
    env.update(GOOS="linux", GOARCH=ARCHITECTURES[architecture], CGO_ENABLED="0", GOARM="7")
    manifest = {
        "name": "sparrow-chat.touchwrapper",
        "title": "Sparrow Chat",
        "description": "Lightweight native Telegram messenger",
        "version": VERSION,
        "architecture": architecture,
        "framework": "ubuntu-sdk-16.04.8",
        "maintainer": "Sparrow Chat <maintainer@example.invalid>",
        "hooks": {"sparrow-chat": {
            "apparmor": "sparrow-chat.apparmor",
            "desktop": "sparrow-chat.desktop",
        }},
    }
    apparmor = {"policy_groups": ["networking", "content_exchange_source"], "policy_version": 16.04}
    with TemporaryDirectory(prefix="sparrow-click-") as temporary:
        staging = Path(temporary) / "app"
        copytree(project / "app", staging)
        run(
            ["go", "build", "-buildvcs=false", "-p", "2", "-trimpath", "-ldflags=-s -w",
             "-o", str(staging / "sparrow-backend"), "."],
            cwd=project, env=env, check=True,
        )
        licenses(staging / "licenses", project, env)
        for name, data in [("manifest.json", manifest), ("sparrow-chat.apparmor", apparmor)]:
            (staging / name).write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
        staging.chmod(0o755)
        for path in staging.rglob("*"):
            executable = path.is_dir() or path.name == "sparrow-backend"
            path.chmod(0o755 if executable else 0o644)
        run(["click", "build", str(staging)], cwd=output, check=True)
        (output / f"sparrow-chat.touchwrapper_{VERSION}_{architecture}.click").chmod(0o644)


def main():
    project = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("architecture", choices=ARCHITECTURES)
    parser.add_argument("--output", type=Path, default=project / "dist")
    options = parser.parse_args()
    output = options.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    build(project, output, options.architecture)


if __name__ == "__main__":
    main()
