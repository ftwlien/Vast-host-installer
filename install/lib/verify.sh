#!/usr/bin/env bash
set -euo pipefail

verify_host_state() {
  local failed=0
  echo "VERIFY_BEGIN"
  echo "CHECK=nvidia-smi"
  if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
    nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n1 | sed 's/^/RESULT=driver:/'
  else
    echo "RESULT=nvidia-smi:missing"
    failed=1
  fi

  echo "CHECK=docker"
  if systemctl is-active docker >/dev/null 2>&1; then
    echo "RESULT=docker:active"
  else
    echo "RESULT=docker:inactive"
    failed=1
  fi

  echo "CHECK=nvidia-runtime"
  if docker info --format '{{json .Runtimes}}' 2>/dev/null | grep -q 'nvidia'; then
    echo "RESULT=nvidia-runtime:present"
  else
    echo "RESULT=nvidia-runtime:missing"
    failed=1
  fi

  echo "CHECK=vast-service"
  if systemctl is-active vastai >/dev/null 2>&1; then
    echo "RESULT=vastai:active"
  else
    echo "RESULT=vastai:inactive"
    failed=1
  fi

  echo "CHECK=vast-port-range"
  if [[ -f /var/lib/vastai_kaalia/host_port_range ]]; then
    printf 'RESULT=host-port-range:%s\n' "$(cat /var/lib/vastai_kaalia/host_port_range 2>/dev/null)"
  else
    echo "RESULT=host-port-range:missing"
    echo "WARN=host-port-range file missing; not failing because Vast interactive setup may own port collection"
  fi

  echo "CHECK=console-reachability"
  if curl -I -fsS https://console.vast.ai >/dev/null 2>&1; then
    echo "RESULT=console:ok"
  else
    echo "RESULT=console:fail"
  fi
  echo "VERIFY_END"
  if [[ "$failed" -ne 0 ]]; then
    die "Final verification failed. Vast setup is not complete; see VERIFY results above."
  fi
}

preflight_phase3() {
  local failed=0 next_phase=""
  banner "Phase 3 Preflight Check"

  echo "CHECK=resume-state"
  if [[ -f /var/lib/vast-host-installer/resume.env ]]; then
    # shellcheck disable=SC1091
    next_phase="$(grep -E '^NEXT_PHASE=' /var/lib/vast-host-installer/resume.env 2>/dev/null | cut -d= -f2- | sed "s/^'//;s/'$//")"
    if [[ "$next_phase" == "after-nvidia-reboot" ]]; then
      echo "RESULT=resume-state:phase3-ready"
    else
      echo "RESULT=resume-state:unexpected:${next_phase:-missing-next-phase}"
      failed=1
    fi
  else
    echo "RESULT=resume-state:missing"
    failed=1
  fi

  echo "CHECK=nvidia-smi"
  if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
    nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n1 | sed 's/^/RESULT=driver:/'
  else
    echo "RESULT=nvidia-smi:failed"
    failed=1
  fi

  echo "CHECK=nvidia-module"
  if lsmod | awk '{print $1}' | grep -qx 'nvidia'; then
    echo "RESULT=nvidia-module:loaded"
  else
    echo "RESULT=nvidia-module:not-loaded"
    failed=1
  fi

  echo "CHECK=secure-boot"
  if command -v mokutil >/dev/null 2>&1; then
    if mokutil --sb-state 2>/dev/null | grep -qi 'enabled'; then
      echo "RESULT=secure-boot:enabled"
      echo "WARN=secure boot is enabled; NVIDIA may be blocked unless modules are signed/enrolled"
    else
      echo "RESULT=secure-boot:not-enabled"
    fi
  else
    echo "RESULT=secure-boot:mokutil-missing"
  fi

  echo "CHECK=console-reachability"
  if curl -I -fsS https://console.vast.ai >/dev/null 2>&1; then
    echo "RESULT=console:ok"
  else
    echo "RESULT=console:fail"
    failed=1
  fi

  if [[ "$failed" -eq 0 ]]; then
    success_banner "READY FOR PHASE 3"
    command_box "sudo /opt/vast-host-installer/bin/vast-host-installer --resume"
  else
    die "Phase 3 preflight failed. Fix the failed checks above before running --resume."
  fi
}
