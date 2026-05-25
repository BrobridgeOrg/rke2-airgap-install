# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

A collection of Bash scripts and Makefiles for installing RKE2 (Rancher Kubernetes Engine 2) in air-gapped (offline) environments. The workflow is split into two phases: **bundle** (online machine, prepares artifacts) and **deploy** (air-gap machine, installs RKE2).

## Repository Structure

```
Makefile                  ← includes config.env and bundle/bundle.mk
config.env.example        ← copy to config.env and fill in values
bundle/                   ← online machine: fetch and package artifacts
  bundle.mk               ← all Make targets
  fetch-install.sh        ← downloads install.sh from get.rke2.io
  fetch-artifacts.sh      ← downloads RKE2 image tarballs and verifies checksums
  fetch-helm.sh           ← downloads Helm binary into output/cmd/
  build-rpm-repo.sh       ← syncs RKE2 RPM repos (RHEL only, requires createrepo_c)
  gen-config.sh           ← generates config-server.yaml and config-agent.yaml
deploy/                   ← air-gap machine: interactive installer and scripts
  install.sh              ← interactive installer (entry point)
  scripts/                ← numbered scripts invoked by install.sh
    01-import-rpm-repo.sh   ← registers local RPM repo for offline install
    02-set-firewalld.sh     ← opens required firewall ports and CNI interfaces
    03-set-cis-optional.sh  ← applies CIS kernel hardening (optional)
    04-install-rke2.sh      ← installs RKE2: DNF on RHEL, install.sh on Ubuntu
    05-prepare-node.sh      ← copies config files and pre-loads extra images
    06-start-rke2.sh        ← starts rke2 systemd service
    07-retag-images.sh      ← retags images per images/retag.yaml (optional)
  cmd/                    ← wrapper scripts for kubectl, crictl, ctr
```

## Key Conventions

- All scripts use `#!/usr/bin/env bash` with `set -euo pipefail`.
- Defaults are declared as variables at the top; all flags override them.
- Output uses numbered step prefixes: `[1] Step name`, `[2] Step name`, etc.
- CNI options: `canal` (default), `cilium`, `calico`, `none`.
- Ingress options: `traefik` (default), `nginx`, `none`.
- `RKE2_MINOR` is automatically derived from `RKE2_VERSION` in `bundle.mk`.
- Auto-detected variables in `bundle.mk` use `$(or $(strip $(VAR)),$(shell ...))` — not `?=`, which does not override empty strings set in `config.env`.

## Interactive Installer (`install.sh`)

The installer prompts through four steps before running the numbered scripts:

1. **Node type** — `Server (first node)` / `Server (additional node)` / `Agent`
2. **Node identity** (all nodes) — node name and IP, auto-detected from the current machine as defaults; example values shown when detection fails
3. **TLS SANs** (server nodes only) — always-included SANs displayed; additional ones optional
4. **First server URL** (agent + additional server) — agent shows the URL from `config-agent.yaml` as default

After prompting, the installer patches the selected config file in a tmpfile (via awk) and passes it to `05-prepare-node.sh`. Agent node identity (`node-name`, `node-ip`) is appended to the config since it is not present at bundle time.

## Make Targets

```bash
make fetch       # download install.sh and image tarballs into output/artifacts/
make rpm-repo    # sync RPM packages into output/rpm-repo/ (RHEL only)
make config      # generate output/config-server.yaml and output/config-agent.yaml
make prepare     # runs fetch + rpm-repo + config, copies deploy/ into output/, creates images/
make bundle      # tars output/ into rke2-airgap-<version>-<arch>.tar.gz
make clean       # removes output/ and the bundle tarball
```

Typical flow:
```bash
cp config.env.example config.env
# edit config.env
make prepare
make bundle
```

## Bundle Output Structure

After `make prepare`, `output/` contains:

```
artifacts/          ← install.sh + binary tarball + image tarballs
rpm-repo/           ← RPM packages + repodata (RHEL only)
images/             ← auto-created; drop extra tarballs and retag.yaml here
bin/                ← auto-created; downloaded tool binaries (helm, ...)
config-server.yaml  ← generated RKE2 config for first server node
config-agent.yaml   ← generated RKE2 config for agent nodes (token + server URL)
rke2-version.txt    ← RKE2 version string
install.sh
scripts/
  01-import-rpm-repo.sh
  02-set-firewalld.sh
  03-set-cis-optional.sh
  04-install-rke2.sh
  05-prepare-node.sh
  06-start-rke2.sh
  07-retag-images.sh
cmd/                ← wrapper scripts; add to PATH to use all tools
  kubectl           ← calls /var/lib/rancher/rke2/bin/kubectl with KUBECONFIG set
  crictl            ← calls /var/lib/rancher/rke2/bin/crictl
  ctr               ← calls /var/lib/rancher/rke2/bin/ctr
  helm              ← calls ../bin/helm with KUBECONFIG set
bin/
  helm              ← downloaded by fetch-helm.sh
```

### images/ directory

- Extra image tarballs (`.tar`, `.tar.gz`, `.tar.zst`) placed here are copied to `/var/lib/rancher/rke2/agent/images/` and loaded automatically by RKE2 on startup.
- Optional `images/retag.yaml` maps source → target image references. After RKE2 starts, `07-retag-images.sh` runs `ctr images tag` for each entry (retries ~60s per entry; failures are warnings, not errors).

```yaml
# images/retag.yaml format
ghcr.io/org/my-app:v1.0: internal.registry/my-app:v1.0
```

## config.env Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `HELM_VERSION` | — | Helm version (e.g. `3.17.0`); auto-fetched from GitHub releases if empty |
| `TOKEN` | — | Shared cluster secret; auto-generated on first run if empty |
| `NODE_NAME` | — | First server hostname; auto-detected from `hostname -s` if empty |
| `NODE_IP` | — | First server IP; auto-detected from primary route (`ip route get 1.1.1.1`) if empty |
| `CNI` | — | `canal` (default), `cilium`, `calico`, `none` |
| `INGRESS` | — | `traefik` (default), `nginx`, `none` |
| `CIS` | — | `false` (default); enables CIS hardening profile |
| `DISABLE_CLOUD_CONTROLLER` | — | `false` (default) |
| `DISABLE_KUBE_PROXY` | — | `false` (default); recommended with Cilium |
| `TLS_SANS` | — | Extra SANs appended to NODE_NAME and NODE_IP in config-server.yaml |
| `RANCHER_PRIME` | — | `false` (default); sets `system-default-registry: registry.rancher.com` |
| `TIMEZONE` | — | `Asia/Taipei` (default); timezone for kube component extra-env |
| `ARCH` | — | auto-detected from `uname -m`; override for cross-building |
| `TARGET_OS` | — | auto-detected from build machine `/etc/os-release`; `rhel` or `ubuntu` |
| `LINUX_MAJOR` | — | auto-detected from `VERSION_ID`; RHEL major version for RPM repo, default `9` |
