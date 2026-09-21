"""Command-line orchestration for the dotfiles repository."""

from __future__ import annotations

import argparse
import sys
from collections.abc import Sequence
from pathlib import Path
from typing import TextIO

from dotfiles.action_manifest import ActionManifest
from dotfiles.context import Context
from dotfiles.executor import Executor
from dotfiles.plan import Plan
from dotfiles.private_state import PrivateState
from dotfiles.signing_setup import SigningSetup


def build_parser() -> argparse.ArgumentParser:
    """Build the command-line parser."""
    parser = argparse.ArgumentParser(prog="dotfiles")
    parser.add_argument(
        "--repository-root",
        type=Path,
        default=Path.cwd(),
        metavar="PATH",
        help="Repository containing actions.yml (default: current directory)",
    )

    subcommands = parser.add_subparsers(dest="command")

    subcommands.add_parser("help", help="Show command help")
    subcommands.add_parser("status", help="Report the runtime and repository context")
    subcommands.add_parser("plan", help="Show the actions for this machine")

    apply_parser = subcommands.add_parser("apply", help="Apply the actions for this machine")
    apply_parser.add_argument("--clean", action="store_true", help="Replace conflicting managed files")

    subcommands.add_parser("decrypt", aliases=["unlock"], help="Decrypt private state")
    subcommands.add_parser("encrypt", aliases=["lock"], help="Encrypt private state")

    return parser


def main(
    arguments: Sequence[str] | None = None,
    *,
    input_stream: TextIO | None = None,
    output_stream: TextIO | None = None,
) -> int:
    """Run the command-line interface."""
    parser = build_parser()
    options = parser.parse_args(arguments)
    output = output_stream or sys.stdout
    context = Context(repository_root=options.repository_root.resolve())

    if options.command == "status":
        _write_status(context, output)
    elif options.command == "help":
        parser.print_help(file=output)
    elif options.command == "plan":
        _write_plan(context, output)
    elif options.command == "apply":
        _apply(context, options.clean, input_stream, output)
    elif options.command in {"decrypt", "unlock"}:
        PrivateState(context.repository_root, input_stream, output).decrypt()
    elif options.command in {"encrypt", "lock"}:
        PrivateState(context.repository_root, input_stream, output).encrypt()
    else:
        parser.print_help(file=output)
    return 0


def resolve_plan(context: Context) -> Plan:
    """Load public and private actions for the current platform."""
    manifest = ActionManifest(context)

    return Plan(manifest.actions()).for_platform(context.platform_name)


def _write_status(context: Context, output: TextIO) -> None:
    output.write("Dotfiles orchestrator\n")
    output.write(f"Platform: {context.platform}\n")
    output.write(f"Python: {context.python_version}\n")

    output.write(f"Repository: {context.repository_root}\n")


def _write_plan(context: Context, output: TextIO) -> None:
    plan = resolve_plan(context)
    executor = Executor(context.repository_root, platform_name=context.platform_name)

    output.write("Execution plan\n")
    if plan.empty:
        output.write("No actions planned.\n")
    else:
        for action in plan.actions:
            state = executor.status(action)
            parameters = ", ".join(f"{key}={value}" for key, value in action.parameters.items())
            suffix = f": {parameters}" if parameters else ""

            output.write(f"- [{state}] {action.description} ({action.platform}){suffix}\n")

    output.write("- [optional] Prepare SSH signing key after apply (interactive; not run automatically)\n")


def _apply(context: Context, clean: bool, input_stream: TextIO | None, output: TextIO) -> None:
    manifest = ActionManifest(context)
    manifest.require_public_manifest()

    private_state = PrivateState(context.repository_root, input_stream, output)
    private_state.decrypt()

    plan = resolve_plan(context)
    executor = Executor(context.repository_root, clean=clean, platform_name=context.platform_name)
    results = executor.execute(plan)

    changed_results = {"linked", "copied", "executed"}
    applied_count = sum(result in changed_results for result in results)
    skipped_count = len(results) - applied_count

    output.write(f"Applied {applied_count} action(s).\n")
    if skipped_count:
        output.write(f"Skipped {skipped_count} already-satisfied action(s).\n")
    if _ask_signing_setup(input_stream, output):
        SigningSetup(context, input_stream, output).run()


def _ask_signing_setup(input_stream: TextIO | None, output: TextIO) -> bool:
    prompt = "Prepare SSH signing key now? [y/N] "
    output.write(prompt)
    output.flush()
    if input_stream is None:
        return input().strip().casefold() in {"y", "yes"}
    return input_stream.readline().strip().casefold() in {"y", "yes"}
