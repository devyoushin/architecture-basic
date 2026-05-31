#!/usr/bin/env bash
set -euo pipefail

: "${MYSQL_HOST:?set MYSQL_HOST}"
: "${MYSQL_USER:?set MYSQL_USER}"
: "${MYSQL_PASSWORD:?set MYSQL_PASSWORD}"
: "${MYSQL_DB:?set MYSQL_DB}"

THREADS="${THREADS:-32}"
TIME="${TIME:-300}"
TABLE_SIZE="${TABLE_SIZE:-1000000}"

command -v sysbench >/dev/null 2>&1 || {
  echo "sysbench is required." >&2
  exit 1
}

COMMON_ARGS=(
  oltp_read_write
  --db-driver=mysql
  --mysql-host="${MYSQL_HOST}"
  --mysql-user="${MYSQL_USER}"
  --mysql-password="${MYSQL_PASSWORD}"
  --mysql-db="${MYSQL_DB}"
  --tables=8
  --table-size="${TABLE_SIZE}"
  --threads="${THREADS}"
)

sysbench "${COMMON_ARGS[@]}" prepare
sysbench "${COMMON_ARGS[@]}" --time="${TIME}" --report-interval=10 run
sysbench "${COMMON_ARGS[@]}" cleanup
