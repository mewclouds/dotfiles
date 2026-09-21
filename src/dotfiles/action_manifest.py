"""Load public and private action manifests."""

from __future__ import annotations

from pathlib import Path
from typing import Any

import yaml

from dotfiles.action import Action
from dotfiles.context import Context


class ActionManifest:
    """Resolve applicable actions from the public and private manifests."""

    PUBLIC_PATH = Path("actions.yml")
    PRIVATE_PATH = Path("private/actions.yml")

    def __init__(self, context: Context) -> None:
        self._context = context

    def actions(self) -> list[Action]:
        """Return public actions followed by applicable private actions."""
        public_path = self._context.repository_root / self.PUBLIC_PATH
        private_path = self._context.repository_root / self.PRIVATE_PATH

        return self._load(public_path, required=True) + self._load(private_path)

    def require_public_manifest(self) -> None:
        """Fail before mutation when the public action manifest is unavailable."""
        path = self._context.repository_root / self.PUBLIC_PATH

        if not path.is_file():
            raise FileNotFoundError(f"Public action manifest does not exist: {path}")

    def _load(self, path: Path, *, required: bool = False) -> list[Action]:
        if not path.is_file():
            if required:
                raise FileNotFoundError(f"Public action manifest does not exist: {path}")

            return []

        data = yaml.safe_load(path.read_text(encoding="utf-8"))

        if not isinstance(data, dict):
            raise ValueError(f"Action manifest must contain an object: {path}")

        if "actions" not in data:
            raise ValueError(f"Action manifest is missing its actions list: {path}")

        raw_actions = data["actions"]

        if not isinstance(raw_actions, list):
            raise ValueError(f"Manifest actions must be an array: {path}")

        actions: list[Action] = []

        for index, entry in enumerate(raw_actions, start=1):
            if not isinstance(entry, dict):
                raise ValueError(f"Action entry {index} must be an object: {path}")

            if not self._machine_matches(entry.get("machine")):
                continue

            actions.append(self._build_action(entry, path, index))

        return actions

    def _build_action(self, entry: dict[str, Any], path: Path, index: int) -> Action:
        missing = [key for key in ("id", "name", "description") if key not in entry]
        if missing:
            names = ", ".join(missing)
            raise ValueError(f"Action entry {index} is missing {names}: {path}")

        parameters = entry.get("parameters", {})
        if not isinstance(parameters, dict):
            raise ValueError(f"Action parameters must be an object: {path}:{index}")

        return Action(
            id=entry["id"],
            name=entry["name"],
            description=entry["description"],
            platform=entry.get("platform", "shared"),
            parameters=parameters,
            elevation=entry.get("elevation", "any"),
        )

    def _machine_matches(self, machine_filter: Any) -> bool:
        if machine_filter is None:
            return True

        targets = machine_filter if isinstance(machine_filter, list) else [machine_filter]
        normalized_targets = {str(target).casefold() for target in targets}

        return self._context.hostname.casefold() in normalized_targets
