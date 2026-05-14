# RKE2 離線安裝工具

適用於 RHEL 與 Ubuntu 的 [RKE2](https://docs.rke2.io/) 離線（Air-Gap）環境安裝腳本與 Makefile 工具集。

## 環境需求

**線上機器**（打包準備）：
- `git`、`make`
- `curl`
- `openssl`（用於自動產生 TOKEN）
- `vim`（或任意文字編輯器，用於編輯 `config.env`）
- `createrepo_c`、`dnf-plugins-core`（僅 RHEL 打包時需要，用於同步 RPM repo）

**離線機器**（部署）：
- RHEL / CentOS / Rocky / AlmaLinux — 或 — Ubuntu / Debian
- `dnf`（RHEL）或 `bash`（Ubuntu，使用捆綁的 `install.sh`）
- `firewalld`（RHEL）；Ubuntu 使用 `ufw` 或手動設定防火牆規則
- `systemd`

## 快速開始

### 1. 設定

```bash
cp config.env.example config.env
# 編輯 config.env，通常只需設定 CNI、INGRESS 及叢集相關參數。
# TOKEN、NODE_NAME、NODE_IP、ARCH 會在首次執行時自動偵測。
```

### 2. 準備安裝包（線上機器）

```bash
make prepare                   # 下載套件、同步 RPM repo（RHEL）、產生設定檔
make prepare TARGET_OS=ubuntu  # Ubuntu 目標機器，跳過 RPM repo 步驟
make bundle                    # 打包成 rke2-airgap-<version>-<arch>.tar.gz
```

執行後會在 `output/` 產生**兩份設定檔**：
- `config-server.yaml` — 適用於第一台（初始化）Server 節點
- `config-agent.yaml` — 適用於 Agent 節點；`server:` 欄位已預設指向第一台 Server 的 IP

#### 私有 Registry（選用）

若需設定私有 Registry 鏡像，請在執行 `make bundle` 前，將 `registries.yaml` 放到 `output/` 目錄：

```
output/
  registries.yaml
```

安裝時，`05-prepare-node.sh` 會自動將其複製到 `/etc/rancher/rke2/registries.yaml`。若檔案不存在則跳過此步驟。格式請參考 [RKE2 Registry 文件](https://docs.rke2.io/install/containerd_registry_configuration)。

#### 額外映像檔（選用）

若需在 RKE2 啟動前預先載入額外的映像檔（`.tar`、`.tar.gz`、`.tar.zst`），請在執行 `make bundle` 前，將映像檔放到 `output/images/` 目錄：

```
output/
  images/
    my-app.tar.zst
    another-image.tar.gz
```

安裝時，`scripts/05-prepare-node.sh` 會自動將映像檔複製到 `/var/lib/rancher/rke2/agent/images/`，RKE2 啟動時會自動載入。若 `images/` 為空或不存在則跳過此步驟。

將 `.tar.gz` 傳輸到離線機器後，解壓縮：

```bash
tar -xzf rke2-airgap-v1.35.3+rke2r1-amd64.tar.gz
```

### 3. 部署（離線機器）

執行互動式安裝程式：

```bash
./install.sh
```

安裝程式會提示選擇節點類型：

```
Node type:
  1) Server (first node)       ← 初始化叢集
  2) Server (additional node)  ← 提示輸入第一台 Server URL，自動 patch 設定檔
  3) Agent
```

程式會根據選擇自動選用 `config-server.yaml` 或 `config-agent.yaml`，從套件與設定檔中偵測 CNI 和 CIS 設定，再依序執行安裝腳本。

> **CIS 強化**：若已啟用，核心參數會立即套用。建議安裝完成後重新開機，確認設定在重啟後仍然生效。

### 4. 使用 kubectl

```bash
export PATH=$PATH:$(pwd)/cmd
kubectl get nodes
```

## 設定說明

所有選項都在 `config.env` 中設定（從 `config.env.example` 複製而來）：

標示**自動**的變數會在 `make prepare` 時自動偵測，可在 `config.env` 中設定值來覆蓋。

**Bundle**

| 變數 | 預設值 | 說明 |
|------|--------|------|
| `RKE2_VERSION` | `v1.35.4+rke2r1` | 要安裝的 RKE2 版本 |
| `ARCH` | **自動** `uname -m` | 架構（`amd64` \| `arm64`） |
| `TARGET_OS` | **自動** 建置機器 OS | 目標 OS 類型（`rhel` \| `ubuntu`） |
| `LINUX_MAJOR` | **自動** `VERSION_ID` | RHEL 主版本號（RPM repo 用） |

**Node**

| 變數 | 預設值 | 說明 |
|------|--------|------|
| `TOKEN` | **自動**產生 | 叢集共用密鑰；首次執行時自動產生並寫回 `config.env` |
| `NODE_NAME` | **自動** `hostname -s` | 第一台 Server 的主機名稱 |
| `NODE_IP` | **自動** 主要路由 | 第一台 Server 的 IP 位址 |
| `TLS_SANS` | — | 附加到 NODE_NAME 和 NODE_IP 的額外 SAN |

**Security**

| 變數 | 預設值 | 說明 |
|------|--------|------|
| `CIS` | `false` | 啟用 CIS 強化設定檔 |

**Advanced（僅 server 節點）**

| 變數 | 預設值 | 說明 |
|------|--------|------|
| `CNI` | `canal` | `canal` \| `cilium` \| `calico` \| `none` |
| `INGRESS` | `traefik` | `traefik` \| `nginx` \| `none` |
| `SCHEDULABLE` | `true` | `false`：加上 `CriticalAddonsOnly=true:NoExecute` taint（專用控制平面） |
| `DISABLE_CLOUD_CONTROLLER` | `false` | 停用內建 Cloud Controller |
| `DISABLE_KUBE_PROXY` | `false` | 停用 kube-proxy（使用 Cilium 時建議開啟） |
| `RANCHER_PRIME` | `false` | 將 `system-default-registry` 設為 `registry.rancher.com` |
| `TIMEZONE` | `Asia/Taipei` | 注入至 kube 元件 env 的時區 |

## 多節點部署

一個安裝包可支援所有節點類型。在第一台 Server 機器上準備安裝包，TOKEN、NODE_NAME 與 NODE_IP 皆會自動偵測。

**第一台 Server**
```bash
# config.env — 只需設定與預設值不同的項目
CNI=canal
# 執行 make prepare，TOKEN/NODE_NAME/NODE_IP 自動偵測
```

**額外 Server / Agent**

將相同的安裝包傳輸過去，執行 `./install.sh` 並選擇：
- `Server (additional node)` — 提示輸入第一台 Server URL，節點身份自動偵測
- `Agent` — 使用 `config-agent.yaml`，其中 `server:` 已預設指向第一台 Server

## Make 指令

| 指令 | 說明 |
|------|------|
| `make fetch` | 下載 install.sh 與映像 tarball |
| `make rpm-repo` | 同步 RPM 套件（僅 RHEL） |
| `make config` | 產生 `config-server.yaml` 與 `config-agent.yaml` |
| `make prepare` | 執行以上所有步驟並複製部署腳本 |
| `make bundle` | 將 `output/` 打包為 `.tar.gz` |
| `make clean` | 刪除 `output/` 與打包檔案 |
