#!/usr/bin/env bash

set -euo pipefail

# Defaults
ROLE="server"
CONFIG_SRC="./config.yaml"
CONFIG_DEST="/etc/rancher/rke2/config.yaml"

# Usage
usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -r, --role    Node role: server | agent  (default: ${ROLE})
  -c, --config  Path to config.yaml  (default: ${CONFIG_SRC})
  -h, --help    Show this help

Examples:
  $(basename "$0") --role server
  $(basename "$0") --role agent --config ./config.yaml
EOF
  exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--role)   ROLE="$2";       shift 2 ;;
    -c|--config) CONFIG_SRC="$2"; shift 2 ;;
    -h|--help)   usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

case "${ROLE}" in
  server|agent) ;;
  *) echo "Error: unsupported role: ${ROLE}"; exit 1 ;;
esac

if [[ ! -f "${CONFIG_SRC}" ]]; then
  echo "Error: config file not found: ${CONFIG_SRC}"
  exit 1
fi

# main
echo "Role: ${ROLE}"
echo ""

echo "[1] Copying config"
sudo mkdir -p "$(dirname "${CONFIG_DEST}")"
sudo cp "${CONFIG_SRC}" "${CONFIG_DEST}"
echo "  -> ${CONFIG_DEST}"

echo "[2] Enabling and starting rke2-${ROLE}"
sudo systemctl enable --now rke2-${ROLE}

echo ""
echo "Done."
echo "Check status:  sudo systemctl status rke2-${ROLE}"
echo "Check journal: sudo journalctl -fu rke2-${ROLE}"
echo ""
echo "To use kubectl, crictl, and ctr:"
echo "  export PATH=\$PATH:$(pwd)/cmd"
echo "Check status:  sudo systemctl status rke2-${ROLE}"
echo "Check journal: sudo journalctl -fu rke2-${ROLE}"
