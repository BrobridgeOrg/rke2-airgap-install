# RKE2 Air-Gap install

Bash scripts and Makefiles for installing [RKE2](https://docs.rke2.io/) in air-gapped (offline) environments on RHEL.

## Requirements

**Online machine** (bundle preparation):
- `git`, `make`
- `curl`
- `vim` (or any text editor, for editing `config.env`)
- `createrepo_c`, `dnf-plugins-core` (RPM repo sync, RHEL only)

**Air-gap machine** (deployment):
- RHEL
- `dnf`
- `firewalld`
- `systemd`

## Quick Start

### 1. Configure

```bash
cp config.env.example config.env
# Edit config.env and fill in TOKEN, NODE_NAME, NODE_IP, etc.
```

### 2. Prepare bundle (online machine)

```bash
make prepare    # fetch artifacts, sync RPM repo, generate config
make bundle     # package everything into rke2-airgap-<version>-<arch>.tar.gz
```

#### Extra images (optional)

To pre-load additional image tarballs (`.tar`, `.tar.gz`, `.tar.zst`) before RKE2 starts, place them in `output/images/` before running `make bundle`:

```
output/
  images/
    my-app.tar.zst
    another-image.tar.gz
```

During installation, `scripts/05-prepare-node.sh` copies them into `/var/lib/rancher/rke2/agent/images/` so RKE2 loads them automatically on startup. If `images/` is empty or absent, the step is skipped.

Transfer the `.tar.gz` to the air-gap machine, then extract it:

```bash
tar -xzf rke2-airgap-v1.35.3+rke2r1-amd64.tar.gz
```

### 3. Deploy (air-gap machine)

Run the interactive installer:

```bash
./install.sh
```

It reads `config.yaml` and `artifacts/` to auto-detect role, CNI, and CIS settings, then runs the numbered scripts in `scripts/` in order.

> **CIS hardening**: if enabled, kernel parameters take effect immediately. A reboot after installation is recommended to verify settings persist.

### 4. Use kubectl

```bash
export PATH=$PATH:$(pwd)/cmd
kubectl get nodes
```

## Configuration

All options are set in `config.env` (copied from `config.env.example`):

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `RKE2_VERSION` | | `v1.35.3+rke2r1` | RKE2 version to install |
| `ARCH` | | `amd64` | Architecture (`amd64` \| `arm64`) |
| `TOKEN` | yes | — | Shared cluster secret |
| `NODE_NAME` | yes | — | Node hostname |
| `NODE_IP` | yes | — | Node IP address |
| `ROLE` | | `server` | Node role (`server` \| `agent`) |
| `SERVER_URL` | for agent / additional server | — | e.g. `https://192.168.1.10:9345` |
| `CNI` | | `canal` | `canal` \| `cilium` \| `calico` \| `none` |
| `INGRESS` | | `traefik` | `traefik` \| `nginx` \| `none` |
| `TLS_SANS` | | — | Extra SANs appended to NODE_NAME and NODE_IP |
| `CIS` | | `false` | Enable CIS hardening profile |
| `SCHEDULABLE` | | `true` | `false`: add `CriticalAddonsOnly=true:NoExecute` taint (dedicated control plane) |
| `DISABLE_CLOUD_CONTROLLER` | | `false` | Disable built-in cloud controller |
| `DISABLE_KUBE_PROXY` | | `false` | Disable kube-proxy (recommended with Cilium) |
| `RANCHER_PRIME` | | `false` | Set `system-default-registry` to `registry.rancher.com` |
| `LINUX_MAJOR` | | `9` | RHEL major version (RPM repo) |

## Multi-node Setup

Generate a separate bundle for each node. Edit `config.env` for each node before running `make prepare`.

**First server**
```bash
# config.env
TOKEN=secret
NODE_NAME=node1
NODE_IP=192.168.1.10
```

**Additional server**
```bash
# config.env
TOKEN=secret
NODE_NAME=node2
NODE_IP=192.168.1.11
SERVER_URL=https://192.168.1.10:9345
```

**Agent**
```bash
# config.env
ROLE=agent
TOKEN=secret
NODE_NAME=node3
NODE_IP=192.168.1.12
SERVER_URL=https://192.168.1.10:9345
```

## Make Targets

| Target | Description |
|--------|-------------|
| `make fetch` | Download install.sh and image tarballs |
| `make rpm-repo` | Sync RPM packages (RHEL only) |
| `make config` | Generate `config.yaml` |
| `make prepare` | Run all of the above and copy deploy scripts |
| `make bundle` | Package `output/` into a `.tar.gz` |
| `make clean` | Remove `output/` and the bundle tarball |
