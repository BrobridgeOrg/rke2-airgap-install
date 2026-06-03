#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"

# Defaults
ROLE=""
ARTIFACTS_DIR="${SCRIPT_DIR}/artifacts"
IMAGES_DIR="${SCRIPT_DIR}/images"

# Usage
usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Upgrades RKE2 on this node to the version in the bundle.

Options:
  -r, --role       Node role: server | agent  (skips role prompt)
  -a, --artifacts  Path to artifacts directory  (default: ${ARTIFACTS_DIR})
  -i, --images     Path to extra images directory  (default: ${IMAGES_DIR})
  -h, --help       Show this help

Examples:
  $(basename "$0")
  $(basename "$0") --role server
EOF
  exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--role)       ROLE="$2";          shift 2 ;;
    -a|--artifacts)  ARTIFACTS_DIR="$2"; shift 2 ;;
    -i|--images)     IMAGES_DIR="$2";    shift 2 ;;
    -h|--help)       usage ;;
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
echo "║     RKE2 Air-Gap Upgrader            ║"
echo "╚══════════════════════════════════════╝"
echo ""

# ── Role selection ────────────────────────────────────────────────────────────

if [[ -n "${ROLE}" ]]; then
  case "${ROLE}" in
    server|agent) ;;
    *) echo "Error: unsupported role: ${ROLE}"; exit 1 ;;
  esac
else
  _choice=$(ask_choice "Node role:" "Server" "Server" "Agent")
  case "${_choice}" in
    "Server") ROLE="server" ;;
    "Agent")  ROLE="agent"  ;;
    *) echo "Error: unknown selection: ${_choice}"; exit 1 ;;
  esac
fi

# ── Version detection ─────────────────────────────────────────────────────────

CURRENT_VERSION="$(rke2 --version 2>/dev/null | awk '/^rke2 version/{print $3}' || echo "(not installed)")"
VERSION_FILE="${SCRIPT_DIR}/rke2-version.txt"
if [[ -f "${VERSION_FILE}" ]]; then
  NEW_VERSION="$(cat "${VERSION_FILE}")"
else
  echo "Warning: rke2-version.txt not found — bundle version unknown"
  NEW_VERSION="(unknown)"
fi

# ── Summary ───────────────────────────────────────────────────────────────────

echo "┌─────────────────────────────────────┐"
echo "│ Upgrade summary                     │"
echo "├─────────────────────────────────────┤"
printf "│  %-10s  %-22s │\n" "OS:"      "${OS_FAMILY}"
printf "│  %-10s  %-22s │\n" "Role:"    "${ROLE}"
printf "│  %-10s  %-22s │\n" "Current:" "${CURRENT_VERSION}"
printf "│  %-10s  %-22s │\n" "New:"     "${NEW_VERSION}"
echo "└─────────────────────────────────────┘"
echo ""

if [[ "${CURRENT_VERSION}" == "${NEW_VERSION}" && "${CURRENT_VERSION}" != "(not installed)" ]]; then
  echo ""
  echo "Warning: current version matches bundle version (${NEW_VERSION})"
fi

echo ""
read -r -p "Press Enter to begin, or Ctrl+C to cancel..."

# ── Stop service ──────────────────────────────────────────────────────────────

print_header "Stop RKE2"
if sudo systemctl is-active --quiet "rke2-${ROLE}" 2>/dev/null; then
  echo "Stopping rke2-${ROLE}..."
  sudo systemctl stop "rke2-${ROLE}"
else
  echo "Service rke2-${ROLE} is not running, skipping stop"
fi

# ── Upgrade steps ─────────────────────────────────────────────────────────────

run_step "Install RKE2" \
  "${SCRIPTS_DIR}/04-install-rke2.sh" --role "${ROLE}" --artifacts "${ARTIFACTS_DIR}"

run_step "Load images" \
  "${SCRIPTS_DIR}/05-prepare-node.sh" --role "${ROLE}" --skip-config \
    --artifacts "${ARTIFACTS_DIR}" --images "${IMAGES_DIR}"

run_step "Start RKE2" \
  "${SCRIPTS_DIR}/06-start-rke2.sh" --role "${ROLE}"

run_step "Retag images" \
  "${SCRIPTS_DIR}/07-retag-images.sh"

echo ""
echo "Upgrade complete."
