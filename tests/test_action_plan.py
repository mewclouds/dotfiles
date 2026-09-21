"""Tests for action models and platform filtering."""

import pytest

from dotfiles.action import Action
from dotfiles.plan import Plan


def test_plan_preserves_order_and_filters_platforms():
    plan = Plan(
        [
            Action("shared", "run_command", "Shared"),
            Action("linux", "run_command", "Linux", platform="linux"),
            Action("windows", "run_command", "Windows", platform="windows"),
        ]
    )

    assert [action.id for action in plan.for_platform("windows").actions] == ["shared", "windows"]


def test_plan_rejects_duplicate_ids():
    action = Action("same", "run_command", "One")

    with pytest.raises(ValueError, match="Duplicate action ID: same"):
        Plan([action, Action("same", "run_command", "Two")])


def test_action_fingerprint_changes_when_declared_input_changes(tmp_path):
    input_path = tmp_path / "input.txt"
    input_path.write_text("one", encoding="utf-8")
    action = Action("command", "run_command", "Command", parameters={"inputs": ["input.txt"]})

    first = action.fingerprint(tmp_path)
    input_path.write_text("two", encoding="utf-8")

    assert action.fingerprint(tmp_path) != first


def test_action_fingerprint_includes_elevation(tmp_path):
    user_action = Action("command", "run_command", "Command", elevation="user")
    admin_action = Action("command", "run_command", "Command", elevation="admin")

    assert user_action.fingerprint(tmp_path) != admin_action.fingerprint(tmp_path)
