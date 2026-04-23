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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION_FILE="${SCRIPT_DIR}/../rke2-version.txt"

# main
echo "Role: ${ROLE}"
if [[ -f "${VERSION_FILE}" ]]; then
  echo "Expected version: $(cat "${VERSION_FILE}")"
fi
echo ""

echo "[1] Installing rke2-${ROLE}"
sudo dnf install -y "rke2-${ROLE}"

INSTALLED_VERSION="$(rke2 --version 2>/dev/null | awk '/^rke2 version/{print $3}' || echo "unknown")"
echo "Installed version: ${INSTALLED_VERSION}"

if [[ -f "${VERSION_FILE}" ]]; then
  EXPECTED_VERSION="$(cat "${VERSION_FILE}")"
  if [[ "${INSTALLED_VERSION}" != "${EXPECTED_VERSION}" ]]; then
    echo "Warning: installed version (${INSTALLED_VERSION}) does not match bundle version (${EXPECTED_VERSION})"
  fi
fi

echo ""
echo "Done."
echo "Next step: copy config files and pre-load images"
echo "  ./05-prepare-node.sh --role ${ROLE}"
