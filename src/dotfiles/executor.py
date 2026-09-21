"""Apply planned filesystem and command actions."""

from __future__ import annotations

import filecmp
import json
import os
import re
import shutil
import sys
import tempfile
from pathlib import Path
from typing import Any
from uuid import uuid4

from dotfiles.action import Action
from dotfiles.command_runner import CommandRunner
from dotfiles.context import Context
from dotfiles.plan import Plan
from dotfiles.state_store import StateStore


class Executor:
    """Apply actions while protecting unmanaged files by default."""

    WINDOWS_POWERSHELL = r"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
    ELEVATOR_SCRIPT = r"""
param([Parameter(Mandatory = $true)][string]$PayloadPath)

$ErrorActionPreference = 'Stop'
$payload = Get-Content -Raw -Path $PayloadPath | ConvertFrom-Json
$quotedArguments = @($payload.arguments) | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }
$startParameters = @{
    FilePath = $payload.file_path
    ArgumentList = ($quotedArguments -join ' ')
    Verb = 'RunAs'
    Wait = $true
    PassThru = $true
}
if ($payload.working_directory) {
    $startParameters.WorkingDirectory = $payload.working_directory
}
try {
    $process = Start-Process @startParameters
    if ($null -eq $process) {
        throw 'Start-Process did not return a process.'
    }
    exit [int]$process.ExitCode
} catch {
    Write-Error $_
    exit 1
}
""".lstrip()

    def __init__(
        self,
        repository_root: Path,
        home_directory: Path | None = None,
        clean: bool = False,
        state_path: Path | None = None,
        runner: CommandRunner | Any | None = None,
        platform_name: str | None = None,
    ) -> None:
        self.repository_root = Path(repository_root)
        self.home_directory = Path.home() if home_directory is None else Path(home_directory)
        self.clean = clean
        self.platform_name = platform_name or Context.determine_platform(sys.platform)

        self.runner = runner or CommandRunner()
        self.state_store = StateStore(
            Path(state_path) if state_path is not None else self.repository_root / ".local/state.json"
        )

    def execute(self, plan: Plan) -> list[str]:
        """Apply every action in order and return its result status."""
        return [self._execute_action(action) for action in plan.actions]

    def status(self, action: Action) -> str:
        """Describe whether an action is satisfied, pending, or blocked."""
        handlers = {
            "link_file": self._link_status,
            "copy_file": self._copy_status,
            "run_command": self._command_status,
        }

        handler = handlers.get(action.name)

        return handler(action) if handler else "unsupported"

    def _execute_action(self, action: Action) -> str:
        handlers = {
            "link_file": self._link_file,
            "copy_file": self._copy_file,
            "run_command": self._run_command,
        }

        handler = handlers.get(action.name)
        if handler is None:
            raise ValueError(f"Unsupported action: {action.name}")

        return handler(action)

    def _link_file(self, action: Action) -> str:
        source, target = self._file_paths(action)

        if not source.is_file():
            raise FileNotFoundError(f"Source file does not exist: {source}")

        if target.is_symlink():
            current_target = self._resolved_link(target)

            if current_target == source.resolve():
                return "already_linked"

            if not self.clean:
                raise FileExistsError(f"Refusing to replace existing symlink: {target}")
        elif target.exists():
            if not self.clean:
                raise FileExistsError(f"Refusing to replace existing file: {target}")
            if not target.is_file():
                raise IsADirectoryError(f"Refusing to remove existing non-file path: {target}")

        target.parent.mkdir(parents=True, exist_ok=True)
        self._replace_with_symlink(source, target, action.elevation)

        return "linked"

    def _replace_with_symlink(self, source: Path, target: Path, elevation: str) -> None:
        staged_target = target.with_name(f".{target.name}.dotfiles-{uuid4().hex}")

        try:
            self._create_symlink(source, staged_target, elevation)
            os.replace(staged_target, target)
        finally:
            staged_target.unlink(missing_ok=True)

    def _create_symlink(self, source: Path, target: Path, elevation: str) -> None:
        try:
            target.symlink_to(source)
            return
        except PermissionError:
            if elevation != "admin":
                raise

        if self.platform_name == "windows":
            script = (
                f"New-Item -ItemType SymbolicLink -Path '{self._powershell_quote(target)}' "
                f"-Target '{self._powershell_quote(source)}' -Force | Out-Null"
            )
            command = [self.WINDOWS_POWERSHELL, "-NoProfile", "-Command", script]
        else:
            command = ["ln", "-s", "--", str(source), str(target)]

        self._run_elevated(command)

        if self._resolved_link(target) != source.resolve():
            raise RuntimeError(f"Elevated symlink creation did not create the requested link: {target}")

    @staticmethod
    def _powershell_quote(value: Path) -> str:
        return str(value).replace("'", "''")

    def _link_status(self, action: Action) -> str:
        source, target = self._file_paths(action)

        if not source.is_file():
            return "missing_source"
        if not target.exists() and not target.is_symlink():
            return "pending"
        if not target.is_symlink():
            return "blocked"

        return "linked" if self._resolved_link(target) == source.resolve() else "replaceable"

    def _copy_file(self, action: Action) -> str:
        source, target = self._file_paths(action)

        if not source.is_file():
            raise FileNotFoundError(f"Source file does not exist: {source}")
        if target.is_dir() and not target.is_symlink():
            raise IsADirectoryError(f"Refusing to replace existing non-file path: {target}")

        files_match = target.is_file() and not target.is_symlink() and filecmp.cmp(source, target, shallow=False)
        if files_match:
            return "already_copied"

        if (target.exists() or target.is_symlink()) and not self.clean:
            raise FileExistsError(f"Refusing to replace existing file: {target}")

        target.parent.mkdir(parents=True, exist_ok=True)
        self._replace_with_copy(source, target)

        return "copied"

    @staticmethod
    def _replace_with_copy(source: Path, target: Path) -> None:
        file_descriptor, temporary_name = tempfile.mkstemp(
            prefix=f".{target.name}.dotfiles-",
            dir=target.parent,
        )
        os.close(file_descriptor)
        staged_target = Path(temporary_name)

        try:
            shutil.copy2(source, staged_target)
            os.replace(staged_target, target)
        finally:
            staged_target.unlink(missing_ok=True)

    def _copy_status(self, action: Action) -> str:
        source, target = self._file_paths(action)

        if not source.is_file():
            return "missing_source"
        if not target.is_file() or target.is_symlink():
            return "pending"

        files_match = filecmp.cmp(source, target, shallow=False)

        return "already_copied" if files_match else "pending"

    def _run_command(self, action: Action) -> str:
        command = action.parameters.get("command")
        self._validate_command(command)

        fingerprint = action.fingerprint(self.repository_root)
        if self.state_store.completed(action, fingerprint):
            return "already_applied"

        if action.elevation == "admin":
            self._run_elevated(command)
        else:
            self.runner.interactive(command, cwd=self.repository_root)

        self.state_store.record(action, fingerprint)

        return "executed"

    def _run_elevated(self, command: list[str]) -> None:
        if self.platform_name == "linux":
            self.runner.interactive(["sudo", "--", *command], cwd=self.repository_root)
            return

        if self.platform_name != "windows":
            raise RuntimeError(f"Administrator elevation is not supported on {self.platform_name}.")

        self._run_windows_elevated(command)

    def _run_windows_elevated(self, command: list[str]) -> None:
        resolved_command = list(command)

        for index, argument in enumerate(resolved_command):
            if index and resolved_command[index - 1] == "-File":
                resolved_command[index] = str(self.repository_root / argument)

        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", suffix=".json", prefix="dotfiles-elevate-", delete=False
        ) as payload_file:
            payload_path = Path(payload_file.name)
            payload = {
                "file_path": resolved_command[0],
                "arguments": resolved_command[1:],
                "working_directory": str(self.repository_root),
            }

            json.dump(payload, payload_file)

        script_path = Path(tempfile.gettempdir()) / f"dotfiles-elevate-{os.getpid()}.ps1"

        try:
            script_path.write_text(self.ELEVATOR_SCRIPT, encoding="utf-8")
            self.runner.interactive(
                [
                    self.WINDOWS_POWERSHELL,
                    "-NoProfile",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-File",
                    str(script_path),
                    "-PayloadPath",
                    str(payload_path),
                ]
            )
        finally:
            payload_path.unlink(missing_ok=True)
            script_path.unlink(missing_ok=True)

    def _command_status(self, action: Action) -> str:
        fingerprint = action.fingerprint(self.repository_root)

        return "already_applied" if self.state_store.completed(action, fingerprint) else "planned"

    @staticmethod
    def _validate_command(command: Any) -> None:
        valid = isinstance(command, list) and command and all(isinstance(item, str) for item in command)
        if not valid:
            raise ValueError("Command must be a non-empty array of strings.")

    def _file_paths(self, action: Action) -> tuple[Path, Path]:
        source = self.repository_root / action.parameters["source"]
        target = self._expand_target(action.parameters["target"])

        return source, target

    def _expand_target(self, target: str) -> Path:
        def replace_environment_variable(match: re.Match[str]) -> str:
            name = match.group(1)
            value = os.environ.get(name)

            if value is None:
                raise RuntimeError(f"Environment variable is not set: {name}")

            return value

        expanded = re.sub(r"%([^%]+)%", replace_environment_variable, target)

        home_relative = re.match(r"^[~][\\/]", expanded)
        if home_relative:
            return self.home_directory / expanded[2:]

        return Path(expanded).expanduser().absolute()

    @staticmethod
    def _resolved_link(path: Path) -> Path | None:
        try:
            return path.resolve(strict=True)
        except FileNotFoundError:
            return None
