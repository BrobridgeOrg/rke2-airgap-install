#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"

# Defaults
ROLE=""       # server | agent (RKE2 role)
NODE_ROLE=""  # server-init | server-additional | agent (install intent)
CNI=""
CIS=""
CONFIG_FILE=""
ARTIFACTS_DIR="${SCRIPT_DIR}/artifacts"

# Usage
usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Reads config-server.yaml or config-agent.yaml and installs RKE2.

Options:
  -r, --role        Node role: server | agent  (skips role prompt)
  -c, --cni         CNI type: canal | cilium | calico | none
  --cis             Enable CIS hardening
  --config          Path to config file (default: auto-selected by role)
  --artifacts       Path to artifacts directory  (default: ${ARTIFACTS_DIR})
  -h, --help        Show this help

Examples:
  $(basename "$0")
  $(basename "$0") --role agent
EOF
  exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--role)     ROLE="$2";          shift 2 ;;
    -c|--cni)      CNI="$2";           shift 2 ;;
    --cis)         CIS="true";         shift ;;
    --config)      CONFIG_FILE="$2";   shift 2 ;;
    --artifacts)   ARTIFACTS_DIR="$2"; shift 2 ;;
    -h|--help)     usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

# ── OS detection ──────────────────────────────────────────────────────────────

# shellcheck source=scripts/lib/os-detect.sh
source "${SCRIPT_DIR}/scripts/lib/os-detect.sh"
OS_FAMILY="$(detect_os_family)"

# ── helpers ───────────────────────────────────────────────────────────────────

print_header() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo " $1"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

run_step() {
  local label="$1"; shift
  print_header "${label}"
  "$@"
}

ask_choice() {
  local prompt="$1"; shift
  local default="$1"; shift
  local -a options=("$@")
  echo "${prompt}" >&2
  local i=1
  for opt in "${options[@]}"; do
    if [[ "${opt}" == "${default}" ]]; then
      echo "  ${i}) ${opt} (default)" >&2
    else
      echo "  ${i}) ${opt}" >&2
    fi
    (( i++ ))
  done
  read -r -p "Select [default: ${default}]: " input
  if [[ -z "${input}" ]]; then
    echo "${default}"
    return
  fi
  if [[ "${input}" =~ ^[0-9]+$ ]] && (( input >= 1 && input <= ${#options[@]} )); then
    echo "${options[$(( input - 1 ))]}"
  else
    echo "${input}"
  fi
}

# ── Show header ───────────────────────────────────────────────────────────────

echo ""
echo "╔══════════════════════════════════════╗"
echo "║     RKE2 Air-Gap Installer           ║"
echo "╚══════════════════════════════════════╝"
echo ""

# ── Role selection ────────────────────────────────────────────────────────────

if [[ -n "${ROLE}" ]]; then
  case "${ROLE}" in
    server) NODE_ROLE="server-init" ;;
    agent)  NODE_ROLE="agent" ;;
    *) echo "Error: unsupported role: ${ROLE}"; exit 1 ;;
  esac
else
  _choice=$(ask_choice "Node type:" "Server (first node)" \
    "Server (first node)" \
    "Server (additional node)" \
    "Agent")
  case "${_choice}" in
    "Server (first node)")      NODE_ROLE="server-init"       ;;
    "Server (additional node)") NODE_ROLE="server-additional" ;;
    "Agent")                    NODE_ROLE="agent"             ;;
    *) echo "Error: unknown selection: ${_choice}"; exit 1 ;;
  esac
fi

case "${NODE_ROLE}" in
  server-init|server-additional) ROLE="server" ;;
  agent)                         ROLE="agent"  ;;
esac

# ── Select config file ────────────────────────────────────────────────────────

