# Upgrade Feature Design

Date: 2026-06-03

## Overview

Add a single-node in-place upgrade capability to the air-gap bundle. The user extracts a newer bundle on an existing node and runs `upgrade.sh` to stop the service, replace binaries and images, and restart.

## Scope

- Single-node re-deployment (stop → install new binaries → load new images → start).
- No rolling upgrade or multi-node coordination.
- No separate upgrade bundle; `upgrade.sh` ships in the same tarball as `install.sh`.

## Files Changed

| File | Change |
|------|--------|
| `deploy/upgrade.sh` | New file — upgrade entry point |
| `deploy/scripts/05-prepare-node.sh` | Add `--skip-config` flag |

`bundle/bundle.mk` requires no changes; the existing `cp -r deploy/. $(OUT_DIR)/` already copies all files in `deploy/`.

## `upgrade.sh`

### Interface

```
Usage: upgrade.sh [options]

Options:
  -r, --role       Node role: server | agent  (skips interactive prompt)
  -a, --artifacts  Path to artifacts directory  (default: ./artifacts)
  -i, --images     Path to extra images directory  (default: ./images)
  -h, --help       Show this help
```

### Execution Flow

1. Parse arguments.
2. Detect OS family (reuse `scripts/lib/os-detect.sh`).
3. If `--role` not provided, prompt interactively (choices: `Server` / `Agent`).
4. Detect current installed version via `rke2 --version`; display `(not installed)` if the command fails.
5. Read bundle version from `rke2-version.txt`; display `(unknown)` if the file is absent.
6. Display upgrade summary and wait for Enter / Ctrl+C.
7. `systemctl stop rke2-{role} || true` — tolerate the service not running.
8. `scripts/04-install-rke2.sh --role {role} --artifacts {artifacts_dir}`
9. `scripts/05-prepare-node.sh --role {role} --skip-config --artifacts {artifacts_dir} --images {images_dir}`
10. `scripts/06-start-rke2.sh --role {role}`
11. `scripts/07-retag-images.sh`

### Summary Display

```
┌─────────────────────────────────────┐
│ Upgrade summary                     │
├─────────────────────────────────────┤
│  OS:       rhel                     │
│  Role:     server                   │
│  Current:  v1.28.5+rke2r1           │
│  New:      v1.29.3+rke2r1           │
└─────────────────────────────────────┘

Press Enter to begin, or Ctrl+C to cancel...
```

## `05-prepare-node.sh` Change

Add a `--skip-config` flag (default: false).

- **false** (existing behaviour): copy config file + copy images (steps 1, 2, 3).
- **true** (upgrade): skip step 1 (copy config), execute only steps 2 and 3 (images).

Implementation: one new variable `SKIP_CONFIG="false"`, one `--skip-config` case in the argument parser, and one `if [[ "${SKIP_CONFIG}" == "false" ]]` block wrapping step 1.

## Error Handling

| Situation | Behaviour |
|-----------|-----------|
| `systemctl stop` fails (service not running) | `\|\| true` — continue |
| Current version == bundle version | Warn in summary, do not block; user can Ctrl+C |
| `rke2-version.txt` absent | Display `(unknown)` for New version, continue |
| Any script step fails | `set -euo pipefail` — abort immediately |

## Out of Scope

- Rolling upgrade across multiple nodes.
- Drain / cordon / uncordon.
- Config migration between versions.
- Separate upgrade-only bundle.
