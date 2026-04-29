#!/usr/bin/env bash

set -euo pipefail

# Defaults
DEST_DIR="./artifacts"
INSTALL_URL="https://get.rke2.io"

# Usage
usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Downloads install.sh from get.rke2.io.

Options:
  -d, --dest   Destination directory  (default: ${DEST_DIR})
  -h, --help   Show this help

Examples:
  $(basename "$0") --dest ./artifacts
EOF
  exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--dest) DEST_DIR="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

mkdir -p "${DEST_DIR}"

echo "[1] Downloading install.sh"
curl -fL --progress-bar "${INSTALL_URL}" -o "${DEST_DIR}/install.sh"
chmod +x "${DEST_DIR}/install.sh"
echo "  -> ${DEST_DIR}/install.sh"

echo ""
echo "Done."
