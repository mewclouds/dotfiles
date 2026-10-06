"""Clone the pouch repository into the home directory and link its contents."""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

REPOSITORY = "git@github.com:mewclouds/pouch.git"
DIRECTORY_NAME = "pouch"
ENTRY_POINT = "pouch.py"


def main(arguments: list[str] | None = None) -> int:
    """Clone pouch into ~/ when missing, then run its link step."""
    parser = argparse.ArgumentParser(description="Clone pouch and link its contents.")
    parser.add_argument("--repository", default=REPOSITORY, help="Pouch Git URL (default: %(default)s)")
    parser.add_argument(
        "--destination",
        type=Path,
        default=Path.home() / DIRECTORY_NAME,
        help="Checkout directory (default: %(default)s)",
    )
    options = parser.parse_args(arguments)

    try:
        ensure_clone(options.destination, options.repository)
        run_link_step(options.destination)
    except (OSError, subprocess.CalledProcessError, RuntimeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


def ensure_clone(destination: Path, repository: str) -> None:
    """Clone the repository unless the destination already looks like pouch."""
    if (destination / ENTRY_POINT).is_file():
        print(f"present: {destination}")
        return

    if destination.exists() and any(destination.iterdir()):
        raise RuntimeError(f"Refusing to clone into non-empty directory: {destination}")

    if shutil.which("git") is None:
        raise RuntimeError("Git is required to clone pouch but was not found on PATH.")

    print(f"cloning: {repository} -> {destination}")
    subprocess.run(["git", "clone", repository, str(destination)], check=True)


def run_link_step(destination: Path) -> None:
    """Run pouch's link step inside an existing checkout."""
    entry_point = destination / ENTRY_POINT
    if not entry_point.is_file():
        raise RuntimeError(f"Pouch checkout does not contain {ENTRY_POINT}: {destination}")

    print(f"linking: {entry_point} install")
    subprocess.run([sys.executable, ENTRY_POINT, "install"], cwd=destination, check=True)


if __name__ == "__main__":
    sys.exit(main())
