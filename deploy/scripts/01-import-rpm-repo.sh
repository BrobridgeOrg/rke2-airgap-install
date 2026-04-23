#!/usr/bin/env bash

set -euo pipefail

# Defaults
REPO_SRC="./rpm-repo"
REPO_DIR="/opt/rke2/rpm-repo"
REPO_FILE="/etc/yum.repos.d/local-rke2.repo"

# Usage
usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -s, --src    RPM repo source directory  (default: ${REPO_SRC})
  -d, --dest   RPM repo destination path  (default: ${REPO_DIR})
  -h, --help   Show this help

Examples:
  $(basename "$0") --src ./rpm-repo
  $(basename "$0") --src ./rpm-repo --dest /opt/rke2/rpm-repo
EOF
  exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--src)   REPO_SRC="$2";  shift 2 ;;
    -d|--dest)  REPO_DIR="$2";  shift 2 ;;
    -h|--help)  usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

# main
echo "Source:   ${REPO_SRC}"
echo "Repo dir: ${REPO_DIR}"
echo ""

echo "[1] Copying RPM repository"
sudo mkdir -p "${REPO_DIR}"
sudo cp -r "${REPO_SRC}/." "${REPO_DIR}/"

echo "[2] Creating repo file"
sudo tee "${REPO_FILE}" <<EOF
[rancher-rke2-local]
name=RKE2 Local Offline Repo
baseurl=file://${REPO_DIR}
enabled=1
gpgcheck=0
# gpgcheck disabled: packages come from a controlled local bundle
EOF

echo ""
echo "Done."
echo "Next step: open firewall ports"
echo "  ./02-set-firewalld.sh --role server --cni canal"
