"""External command execution with captured and interactive modes."""

from __future__ import annotations

import subprocess
from collections.abc import Mapping, Sequence
from pathlib import Path


class CommandFailure(RuntimeError):
    """Indicate that an external command returned a failure status."""


class CommandRunner:
    """Run commands without invoking a shell."""

    def capture(
        self,
        command: Sequence[str],
        cwd: Path | None = None,
        env: Mapping[str, str] | None = None,
    ) -> str:
        """Return standard output or raise with the command failure details."""
        completed = subprocess.run(
            list(command),
            cwd=cwd,
            env=env,
            capture_output=True,
            text=True,
            check=False,
        )
        if completed.returncode == 0:
            return completed.stdout

        output = completed.stderr or completed.stdout
        message = output if output.strip() else f"command failed ({completed.returncode}): {' '.join(command)}"

        raise CommandFailure(message)

    def interactive(
        self,
        command: Sequence[str],
        cwd: Path | None = None,
        env: Mapping[str, str] | None = None,
    ) -> None:
        """Run a command with the current terminal attached."""
        completed = subprocess.run(list(command), cwd=cwd, env=env, check=False)

        if completed.returncode != 0:
            raise CommandFailure(f"command failed ({completed.returncode}): {' '.join(command)}")
