# Dotfiles

Personal dotfiles and machine setup, coordinated by Ruby, given my goal to learn the language.

This project is intentionally small and custom. Ruby acts as the orchestrator, it determines the machine context, resolves the desired state, builds an execution plan, and coordinates the actions needed to apply it. PowerShell, Bash, and external tools are used where they are the clearest fit for platform-specific work.

The project targets Windows and Linux, with Windows currently receiving the most attention.

## Documentation

- [SPEC.md](SPEC.md) defines the project goals, boundaries, privacy model, and deferred decisions.
- [ARCHITECTURE.md](ARCHITECTURE.md) explains the Ruby orchestration model and execution flow.
- [AGENTS.md](AGENTS.md) contains repository guidance for contributors and coding agents.

## Intended workflow

The system is designed for a fresh machine:

1. Run the platform bootstrap.
2. Install the minimum tools required by the orchestrator.
3. Acquire this repository.
4. Inspect the desired state with `dotfiles plan`.
5. Apply the desired state with `dotfiles apply`.
6. Verify the resulting machine state.

Managed configuration may be replaced when applying the desired state. Unrelated or unmanaged files should not be changed.

## Repository layout

```text
install/       Platform bootstrap scripts
bin/           User-facing entrypoints
lib/           Ruby orchestration code
scripts/       Platform utilities and validation scripts
.config/       Public configuration files
private/       Future encrypted private state
test/          Ruby tests
```

The repository is public. `.gitconfig` is public configuration by design. Private keys, credentials, decrypted private state, and machine-specific secrets do not belong here.

## Ruby development

Install the project dependencies, then run the tests and linter:

```text
bundle install
bundle exec ruby -Itest test/dotfiles_test.rb
bundle exec standardrb
```

The project uses Standard Ruby for Ruby formatting and linting.

## Status

This project is a work in progress. The architecture is intentionally being built in small, verifiable pieces.
