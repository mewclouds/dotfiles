"""Coordinate encrypted private-state archive operations."""

from __future__ import annotations

import getpass
import json
import os
import shutil
import stat
import sys
import tempfile
import zipfile
from contextlib import suppress
from pathlib import Path, PurePosixPath
from typing import TextIO

from dotfiles.command_runner import CommandFailure, CommandRunner


class PrivateState:
    """Decrypt private state without overwriting an existing private workspace."""

    BITWARDEN_ITEM_NAME = "dotfiles-age-keys"

    def __init__(
        self,
        repository_root: Path,
        input_stream: TextIO | None = None,
        output_stream: TextIO | None = None,
        runner: CommandRunner | None = None,
        private_directory: Path | None = None,
        archive_path: Path | None = None,
        encrypt_script: Path | None = None,
    ) -> None:
        self.repository_root = Path(repository_root)
        self.input_stream = input_stream
        self.output_stream = output_stream
        self.runner = runner or CommandRunner()

        self.private_directory = private_directory or self.repository_root / "private"
        self.archive_path = archive_path or self.repository_root / "private.age"
        self.encrypt_script = encrypt_script or self.repository_root / "scripts/system/Encrypt-Private.ps1"
        self.session_key = os.environ.get("BW_SESSION")

    def present(self) -> bool:
        """Return whether the private workspace contains files."""
        return self.private_directory.is_dir() and any(self.private_directory.iterdir())

    def archive_exists(self) -> bool:
        """Return whether the encrypted archive exists."""
        return self.archive_path.is_file()

    def encrypt_script_exists(self) -> bool:
        """Return whether the private-state encryption script exists."""
        return self.encrypt_script.is_file()

    def encrypt(self) -> str:
        """Encrypt the private workspace through the repository script."""
        if not self.encrypt_script_exists():
            return "missing_script"

        command = [
            self._powershell_command(),
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(self.encrypt_script),
            "-RepositoryRoot",
            str(self.repository_root),
        ]

        self.runner.interactive(command)

        return "encrypted"

    def decrypt(self) -> str:
        """Decrypt and extract private state when it is not already present."""
        if self.present():
            self._write("Private state already present; skipping decryption.\n")
            return "already_present"

        if not self.archive_exists():
            return "missing_archive"

        identity = self._retrieve_identity()

        try:
            with tempfile.TemporaryDirectory(prefix="dotfiles-decrypt-") as temporary_directory:
                temporary_path = Path(temporary_directory)
                identity_path = temporary_path / "identity.txt"
                archive_path = temporary_path / "archive"

                identity_path.write_text(identity, encoding="utf-8")
                with suppress(OSError):
                    identity_path.chmod(0o600)

                self._write(f"Decrypting private state from {self.archive_path.name}...\n")
                self.runner.capture(
                    [
                        "age",
                        "--decrypt",
                        "-i",
                        str(identity_path),
                        "-o",
                        str(archive_path),
                        str(self.archive_path),
                    ]
                )
                self._extract_archive(archive_path)
                self._write("Private state decrypted successfully.\n")

        except CommandFailure as error:
            raise RuntimeError(
                f"Failed to decrypt private state archive '{self.archive_path.name}'.\n{error}"
            ) from error
        return "decrypted"

    def _retrieve_identity(self) -> str:
        self._ensure_authenticated_and_unlocked()
        command = ["bw", "get", "notes", self.BITWARDEN_ITEM_NAME]

        try:
            identity = self.runner.capture(command, env=self._bitwarden_environment()).strip()
        except CommandFailure as error:
            message = f"Bitwarden CLI failed to retrieve '{self.BITWARDEN_ITEM_NAME}'.\n{error}"
            raise RuntimeError(message) from error

        if not identity:
            message = f"Could not retrieve '{self.BITWARDEN_ITEM_NAME}' from Bitwarden. The note is empty."
            raise RuntimeError(message)

        return identity

    def _ensure_authenticated_and_unlocked(self) -> None:
        status = self._vault_status()
        if status == "unauthenticated":
            self._write("Bitwarden is not logged in. Logging in...\n")
            self.runner.interactive(["bw", "login"])
            status = self._vault_status()

        if status == "locked":
            self._unlock_vault()

    def _vault_status(self) -> str:
        try:
            response = self.runner.capture(
                ["bw", "status"],
                env=self._bitwarden_environment(),
            )
            status = json.loads(response).get("status", "unknown")

            return status
        except (json.JSONDecodeError, AttributeError, CommandFailure):
            return "unknown"

    def _unlock_vault(self) -> None:
        password = self._ask_password("Bitwarden master password: ")

        if not password:
            raise RuntimeError("Master password cannot be empty.")

        try:
            command = ["bw", "unlock", "--passwordenv", "BW_PASSWORD", "--raw"]
            environment = self._bitwarden_environment(BW_PASSWORD=password)
            self.session_key = self.runner.capture(command, env=environment).strip()
        except CommandFailure as error:
            raise RuntimeError(f"Failed to unlock Bitwarden vault. Verify your master password.\n{error}") from error

    def _bitwarden_environment(self, **extra: str) -> dict[str, str]:
        environment = dict(os.environ)

        if self.session_key:
            environment["BW_SESSION"] = self.session_key

        environment.update(extra)

        return environment

    def _ask_password(self, prompt: str) -> str | None:
        input_stream = self.input_stream
        output_stream = self.output_stream

        if input_stream is None:
            return getpass.getpass(prompt)

        if input_stream is sys.stdin and input_stream.isatty():
            try:
                return getpass.getpass(prompt)
            except (EOFError, OSError):
                pass
        if output_stream is not None:
            output_stream.write(prompt)
            output_stream.flush()

        return input_stream.readline().rstrip("\r\n") or None

    def _extract_archive(self, archive_path: Path) -> None:
        with tempfile.TemporaryDirectory(prefix="dotfiles-extract-") as temporary_directory:
            temporary_path = Path(temporary_directory)
            self._extract_zip(archive_path, temporary_path)
            extracted_private = temporary_path / "private"
            source = extracted_private if extracted_private.is_dir() else temporary_path

            self._install_private_directory(source)

    @staticmethod
    def _extract_zip(archive_path: Path, destination: Path) -> None:
        destination_root = destination.resolve()

        with zipfile.ZipFile(archive_path) as archive:
            for member in archive.infolist():
                member_path = PurePosixPath(member.filename.replace("\\", "/"))
                parts = tuple(part for part in member_path.parts if part not in {"", "."})

                if member_path.is_absolute() or ".." in parts:
                    raise RuntimeError(f"Private archive contains an unsafe path: {member.filename}")

                if stat.S_ISLNK(member.external_attr >> 16):
                    raise RuntimeError(f"Private archive contains a symbolic link: {member.filename}")

                target = destination.joinpath(*parts)
                target_path = target.resolve(strict=False)

                if os.path.commonpath((destination_root, target_path)) != str(destination_root):
                    raise RuntimeError(f"Private archive escapes its destination: {member.filename}")

                if member.is_dir():
                    target.mkdir(parents=True, exist_ok=True)
                    continue

                target.parent.mkdir(parents=True, exist_ok=True)

                with archive.open(member) as source, target.open("wb") as output:
                    shutil.copyfileobj(source, output)

    def _install_private_directory(self, source: Path) -> None:
        destination_parent = self.private_directory.parent
        destination_parent.mkdir(parents=True, exist_ok=True)

        staging_directory = Path(
            tempfile.mkdtemp(
                prefix=f".{self.private_directory.name}.staging-",
                dir=destination_parent,
            )
        )

        try:
            for entry in source.iterdir():
                destination = staging_directory / entry.name

                if entry.is_dir():
                    shutil.copytree(entry, destination)
                else:
                    shutil.copy2(entry, destination)

            if self.private_directory.exists():
                if not self.private_directory.is_dir() or any(self.private_directory.iterdir()):
                    raise RuntimeError(f"Private state destination is not empty: {self.private_directory}")

                self.private_directory.rmdir()

            os.replace(staging_directory, self.private_directory)
        finally:
            shutil.rmtree(staging_directory, ignore_errors=True)

    def _powershell_command(self) -> str:
        return "pwsh" if shutil.which("pwsh") else "powershell"

    def _write(self, message: str) -> None:
        if self.output_stream is not None:
            self.output_stream.write(message)
            self.output_stream.flush()
