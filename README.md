# Dotfiles

This repository defines repeatable setup for Windows and Linux machines.

The Python orchestrator reads public actions from `actions.yml`. It also reads
machine-specific actions from the decrypted `private/actions.yml` file.

## Commands

Run commands through `uv`:

```powershell
uv run dotfiles help
uv run dotfiles status
uv run dotfiles plan
uv run dotfiles apply
uv run dotfiles decrypt
```

Run these commands from the repository root. From another directory, put
`--repository-root PATH` before the subcommand.

Use `uv run dotfiles apply --clean` only when managed files may replace regular
files at their target paths.

## Action manifests

Each manifest contains an `actions` list. Each action has an `id`, `name`, and
`description`. It can also set `platform`, `elevation`, and `parameters`.

The public manifest contains reusable setup. The private manifest can contain
machine-specific setup. A `machine` field limits an action to hostnames that
match the current machine.

Supported action names are:

- `link_file` for managed symlinks.
- `copy_file` for applications that do not support symlinks.
- `run_command` for external tools and platform scripts.

## Repository layout

```text
actions.yml    Public action manifest
install/       Platform bootstrap scripts
private/       Decrypted private state, ignored by Git
scripts/       Platform utilities and validation scripts
src/dotfiles/  Python orchestrator package
tests/         Focused Python tests
.config/       Public configuration files
```

The repository is public on purpose. Private keys, credentials, decrypted
private state, and machine-specific secrets do not belong in Git.

## Development

Install the project and run the checks:

```powershell
uv sync
uv run pytest
uv run ruff check .
uv run ruff format --check .
```

PowerShell checks remain available through `scripts/PSFormat.ps1` and
`scripts/PSLint.ps1`.

Enable the repository pre-commit hook with:

```powershell
git config core.hooksPath .githooks
```
