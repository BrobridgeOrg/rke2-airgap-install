#!/usr/bin/env bash

set -euo pipefail

# Defaults
HELM_VERSION=""   # empty = fetch latest stable
ARCH="amd64"
DEST_DIR="./cmd"

# Usage
usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Downloads the Helm binary into the destination directory.

Options:
  -v, --version  Helm version without 'v' prefix (e.g. 3.17.0); default: latest stable
  -a, --arch     Architecture: amd64 | arm64  (default: ${ARCH})
  -d, --dest     Destination directory  (default: ${DEST_DIR})
  -h, --help     Show this help

Examples:
  $(basename "$0") --arch amd64
  $(basename "$0") --version 3.17.0 --arch arm64
EOF
  exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--version) HELM_VERSION="$2"; shift 2 ;;
    -a|--arch)    ARCH="$2";         shift 2 ;;
    -d|--dest)    DEST_DIR="$2";     shift 2 ;;
    -h|--help)    usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

# Resolve latest version if not specified
if [[ -z "${HELM_VERSION}" ]]; then
  echo "Fetching latest Helm version..."
  HELM_VERSION=$(curl -fsSL "https://api.github.com/repos/helm/helm/releases/latest" \
    | grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/')
  echo "Latest: v${HELM_VERSION}"
fi

TARBALL="helm-v${HELM_VERSION}-linux-${ARCH}.tar.gz"
BASE_URL="https://get.helm.sh"

mkdir -p "${DEST_DIR}"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

echo "Helm v${HELM_VERSION} | ARCH: ${ARCH}"
echo "Source: ${BASE_URL}"
echo ""

echo "[1] Downloading ${TARBALL}"
curl -fL --progress-bar "${BASE_URL}/${TARBALL}" -o "${TMP_DIR}/${TARBALL}"
curl -fsSL "${BASE_URL}/${TARBALL}.sha256sum" -o "${TMP_DIR}/${TARBALL}.sha256sum"

echo ""
echo "[2] Verifying checksum"
expected=$(awk '{print $1}' "${TMP_DIR}/${TARBALL}.sha256sum")
actual=$(sha256sum "${TMP_DIR}/${TARBALL}" | awk '{print $1}')
if [[ "${expected}" != "${actual}" ]]; then
  echo "  FAIL ${TARBALL}: checksum mismatch"
  exit 1
fi
echo "  OK ${TARBALL}"

echo ""
echo "[3] Extracting helm binary"
tar -xzf "${TMP_DIR}/${TARBALL}" -C "${TMP_DIR}" "linux-${ARCH}/helm"
mv "${TMP_DIR}/linux-${ARCH}/helm" "${DEST_DIR}/helm"
chmod +x "${DEST_DIR}/helm"

echo ""
echo "Done. helm v${HELM_VERSION} saved to ${DEST_DIR}/helm"
