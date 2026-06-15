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

run_installer() {
  local tmp="$1"
  COMMAND_LOG="$tmp/commands.log" \
    PATH="$tmp/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    bash "$ROOT/script/install_shadowsocks.sh" > "$tmp/stdout" 2> "$tmp/stderr"
}

setup_common_stubs() {
  local tmp="$1"
  mkdir -p "$tmp/bin"
  : > "$tmp/commands.log"

  write_executable "$tmp/bin/sudo" '#!/bin/sh
echo "sudo $*" >> "$COMMAND_LOG"
exec "$@"'

  write_executable "$tmp/bin/systemctl" '#!/bin/sh
echo "systemctl $*" >> "$COMMAND_LOG"
exit 0'

  write_executable "$tmp/bin/apt" '#!/bin/sh
echo "apt $*" >> "$COMMAND_LOG"
exit 0'
}

test_removes_docker_container_publishing_shadowsocks_port_before_start() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  setup_common_stubs "$tmp"

  write_executable "$tmp/bin/docker" '#!/bin/sh
echo "docker $*" >> "$COMMAND_LOG"
if [ "$1" = "ps" ] && [ "$2" = "-a" ]; then
  exit 0
fi
if [ "$1" = "ps" ] && [ "$2" = "--filter" ]; then
  echo "abc123 old-ss"
  exit 0
fi
if [ "$1" = "run" ]; then
  echo "new-container-id"
  exit 0
fi
exit 0'

  write_executable "$tmp/bin/ss" '#!/bin/sh
echo "ss $*" >> "$COMMAND_LOG"
exit 0'

  run_installer "$tmp" || fail "installer failed: $(cat "$tmp/stderr") $(cat "$tmp/stdout")"

  grep -q "docker rm -f abc123" "$tmp/commands.log" ||
    fail "expected conflicting Docker container to be removed"
  grep -q "docker run -d" "$tmp/commands.log" ||
    fail "expected Shadowsocks container to start"
  grep -q "Shadowsocks ready on port 8388" "$tmp/stdout" ||
    fail "expected success message"
}

test_kills_non_docker_process_using_shadowsocks_port_before_start() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  setup_common_stubs "$tmp"

  write_executable "$tmp/bin/docker" '#!/bin/sh
echo "docker $*" >> "$COMMAND_LOG"
if [ "$1" = "ps" ]; then
  exit 0
fi
if [ "$1" = "run" ]; then
  echo "new-container-id"
  exit 0
fi
exit 0'

  write_executable "$tmp/bin/ss" '#!/bin/sh
echo "ss $*" >> "$COMMAND_LOG"
if [ ! -f "${COMMAND_LOG}.fuser_ran" ]; then
  echo "tcp LISTEN 0 4096 0.0.0.0:8388 0.0.0.0:* users:(('\''old'\'',pid=123,fd=3))"
fi
exit 0'

  write_executable "$tmp/bin/fuser" '#!/bin/sh
echo "fuser $*" >> "$COMMAND_LOG"
touch "${COMMAND_LOG}.fuser_ran"
exit 0'

  run_installer "$tmp" || fail "installer failed: $(cat "$tmp/stderr") $(cat "$tmp/stdout")"

  grep -q "fuser -k 8388/tcp" "$tmp/commands.log" ||
    fail "expected TCP port owner to be killed"
  grep -q "fuser -k 8388/udp" "$tmp/commands.log" ||
    fail "expected UDP port owner to be killed"
  grep -q "docker run -d" "$tmp/commands.log" ||
    fail "expected Shadowsocks container to start"
}

test_removes_docker_container_publishing_shadowsocks_port_before_start
test_kills_non_docker_process_using_shadowsocks_port_before_start

echo "install_shadowsocks tests passed"
