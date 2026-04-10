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
               server: also creates etcd user for control-plane
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

# Confirm
echo "This script applies CIS hardening to the node."
echo "It will modify kernel parameters and require a reboot before installing RKE2."
echo ""
read -r -p "Are you sure you want to enable CIS hardening? [y/N] " CONFIRM
if [[ ! "${CONFIRM}" =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 0
fi
echo ""

# main
echo "Role: ${ROLE}"
echo ""

echo "[1] Applying CIS kernel parameters"
sudo tee /etc/sysctl.d/60-rke2-cis.conf <<EOF
vm.panic_on_oom=0
vm.overcommit_memory=1
kernel.panic=10
kernel.panic_on_oops=1
EOF

sudo systemctl restart systemd-sysctl

if [[ "${ROLE}" == "server" ]]; then
  echo "[2] Creating etcd user (control-plane)"
  if ! id etcd &>/dev/null; then
    sudo useradd -r -c "etcd user" -s /sbin/nologin -M etcd -U
    echo "  -> etcd user created"
  else
    echo "  -> etcd user already exists, skipping"
  fi
fi

echo ""
echo "Done. Reboot the node, then proceed to install RKE2."
echo "  sudo reboot"
echo "  ./04-install-rke2.sh --role server"
