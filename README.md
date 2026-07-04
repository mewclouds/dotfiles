# My Dots

Because setting up a new Windows install manually is a form of self-torture.

This repository contains my personal configurations, terminal profiles, and automation scripts. It’s designed to bootstrap a fresh machine into my exact development environment with as little friction as possible, so I can get back to actually building things.

## The Layout

The repository is structured logically by purpose:

- **`.config/`**: App-specific configuration files (`windows-terminal`, `fastfetch`, `.gitconfig`).
- **`install/`**: The bootstrap scripts and `winget` manifests that pull down every app I need.
- **`scripts/`**: The actual automation and utility scripts.
    - `backup/`: Scheduled tasks to safely back up my game mods.
    - `shell/`: My PowerShell profile and custom terminal utilities.
    - `system/`: Hardware tweaks (e.g., my Legion laptop display resolution and refresh rate switcher).
    - `tools/`: Utilities to maintain this repository, like exporting installed Winget packages.

## Setup

If I ever wipe my machine, here is how I get it back:

1. Clone the repository.
2. Run `install/pre-setup.ps1` to configure environment paths.
3. Run `install/setup.ps1` as Administrator to link configs, install winget apps, and register scheduled tasks.
