"""Tests for private-state safety checks."""

import os
import zipfile
from io import StringIO

import pytest

from dotfiles.private_state import PrivateState
from tests.helpers import FakeRunner


def test_decrypt_does_not_overwrite_existing_private_state(tmp_path):
    private_directory = tmp_path / "private"
    private_directory.mkdir()
    (private_directory / "config.txt").write_text("private", encoding="utf-8")
    output = StringIO()
    runner = FakeRunner()
    state = PrivateState(tmp_path, output_stream=output, runner=runner, private_directory=private_directory)

    assert state.decrypt() == "already_present"
    assert not runner.commands
    assert "skipping" in output.getvalue()


def test_encrypt_reports_a_missing_script(tmp_path):
    state = PrivateState(tmp_path, runner=FakeRunner(), encrypt_script=tmp_path / "missing.ps1")

    assert state.encrypt() == "missing_script"


def test_private_archive_uses_zip_extraction(tmp_path):
    archive_path = tmp_path / "archive.zip"

    with zipfile.ZipFile(archive_path, "w") as archive:
        archive.writestr("private/config.txt", "private")

    state = PrivateState(tmp_path, runner=FakeRunner())
    state._extract_archive(archive_path)

    assert (tmp_path / "private/config.txt").read_text(encoding="utf-8") == "private"


def test_private_archive_rejects_paths_outside_the_destination(tmp_path):
    archive_path = tmp_path / "archive.zip"

    with zipfile.ZipFile(archive_path, "w") as archive:
        archive.writestr("../outside.txt", "unsafe")

    state = PrivateState(tmp_path, runner=FakeRunner())

    with pytest.raises(RuntimeError, match="unsafe path"):
        state._extract_archive(archive_path)

    assert not (tmp_path / "outside.txt").exists()
    assert not (tmp_path / "private").exists()


def test_private_install_failure_does_not_leave_partial_state(tmp_path, monkeypatch):
    archive_path = tmp_path / "archive.zip"

    with zipfile.ZipFile(archive_path, "w") as archive:
        archive.writestr("private/config.txt", "private")

    def fail_to_copy(_source, _target):
        raise OSError("synthetic private copy failure")

    monkeypatch.setattr("dotfiles.private_state.shutil.copy2", fail_to_copy)
    state = PrivateState(tmp_path, runner=FakeRunner())

    with pytest.raises(OSError, match="synthetic private copy failure"):
        state._extract_archive(archive_path)

    assert not (tmp_path / "private").exists()


def test_bitwarden_session_is_passed_only_through_the_child_environment(tmp_path):
    session = "synthetic-session"
    responses = {
        ("bw", "status"): '{"status":"unlocked"}',
        ("bw", "get", "notes", PrivateState.BITWARDEN_ITEM_NAME): "synthetic-identity",
    }
    runner = FakeRunner(responses)
    state = PrivateState(tmp_path, runner=runner)
    state.session_key = session

    assert state._retrieve_identity() == "synthetic-identity"

    for _, command, _, environment in runner.commands:
        assert session not in command
        assert environment is not None
        assert environment["BW_SESSION"] == session


def test_bitwarden_unlock_does_not_change_the_process_environment(tmp_path, monkeypatch):
    monkeypatch.delenv("BW_PASSWORD", raising=False)
    monkeypatch.delenv("BW_SESSION", raising=False)
    command = ("bw", "unlock", "--passwordenv", "BW_PASSWORD", "--raw")
    runner = FakeRunner({command: "synthetic-session"})
    state = PrivateState(tmp_path, input_stream=StringIO("synthetic-password\n"), runner=runner)

    state._unlock_vault()

    assert state.session_key == "synthetic-session"
    assert "BW_PASSWORD" not in os.environ
    assert "BW_SESSION" not in os.environ
