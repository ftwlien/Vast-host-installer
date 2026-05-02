#!/usr/bin/env bash
set -euo pipefail

infer_profile_from_layout() {
  local layout
  layout="$(classify_layout)"
  case "$layout" in
    single-disk)
      echo "fresh-single-disk"
      ;;
    two-disk)
      echo "fresh-two-disk"
      ;;
    *)
      echo "fresh-basic"
      ;;
  esac
}
