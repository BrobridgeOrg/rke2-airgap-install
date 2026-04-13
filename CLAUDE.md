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
  build-rpm-repo.sh       ← syncs RKE2 RPM repos (RHEL only, requires createrepo_c)
  gen-config.sh           ← generates /etc/rancher/rke2/config.yaml
deploy/                    ← air-gap machine: interactive installer and scripts
  install.sh               ← interactive installer (entry point)
  scripts/                 ← numbered scripts invoked by run.sh
    01-import-rpm-repo.sh    ← registers local RPM repo for offline install
    02-set-firewalld.sh      ← opens required firewall ports and CNI interfaces
    03-set-cis-optional.sh   ← applies CIS kernel hardening (optional)
    04-install-rke2.sh       ← runs install.sh with artifact path and role
    05-load-extra-images.sh  ← copies extra image tarballs into agent images dir (optional)
    06-start-rke2.sh         ← copies config.yaml and starts rke2 systemd service
  cmd/                     ← wrapper scripts for kubectl, crictl, ctr
```

## Key Conventions

- All scripts use `#!/usr/bin/env bash` with `set -euo pipefail`.
- Defaults are declared as variables at the top; all flags override them.
- Output uses numbered step prefixes: `[1] Step name`, `[2] Step name`, etc.
- Each script ends with a prompt showing the next command to run.
- CNI options: `canal` (default), `cilium`, `calico`, `none`.
- Ingress options: `traefik` (default), `nginx`, `none`.
- `RKE2_MINOR` is automatically derived from `RKE2_VERSION` in `bundle.mk`.

## Make Targets

```bash
make fetch       # download install.sh and image tarballs into output/artifacts/
make rpm-repo    # sync RPM packages into output/rpm-repo/ (RHEL only)
make config      # generate output/config.yaml (requires TOKEN, NODE_NAME, NODE_IP)
make prepare     # runs fetch + rpm-repo + config, then copies deploy/ into output/
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
artifacts/          ← image tarballs + install.sh
rpm-repo/           ← RPM packages + repodata
images/             ← (optional) extra image tarballs to pre-load
config.yaml         ← generated RKE2 config
install.sh
scripts/
  01-import-rpm-repo.sh
  02-set-firewalld.sh
  03-set-cis-optional.sh
  04-install-rke2.sh
  05-load-extra-images.sh
  06-start-rke2.sh
cmd/
  kubectl
  crictl
  ctr
```

## config.env Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `TOKEN` | yes | Shared cluster secret |
| `NODE_NAME` | yes | Node hostname |
| `NODE_IP` | yes | Node IP address |
| `ROLE` | — | `server` (default) or `agent` |
| `SERVER_URL` | for agent/additional server | e.g. `https://192.168.1.10:9345` |
| `CNI` | — | `canal` (default), `cilium`, `calico`, `none` |
| `INGRESS` | — | `traefik` (default), `nginx`, `none` |
| `CIS` | — | `false` (default); enables CIS hardening profile |
| `DISABLE_CLOUD_CONTROLLER` | — | `false` (default) |
| `DISABLE_KUBE_PROXY` | — | `false` (default); recommended with Cilium |
| `TLS_SANS` | — | Extra SANs appended to NODE_NAME and NODE_IP |
| `REGISTRY` | — | Private registry hostname for air-gap |
| `LINUX_MAJOR` | — | RHEL major version, default `9` |
