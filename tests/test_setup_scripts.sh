#!/bin/bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

assert_file_exists() {
  local path="$1"
  if [ ! -f "$REPO_ROOT/$path" ]; then
    echo "Expected file to exist: $path" >&2
    exit 1
  fi
}

assert_file_missing() {
  local path="$1"
  if [ -e "$REPO_ROOT/$path" ]; then
    echo "Expected file to be absent: $path" >&2
    exit 1
  fi
}

assert_contains() {
  local path="$1"
  local text="$2"
  if ! grep -Fq -- "$text" "$REPO_ROOT/$path"; then
    echo "Expected $path to contain: $text" >&2
    exit 1
  fi
}

assert_not_contains() {
  local path="$1"
  local text="$2"
  if grep -Fq -- "$text" "$REPO_ROOT/$path"; then
    echo "Expected $path not to contain: $text" >&2
    exit 1
  fi
}

assert_file_missing "setup.sh"
assert_file_missing "netdata.conf"
assert_file_missing "iperf-lines.csv"
assert_file_missing "cron"
assert_file_missing "nginx"

assert_file_exists "setup-node.sh"
assert_contains "setup-node.sh" "bash script/install_prerequisites.sh"
assert_contains "setup-node.sh" "bash script/install_shadowsocks.sh"
assert_contains "setup-node.sh" "bash script/copy_nginx_config.sh"
assert_contains "setup-node.sh" "bash script/validate_and_restart_nginx.sh"
assert_contains "setup-node.sh" "bash script/install_netdata_child.sh"

assert_file_exists "setup-main.sh"
assert_contains "setup-main.sh" "bash script/install_shadowsocks.sh"
assert_contains "setup-main.sh" "bash script/install_iperf_server.sh"
assert_contains "setup-main.sh" "bash script/install_netdata_parent.sh"
assert_not_contains "setup-main.sh" "copy_nginx_config.sh"
assert_not_contains "setup-main.sh" "validate_and_restart_nginx.sh"
assert_not_contains "setup-main.sh" "setup_logrotate.sh"
assert_not_contains "setup-main.sh" "enable_cn2_mode.sh"
assert_not_contains "setup-main.sh" "disable_cn2_mode.sh"

assert_file_exists "config/netdata.conf"
assert_contains "config/netdata.conf" 'NETDATA_PARENT="ipfs.otakuroom.net:19999"'
assert_contains "config/netdata.conf" 'NETDATA_API_KEY="7f0c7a76-0e46-4d3d-96df-bd8b08753b39"'
assert_file_exists "config/cn2_schedule"
assert_file_exists "config/nginx/nginx.conf"
assert_file_exists "config/nginx/logrotate.conf"
assert_file_exists "config/nginx/streams/iperf.conf"

assert_file_exists "script/install_netdata.sh"
assert_file_exists "script/install_netdata_child.sh"
assert_file_exists "script/install_netdata_parent.sh"
assert_file_exists "script/install_iperf_server.sh"

assert_file_exists "config/iperf-lines.csv"
assert_contains "config/iperf-lines.csv" "Name,Host,Port"
assert_file_exists "test-iperf-lines.sh"
assert_contains "test-iperf-lines.sh" "iperf3 -c"
assert_contains "test-iperf-lines.sh" "--reverse"
assert_file_exists "test-iperf-lines.ps1"
assert_contains "test-iperf-lines.ps1" "Import-Csv"
assert_contains "test-iperf-lines.ps1" "iperf3"

echo "setup script structure checks passed"