if [[ -z "${CONFIG_FILE}" ]]; then
  case "${NODE_ROLE}" in
    server-init|server-additional)
      if [[ -f "${SCRIPT_DIR}/config-server.yaml" ]]; then
        CONFIG_FILE="${SCRIPT_DIR}/config-server.yaml"
      elif [[ -f "${SCRIPT_DIR}/config.yaml" ]]; then
        CONFIG_FILE="${SCRIPT_DIR}/config.yaml"
      else
        echo "Error: config-server.yaml not found in ${SCRIPT_DIR}"
        exit 1
      fi
      ;;
    agent)
      if [[ -f "${SCRIPT_DIR}/config-agent.yaml" ]]; then
        CONFIG_FILE="${SCRIPT_DIR}/config-agent.yaml"
      elif [[ -f "${SCRIPT_DIR}/config.yaml" ]]; then
        CONFIG_FILE="${SCRIPT_DIR}/config.yaml"
      else
        echo "Error: config-agent.yaml not found in ${SCRIPT_DIR}"
        exit 1
      fi
      ;;
  esac
fi

if [[ ! -f "${CONFIG_FILE}" ]]; then
  echo "Error: config file not found: ${CONFIG_FILE}"
  exit 1
fi

# ── Collect node identity ─────────────────────────────────────────────────────

echo ""
case "${NODE_ROLE}" in
  server-init)       echo "First server setup"      ;;
  server-additional) echo "Additional server setup"  ;;
  agent)             echo "Agent setup"              ;;
esac
echo "─────────────────────────────────────────"

