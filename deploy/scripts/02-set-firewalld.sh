#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/os-detect.sh
source "${SCRIPT_DIR}/lib/os-detect.sh"

# Defaults
ROLE="all"
CNI="canal"
EXTRA_PORTS=""

# Base ports by role
SERVER_PORTS="6443/tcp 9345/tcp 2379/tcp 2380/tcp 2381/tcp 10250/tcp 30000-32767/tcp"
AGENT_PORTS="10250/tcp 30000-32767/tcp"

# CNI-specific ports
CANAL_PORTS="8472/udp 9099/tcp 51820/udp 51821/udp"
CILIUM_PORTS="4240/tcp 8472/udp 51871/udp"
CALICO_PORTS="179/tcp 4789/udp 5473/tcp 9098/tcp 9099/tcp"

# CNI-specific trusted interfaces
CANAL_IFACES="flannel.1 cni0"
CILIUM_IFACES="cilium_host cilium_net lxc+"
CALICO_IFACES="cali+ tunl0"

# Usage
usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -r, --role          Node role: server | agent | all  (default: ${ROLE})
  -c, --cni           CNI type: canal | cilium | calico | none  (default: ${CNI})
  -e, --extra-ports   Additional ports to open, space-separated (e.g. "8080/tcp 9090/tcp")
  -h, --help          Show this help

Examples:
  $(basename "$0") --role server --cni canal
  $(basename "$0") --role agent --cni cilium
  $(basename "$0") --role server --cni calico --extra-ports "8080/tcp"
EOF
  exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--role)         ROLE="$2";         shift 2 ;;
    -c|--cni)          CNI="$2";          shift 2 ;;
    -e|--extra-ports)  EXTRA_PORTS="$2";  shift 2 ;;
    -h|--help)         usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

# Resolve base ports by role
case "${ROLE}" in
  server) PORTS="${SERVER_PORTS}" ;;
  agent)  PORTS="${AGENT_PORTS}" ;;
  all)    PORTS="${SERVER_PORTS} ${AGENT_PORTS}" ;;
  *)      echo "Error: unsupported role: ${ROLE}"; exit 1 ;;
esac

# Resolve CNI ports and interfaces
# Note: Cilium also requires ICMP echo-request (type 8), which most firewalls allow by default
case "${CNI}" in
  canal)  PORTS="${PORTS} ${CANAL_PORTS}"; IFACES="${CANAL_IFACES}" ;;
  cilium) PORTS="${PORTS} ${CILIUM_PORTS}"; IFACES="${CILIUM_IFACES}" ;;
  calico) PORTS="${PORTS} ${CALICO_PORTS}"; IFACES="${CALICO_IFACES}" ;;
  none)   IFACES="" ;;
  *)      echo "Error: unsupported CNI: ${CNI}"; exit 1 ;;
esac

if [[ -n "${EXTRA_PORTS}" ]]; then
  PORTS="${PORTS} ${EXTRA_PORTS}"
fi

# Deduplicate ports
PORTS=$(echo "${PORTS}" | tr ' ' '\n' | sort -u | tr '\n' ' ')

OS_FAMILY="$(detect_os_family)"

# main
echo "Role: ${ROLE} | CNI: ${CNI} | OS: ${OS_FAMILY:-unknown}"
echo "Ports: ${PORTS}"
[[ -n "${IFACES}" ]] && echo "Trusted interfaces: ${IFACES}"
echo ""

case "${OS_FAMILY}" in
  rhel)
    if ! systemctl is-active firewalld &>/dev/null; then
      echo "firewalld is not active; skipping firewall configuration"
      exit 0
    fi

    STEP=1
    echo "[${STEP}] Opening firewall ports (firewalld)"; (( STEP++ ))
    for port in ${PORTS}; do
      sudo firewall-cmd --permanent --add-port="${port}"
      echo "  -> ${port}"
    done

    if [[ -n "${IFACES}" ]]; then
      echo "[${STEP}] Adding CNI interfaces to trusted zone"; (( STEP++ ))
      for iface in ${IFACES}; do
        sudo firewall-cmd --permanent --zone=trusted --add-interface="${iface}"
        echo "  -> ${iface}"
      done
    fi

    echo "[${STEP}] Reloading firewall"
    sudo firewall-cmd --reload
    ;;

  debian)
    if ! sudo ufw status | grep -q "Status: active"; then
      echo "ufw is not active; skipping firewall configuration"
      exit 0
    fi

    STEP=1
    echo "[${STEP}] Opening firewall ports (ufw)"; (( STEP++ ))
    for port in ${PORTS}; do
      # ufw uses colon for port ranges (e.g. 30000:32767/tcp), firewalld uses dash
      sudo ufw allow "${port//-/:}"
      echo "  -> ${port}"
    done

    if [[ -n "${IFACES}" ]]; then
      echo "[${STEP}] Allowing CNI interfaces"
      for iface in ${IFACES}; do
        if [[ "${iface}" == *"+"* ]]; then
          # ufw does not support wildcard interface names
          echo "  -- ${iface}: wildcard interfaces not supported by ufw; configure manually"
        else
          sudo ufw allow in on "${iface}"
          echo "  -> ${iface}"
        fi
      done
    fi
    ;;

  *)
    echo "Unknown OS; skipping firewall configuration"
    echo "Please open the required ports manually: ${PORTS}"
    exit 0
    ;;
esac

echo ""
echo "Done."
echo "Next step: (optional) apply CIS hardening"
echo "  ./03-set-cis-optional.sh --role server"
echo "Otherwise, proceed to install RKE2"
echo "  ./04-install-rke2.sh --role server"
