"""Declarative action models and execution fingerprints."""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


@dataclass(frozen=True, slots=True)
class Action:
    """Describe one state change without coupling it to an implementation."""

    id: str
    name: str
    description: str
    platform: str = "shared"
    parameters: dict[str, Any] = field(default_factory=dict)
    elevation: str = "any"

    def __post_init__(self) -> None:
        object.__setattr__(self, "id", str(self.id))
        object.__setattr__(self, "name", str(self.name))
        object.__setattr__(self, "platform", str(self.platform))

        object.__setattr__(self, "parameters", dict(self.parameters))
        object.__setattr__(self, "elevation", str(self.elevation))

    def fingerprint(self, repository_root: Path) -> str:
        """Return a stable digest of the action and its declared input files."""
        input_paths = self.parameters.get("inputs", [])
        action_parameters = {key: value for key, value in self.parameters.items() if key != "inputs"}

        definition = {
            "id": self.id,
            "name": self.name,
            "platform": self.platform,
            "elevation": self.elevation,
            "parameters": action_parameters,
            "inputs": self._input_fingerprints(input_paths, repository_root),
        }

        canonical = self._canonicalize(definition)
        encoded = json.dumps(canonical, ensure_ascii=False, separators=(",", ":"))

        return hashlib.sha256(encoded.encode("utf-8")).hexdigest()

    @staticmethod
    def _input_fingerprints(input_paths: list[str], repository_root: Path) -> dict[str, str]:
        fingerprints: dict[str, str] = {}

        for input_path in input_paths:
            path = repository_root / input_path
            if not path.is_file():
                raise FileNotFoundError(f"Fingerprint input does not exist: {path}")

            fingerprints[str(input_path)] = hashlib.sha256(path.read_bytes()).hexdigest()

        return fingerprints

    @classmethod
    def _canonicalize(cls, value: Any) -> Any:
        if isinstance(value, dict):
            return {str(key): cls._canonicalize(value[key]) for key in sorted(value, key=str)}
        if isinstance(value, list):
            return [cls._canonicalize(item) for item in value]
        return value
