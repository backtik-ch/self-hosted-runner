#!/bin/bash
set -euo pipefail

RUNNER_DIR="/home/docker/actions-runner"

if [ ! -f "${RUNNER_DIR}/.runner" ]; then
  echo "unhealthy: runner is not configured"
  exit 1
fi

if pgrep -f "${RUNNER_DIR}/bin/Runner.Listener" >/dev/null 2>&1; then
  echo "healthy: Runner.Listener is running"
  exit 0
fi

if pgrep -f "${RUNNER_DIR}/run.sh" >/dev/null 2>&1; then
  echo "healthy: run.sh is running"
  exit 0
fi

echo "unhealthy: runner process is not running"
exit 1
