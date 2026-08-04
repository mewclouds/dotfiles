# Dotfiles Specification

**Status:** Draft

## Overview

This repository contains my personal cross-platform dotfiles and machine setup system.

It targets Windows and Linux and is intentionally custom rather than built around a full dotfiles framework.

Ruby is the primary orchestrator. PowerShell, Bash, and external tools may be used where they are the better fit for platform-specific work.

## Goals

- Bootstrap a fresh Windows or Linux machine.
- Share common setup logic across platforms.
- Keep platform-specific behavior isolated where useful.
- Keep private configuration encrypted in the public repository.
- Keep machine-specific information private.
- Remain small, understandable, and fun to work on.

## Architecture

```mermaid
flowchart TD
    %% Ruby is the primary orchestrator.
    %% Individual actions may be implemented in Ruby, PowerShell, Bash,
    %% or external tools depending on what fits best.

    START([Fresh Machine]) --> BOOT[Run Platform Bootstrap]
    BOOT --> PREP[Prepare Runtime and Required Tools]
    PREP --> REPO[Acquire Dotfiles Repository]
    REPO --> RUBY[Start Ruby Orchestrator]

    RUBY --> PUBLIC[Apply Public State]
    PUBLIC --> PRIVATE{Private State Available?}

    PRIVATE -->|Yes| AUTH[Authenticate]
    AUTH --> UNLOCK[Decrypt Private State]
    UNLOCK --> CONFIG[Load Configuration]

    PRIVATE -->|No| CONFIG

    CONFIG --> MACHINE[Determine Machine Context]
    MACHINE --> PLAN[Determine Required Actions]
    PLAN --> EXECUTE[Execute Actions]

    EXECUTE --> VERIFY[Verify Result]
    VERIFY --> DONE([Machine Ready])
```

## Public and private state

The repository is assumed to be public.

Public state may include dotfiles, orchestration code, platform scripts, bootstrap scripts, documentation, and encrypted private data.

Private state may include machine definitions, hostnames, private configuration, private scripts, and sensitive machine-specific information.

Private state must never be committed as plaintext.

## Encryption

Private files may be stored as an encrypted archive in the repository.

Use an established encryption tool (age is the intended as of right now) and format rather than implementing cryptography directly.

Decryption keys or identities should be stored outside Git, such as in Bitwarden.

```text
private workspace -> archive -> encrypt -> Git

Git -> decrypt -> extract -> private workspace
```

## Bootstrap

Platform bootstrap scripts should stay small.

Their job is to prepare enough of the environment to start the Ruby orchestrator.

## Platform behavior

Ruby owns shared orchestration and decides what needs to happen.

Individual actions may be implemented in Ruby, PowerShell, Bash, or external utilities depending on what is clearest.

## Safety

- Do not silently overwrite unrelated user files.
- Keep private plaintext, keys, secrets, and temporary decrypted data out of Git.
- Report failures clearly instead of presenting partial setup as success.

## Deferred decisions

- Final repository layout.
- CLI name and command structure.
- Machine configuration schema.
- Exact encryption implementation.
- Archive format.
- Ruby installation strategy on each platform.
