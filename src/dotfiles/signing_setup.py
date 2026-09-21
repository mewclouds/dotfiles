"""Interactive GitHub SSH signing-key setup."""

from __future__ import annotations

import json
from pathlib import Path
from typing import TextIO

from dotfiles.command_runner import CommandFailure, CommandRunner
from dotfiles.context import Context


class SigningSetup:
    """Prepare a local signing key without deleting existing keys."""

    DEFAULT_KEY_NAME = "id_ed25519_signing"

    def __init__(
        self,
        context: Context,
        input_stream: TextIO | None = None,
        output_stream: TextIO | None = None,
        home_directory: Path | None = None,
        runner: CommandRunner | None = None,
    ) -> None:
        self.context = context
        self.input_stream = input_stream
        self.output_stream = output_stream
        self.home_directory = Path.home() if home_directory is None else Path(home_directory)
        self.runner = runner or CommandRunner()

        self.key_title: str | None = None

    def run(self) -> None:
        """Run the interactive signing setup flow."""
        self._ensure_github_authentication()
        key_path = self.home_directory / ".ssh" / self.DEFAULT_KEY_NAME

        if not key_path.is_file():
            self._generate_key(key_path)

        if key_path.is_file():
            public_key_path = Path(f"{key_path}.pub")

            if not self._github_has_signing_key(public_key_path):
                self._upload_key(public_key_path)

    def _ensure_github_authentication(self) -> None:
        try:
            self.runner.capture(["gh", "auth", "status"])
        except CommandFailure as error:
            message = f"GitHub CLI is not authenticated. Run `gh auth login` first.\n{error}"
            raise RuntimeError(message) from error

    def _generate_key(self, key_path: Path) -> None:
        if not self._ask("No SSH signing key exists. Generate one now?", default=False):
            return

        self.key_title = self._ask_text(
            "GitHub key title",
            default=self._default_title(),
        )
        key_path.parent.mkdir(parents=True, exist_ok=True)

        command = [
            "ssh-keygen",
            "-t",
            "ed25519",
            "-C",
            self.key_title,
            "-f",
            str(key_path),
        ]
        self.runner.interactive(command)

    def _github_has_signing_key(self, public_key_path: Path) -> bool:
        self._ensure_github_signing_key_scope()
        public_key = public_key_path.read_text(encoding="utf-8").strip()

        try:
            response = self.runner.capture(["gh", "api", "user/ssh_signing_keys"])
            keys = json.loads(response)
        except json.JSONDecodeError as error:
            raise RuntimeError(f"Could not read the SSH keys returned by GitHub CLI: {error}") from error

        if not isinstance(keys, list) or not all(
            isinstance(key, dict) and isinstance(key.get("key"), str) for key in keys
        ):
            raise RuntimeError("GitHub returned an unexpected SSH signing-key response.")

        return any(self._key_material(key["key"]) == self._key_material(public_key) for key in keys)

    def _ensure_github_signing_key_scope(self) -> None:
        try:
            command = [
                "gh",
                "auth",
                "refresh",
                "-h",
                "github.com",
                "-s",
                "admin:ssh_signing_key",
            ]
            self.runner.interactive(command)
        except CommandFailure as error:
            raise RuntimeError(
                "GitHub CLI could not obtain the SSH signing-key permission. "
                "Run `gh auth refresh -h github.com -s admin:ssh_signing_key` and try again.\n"
                f"{error}"
            ) from error

    def _upload_key(self, public_key_path: Path) -> None:
        if not self._ask("Upload this key to GitHub as a signing key?", default=True):
            return

        self.key_title = self.key_title or self._ask_text(
            "GitHub key title",
            default=self._default_title(),
        )

        self.runner.capture(
            [
                "gh",
                "ssh-key",
                "add",
                str(public_key_path),
                "--type",
                "signing",
                "--title",
                self.key_title,
            ]
        )

    @staticmethod
    def _key_material(public_key: str) -> str:
        return " ".join(public_key.split()[:2])

    def _default_title(self) -> str:
        return f"{self.context.platform_name.capitalize()} - SSH signing"

    def _ask(self, question: str, default: bool) -> bool:
        answer = self._read(f"{question} {'[Y/n]' if default else '[y/N]'} ")

        if answer is None or not answer.strip():
            return default

        return answer.strip().casefold() in {"y", "yes"}

    def _ask_text(self, question: str, default: str) -> str:
        answer = self._read(f"{question} [{default}]: ")

        return default if answer is None or not answer.strip() else answer.strip()

    def _read(self, prompt: str) -> str | None:
        if self.output_stream is not None:
            self.output_stream.write(prompt)
            self.output_stream.flush()

        if self.input_stream is None:
            return input()

        return self.input_stream.readline().rstrip("\r\n") or None
