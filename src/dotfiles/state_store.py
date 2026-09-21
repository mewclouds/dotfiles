"""Persistent state for successfully completed command actions."""

from __future__ import annotations

import json
import os
import tempfile
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path

from dotfiles.action import Action


class StateStore:
    """Read and atomically update local command execution state."""

    VERSION = 1

    def __init__(self, path: Path) -> None:
        self._path = Path(path)

        self._actions = self._load()

    def completed(self, action: Action, fingerprint: str) -> bool:
        """Return whether an action has the requested completed fingerprint."""
        entry = self._actions.get(action.id)

        return bool(entry and entry["fingerprint"] == fingerprint)

    def record(self, action: Action, fingerprint: str) -> None:
        """Record a successful action without losing concurrent updates."""
        with self._exclusive_lock():
            updated = {
                **self._load(),
                action.id: {"status": "completed", "fingerprint": fingerprint},
            }

            self._save(updated)
            self._actions = updated

    @contextmanager
    def _exclusive_lock(self) -> Iterator[None]:
        self._path.parent.mkdir(parents=True, exist_ok=True)
        lock_path = self._path.with_name(f"{self._path.name}.lock")

        with lock_path.open("a+b") as lock_file:
            lock_file.seek(0, os.SEEK_END)

            if lock_file.tell() == 0:
                lock_file.write(b"\0")
                lock_file.flush()

            lock_file.seek(0)

            if os.name == "nt":
                import msvcrt

                msvcrt.locking(lock_file.fileno(), msvcrt.LK_LOCK, 1)

                try:
                    yield
                finally:
                    lock_file.seek(0)
                    msvcrt.locking(lock_file.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                import fcntl

                fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)

                try:
                    yield
                finally:
                    fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)

    def _load(self) -> dict[str, dict[str, str]]:
        if not self._path.is_file():
            return {}

        try:
            data = json.loads(self._path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as error:
            raise ValueError(f"Could not read orchestration state: {error}") from error

        if not isinstance(data, dict):
            raise ValueError("State file must contain a JSON object.")

        if data.get("version") != self.VERSION:
            if "version" not in data:
                raise ValueError("Orchestration state is missing its version.")
            raise ValueError(f"Unsupported orchestration state version: {data['version']}")

        actions = data.get("actions")

        if not isinstance(actions, dict):
            raise ValueError("State file actions must be an object.")

        for action_id, entry in actions.items():
            valid = (
                isinstance(entry, dict)
                and entry.get("status") == "completed"
                and isinstance(entry.get("fingerprint"), str)
            )
            if not valid:
                raise ValueError(f"Invalid orchestration state entry: {action_id}")
        return actions

    def _save(self, actions: dict[str, dict[str, str]]) -> None:
        self._path.parent.mkdir(parents=True, exist_ok=True)
        temporary_path: str | None = None
        try:
            file_descriptor, temporary_path = tempfile.mkstemp(
                prefix=f"{self._path.name}.tmp-",
                dir=self._path.parent,
                text=True,
            )
            with os.fdopen(file_descriptor, "w", encoding="utf-8") as output:
                json.dump({"version": self.VERSION, "actions": actions}, output, indent=2)
                output.write("\n")

            os.replace(temporary_path, self._path)
            temporary_path = None
        finally:
            if temporary_path:
                Path(temporary_path).unlink(missing_ok=True)
