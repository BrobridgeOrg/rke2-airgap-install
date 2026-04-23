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
OUT_FILE="./config.yaml"

# Usage
usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -r, --role        Node role: server | agent  (default: ${ROLE})
                    server without --server-url = init (first) node
                    server with    --server-url = additional server node
  -t, --token       Cluster shared secret  (required)
  -n, --node-name   Node name  (required)
      --node-ip     Node IP address  (required)
  -s, --server-url  First server URL, e.g. https://192.168.1.10:9345
                    (required for agent and additional server)
      --tls-san     Additional SANs, space-separated (default: node-name and node-ip)
  -c, --cni         CNI type: canal | cilium | calico | none  (default: ${CNI})
  -i, --ingress     Ingress controller: nginx | traefik | none  (default: ${INGRESS})
      --cis                     Enable CIS hardening profile
      --no-schedule             Add CriticalAddonsOnly=true:NoExecute taint (dedicated control plane)
      --disable-cloud-controller  Disable built-in cloud controller manager
      --disable-kube-proxy        Disable kube-proxy (e.g. when using Cilium)
      --rancher-prime               Use Rancher Prime registry (registry.rancher.com)
  -d, --dest        Output file path  (default: ${OUT_FILE})
  -h, --help        Show this help

Examples:
  $(basename "$0") --role server --token mytoken --node-name node1 --node-ip 192.168.1.10
  $(basename "$0") --role server --token mytoken --node-name node1 --node-ip 192.168.1.10 --tls-san "192.168.1.10 rke2.example.com"
  $(basename "$0") --role agent  --token mytoken --node-name node2 --node-ip 192.168.1.11 --server-url https://192.168.1.10:9345
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
       --cis)                      CIS=true;          shift ;;
       --no-schedule)              SCHEDULABLE=false; shift ;;
       --disable-cloud-controller) DISABLE_CLOUD_CONTROLLER=true;        shift ;;
       --disable-kube-proxy)       DISABLE_KUBE_PROXY=true; shift ;;
       --rancher-prime)            RANCHER_PRIME=true;    shift ;;
    -d|--dest)        OUT_FILE="$2";    shift 2 ;;
    -h|--help)        usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

# Validate
[[ -z "${TOKEN}" ]]     && echo "Error: --token is required"     && exit 1
[[ -z "${NODE_NAME}" ]] && echo "Error: --node-name is required" && exit 1
[[ -z "${NODE_IP}" ]]   && echo "Error: --node-ip is required"   && exit 1

if [[ "${ROLE}" == "agent" && -z "${SERVER_URL}" ]]; then
  echo "Error: --server-url is required for agent role"
  exit 1
fi

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

# Always include node-name and node-ip in TLS SANs, append extra SANs if provided
TLS_SANS="${NODE_NAME} ${NODE_IP}${TLS_SANS:+ ${TLS_SANS}}"

# Generate config
mkdir -p "$(dirname "${OUT_FILE}")"

{
  # General
  echo "debug: false"

  if [[ "${ROLE}" == "server" ]]; then
    echo 'write-kubeconfig-mode: "0644"'
  fi

  echo ""

  # Node
  echo "node-name: ${NODE_NAME}"
  echo "node-ip: ${NODE_IP}"

  if [[ "${ROLE}" == "server" ]]; then
    echo "advertise-address: ${NODE_IP}"

    echo "tls-san:"
    for san in ${TLS_SANS}; do
      echo "  - ${san}"
    done

    if [[ "${SCHEDULABLE}" == false ]]; then
      echo "node-taint:"
      echo '  - "CriticalAddonsOnly=true:NoExecute"'
    fi
  fi

  echo ""

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

  if [[ "${ROLE}" == "server" ]]; then
    echo ""

    # Networking
    if [[ "${CNI}" != "none" ]]; then
      echo "cni:"
      echo "  - ${CNI}"
    fi

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

    # Air-gap
    if [[ "${RANCHER_PRIME}" == true ]]; then
      echo "system-default-registry: registry.rancher.com"
    fi

    echo ""

    # Component timezone
    for component in etcd kube-apiserver kube-controller-manager kube-scheduler cloud-controller-manager; do
      echo "${component}-extra-env:"
      echo '  - "TZ=Asia/Taipei"'
    done
  fi
} > "${OUT_FILE}"

echo "Role: ${ROLE}"
echo "Node name: ${NODE_NAME}"
echo "Node IP: ${NODE_IP}"
[[ -n "${SERVER_URL}" ]] && echo "Server URL: ${SERVER_URL}"
echo "TLS SANs: ${TLS_SANS}"
echo "CNI: ${CNI}"
echo "Ingress: ${INGRESS}"
[[ "${RANCHER_PRIME}" == true ]] && echo "Rancher Prime: yes (registry.rancher.com)"
echo ""
echo "Config written to: ${OUT_FILE}"
