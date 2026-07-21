#!/usr/bin/env python3
"""Build the only supported artifact type: a platform-native debug portable ZIP."""

from __future__ import annotations

import argparse
import platform
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def platform_name() -> str:
    value = platform.system().lower()
    if value == "windows":
        return "win"
    if value == "darwin":
        return "mac"
    if value == "linux":
        return "linux"
    return value.replace(" ", "-")


def build() -> Path:
    name = "TimelapseManager"
    tag = platform_name()
    build_root = ROOT / "build" / "debug" / tag
    dist_root = build_root / "dist"
    work_root = build_root / "work"
    spec_root = build_root / "spec"
    command = [
        sys.executable,
        "-m",
        "PyInstaller",
        "--noconfirm",
        "--clean",
        "--onedir",
        "--console",
        "--name",
        name,
        "--paths",
        str(ROOT / "src"),
        "--distpath",
        str(dist_root),
        "--workpath",
        str(work_root),
        "--specpath",
        str(spec_root),
        str(ROOT / "timelapse.py"),
    ]
    subprocess.run(command, cwd=ROOT, check=True)
    application_dir = dist_root / name
    if not application_dir.is_dir():
        raise RuntimeError(f"PyInstaller 未生成预期目录: {application_dir}")

    config_dir = application_dir / "config"
    config_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT / "config" / "auto_timelapse.example.yaml", config_dir)
    shutil.copy2(ROOT / "config" / "webhook.example.yaml", config_dir)
    shutil.copy2(ROOT / "README.md", application_dir)
    shutil.copy2(ROOT / "requirements.txt", application_dir)

    timestamp = datetime.now().strftime("%y%m%d-%H%M%S")
    archive_dir = ROOT / "bin" / "Debug-Archives"
    archive_dir.mkdir(parents=True, exist_ok=True)
    archive_base = archive_dir / f"{name}-{tag}-debug-portable-{timestamp}"
    archive_path = Path(
        shutil.make_archive(
            str(archive_base),
            "zip",
            root_dir=dist_root,
            base_dir=name,
        )
    )
    return archive_path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.parse_args()
    archive = build()
    print(archive)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
