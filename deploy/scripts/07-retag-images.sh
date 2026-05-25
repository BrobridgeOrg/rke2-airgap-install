#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RETAG_FILE="${SCRIPT_DIR}/../images/retag.yaml"

ctr_cmd=(/var/lib/rancher/rke2/bin/ctr
  --address /run/k3s/containerd/containerd.sock
  --namespace k8s.io)

if [[ ! -f "${RETAG_FILE}" ]]; then
  echo "No images/retag.yaml found, skipping."
  exit 0
fi

echo "[1] Waiting for containerd socket..."
elapsed=0
until [[ -S /run/k3s/containerd/containerd.sock ]]; do
  sleep 2
  elapsed=$(( elapsed + 2 ))
  if [[ ${elapsed} -ge 120 ]]; then
    echo "Error: containerd socket not available after 120s"
    exit 1
  fi
done
echo "  ready"

echo ""
echo "[2] Retagging images"

failed=0
while IFS= read -r line; do
  [[ -z "${line}" || "${line}" == \#* ]] && continue

  src="${line%%: *}"
  dst="${line#*: }"
  [[ -z "${src}" || -z "${dst}" || "${src}" == "${dst}" ]] && continue

  printf "  %-50s -> %s\n" "${src}" "${dst}"

  # Retry up to ~60s in case the image is still being imported by RKE2
  retries=15
  ok=false
  while (( retries-- > 0 )); do
    if "${ctr_cmd[@]}" images tag "${src}" "${dst}" 2>/dev/null; then
      ok=true
      break
    fi
    sleep 4
  done

  if [[ "${ok}" != "true" ]]; then
    echo "    Warning: failed — source image not found"
    failed=$(( failed + 1 ))
  fi
done < "${RETAG_FILE}"

echo ""
if [[ ${failed} -gt 0 ]]; then
  echo "Done (${failed} retag(s) failed — verify image names in images/retag.yaml)"
else
  echo "Done."
fi
