# RKE2 Air-Gap install

Bash scripts and Makefiles for installing [RKE2](https://docs.rke2.io/) in air-gapped (offline) environments on RHEL and Ubuntu.

## Requirements

**Online machine** (bundle preparation):
- `git`, `make`
- `curl`
- `openssl` (for TOKEN auto-generation)
- `vim` (or any text editor, for editing `config.env`)
- `createrepo_c`, `dnf-plugins-core` (RPM repo sync, RHEL bundles only)

**Air-gap machine** (deployment):
- RHEL / CentOS / Rocky / AlmaLinux — or — Ubuntu / Debian
- `dnf` (RHEL) or `bash` (Ubuntu, uses bundled `install.sh`)
- `firewalld` (RHEL); `ufw` or manual rules for Ubuntu
- `systemd`

## Quick Start

### 1. Configure

```bash
cp config.env.example config.env
# Edit config.env — only CNI, INGRESS, and cluster settings are typically needed.
# TOKEN, NODE_NAME, NODE_IP, and ARCH are auto-detected on first run.
```

### 2. Prepare bundle (online machine)

```bash
make prepare              # fetch artifacts, sync RPM repo (RHEL), generate configs
make prepare TARGET_OS=ubuntu  # skip RPM repo for Ubuntu target machines
make bundle               # package everything into rke2-airgap-<version>-<arch>.tar.gz
```

This produces **two config files** in `output/`:
- `config-server.yaml` — for the first (init) server node
- `config-agent.yaml` — for agent nodes; `server:` is pre-set to the first server's IP

#### Private registry (optional)

To configure a private registry mirror, place a `registries.yaml` in `output/` before running `make bundle`:

```
output/
  registries.yaml
```

During installation, `05-prepare-node.sh` copies it to `/etc/rancher/rke2/registries.yaml`. If the file is absent, the step is skipped. See the [RKE2 registry docs](https://docs.rke2.io/install/containerd_registry_configuration) for the file format.

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

The installer prompts for the node type:

```
Node type:
  1) Server (first node)    ← init cluster
  2) Server (additional node) ← prompts for first server URL, patches config
  3) Agent
```

It auto-selects `config-server.yaml` or `config-agent.yaml` based on the selection, detects CNI and CIS from artifacts and config, then runs the numbered scripts in order.

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
| `RKE2_VERSION` | | `v1.35.4+rke2r1` | RKE2 version to install |
| `ARCH` | | auto (`uname -m`) | Architecture (`amd64` \| `arm64`) |
| `TARGET_OS` | | auto (build OS) | Target OS family (`rhel` \| `ubuntu`) |
| `TOKEN` | | auto-generated | Shared cluster secret; written to `config.env` on first run |
| `NODE_NAME` | | auto (`hostname -s`) | First server hostname |
| `NODE_IP` | | auto (primary route) | First server IP address |
| `CNI` | | `canal` | `canal` \| `cilium` \| `calico` \| `none` |
| `INGRESS` | | `traefik` | `traefik` \| `nginx` \| `none` |
| `TLS_SANS` | | — | Extra SANs appended to NODE_NAME and NODE_IP |
| `CIS` | | `false` | Enable CIS hardening profile |
| `SCHEDULABLE` | | `true` | `false`: add `CriticalAddonsOnly=true:NoExecute` taint (dedicated control plane) |
| `DISABLE_CLOUD_CONTROLLER` | | `false` | Disable built-in cloud controller |
| `DISABLE_KUBE_PROXY` | | `false` | Disable kube-proxy (recommended with Cilium) |
| `RANCHER_PRIME` | | `false` | Set `system-default-registry` to `registry.rancher.com` |
| `TIMEZONE` | | `Asia/Taipei` | Timezone injected into kube component env vars |
| `LINUX_MAJOR` | | `9` | RHEL major version (RPM repo) |

## Multi-node Setup

One bundle covers all node types. Prepare the bundle once on the first server machine — TOKEN, NODE_NAME, and NODE_IP are auto-detected.

**First server**
```bash
# config.env — only set what differs from defaults
CNI=canal
# run make prepare; TOKEN/NODE_NAME/NODE_IP auto-detected
```

**Additional server / Agent**

Transfer the same bundle. Run `./install.sh` and select:
- `Server (additional node)` — prompted for the first server URL, node identity auto-detected
- `Agent` — uses `config-agent.yaml` which already has `server:` set to the first server

## Make Targets

| Target | Description |
|--------|-------------|
| `make fetch` | Download install.sh and image tarballs |
| `make rpm-repo` | Sync RPM packages (RHEL only) |
| `make config` | Generate `config-server.yaml` and `config-agent.yaml` |
| `make prepare` | Run all of the above and copy deploy scripts |
| `make bundle` | Package `output/` into a `.tar.gz` |
| `make clean` | Remove `output/` and the bundle tarball |
