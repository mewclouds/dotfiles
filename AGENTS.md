# Agent Instructions

## Project

This repository contains a personal Windows/Linux dotfiles and machine setup system.

Read `SPEC.md` for the project architecture and boundaries. Treat it as the source of truth.

## Working rules

- Keep changes small and scoped to the active task.
- Inspect existing code before introducing new structure or abstractions.
- Prefer simple implementations over speculative frameworks.
- Add docstrings or documentation comments for public APIs, exported symbols, and non-obvious behavior in any language. Do not document obvious code that explains itself.
- Do not fabricate repository state, command output, or test results.
- Do not commit, push, tag, or discard user changes unless explicitly asked.

## Architecture

- Ruby is the primary orchestrator.
- PowerShell, Bash, and external tools are valid where they fit better.
- Do not move working platform-specific code into Ruby merely for consistency.
- Keep bootstrap scripts small.

## Privacy and secrets

Assume the repository is public.

Never add real secrets, private keys, hostnames, machine identifiers, private configuration, or decrypted private-state files.

The `.config/.gitconfig` file is public configuration by design. Git identity details such as the user name and GitHub noreply email are not considered private state for this project.

Use synthetic values in examples and tests.

Never implement custom cryptographic primitives.

## Safety and verification

- This project is intended to establish the desired state on a new machine. Overwriting managed configuration during bootstrap or application is intentional and expected.
- Do not silently overwrite unrelated or unmanaged user files; the intentional overwrite policy applies only to configuration managed by this repository.
- Test filesystem mutations with temporary directories when practical.
- Keep decrypted private data and temporary plaintext artifacts out of Git.
- Run relevant checks for changed code when possible.
- Review `git status` and the relevant diff before reporting completion.
- Clearly state anything that could not be verified.

Update `SPEC.md` only when the task changes an actual project contract or architectural boundary.
