"""Tests for declarative action manifest loading."""

import pytest

from dotfiles.action_manifest import ActionManifest
from dotfiles.context import Context


def test_manifest_loads_public_and_matching_private_actions(tmp_path):
    (tmp_path / "actions.yml").write_text(
        """
actions:
  - id: public_action
    name: run_command
    description: Public action
    parameters:
      command: [echo, public]
  - id: other_machine
    name: run_command
    description: Other machine
    machine: laptop
    parameters:
      command: [echo, other]
""",
        encoding="utf-8",
    )
    private_directory = tmp_path / "private"
    private_directory.mkdir()
    (private_directory / "actions.yml").write_text(
        """
actions:
  - id: private_action
    name: run_command
    description: Private action
    machine: DESKTOP
    parameters:
      command: [echo, private]
""",
        encoding="utf-8",
    )

    actions = ActionManifest(Context(repository_root=tmp_path, hostname="desktop")).actions()

    assert [action.id for action in actions] == ["public_action", "private_action"]


def test_manifest_rejects_missing_action_fields(tmp_path):
    (tmp_path / "actions.yml").write_text("actions:\n  - id: incomplete\n", encoding="utf-8")

    with pytest.raises(ValueError, match="missing name, description"):
        ActionManifest(Context(repository_root=tmp_path)).actions()


def test_manifest_requires_the_public_manifest(tmp_path):
    with pytest.raises(FileNotFoundError, match="Public action manifest does not exist"):
        ActionManifest(Context(repository_root=tmp_path)).actions()


@pytest.mark.parametrize(
    ("content", "message"),
    [
        ("", "must contain an object"),
        ("[]\n", "must contain an object"),
        ("{}\n", "missing its actions list"),
        ("action: []\n", "missing its actions list"),
    ],
)
def test_manifest_rejects_missing_or_invalid_action_lists(tmp_path, content, message):
    (tmp_path / "actions.yml").write_text(content, encoding="utf-8")

    with pytest.raises(ValueError, match=message):
        ActionManifest(Context(repository_root=tmp_path)).actions()
