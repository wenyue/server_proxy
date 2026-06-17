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

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/systemd"
: > "$tmp/commands.log"

write_executable "$tmp/bin/sudo" '#!/bin/sh
echo "sudo $*" >> "$COMMAND_LOG"
if [ "$1" = "tee" ]; then
  shift
  target="$1"
  cat > "$SYSTEMD_DIR/$(basename "$target")"
  exit 0
fi
if [ "$1" = "systemctl" ]; then
  shift
  echo "systemctl $*" >> "$COMMAND_LOG"
  exit 0
fi
if [ "$1" = "apt" ]; then
  shift
  echo "apt $*" >> "$COMMAND_LOG"
  exit 0
fi
exec "$@"'

COMMAND_LOG="$tmp/commands.log" \
  SYSTEMD_DIR="$tmp/systemd" \
  PATH="$tmp/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  /bin/bash "$ROOT/script/install_registry_refresh_timer.sh" > "$tmp/stdout" 2> "$tmp/stderr" ||
  fail "timer installer failed: $(cat "$tmp/stderr") $(cat "$tmp/stdout")"

timer_file="$tmp/systemd/otaku-registry-refresh.timer"
service_file="$tmp/systemd/otaku-registry-refresh.service"

[ -f "$timer_file" ] || fail "expected timer unit to be written"
[ -f "$service_file" ] || fail "expected service unit to be written"

grep -q "^OnUnitActiveSec=1h$" "$timer_file" ||
  fail "expected hourly refresh interval"
! grep -q "^OnBootSec=" "$timer_file" ||
  fail "expected no boot-delay refresh"
grep -q "^Persistent=true$" "$timer_file" ||
  fail "expected persistent timer"
grep -q "ExecStart=/bin/bash .*script/refresh_registry.sh --reload-nginx" "$service_file" ||
  fail "expected service to run registry refresh with nginx reload"
grep -q "systemctl enable --now otaku-registry-refresh.timer" "$tmp/commands.log" ||
  fail "expected timer to be enabled and started by default"

echo "install_registry_refresh_timer tests passed"
