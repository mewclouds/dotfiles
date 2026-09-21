"""Tests for persistent command action state."""

from dotfiles.action import Action
from dotfiles.state_store import StateStore


def test_state_store_round_trips_completed_action(tmp_path):
    path = tmp_path / ".local" / "state.json"
    action = Action("command", "run_command", "Command")
    store = StateStore(path)

    assert not store.completed(action, "first")
    store.record(action, "first")

    assert StateStore(path).completed(action, "first")
    assert not StateStore(path).completed(action, "changed")


def test_state_store_merges_records_from_stale_instances(tmp_path):
    path = tmp_path / ".local" / "state.json"
    first_action = Action("first", "run_command", "First")
    second_action = Action("second", "run_command", "Second")
    first_store = StateStore(path)
    second_store = StateStore(path)

    first_store.record(first_action, "first-fingerprint")
    second_store.record(second_action, "second-fingerprint")

    stored = StateStore(path)

    assert stored.completed(first_action, "first-fingerprint")
    assert stored.completed(second_action, "second-fingerprint")
