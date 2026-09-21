"""Test doubles for external command execution."""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from pathlib import Path


class FakeRunner:
    """Record commands and return configured output without changing the host."""

    def __init__(self, responses: dict[tuple[str, ...], str] | None = None) -> None:
        self.responses = responses or {}
        self.commands: list[tuple[str, list[str], Path | None, Mapping[str, str] | None]] = []

    def capture(
        self,
        command: Sequence[str],
        cwd: Path | None = None,
        env: Mapping[str, str] | None = None,
    ) -> str:
        recorded_command = list(command)
        self.commands.append(("capture", recorded_command, cwd, env))

        return self.responses.get(tuple(recorded_command), "")

    def interactive(
        self,
        command: Sequence[str],
        cwd: Path | None = None,
        env: Mapping[str, str] | None = None,
    ) -> None:
        self.commands.append(("interactive", list(command), cwd, env))
