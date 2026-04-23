#!/usr/bin/env bash

set -euo pipefail

# Defaults
ROLE="server"
CONFIG_SRC="./config.yaml"
CONFIG_DEST="/etc/rancher/rke2/config.yaml"
REGISTRIES_SRC="./registries.yaml"
REGISTRIES_DEST="/etc/rancher/rke2/registries.yaml"
ARTIFACTS_SRC="./artifacts"
IMAGES_SRC="./images"
IMAGES_DEST="/var/lib/rancher/rke2/agent/images"

# Usage
usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Places config files and pre-loads images before starting RKE2.

Options:
  -r, --role       Node role: server | agent  (default: ${ROLE})
  -c, --config     Path to config.yaml  (default: ${CONFIG_SRC})
  -a, --artifacts  Path to artifacts directory  (default: ${ARTIFACTS_SRC})
  -i, --images     Path to extra images directory  (default: ${IMAGES_SRC})
  -h, --help       Show this help

Examples:
  $(basename "$0") --role server
  $(basename "$0") --role agent --config ./config.yaml
EOF
  exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--role)       ROLE="$2";          shift 2 ;;
    -c|--config)     CONFIG_SRC="$2";    shift 2 ;;
    -a|--artifacts)  ARTIFACTS_SRC="$2"; shift 2 ;;
    -i|--images)     IMAGES_SRC="$2";    shift 2 ;;
    -h|--help)       usage ;;
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

echo "[1] Copying config files"
sudo mkdir -p "$(dirname "${CONFIG_DEST}")"
sudo cp "${CONFIG_SRC}" "${CONFIG_DEST}"
echo "  -> ${CONFIG_DEST}"

if [[ -f "${REGISTRIES_SRC}" ]]; then
  sudo cp "${REGISTRIES_SRC}" "${REGISTRIES_DEST}"
  echo "  -> ${REGISTRIES_DEST}"
fi

echo "[2] Copying RKE2 image tarballs"
shopt -s nullglob
artifact_files=("${ARTIFACTS_SRC}"/*.tar.zst "${ARTIFACTS_SRC}"/*.tar.gz "${ARTIFACTS_SRC}"/*.tar)
shopt -u nullglob

if [[ ${#artifact_files[@]} -gt 0 ]]; then
  sudo mkdir -p "${IMAGES_DEST}"
  for f in "${artifact_files[@]}"; do
    echo "  -> $(basename "${f}")"
    sudo cp "${f}" "${IMAGES_DEST}/"
  done
else
  echo "  (no image tarballs found in ${ARTIFACTS_SRC}, skipping)"
fi

echo "[3] Pre-loading extra images"
shopt -s nullglob
extra_files=("${IMAGES_SRC}"/*.tar "${IMAGES_SRC}"/*.tar.gz "${IMAGES_SRC}"/*.tar.zst)
shopt -u nullglob

if [[ ${#extra_files[@]} -gt 0 ]]; then
  sudo mkdir -p "${IMAGES_DEST}"
  for f in "${extra_files[@]}"; do
    echo "  -> $(basename "${f}")"
    sudo cp "${f}" "${IMAGES_DEST}/"
  done
else
  echo "  (no extra images found, skipping)"
fi

echo ""
echo "Done."
echo "Next step: start RKE2"
echo "  ./06-start-rke2.sh --role ${ROLE}"
