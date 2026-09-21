# Dotfiles Specification

**Status:** Draft

## Overview

This repository contains custom cross-platform dotfiles and machine setup for
Windows and Linux.

Python is the primary orchestrator. `uv` is installed as a standalone tool and
manages the Python project environment. PowerShell, Bash, and external tools
remain valid for platform-specific work.

## Goals

- Bootstrap a fresh Windows or Linux machine.
- Share common setup logic across platforms.
- Keep platform-specific behavior isolated where useful.
- Keep private configuration encrypted in the public repository.
- Let others reuse the public action manifest.
- Keep the code small and understandable.

## Architecture

The bootstrap prepares uv and starts the package with `uv run`. The Python
package loads `actions.yml`, loads applicable private actions, filters by
platform, and executes the resulting plan.

The public action manifest is the extension point. It contains an `actions`
list. Each action requires `id`, `name`, and `description` fields. It can also
set `platform`, `elevation`, `machine`, and `parameters`.

Supported action names are `link_file`, `copy_file`, and `run_command`.
Administrator actions use UAC on Windows and `sudo` on Linux.

Private actions use the same schema in `private/actions.yml`. A `machine` value
or list limits an action to matching hostnames. Private plaintext must never be
committed.

## Encryption

Private files are stored in an encrypted `private.age` archive at the repository
root.

`uv run dotfiles encrypt` creates the archive from `private/`.
`uv run dotfiles decrypt` extracts the archive into `private/`.

The age identity is stored outside Git in Bitwarden under `dotfiles-age-keys`.

## Bootstrap

Bootstrap scripts must stay small. Their job is to install uv, acquire the
repository, and start the Python orchestrator.

## SSH signing

`dotfiles apply` can prepare a machine-specific SSH signing key. The setup can
generate a local key and upload its public key to GitHub. It must not delete
existing GitHub keys or store private keys in the repository.

## Safety

- Do not replace unrelated user files without `--clean`.
- Keep private plaintext, keys, credentials, and temporary decrypted data out of Git.
- Report failures instead of presenting partial setup as success.

## Tooling

Ruff provides Python linting and formatting. Pytest runs the focused tests in
`tests/`. The `.githooks/pre-commit` hook runs these checks before a commit.
PowerShell checks use the repository scripts.

```powershell
uv sync
uv run pytest
uv run ruff check .
uv run ruff format --check .
```
