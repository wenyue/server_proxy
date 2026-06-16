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

setup_common_stubs() {
  local tmp="$1"
  mkdir -p "$tmp/bin" "$tmp/netdata"
  : > "$tmp/commands.log"
  printf 'NETDATA_API_KEY="11111111-2222-3333-4444-555555555555"\n' > "$tmp/secrets.conf"

  write_executable "$tmp/bin/sudo" '#!/bin/sh
echo "sudo $*" >> "$COMMAND_LOG"
exec "$@"'

  write_executable "$tmp/bin/systemctl" '#!/bin/sh
echo "systemctl $*" >> "$COMMAND_LOG"
exit 0'

  write_executable "$tmp/bin/bash" '#!/bin/sh
if [ "$1" = "script/install_netdata.sh" ]; then
  echo "install_netdata" >> "$COMMAND_LOG"
  exit 0
fi
exec /bin/bash "$@"'
}

test_parent_allows_external_web_and_accepts_child_streams() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  setup_common_stubs "$tmp"
  printf '[global]\n    run as user = netdata\n\n[web]\n    bind to = localhost\n' > "$tmp/netdata/netdata.conf"

  COMMAND_LOG="$tmp/commands.log" \
    PATH="$tmp/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    NETDATA_SECRETS_FILE="$tmp/secrets.conf" \
    NETDATA_CONFIG_DIR="$tmp/netdata" \
    /bin/bash "$ROOT/script/install_netdata_parent.sh" > "$tmp/stdout" 2> "$tmp/stderr" ||
    fail "parent installer failed: $(cat "$tmp/stderr") $(cat "$tmp/stdout")"

  cmp -s "$tmp/netdata/netdata.conf" - <<'EOF' ||
[web]
    bind to = *
EOF
    fail "expected parent installer to own the full netdata.conf"
  grep -q "\\[11111111-2222-3333-4444-555555555555\\]" "$tmp/netdata/stream.conf" ||
    fail "expected parent stream API key section"
  grep -q "enabled = yes" "$tmp/netdata/stream.conf" ||
    fail "expected parent to accept child streams"
}

test_child_keeps_local_web_and_streams_to_parent() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  setup_common_stubs "$tmp"

  write_executable "$tmp/bin/python" '#!/bin/sh
if [ "$1" = "script/registry.py" ] && [ "$2" = "netdata-parent" ]; then
  echo "67.215.234.162:19999"
  exit 0
fi
exit 1'

  COMMAND_LOG="$tmp/commands.log" \
    PATH="$tmp/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    NETDATA_SECRETS_FILE="$tmp/secrets.conf" \
    NETDATA_CONFIG_DIR="$tmp/netdata" \
    PYTHON_BIN=python \
    /bin/bash "$ROOT/script/install_netdata_child.sh" > "$tmp/stdout" 2> "$tmp/stderr" ||
    fail "child installer failed: $(cat "$tmp/stderr") $(cat "$tmp/stdout")"

  cmp -s "$tmp/netdata/netdata.conf" - <<'EOF' ||
[web]
    bind to = localhost
EOF
    fail "expected child installer to own the full netdata.conf"
  grep -q "destination = 67.215.234.162:19999" "$tmp/netdata/stream.conf" ||
    fail "expected child to stream to registry parent"
  grep -q "api key = 11111111-2222-3333-4444-555555555555" "$tmp/netdata/stream.conf" ||
    fail "expected child stream API key"
}

test_parent_allows_external_web_and_accepts_child_streams
test_child_keeps_local_web_and_streams_to_parent

echo "install_netdata tests passed"
