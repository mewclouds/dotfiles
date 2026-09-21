"""Tests for filesystem and command action execution."""

import os

import pytest

from dotfiles.action import Action
from dotfiles.command_runner import CommandFailure
from dotfiles.executor import Executor
from dotfiles.plan import Plan
from tests.helpers import FakeRunner


def test_copy_action_is_idempotent(tmp_path):
    source = tmp_path / "source.txt"
    source.write_text("content", encoding="utf-8")
    target = tmp_path / "target.txt"
    action = Action(
        "copy",
        "copy_file",
        "Copy a file",
        parameters={"source": "source.txt", "target": str(target)},
    )

    executor = Executor(tmp_path)

    plan = Plan([action])

    assert executor.execute(plan) == ["copied"]
    assert executor.status(action) == "already_copied"
    assert target.read_text(encoding="utf-8") == "content"


def test_link_action_refuses_to_replace_existing_file(tmp_path):
    source = tmp_path / "source.txt"
    source.write_text("source", encoding="utf-8")
    target = tmp_path / "target.txt"
    target.write_text("unmanaged", encoding="utf-8")
    action = Action(
        "link",
        "link_file",
        "Link a file",
        parameters={"source": "source.txt", "target": str(target)},
    )

    with pytest.raises(FileExistsError, match="Refusing to replace"):
        Executor(tmp_path).execute(Plan([action]))


def test_link_action_preserves_existing_file_when_staging_fails(tmp_path, monkeypatch):
    source = tmp_path / "source.txt"
    source.write_text("source", encoding="utf-8")
    target = tmp_path / "target.txt"
    target.write_text("unmanaged", encoding="utf-8")
    action = Action(
        "link",
        "link_file",
        "Link a file",
        parameters={"source": "source.txt", "target": str(target)},
    )
    executor = Executor(tmp_path, clean=True)

    def fail_to_create_link(_source, _target, _elevation):
        raise OSError("synthetic link failure")

    monkeypatch.setattr(executor, "_create_symlink", fail_to_create_link)

    with pytest.raises(OSError, match="synthetic link failure"):
        executor.execute(Plan([action]))

    assert target.read_text(encoding="utf-8") == "unmanaged"


def test_link_action_replaces_an_existing_file_with_clean(tmp_path):
    source = tmp_path / "source.txt"
    source.write_text("managed", encoding="utf-8")
    target = tmp_path / "target.txt"
    target.write_text("unmanaged", encoding="utf-8")
    action = Action(
        "link",
        "link_file",
        "Link a file",
        parameters={"source": "source.txt", "target": str(target)},
    )

    assert Executor(tmp_path, clean=True).execute(Plan([action])) == ["linked"]
    assert target.is_symlink()
    assert target.resolve() == source.resolve()


def test_link_action_replaces_a_different_link_with_clean(tmp_path):
    source = tmp_path / "source.txt"
    source.write_text("managed", encoding="utf-8")
    old_source = tmp_path / "old-source.txt"
    old_source.write_text("unmanaged", encoding="utf-8")
    target = tmp_path / "target.txt"

    try:
        target.symlink_to(old_source)
    except OSError as error:
        pytest.skip(f"Symbolic links are unavailable: {error}")

    action = Action(
        "link",
        "link_file",
        "Link a file",
        parameters={"source": "source.txt", "target": str(target)},
    )

    assert Executor(tmp_path, clean=True).execute(Plan([action])) == ["linked"]
    assert target.resolve() == source.resolve()


def test_copy_action_requires_clean_to_replace_a_different_file(tmp_path):
    source = tmp_path / "source.txt"
    source.write_text("managed", encoding="utf-8")
    target = tmp_path / "target.txt"
    target.write_text("unmanaged", encoding="utf-8")
    action = Action(
        "copy",
        "copy_file",
        "Copy a file",
        parameters={"source": "source.txt", "target": str(target)},
    )

    with pytest.raises(FileExistsError, match="Refusing to replace"):
        Executor(tmp_path).execute(Plan([action]))

    assert target.read_text(encoding="utf-8") == "unmanaged"


