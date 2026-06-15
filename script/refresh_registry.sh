#!/bin/bash
# Refresh derived configs from the public network registry.

set -euo pipefail

PYTHON_BIN="${PYTHON_BIN:-python}"

if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
  if command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
  else
    echo "Python is required to refresh the network registry outputs." >&2
    exit 1
  fi
fi

RELOAD_NGINX=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --reload-nginx)
      RELOAD_NGINX=1
      shift
      ;;
    -h|--help)
      echo "Usage: bash script/refresh_registry.sh [--reload-nginx]"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

args=(refresh --nginx-output-dir /etc/nginx/streams)
if [ "$RELOAD_NGINX" -eq 1 ]; then
  args+=(--reload-nginx)
fi

"$PYTHON_BIN" script/registry.py "${args[@]}"