_auto_name=$(hostname -s 2>/dev/null || echo "")
_auto_ip=$(ip route get 1.1.1.1 2>/dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p' | head -1)

read -r -p "Node name [${_auto_name}]: " input
THIS_NODE_NAME="${input:-${_auto_name}}"

read -r -p "Node IP   [${_auto_ip}]: " input
THIS_NODE_IP="${input:-${_auto_ip}}"

[[ -z "${THIS_NODE_NAME}" ]] && echo "Error: node name is required" && exit 1
[[ -z "${THIS_NODE_IP}" ]]   && echo "Error: node IP is required"   && exit 1

EXTRA_SANS=""
if [[ "${NODE_ROLE}" == "server-init" || "${NODE_ROLE}" == "server-additional" ]]; then
  echo ""
  echo "TLS SANs"
  echo "  Always included: ${THIS_NODE_NAME}, ${THIS_NODE_IP}"
  read -r -p "  Additional (space-separated, leave blank to skip): " input
  EXTRA_SANS="${input}"
fi

FIRST_SERVER_URL=""
if [[ "${NODE_ROLE}" == "server-additional" ]]; then
  echo ""
  while [[ -z "${FIRST_SERVER_URL}" ]]; do
    read -r -p "First server URL (e.g. https://192.168.1.10:9345): " FIRST_SERVER_URL
  done
fi

PATCHED_CONFIG="$(mktemp)"
if [[ "${NODE_ROLE}" == "server-init" ]]; then
  awk -v name="${THIS_NODE_NAME}" -v ip="${THIS_NODE_IP}" -v extra="${EXTRA_SANS}" '
    /^tls-san:/ {
      skip_tls=1
      print "tls-san:"
      print "  - " name
      print "  - " ip
      n = split(extra, sans, " ")
      for (i = 1; i <= n; i++) if (sans[i] != "") print "  - " sans[i]
      next
    }
    skip_tls && /^  - / { next }
    skip_tls && !/^  - / { skip_tls=0 }
    /^node-name:/         { print "node-name: " name; next }
    /^node-ip:/           { print "node-ip: "   ip;   next }
    /^advertise-address:/ { print "advertise-address: " ip; next }
    { print }
  ' "${CONFIG_FILE}" > "${PATCHED_CONFIG}"
elif [[ "${NODE_ROLE}" == "server-additional" ]]; then
  awk -v name="${THIS_NODE_NAME}" -v ip="${THIS_NODE_IP}" -v extra="${EXTRA_SANS}" -v url="${FIRST_SERVER_URL}" '
    /^tls-san:/ {
      skip_tls=1
      print "tls-san:"
      print "  - " name
      print "  - " ip
      n = split(extra, sans, " ")
      for (i = 1; i <= n; i++) if (sans[i] != "") print "  - " sans[i]
      next
    }
    skip_tls && /^  - / { next }
    skip_tls && !/^  - / { skip_tls=0 }
    /^node-name:/         { print "node-name: " name; next }
    /^node-ip:/           { print "node-ip: "   ip;   next }
    /^advertise-address:/ { print "advertise-address: " ip; next }
    /^# ── Additional/   { exit }
    { print }
    END { print "server: " url }
  ' "${CONFIG_FILE}" > "${PATCHED_CONFIG}"
else
  # agent: base config has token+server; append node identity
  {
    cat "${CONFIG_FILE}"
    echo "node-name: ${THIS_NODE_NAME}"
    echo "node-ip: ${THIS_NODE_IP}"
  } > "${PATCHED_CONFIG}"
fi
CONFIG_FILE="${PATCHED_CONFIG}"

# ── Read config ───────────────────────────────────────────────────────────────

# Detect CNI from artifacts
if [[ -z "${CNI}" ]]; then
  for cni in canal cilium calico; do
    if ls "${ARTIFACTS_DIR}/rke2-images-${cni}.linux-"*.tar.zst &>/dev/null 2>&1; then
      CNI="${cni}"
      break
    fi
  done
  [[ -z "${CNI}" ]] && CNI="none"
fi

# Detect CIS
if [[ -z "${CIS}" ]]; then
  if grep -q '^profile:' "${CONFIG_FILE}"; then
    CIS="true"
  else
    CIS="false"
  fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "┌─────────────────────────────────────┐"
echo "│ Installation summary                │"
echo "├─────────────────────────────────────┤"
printf "│  %-10s  %-22s │\n" "OS:"     "${OS_FAMILY}"
printf "│  %-10s  %-22s │\n" "Role:"   "${NODE_ROLE}"
printf "│  %-10s  %-22s │\n" "CNI:"    "${CNI}"
printf "│  %-10s  %-22s │\n" "CIS:"    "${CIS}"
printf "│  %-10s  %-22s │\n" "Config:" "$(basename "${CONFIG_FILE}")"
echo "└─────────────────────────────────────┘"
echo ""
read -r -p "Press Enter to begin, or Ctrl+C to cancel..."

# ── Run scripts ───────────────────────────────────────────────────────────────

if [[ "${OS_FAMILY}" == "rhel" ]]; then
  run_step "Import RPM repo" \
    "${SCRIPTS_DIR}/01-import-rpm-repo.sh"
fi

run_step "Configure firewall" \
  "${SCRIPTS_DIR}/02-set-firewalld.sh" --role "${ROLE}" --cni "${CNI}"

if [[ "${CIS}" == "true" ]]; then
  run_step "Apply CIS hardening" \
    "${SCRIPTS_DIR}/03-set-cis-optional.sh" --role "${ROLE}" --yes
fi

run_step "Install RKE2" \
  "${SCRIPTS_DIR}/04-install-rke2.sh" --role "${ROLE}" --artifacts "${ARTIFACTS_DIR}"

run_step "Prepare node" \
  "${SCRIPTS_DIR}/05-prepare-node.sh" --role "${ROLE}" --config "${CONFIG_FILE}" --artifacts "${ARTIFACTS_DIR}" --images "${SCRIPT_DIR}/images"

run_step "Start RKE2" \
  "${SCRIPTS_DIR}/06-start-rke2.sh" --role "${ROLE}"

echo ""
if [[ "${CIS}" == "true" ]]; then
  echo "Installation complete. Reboot the node to verify CIS settings persist:"
  echo "  sudo reboot"
else
  echo "Installation complete."
fi
