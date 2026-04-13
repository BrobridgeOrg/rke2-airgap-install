#!/usr/bin/env bash

set -euo pipefail

# Defaults
ROLE="server"
ARTIFACTS_DIR="./artifacts"

# Usage
usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -r, --role      Node role: server | agent  (default: ${ROLE})
  -a, --artifacts Path to artifacts directory  (default: ${ARTIFACTS_DIR})
  -h, --help      Show this help

Examples:
  $(basename "$0") --role server
  $(basename "$0") --role agent --artifacts ./artifacts
EOF
  exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--role)      ROLE="$2";          shift 2 ;;
    -a|--artifacts) ARTIFACTS_DIR="$2"; shift 2 ;;
    -h|--help)      usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

case "${ROLE}" in
  server|agent) ;;
  *) echo "Error: unsupported role: ${ROLE}"; exit 1 ;;
esac

if [[ ! -f "${ARTIFACTS_DIR}/install.sh" ]]; then
  echo "Error: install.sh not found in ${ARTIFACTS_DIR}"
  exit 1
fi

# main
echo "Role: ${ROLE}"
echo "Artifacts: ${ARTIFACTS_DIR}"
echo ""

echo "[1] Installing RKE2"
sudo INSTALL_RKE2_ARTIFACT_PATH="${ARTIFACTS_DIR}" \
INSTALL_RKE2_TYPE="${ROLE}" \
  "${ARTIFACTS_DIR}/install.sh"

echo ""
echo "Done."
echo "Next step: copy config and start RKE2"
echo "  ./05-start-rke2.sh --role server --config ./config.yaml"
