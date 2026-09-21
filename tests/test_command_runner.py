"""Tests for external command execution."""

import sys

import pytest

from dotfiles.command_runner import CommandFailure, CommandRunner


def test_capture_returns_stdout():
    output = CommandRunner().capture([sys.executable, "-c", "print('ok')"])

    assert output.strip() == "ok"


def test_capture_reports_command_failure():
    with pytest.raises(CommandFailure, match="failed"):
        CommandRunner().capture([sys.executable, "-c", "raise SystemExit(2)"])
