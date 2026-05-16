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
    multi-disk)
      echo "fresh-multi-disk-raid0"
      ;;
    *)
      echo "fresh-basic"
      ;;
  esac
}
