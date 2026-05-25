# RKE2 Air-Gap install

[繁體中文](README.zh-TW.md)

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

After `make prepare`, `output/` contains:

```
output/
  artifacts/          ← RKE2 install.sh, binary tarball, image tarballs
  rpm-repo/           ← RPM packages + repodata (RHEL only)
  images/             ← drop extra image tarballs and retag.yaml here
  charts/             ← drop Helm charts (.tgz) and values.yaml files here
  bin/
    helm              ← Helm binary
  config-server.yaml  ← RKE2 config for first server node
  config-agent.yaml   ← RKE2 config for agent nodes (token + server URL)
  rke2-version.txt
  install.sh
  scripts/
  cmd/
    kubectl           ← wrapper (KUBECONFIG pre-set)
    crictl
    ctr
    helm              ← wrapper → ../bin/helm (KUBECONFIG pre-set)
```

The two config files are:
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

#### Image retagging (optional)

Images loaded from tarballs retain the reference name baked into the tarball manifest, which may not match what your workloads expect. Place an optional `retag.yaml` in `output/images/` to remap names after RKE2 starts:

```
output/
  images/
    my-app.tar.zst
    retag.yaml
```

```yaml
# images/retag.yaml
# format: <source reference>: <target reference>
ghcr.io/org/my-app:v1.0: internal.registry/my-app:v1.0
docker.io/library/nginx:1.25: localhost/nginx:1.25
```

After RKE2 starts, `scripts/07-retag-images.sh` reads this file and runs `ctr images tag` for each entry. If the source image is still being imported, the script retries for up to ~60 seconds. Entries that still fail are reported as warnings without failing the installation.

Transfer the `.tar.gz` to the air-gap machine, then extract it:

```bash
tar -xzf rke2-airgap-v1.35.3+rke2r1-amd64.tar.gz
```

### 3. Deploy (air-gap machine)

Run the interactive installer:

```bash
./install.sh
```

The installer walks through a short interactive setup, then runs the numbered scripts in order.

**Step 1 — Node type**

```
Node type:
  1) Server (first node)       ← init cluster
  2) Server (additional node)  ← join an existing cluster
  3) Agent
```

**Step 2 — Node identity** (all node types)

Auto-detected from the current machine; press Enter to accept or type to override. When auto-detection fails, an example is shown instead.

```
Node name [my-server]:
Node IP   [192.168.1.10]:
```

**Step 3 — TLS SANs** (server nodes only)

Always-included SANs are shown; additional ones are optional.

```
TLS SANs
  Always included: my-server, 192.168.1.10
  Additional (space-separated, leave blank to skip):
```

**Step 4 — First server URL** (agent and additional server)

Agent nodes show the URL baked into `config-agent.yaml` as a default.

```
First server URL [https://192.168.1.10:9345]:
```

The installer auto-selects `config-server.yaml` or `config-agent.yaml`, detects CNI and CIS from the artifacts and config, then confirms before running.

> **CIS hardening**: if enabled, kernel parameters take effect immediately. A reboot after installation is recommended to verify settings persist.

### 4. Use kubectl and helm

> **Server nodes only.** The `cmd/` wrappers require the kubeconfig at `/etc/rancher/rke2/rke2.yaml`, which is only generated on server nodes. Run these commands on a server node.

```bash
export PATH=$PATH:$(pwd)/cmd
kubectl get nodes
helm version
```

## Configuration

All options are set in `config.env` (copied from `config.env.example`):

Variables marked **auto** are detected at `make prepare` time and can be overridden by setting them in `config.env`.

**Bundle**

| Variable | Default | Description |
|----------|---------|-------------|
| `RKE2_VERSION` | `v1.35.4+rke2r1` | RKE2 version to install |
| `HELM_VERSION` | **auto** latest stable | Helm version (e.g. `3.17.0`); fetched from GitHub releases if empty |
| `ARCH` | **auto** `uname -m` | Architecture (`amd64` \| `arm64`) |
| `TARGET_OS` | **auto** build OS | Target OS family (`rhel` \| `ubuntu`) |
| `LINUX_MAJOR` | **auto** `VERSION_ID` | RHEL major version for RPM repo |

**Node**

| Variable | Default | Description |
|----------|---------|-------------|
| `TOKEN` | **auto** generated | Shared cluster secret; written back to `config.env` on first run |
| `NODE_NAME` | **auto** `hostname -s` | First server hostname |
| `NODE_IP` | **auto** primary route | First server IP address |
| `TLS_SANS` | — | Extra SANs appended to NODE_NAME and NODE_IP |

**Security**

| Variable | Default | Description |
|----------|---------|-------------|
| `CIS` | `false` | Enable CIS hardening profile |

**Advanced (server only)**

| Variable | Default | Description |
|----------|---------|-------------|
| `CNI` | `canal` | `canal` \| `cilium` \| `calico` \| `none` |
| `INGRESS` | `traefik` | `traefik` \| `nginx` \| `none` |
| `DISABLE_CLOUD_CONTROLLER` | `false` | Disable built-in cloud controller |
| `DISABLE_KUBE_PROXY` | `false` | Disable kube-proxy (recommended with Cilium) |
| `RANCHER_PRIME` | `false` | Set `system-default-registry` to `registry.rancher.com` |
| `TIMEZONE` | `Asia/Taipei` | Timezone injected into kube component env vars |

## Multi-node Setup

One bundle covers all node types. Prepare the bundle once on the first server machine — TOKEN, NODE_NAME, and NODE_IP are auto-detected.

**First server**
```bash
# config.env — only set what differs from defaults
CNI=canal
# run make prepare; TOKEN/NODE_NAME/NODE_IP auto-detected
```

**Additional server / Agent**

Transfer the same bundle. Run `./install.sh` and select the appropriate role. The installer prompts for node identity (name and IP) on every node, and asks for the first server URL on agent and additional server nodes. The agent default URL comes from `config-agent.yaml` baked at bundle time and can be confirmed or overridden.

## Make Targets

| Target | Description |
|--------|-------------|
| `make fetch` | Download install.sh and image tarballs |
| `make rpm-repo` | Sync RPM packages (RHEL only) |
| `make config` | Generate `config-server.yaml` and `config-agent.yaml` |
| `make prepare` | Run all of the above and copy deploy scripts |
| `make bundle` | Package `output/` into a `.tar.gz` |
| `make clean` | Remove `output/` and the bundle tarball |
