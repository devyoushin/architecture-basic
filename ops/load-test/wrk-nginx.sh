#!/usr/bin/env bash
set -euo pipefail

TARGET_URL="${1:?usage: ./wrk-nginx.sh <url> [connections] [threads] [duration]}"
CONNECTIONS="${2:-400}"
THREADS="${3:-8}"
DURATION="${4:-60s}"

command -v wrk >/dev/null 2>&1 || {
  echo "wrk is required. Install wrk before running this script." >&2
  exit 1
}

echo "target=${TARGET_URL}"
echo "connections=${CONNECTIONS} threads=${THREADS} duration=${DURATION}"

wrk \
  -t "${THREADS}" \
  -c "${CONNECTIONS}" \
  -d "${DURATION}" \
  --latency \
  "${TARGET_URL}"
