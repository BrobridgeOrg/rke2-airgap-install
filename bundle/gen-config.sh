#!/usr/bin/env bash

set -euo pipefail

# Defaults
ROLE="server"
TOKEN=""
NODE_NAME=""
NODE_IP=""
SERVER_URL=""
TLS_SANS=""
CNI="canal"
INGRESS="traefik"
CIS=false
SCHEDULABLE=true
DISABLE_CLOUD_CONTROLLER=false
DISABLE_KUBE_PROXY=false
RANCHER_PRIME=false
TIMEZONE="Asia/Taipei"
OUT_FILE="./config.yaml"

# Usage
usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -r, --role        Node role: server | agent  (default: ${ROLE})
  -t, --token       Cluster shared secret  (required)
  -n, --node-name   Node name  (required for server)
      --node-ip     Node IP address  (required for server)
  -s, --server-url  First server URL  (required for agent)
      --tls-san     Additional SANs, space-separated
  -c, --cni         CNI type: canal | cilium | calico | none  (default: ${CNI})
  -i, --ingress     Ingress controller: nginx | traefik | none  (default: ${INGRESS})
      --cis                       Enable CIS hardening profile
      --no-schedule               Add CriticalAddonsOnly=true:NoExecute taint
      --disable-cloud-controller  Disable built-in cloud controller
      --disable-kube-proxy        Disable kube-proxy (e.g. with Cilium)
      --rancher-prime             Use Rancher Prime registry
      --timezone    Timezone for kube component env  (default: ${TIMEZONE})
  -d, --dest        Output file path  (default: ${OUT_FILE})
  -h, --help        Show this help

Examples:
  $(basename "$0") --role server --token mytoken --node-name node1 --node-ip 192.168.1.10
  $(basename "$0") --role agent  --token mytoken --server-url https://192.168.1.10:9345
EOF
  exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--role)        ROLE="$2";        shift 2 ;;
    -t|--token)       TOKEN="$2";       shift 2 ;;
    -n|--node-name)   NODE_NAME="$2";   shift 2 ;;
       --node-ip)     NODE_IP="$2";     shift 2 ;;
    -s|--server-url)  SERVER_URL="$2";  shift 2 ;;
       --tls-san)     TLS_SANS="$2";    shift 2 ;;
    -c|--cni)         CNI="$2";         shift 2 ;;
    -i|--ingress)     INGRESS="$2";     shift 2 ;;
       --cis)                      CIS=true;                        shift ;;
       --no-schedule)              SCHEDULABLE=false;               shift ;;
       --disable-cloud-controller) DISABLE_CLOUD_CONTROLLER=true;  shift ;;
       --disable-kube-proxy)       DISABLE_KUBE_PROXY=true;        shift ;;
       --rancher-prime)            RANCHER_PRIME=true;              shift ;;
       --timezone)                 TIMEZONE="$2";                   shift 2 ;;
    -d|--dest)        OUT_FILE="$2";    shift 2 ;;
    -h|--help)        usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

# Validate
[[ -z "${TOKEN}" ]] && echo "Error: --token is required" && exit 1

case "${ROLE}" in
  server|agent) ;;
  *) echo "Error: unsupported role: ${ROLE}"; exit 1 ;;
esac

case "${CNI}" in
  canal|cilium|calico|none) ;;
  *) echo "Error: unsupported CNI: ${CNI}"; exit 1 ;;
esac

case "${INGRESS}" in
  nginx|traefik|none) ;;
  *) echo "Error: unsupported ingress: ${INGRESS}"; exit 1 ;;
esac

if [[ "${ROLE}" == "server" ]]; then
  [[ -z "${NODE_NAME}" ]] && echo "Error: --node-name is required for server" && exit 1
  [[ -z "${NODE_IP}" ]]   && echo "Error: --node-ip is required for server"   && exit 1
