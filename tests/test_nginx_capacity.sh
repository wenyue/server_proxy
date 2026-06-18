#!/bin/bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

write_executable() {
  local path="$1"
  local content="$2"
  printf '%s\n' "$content" > "$path"
  chmod +x "$path"
}

test_nginx_config_raises_stream_capacity() {
  grep -q '^worker_rlimit_nofile 200000;$' "$ROOT/config/nginx.conf" ||
    fail "expected nginx worker_rlimit_nofile to be raised"
  grep -q 'worker_connections 32768;' "$ROOT/config/nginx.conf" ||
    fail "expected nginx worker_connections to be raised"
  grep -q 'multi_accept on;' "$ROOT/config/nginx.conf" ||
    fail "expected nginx multi_accept to be enabled"
}

test_configure_script_installs_nofile_override() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  mkdir -p "$tmp/bin" "$tmp/systemd"
  : > "$tmp/commands.log"

  write_executable "$tmp/bin/sudo" '#!/bin/sh
echo "sudo $*" >> "$COMMAND_LOG"
if [ "$1" = "tee" ]; then
  shift
  exec tee "$@"
fi
exec "$@"'

  write_executable "$tmp/bin/systemctl" '#!/bin/sh
echo "systemctl $*" >> "$COMMAND_LOG"
exit 0'

  COMMAND_LOG="$tmp/commands.log" \
    NGINX_SYSTEMD_OVERRIDE_DIR="$tmp/systemd/nginx.service.d" \
    PATH="$tmp/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    /bin/bash "$ROOT/script/configure_nginx_limits.sh" > "$tmp/stdout" 2> "$tmp/stderr" ||
    fail "nginx limits configuration failed: $(cat "$tmp/stderr") $(cat "$tmp/stdout")"

  local override="$tmp/systemd/nginx.service.d/override.conf"
  [ -f "$override" ] || fail "expected nginx systemd override to be written"
  grep -q '^\[Service\]$' "$override" ||
    fail "expected systemd service section"
  grep -q '^LimitNOFILE=524288$' "$override" ||
    fail "expected nginx systemd LimitNOFILE override"
  grep -q 'systemctl daemon-reload' "$tmp/commands.log" ||
    fail "expected systemd daemon-reload after writing override"
}

test_restart_script_only_validates_and_restarts_nginx() {
  ! grep -q 'NGINX_SYSTEMD_OVERRIDE_DIR\|LimitNOFILE\|daemon-reload' "$ROOT/script/validate_and_restart_nginx.sh" ||
    fail "expected nginx restart script not to configure systemd file limits"
}

test_node_setup_configures_limits_before_restart() {
  grep -q 'bash script/configure_nginx_limits.sh' "$ROOT/setup-node.sh" ||
    fail "expected node setup to configure nginx limits"
  local configure_line restart_line
  configure_line="$(grep -n 'bash script/configure_nginx_limits.sh' "$ROOT/setup-node.sh" | head -n 1 | cut -d: -f1)"
  restart_line="$(grep -n 'bash script/validate_and_restart_nginx.sh' "$ROOT/setup-node.sh" | head -n 1 | cut -d: -f1)"
  [ "$configure_line" -lt "$restart_line" ] ||
    fail "expected nginx limits to be configured before nginx restart"
}

test_nginx_config_raises_stream_capacity
test_configure_script_installs_nofile_override
test_restart_script_only_validates_and_restarts_nginx
test_node_setup_configures_limits_before_restart

echo "nginx capacity tests passed"