def test_copy_action_replaces_a_different_file_with_clean(tmp_path):
    source = tmp_path / "source.txt"
    source.write_text("managed", encoding="utf-8")
    target = tmp_path / "target.txt"
    target.write_text("unmanaged", encoding="utf-8")
    action = Action(
        "copy",
        "copy_file",
        "Copy a file",
        parameters={"source": "source.txt", "target": str(target)},
    )

    assert Executor(tmp_path, clean=True).execute(Plan([action])) == ["copied"]
    assert target.read_text(encoding="utf-8") == "managed"


def test_copy_action_preserves_existing_file_when_staging_fails(tmp_path, monkeypatch):
    source = tmp_path / "source.txt"
    source.write_text("managed", encoding="utf-8")
    target = tmp_path / "target.txt"
    target.write_text("unmanaged", encoding="utf-8")
    action = Action(
        "copy",
        "copy_file",
        "Copy a file",
        parameters={"source": "source.txt", "target": str(target)},
    )

    def fail_to_copy(_source, _target):
        raise OSError("synthetic copy failure")

    monkeypatch.setattr("dotfiles.executor.shutil.copy2", fail_to_copy)

    with pytest.raises(OSError, match="synthetic copy failure"):
        Executor(tmp_path, clean=True).execute(Plan([action]))

    assert target.read_text(encoding="utf-8") == "unmanaged"


def test_command_action_runs_once_per_input_fingerprint(tmp_path):
    input_path = tmp_path / "input.txt"
    input_path.write_text("one", encoding="utf-8")
    action = Action(
        "command",
        "run_command",
        "Run a command",
        parameters={"command": ["example"], "inputs": ["input.txt"]},
    )
    runner = FakeRunner()
    executor = Executor(tmp_path, runner=runner)
    plan = Plan([action])

    assert executor.execute(plan) == ["executed"]
    assert executor.execute(plan) == ["already_applied"]
    input_path.write_text("two", encoding="utf-8")
    assert executor.execute(plan) == ["executed"]
    assert len(runner.commands) == 2


def test_elevated_command_failure_is_not_recorded(tmp_path):
    action = Action(
        "command",
        "run_command",
        "Run an elevated command",
        parameters={"command": ["example"]},
        elevation="admin",
    )

    class FailingRunner(FakeRunner):
        def interactive(self, command, cwd=None, env=None):
            super().interactive(command, cwd=cwd, env=env)
            raise CommandFailure("synthetic elevation failure")

    executor = Executor(tmp_path, runner=FailingRunner())
    fingerprint = action.fingerprint(tmp_path)

    with pytest.raises(CommandFailure, match="synthetic elevation failure"):
        executor.execute(Plan([action]))

    assert not executor.state_store.completed(action, fingerprint)


def test_linux_elevated_command_uses_sudo(tmp_path):
    action = Action(
        "command",
        "run_command",
        "Run an elevated command",
        parameters={"command": ["example", "argument"]},
        elevation="admin",
    )
    runner = FakeRunner()

    assert Executor(tmp_path, runner=runner, platform_name="linux").execute(Plan([action])) == ["executed"]
    assert runner.commands[0][1] == ["sudo", "--", "example", "argument"]
    assert runner.commands[0][2] == tmp_path


def test_linux_elevated_link_uses_sudo_after_permission_error(tmp_path, monkeypatch):
    source = tmp_path / "source.txt"
    source.write_text("managed", encoding="utf-8")
    target = tmp_path / "target.txt"

    class SymlinkRunner(FakeRunner):
        def interactive(self, command, cwd=None, env=None):
            super().interactive(command, cwd=cwd, env=env)
            os.symlink(command[-2], command[-1])

    def deny_direct_symlink(_path, _target):
        raise PermissionError("synthetic permission failure")

    monkeypatch.setattr("pathlib.Path.symlink_to", deny_direct_symlink)
    runner = SymlinkRunner()
    executor = Executor(tmp_path, runner=runner, platform_name="linux")

    executor._create_symlink(source, target, "admin")

    assert runner.commands[0][1] == ["sudo", "--", "ln", "-s", "--", str(source), str(target)]
    assert target.resolve() == source.resolve()


def test_elevation_rejects_an_unsupported_platform(tmp_path):
    executor = Executor(tmp_path, runner=FakeRunner(), platform_name="unknown")

    with pytest.raises(RuntimeError, match="not supported on unknown"):
        executor._run_elevated(["example"])
