#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"

# Defaults
ROLE=""
CNI=""
CIS=""
CONFIG_FILE="${SCRIPT_DIR}/config.yaml"
ARTIFACTS_DIR="${SCRIPT_DIR}/artifacts"

# Usage
usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Reads config.yaml and installs RKE2. Only prompts for values that
cannot be determined from the config file.

Options:
  -r, --role        Node role: server | agent
  -c, --cni         CNI type: canal | cilium | calico | none
  --cis             Enable CIS hardening
  --config          Path to config.yaml  (default: ${CONFIG_FILE})
  --artifacts       Path to artifacts directory  (default: ${ARTIFACTS_DIR})
  -h, --help        Show this help

Examples:
  $(basename "$0")
  $(basename "$0") --config ./config.yaml
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
  echo "${prompt}"
  local i=1
  for opt in "${options[@]}"; do
    if [[ "${opt}" == "${default}" ]]; then
      echo "  ${i}) ${opt} (default)"
    else
      echo "  ${i}) ${opt}"
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

# ── read config.yaml ──────────────────────────────────────────────────────────

if [[ ! -f "${CONFIG_FILE}" ]]; then
  echo "Error: config file not found: ${CONFIG_FILE}"
  exit 1
fi

# Detect role: server has write-kubeconfig-mode, agent has server: <url>
if [[ -z "${ROLE}" ]]; then
  if grep -q "^write-kubeconfig-mode:" "${CONFIG_FILE}"; then
    ROLE="server"
  elif grep -q "^server:" "${CONFIG_FILE}"; then
    ROLE="agent"
  fi
fi

# Detect CNI from artifacts (rke2-images-<cni>.linux-*.tar.zst)
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

# ── prompt for missing values ─────────────────────────────────────────────────

echo ""
echo "╔══════════════════════════════════════╗"
echo "║     RKE2 Air-Gap Installer           ║"
echo "╚══════════════════════════════════════╝"
echo ""

if [[ -z "${ROLE}" ]]; then
  ROLE=$(ask_choice "Node role:" "server" "server" "agent")
fi

# Validate
case "${ROLE}" in
  server|agent) ;;
  *) echo "Error: unsupported role: ${ROLE}"; exit 1 ;;
esac

case "${CNI}" in
  canal|cilium|calico|none) ;;
  *) echo "Error: unsupported CNI: ${CNI}"; exit 1 ;;
esac

# ── summary ───────────────────────────────────────────────────────────────────

echo ""
echo "┌─────────────────────────────────────┐"
echo "│ Installation summary                │"
echo "├─────────────────────────────────────┤"
printf "│  %-10s  %-22s │\n" "Role:"   "${ROLE}"
printf "│  %-10s  %-22s │\n" "CNI:"    "${CNI}"
printf "│  %-10s  %-22s │\n" "CIS:"    "${CIS}"
printf "│  %-10s  %-22s │\n" "Config:" "$(basename "${CONFIG_FILE}")"
echo "└─────────────────────────────────────┘"
echo ""
read -r -p "Press Enter to begin, or Ctrl+C to cancel..."

# ── run scripts ───────────────────────────────────────────────────────────────

run_step "01 · Import RPM repo" \
  "${SCRIPTS_DIR}/01-import-rpm-repo.sh"

run_step "02 · Configure firewall" \
  "${SCRIPTS_DIR}/02-set-firewalld.sh" --role "${ROLE}" --cni "${CNI}"

if [[ "${CIS}" == "true" ]]; then
  run_step "03 · Apply CIS hardening" \
    "${SCRIPTS_DIR}/03-set-cis-optional.sh" --role "${ROLE}" --yes
fi

run_step "04 · Install RKE2" \
  "${SCRIPTS_DIR}/04-install-rke2.sh" --role "${ROLE}"

run_step "05 · Prepare node" \
  "${SCRIPTS_DIR}/05-prepare-node.sh" --role "${ROLE}" --config "${CONFIG_FILE}" --artifacts "${ARTIFACTS_DIR}" --images "${SCRIPT_DIR}/images"

run_step "06 · Start RKE2" \
  "${SCRIPTS_DIR}/06-start-rke2.sh" --role "${ROLE}"

echo ""
if [[ "${CIS}" == "true" ]]; then
  echo "Installation complete. Reboot the node to verify CIS settings persist:"
  echo "  sudo reboot"
else
  echo "Installation complete."
fi
