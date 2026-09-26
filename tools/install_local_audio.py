"""Copy the user's local sounds into Openplanet storage without adding them to Git."""

from __future__ import annotations

import argparse
import shutil
from pathlib import Path


SUPPORTED = {".wav", ".ogg", ".mp3"}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", required=True, type=Path)
    parser.add_argument(
        "--file", action="append", dest="files", metavar="NAME",
        help="Copy one filename from the source directory; repeat as needed. "
             "If omitted, copy all WAV/OGG/MP3 files in that directory.",
    )
    parser.add_argument(
        "--target-dir", type=Path,
        default=Path.home() / "OpenplanetNext" / "PluginStorage" /
        "GorillaGripTrainer" / "LocalSounds",
    )
    args = parser.parse_args()
    if not args.source_dir.is_dir():
        parser.error(f"Source directory not found: {args.source_dir}")
    names = args.files or [
        path.name for path in args.source_dir.iterdir()
        if path.is_file() and path.suffix.lower() in SUPPORTED
    ]
    invalid = [name for name in names if Path(name).name != name or
               Path(name).suffix.lower() not in SUPPORTED]
    if invalid:
        parser.error("Expected audio basenames only: " + ", ".join(invalid))
    if not names:
        parser.error("No WAV, OGG, or MP3 files found")
    missing = [name for name in names if not (args.source_dir / name).is_file()]
    if missing:
        parser.error("Missing local clips: " + ", ".join(missing))
    args.target_dir.mkdir(parents=True, exist_ok=True)
    for name in names:
        shutil.copy2(args.source_dir / name, args.target_dir / name)
    print(f"Installed {len(names)} local clips in {args.target_dir}")


if __name__ == "__main__":
    main()
