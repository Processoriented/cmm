# cmm — Custom Mac Maintenance

A growing collection of shell scripts for routine macOS housekeeping, built as a DIY replacement for CleanMyMac.

## Philosophy

- **Curated, not blanketed** — paths are explicitly listed, never wildcard-wiped
- **Safe for unattended runs** — all scripts support `--dry-run` and log to `~/Library/Logs/mac-maintenance/`
- **No magic** — plain bash, standard macOS tools, no third-party dependencies (Homebrew cleanup aside)
- **Family-deployable** — designed to run via `launchd` across multiple Macs

## Scripts

| Script | Description |
|--------|-------------|
| [`mac-maintenance.sh`](mac-maintenance.sh) | Core maintenance: cache cleanup, periodic tasks, DNS flush, locate DB rebuild, large-file report |

## Usage

```bash
# Dry run — prints everything that would happen, no changes made
./mac-maintenance.sh --dry-run

# Normal run (user-level tasks)
./mac-maintenance.sh

# Full run including system tasks (periodic, mDNSResponder, locate DB)
sudo ./mac-maintenance.sh
```

Logs are written to `~/Library/Logs/mac-maintenance/YYYY-MM-DD.log` and symlinked from `./logs/`.

## Scheduling with launchd

Coming soon: a `.plist` launchd agent for automatic weekly runs.

## What this doesn't cover

These are handled by free tools instead:

| Task | Tool |
|------|------|
| App uninstall + leftover cleanup | [AppCleaner](https://freemacsoft.net/appcleaner/) |
| Menu bar system monitoring | [Stats](https://github.com/exelban/stats) |
| On-demand malware scanning | [Malwarebytes Free](https://www.malwarebytes.com/mac) |
| Disk space visualization | [GrandPerspective](https://grandperspectiv.sourceforge.net/) or `ncdu` |

Baseline malware protection is handled by macOS XProtect.
