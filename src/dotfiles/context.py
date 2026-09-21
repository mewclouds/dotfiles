"""Runtime context used to resolve platform-specific actions."""

from __future__ import annotations

import platform as platform_module
import socket
import sys
from dataclasses import dataclass, field
from pathlib import Path


def default_repository_root() -> Path:
    """Return the repository root that contains the Python source tree."""
    return Path(__file__).resolve().parents[2]


@dataclass(frozen=True, slots=True)
class Context:
    """Capture the runtime facts that affect one orchestration run."""

    host_os: str = field(default_factory=lambda: sys.platform)
    python_version: str = field(default_factory=platform_module.python_version)
    repository_root: Path = field(default_factory=default_repository_root)
    hostname: str = field(default_factory=socket.gethostname)
    platform_name: str = field(init=False)

    def __post_init__(self) -> None:
        object.__setattr__(self, "repository_root", Path(self.repository_root))

        object.__setattr__(self, "platform_name", self.determine_platform(self.host_os))

    @property
    def platform(self) -> str:
        """Return the friendly platform and its raw host identifier."""
        return f"{self.platform_name} ({self.host_os})"

    @staticmethod
    def determine_platform(host_os: str) -> str:
        """Map a runtime identifier to the supported platform name."""
        normalized = host_os.lower()

        if normalized.startswith(("win", "mswin", "mingw", "cygwin")):
            return "windows"
        if "linux" in normalized:
            return "linux"
        return "unknown"
