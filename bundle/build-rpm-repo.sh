#!/usr/bin/env bash

set -euo pipefail

# Defaults
RKE2_MINOR="35"
LINUX_MAJOR="9"
ARCH="amd64"
DEST_DIR="./rpm-repo"

# Usage
usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -r, --rke2-minor    RKE2 minor version  (default: ${RKE2_MINOR})
  -l, --linux-major   RHEL major version  (default: ${LINUX_MAJOR})
  -a, --arch          Architecture: amd64 | arm64  (default: ${ARCH})
  -d, --dest          RPM repo destination path  (default: ${DEST_DIR})
  -h, --help          Show this help

Examples:
  $(basename "$0") --rke2-minor 35 --linux-major 9
  $(basename "$0") --arch arm64 --rke2-minor 35 --linux-major 9
EOF
  exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--rke2-minor)   RKE2_MINOR="$2";   shift 2 ;;
    -l|--linux-major)  LINUX_MAJOR="$2";  shift 2 ;;
    -a|--arch)         ARCH="$2";         shift 2 ;;
    -d|--dest)         DEST_DIR="$2";     shift 2 ;;
    -h|--help)         usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

# Map arch to RPM format
case "${ARCH}" in
  amd64)  RPM_ARCH="x86_64"  ;;
  arm64)  RPM_ARCH="aarch64" ;;
  *)      echo "Error: unsupported arch: ${ARCH}"; exit 1 ;;
esac

# main
echo "RKE2 minor: ${RKE2_MINOR} | RHEL major: ${LINUX_MAJOR} | ARCH: ${ARCH} (${RPM_ARCH})"
echo ""

echo "[1] Syncing RPM repositories"
mkdir -p "${DEST_DIR}"
dnf reposync \
  --repofrompath="rancher-rke2-common-latest,https://rpm.rancher.io/rke2/latest/common/centos/${LINUX_MAJOR}/noarch" \
  --repo=rancher-rke2-common-latest \
  --arch=noarch \
  -p "${DEST_DIR}" \
  --newest-only \
  --norepopath

dnf reposync \
  --repofrompath="rancher-rke2-1-${RKE2_MINOR}-latest,https://rpm.rancher.io/rke2/latest/1.${RKE2_MINOR}/centos/${LINUX_MAJOR}/${RPM_ARCH}" \
  --repo=rancher-rke2-1-${RKE2_MINOR}-latest \
  --arch="${RPM_ARCH}" \
  -p "${DEST_DIR}" \
  --newest-only \
  --norepopath

echo "[2] Creating RPM repository"
createrepo_c "${DEST_DIR}"

echo ""
echo "Done. Repository at: ${DEST_DIR}"
echo "Next step: transfer the repository to the air-gap machine"