else
  [[ -z "${SERVER_URL}" ]] && echo "Error: --server-url is required for agent" && exit 1
fi

# Build TLS SANs for server
if [[ "${ROLE}" == "server" ]]; then
  TLS_SANS="${NODE_NAME} ${NODE_IP}${TLS_SANS:+ ${TLS_SANS}}"
fi

# Generate config
mkdir -p "$(dirname "${OUT_FILE}")"

{
  if [[ "${ROLE}" == "server" ]]; then
    echo 'write-kubeconfig-mode: "0644"'
    echo ""
    echo "node-name: ${NODE_NAME}"
    echo "node-ip: ${NODE_IP}"
    echo "advertise-address: ${NODE_IP}"
    echo "tls-san:"
    for san in ${TLS_SANS}; do
      echo "  - ${san}"
    done
    if [[ "${SCHEDULABLE}" == false ]]; then
      echo "node-taint:"
      echo '  - "CriticalAddonsOnly=true:NoExecute"'
    fi
    echo ""
  fi

  # Cluster
  echo "token: ${TOKEN}"

  if [[ -n "${SERVER_URL}" ]]; then
    echo "server: ${SERVER_URL}"
  fi

  if [[ "${CIS}" == true ]]; then
    echo 'profile: "cis"'
  fi

  if [[ "${ROLE}" == "server" && "${CIS}" == true ]]; then
    echo "kube-apiserver-arg:"
    echo '  - "service-account-extend-token-expiration=false"'
  fi

  if [[ "${RANCHER_PRIME}" == true ]]; then
    echo "system-default-registry: registry.rancher.com"
  fi

  if [[ "${ROLE}" == "server" ]]; then
    echo ""

    # Networking
    echo "cni: ${CNI}"

    if [[ "${INGRESS}" == "traefik" ]]; then
      echo "ingress-controller: traefik"
    fi

    DISABLE_LIST=()
    [[ "${INGRESS}" == "traefik" || "${INGRESS}" == "none" ]] && DISABLE_LIST+=("rke2-ingress-nginx")
    [[ "${DISABLE_KUBE_PROXY}" == true ]] && DISABLE_LIST+=("rke2-kube-proxy")

    if [[ ${#DISABLE_LIST[@]} -gt 0 ]]; then
      echo "disable:"
      for item in "${DISABLE_LIST[@]}"; do
        echo "  - ${item}"
      done
    fi

    if [[ "${DISABLE_CLOUD_CONTROLLER}" == true ]]; then
      echo "disable-cloud-controller: true"
    fi

    if [[ "${DISABLE_KUBE_PROXY}" == true ]]; then
      echo "disable-kube-proxy: true"
    fi

    echo ""

    # Component timezone
    for component in etcd kube-apiserver kube-controller-manager kube-scheduler cloud-controller-manager; do
      echo "${component}-extra-env:"
      echo "  - \"TZ=${TIMEZONE}\""
    done

    echo ""
    echo "# ── Additional server node ─────────────────────────────────────────────────"
    echo "# To join another server, run install.sh and select 'Server (additional node)'."
    echo "# When prompted for the first server URL, enter:"
    echo "#   https://${NODE_IP}:9345"
  fi
} > "${OUT_FILE}"

echo "Role: ${ROLE}"
if [[ "${ROLE}" == "server" ]]; then
  echo "Node name: ${NODE_NAME}"
  echo "Node IP:   ${NODE_IP}"
  echo "TLS SANs:  ${TLS_SANS}"
  echo "CNI:       ${CNI}"
  echo "Ingress:   ${INGRESS}"
  echo "Timezone:  ${TIMEZONE}"
fi
[[ -n "${SERVER_URL}" ]] && echo "Server URL: ${SERVER_URL}"
[[ "${RANCHER_PRIME}" == true ]] && echo "Rancher Prime: yes (registry.rancher.com)"
echo ""
echo "Config written to: ${OUT_FILE}"
