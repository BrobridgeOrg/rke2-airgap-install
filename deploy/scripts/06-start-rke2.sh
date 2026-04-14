#!/usr/bin/env bash

set -euo pipefail

# Defaults
ROLE="server"

# Usage
usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -r, --role   Node role: server | agent  (default: ${ROLE})
  -h, --help   Show this help

Examples:
  $(basename "$0") --role server
  $(basename "$0") --role agent
EOF
  exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--role) ROLE="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

case "${ROLE}" in
  server|agent) ;;
  *) echo "Error: unsupported role: ${ROLE}"; exit 1 ;;
esac

# main
echo "Role: ${ROLE}"
echo ""

echo "[1] Enabling and starting rke2-${ROLE}"
sudo systemctl enable --now rke2-${ROLE}

echo ""
echo "Done."
echo "Check status:  sudo systemctl status rke2-${ROLE}"
echo "Check journal: sudo journalctl -fu rke2-${ROLE}"
echo ""
echo "To use kubectl, crictl, and ctr:"
echo "  export PATH=\$PATH:$(pwd)/cmd"
