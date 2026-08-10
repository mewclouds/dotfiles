# Dotfiles

This is my attempt to stop rebuilding my computers from memory.

I have maintained dotfiles and setup scripts manually for a long time. They
work, but every new machine still involves remembering which scripts to run,
which files to copy, and which things are meant to be shared. This repository is
where I am turning that process into something more deliberate.

The fun part is that I am building the orchestrator in Ruby. I want to learn
the language, so this is both a useful tool and a small project to learn from.
PowerShell, Bash, and other tools are still welcome when they are the better
way to do something on a particular platform.

Windows is getting most of the attention right now. Linux is part of the plan,
but I am adding it a piece at a time.

## What this is becoming

The general idea is:

```text
bootstrap the machine
        ↓
start Ruby
        ↓
figure out the machine context
        ↓
resolve the desired state
        ↓
build a plan
        ↓
apply and verify it
```

The current commands are intentionally small:

```powershell
ruby .\bin\dotfiles status
ruby .\bin\dotfiles plan
ruby .\bin\dotfiles apply
```

## Documentation

- [SPEC.md](SPEC.md) contains the project boundaries and decisions that are
  still being worked out.
- [ARCHITECTURE.md](ARCHITECTURE.md) explains how Ruby directs the setup and
  why different actions can use different tools.
- [AGENTS.md](AGENTS.md) contains the rules for working in this repository.

## Repository layout

```text
install/       Platform bootstrap scripts
bin/           User-facing entrypoints
lib/           Ruby orchestration code
scripts/       Platform utilities and validation scripts
.config/       Public configuration files
private/       Decrypted private state, ignored by Git
test/          Ruby tests
```

The repository is public on purpose. `.gitconfig` is public configuration by
design. Private keys, credentials, decrypted private state, and machine-specific
secrets do not belong in the public part of the repository.

## Development

Install the dependencies, then run the tests and Ruby checks:

```text
bundle install
bundle exec ruby -Itest test/dotfiles_test.rb
bundle exec standardrb
```

This is a work in progress. The structure will probably change as I learn more
Ruby and as I find the next piece of setup worth automating.
