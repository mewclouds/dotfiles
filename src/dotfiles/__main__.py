"""Command-line entry point for the dotfiles orchestrator."""

from __future__ import annotations

import argparse
import platform
import sys
from collections.abc import Sequence
from pathlib import Path


def repository_root() -> Path:
    """Return the repository root that contains this source tree."""
    return Path(__file__).resolve().parents[2]


def show_status() -> None:
    """Print the runtime and repository context."""
    print("Dotfiles orchestrator")
    print(f"Platform: {platform.system().lower()} ({sys.platform})")
    print(f"Python: {platform.python_version()}")
    print(f"Repository: {repository_root()}")


def build_parser() -> argparse.ArgumentParser:
    """Build the command-line parser."""
    parser = argparse.ArgumentParser(prog="dotfiles")
    subcommands = parser.add_subparsers(dest="command")
    subcommands.add_parser("status", help="Report the runtime and repository context")
    return parser


def main(arguments: Sequence[str] | None = None) -> int:
    """Run the command-line interface."""
    parser = build_parser()
    options = parser.parse_args(arguments)

    if options.command == "status":
        show_status()
    else:
        parser.print_help()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
