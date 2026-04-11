#!/usr/bin/env bash

set -euo pipefail

# Defaults
RKE2_VERSION="v1.35.3+rke2r1"
ARCH="amd64"
CNI="canal"
INGRESS="traefik"
DEST_DIR="./artifacts"
BASE_URL="https://github.com/rancher/rke2/releases/download"
DOWNLOAD_BINARY=false

# Usage
usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -v, --version   RKE2 version  (default: ${RKE2_VERSION})
  -a, --arch      Architecture  (default: ${ARCH})
  -c, --cni       CNI type: canal | cilium | calico | none  (default: ${CNI})
  -i, --ingress   Ingress controller: nginx | traefik | none  (default: ${INGRESS})
  -d, --dest      Download destination path  (default: ${DEST_DIR})
  -u, --url       Source URL prefix  (default: ${BASE_URL})
      --binary     Also download the RKE2 binary
  -h, --help      Show this help

Examples:
  $(basename "$0") --version v1.35.3+rke2r1 --cni cilium
  $(basename "$0") --version v1.35.3+rke2r1 --ingress traefik
  $(basename "$0") --version v1.35.3+rke2r1 --binary
  $(basename "$0") --url https://prime.repo.rancher.com/artifacts/rke2 --version v1.35.3+rke2r1
EOF
  exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--version) RKE2_VERSION="$2"; shift 2 ;;
    -a|--arch)    ARCH="$2";         shift 2 ;;
    -c|--cni)     CNI="$2";          shift 2 ;;
    -i|--ingress) INGRESS="$2";      shift 2 ;;
    -d|--dest)    DEST_DIR="$2";     shift 2 ;;
    -u|--url)     BASE_URL="$2";     shift 2 ;;
    --binary)     DOWNLOAD_BINARY=true; shift ;;
    -h|--help)    usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

# main
mkdir -p "${DEST_DIR}"

# URL-encode version string (e.g. v1.35.3+rke2r1 -> v1.35.3%2Brke2r1)
RKE2_VERSION_ENCODED="${RKE2_VERSION//+/%2B}"

download() {
  local file="$1"
  echo "  -> ${file}"
  curl -fL --progress-bar "${BASE_URL}/${RKE2_VERSION_ENCODED}/${file}" \
    -o "${DEST_DIR}/${file}"
}

echo "RKE2 ${RKE2_VERSION} | CNI: ${CNI} | INGRESS: ${INGRESS} | ARCH: ${ARCH}"
echo "Source: ${BASE_URL}"
echo ""

echo "[1] Core artifacts"
download "sha256sum-${ARCH}.txt"

if [[ "${DOWNLOAD_BINARY}" == true ]]; then
  download "rke2.linux-${ARCH}.tar.gz"
else
  echo "  -> Skipping RKE2 binary (use --binary to include)"
fi

echo "[2] Image tarballs"
download "rke2-images-core.linux-${ARCH}.tar.zst"

case "$CNI" in
  canal|cilium|calico)
    download "rke2-images-${CNI}.linux-${ARCH}.tar.zst"
    ;;
  none)
    echo "  -> CNI=none, skipping CNI tarball"
    ;;
  *)
    echo "Error: unsupported CNI: ${CNI}"
    exit 1
    ;;
esac

case "$INGRESS" in
  traefik)
    download "rke2-images-traefik.linux-${ARCH}.tar.zst"
    ;;
  nginx|none)
    echo "  -> INGRESS=${INGRESS}, skipping traefik tarball"
    ;;
  *)
    echo "Error: unsupported ingress: ${INGRESS}"
    exit 1
    ;;
esac

echo ""
echo "[3] Verifying checksums"
cd "${DEST_DIR}"

for f in rke2.linux-${ARCH}.tar.gz \
          rke2-images-core.linux-${ARCH}.tar.zst \
          rke2-images-${CNI}.linux-${ARCH}.tar.zst \
          rke2-images-traefik.linux-${ARCH}.tar.zst; do
  [[ ! -f "$f" ]] && continue
  expected=$(grep "$f" "sha256sum-${ARCH}.txt" | awk '{print $1}')
  actual=$(sha256sum "$f" | awk '{print $1}')
  if [[ "$expected" == "$actual" ]]; then
    echo "  OK $f"
  else
    echo "  FAIL $f checksum mismatch"
    exit 1
  fi
done

echo ""
echo "Done. Artifacts saved to ${DEST_DIR}"
echo "Next step: transfer artifacts to the air-gap machine"
