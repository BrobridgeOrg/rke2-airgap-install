#!/usr/bin/env bash

set -euo pipefail

# Defaults
DEST_DIR="."
INSTALL_SCRIPT_URL="https://get.rke2.io"

# Usage
usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -d, --dest   Download destination path  (default: ${DEST_DIR})
  -u, --url    Install script URL  (default: ${INSTALL_SCRIPT_URL})
  -h, --help   Show this help

Examples:
  $(basename "$0") --dest ./rke2-artifacts
  $(basename "$0") --url https://get.rke2.io --dest ./rke2-artifacts
EOF
  exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--dest) DEST_DIR="$2";            shift 2 ;;
    -u|--url)  INSTALL_SCRIPT_URL="$2";  shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

# main
echo "Destination: ${DEST_DIR}"
echo "URL: ${INSTALL_SCRIPT_URL}"
echo ""

mkdir -p "${DEST_DIR}"

echo "[1] Downloading install.sh"
curl -sfL "${INSTALL_SCRIPT_URL}" -o "${DEST_DIR}/install.sh"
chmod +x "${DEST_DIR}/install.sh"

echo ""
echo "Done. install.sh saved to ${DEST_DIR}/install.sh"
