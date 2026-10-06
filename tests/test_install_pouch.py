"""Tests for the pouch bootstrap script."""

from __future__ import annotations

import importlib.util
import subprocess
import sys
from pathlib import Path

SCRIPT_PATH = Path(__file__).resolve().parents[1] / "scripts" / "system" / "install_pouch.py"


def load_script(tmp_path: Path):
    """Load the standalone script without importing it as a package module."""
    module_name = f"install_pouch_{tmp_path.name}"
    spec = importlib.util.spec_from_file_location(module_name, SCRIPT_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


def test_skips_clone_when_pouch_is_already_present(tmp_path, monkeypatch):
    module = load_script(tmp_path)
    destination = tmp_path / "pouch"
    destination.mkdir()
    (destination / "pouch.py").write_text("# pouch", encoding="utf-8")

    calls: list[list[str]] = []

    def fake_run(command, **kwargs):
        calls.append(list(command))
        return subprocess.CompletedProcess(command, 0)

    monkeypatch.setattr(module.subprocess, "run", fake_run)

    assert module.main(["--destination", str(destination)]) == 0
    assert calls == [[sys.executable, "pouch.py", "install"]]


def test_clones_when_the_destination_is_missing(tmp_path, monkeypatch):
    module = load_script(tmp_path)
    destination = tmp_path / "pouch"

    calls: list[list[str]] = []

    def fake_run(command, **kwargs):
        calls.append(list(command))
        if command[:2] == ["git", "clone"]:
            Path(command[3]).mkdir(parents=True)
            (Path(command[3]) / "pouch.py").write_text("# pouch", encoding="utf-8")
        return subprocess.CompletedProcess(command, 0)

    monkeypatch.setattr(module.subprocess, "run", fake_run)
    monkeypatch.setattr(module.shutil, "which", lambda _command: "git")

    assert module.main(["--destination", str(destination)]) == 0
    assert calls[0] == ["git", "clone", module.REPOSITORY, str(destination)]
    assert calls[1] == [sys.executable, "pouch.py", "install"]


def test_refuses_a_non_empty_destination_without_pouch(tmp_path, monkeypatch):
    module = load_script(tmp_path)
    destination = tmp_path / "pouch"
    destination.mkdir()
    (destination / "unrelated.txt").write_text("unmanaged", encoding="utf-8")

    monkeypatch.setattr(
        module.subprocess,
        "run",
        lambda *args, **kwargs: (_ for _ in ()).throw(AssertionError("must not run commands")),
    )

    assert module.main(["--destination", str(destination)]) == 1


def test_reports_missing_git_for_a_fresh_destination(tmp_path, monkeypatch):
    module = load_script(tmp_path)

    monkeypatch.setattr(module.shutil, "which", lambda _command: None)

    assert module.main(["--destination", str(tmp_path / "pouch")]) == 1


def test_main_returns_nonzero_when_the_link_step_fails(tmp_path, monkeypatch):
    module = load_script(tmp_path)
    destination = tmp_path / "pouch"
    destination.mkdir()
    (destination / "pouch.py").write_text("# pouch", encoding="utf-8")

    def fake_run(command, **kwargs):
        raise subprocess.CalledProcessError(1, command)

    monkeypatch.setattr(module.subprocess, "run", fake_run)

    assert module.main(["--destination", str(destination)]) == 1
