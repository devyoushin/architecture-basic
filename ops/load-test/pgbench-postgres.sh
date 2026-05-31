#!/usr/bin/env bash
set -euo pipefail

: "${PGHOST:?set PGHOST}"
: "${PGUSER:?set PGUSER}"
: "${PGDATABASE:?set PGDATABASE}"

SCALE="${SCALE:-100}"
CLIENTS="${CLIENTS:-50}"
JOBS="${JOBS:-8}"
TIME="${TIME:-300}"

command -v pgbench >/dev/null 2>&1 || {
  echo "pgbench is required." >&2
  exit 1
}

pgbench -i -s "${SCALE}" "${PGDATABASE}"
pgbench \
  -c "${CLIENTS}" \
  -j "${JOBS}" \
  -T "${TIME}" \
  -P 10 \
  "${PGDATABASE}"
