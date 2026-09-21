"""Tests for the user-facing command-line entry point."""

from io import StringIO

import pytest

from dotfiles.cli import main


def test_status_reports_runtime_context():
    output = StringIO()

    assert main(["status"], output_stream=output) == 0
    assert "Dotfiles orchestrator" in output.getvalue()
    assert "Python:" in output.getvalue()


def test_plan_uses_the_explicit_repository_root(tmp_path):
    (tmp_path / "actions.yml").write_text("actions: []\n", encoding="utf-8")
    output = StringIO()

    assert main(["--repository-root", str(tmp_path), "plan"], output_stream=output) == 0
    assert "No actions planned." in output.getvalue()


def test_apply_fails_before_private_state_when_the_manifest_is_missing(tmp_path, monkeypatch):
    decrypted = False

    def decrypt(_private_state):
        nonlocal decrypted
        decrypted = True

    monkeypatch.setattr("dotfiles.cli.PrivateState.decrypt", decrypt)

    with pytest.raises(FileNotFoundError, match="Public action manifest does not exist"):
        main(["--repository-root", str(tmp_path), "apply"], output_stream=StringIO())

    assert not decrypted
