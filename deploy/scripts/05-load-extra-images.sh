#!/usr/bin/env bash

set -euo pipefail

# Defaults
IMAGES_SRC="./images"
IMAGES_DEST="/var/lib/rancher/rke2/agent/images"

# Usage
usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Copies extra image tarballs into the RKE2 agent images directory so
they are pre-loaded when rke2 starts.

Options:
  -s, --src    Source directory containing image tarballs  (default: ${IMAGES_SRC})
  -d, --dest   RKE2 agent images directory  (default: ${IMAGES_DEST})
  -h, --help   Show this help

Examples:
  $(basename "$0")
  $(basename "$0") --src ./images
EOF
  exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--src)   IMAGES_SRC="$2";  shift 2 ;;
    -d|--dest)  IMAGES_DEST="$2"; shift 2 ;;
    -h|--help)  usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

# main
if [[ ! -d "${IMAGES_SRC}" ]]; then
  echo "No extra images directory found at ${IMAGES_SRC}, skipping."
  echo "Next step: start RKE2"
  echo "  ./06-start-rke2.sh --role server --config ./config.yaml"
  exit 0
fi

shopt -s nullglob
files=("${IMAGES_SRC}"/*.tar "${IMAGES_SRC}"/*.tar.gz "${IMAGES_SRC}"/*.tar.zst)
shopt -u nullglob

if [[ ${#files[@]} -eq 0 ]]; then
  echo "No image tarballs found in ${IMAGES_SRC}, skipping."
  echo "Next step: start RKE2"
  echo "  ./06-start-rke2.sh --role server --config ./config.yaml"
  exit 0
fi

echo "Source: ${IMAGES_SRC}"
echo "Dest:   ${IMAGES_DEST}"
echo ""

echo "[1] Copying extra images"
sudo mkdir -p "${IMAGES_DEST}"
for f in "${files[@]}"; do
  echo "  -> $(basename "${f}")"
  sudo cp "${f}" "${IMAGES_DEST}/"
done

echo ""
echo "Done."
echo "Next step: start RKE2"
echo "  ./06-start-rke2.sh --role server --config ./config.yaml"
