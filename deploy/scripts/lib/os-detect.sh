#!/usr/bin/env bash
# Outputs the OS family: rhel | debian | unknown
detect_os_family() {
  if [[ -f /etc/os-release ]]; then
    # shellcheck source=/dev/null
    . /etc/os-release
    case "${ID:-}" in
      rhel|centos|rocky|almalinux|fedora) echo "rhel" ;;
      ubuntu|debian) echo "debian" ;;
      *)
        case "${ID_LIKE:-}" in
          *rhel*|*fedora*) echo "rhel" ;;
          *debian*) echo "debian" ;;
          *) echo "unknown" ;;
        esac
        ;;
    esac
  else
    echo "unknown"
  fi
}
