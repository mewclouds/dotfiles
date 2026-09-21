"""Tests for the non-destructive signing-key setup flow."""

from pathlib import Path

from dotfiles.context import Context
from dotfiles.signing_setup import SigningSetup
from tests.helpers import FakeRunner


def test_existing_signing_key_is_not_uploaded_twice(tmp_path):
    key_path = tmp_path / ".ssh" / "id_ed25519_signing"
    key_path.parent.mkdir()
    key_path.write_text("synthetic-private-key", encoding="utf-8")
    public_key = "ssh-ed25519 AAAA synthetic-key signing"
    Path(f"{key_path}.pub").write_text(public_key + "\n", encoding="utf-8")
    runner = FakeRunner(
        {
            ("gh", "auth", "status"): "authenticated",
            ("gh", "api", "user/ssh_signing_keys"): '[{"key":"ssh-ed25519 AAAA synthetic-key"}]',
        }
    )

    SigningSetup(Context(repository_root=tmp_path), home_directory=tmp_path, runner=runner).run()

    assert not any(command[1][:3] == ["gh", "ssh-key", "add"] for command in runner.commands)
