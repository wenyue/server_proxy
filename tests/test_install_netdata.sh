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
if [ "$1" = "chown" ]; then
  exit 0
fi
exec "$@"'

  write_executable "$tmp/bin/systemctl" '#!/bin/sh
echo "systemctl $*" >> "$COMMAND_LOG"
exit 0'

  write_executable "$tmp/bin/apt" '#!/bin/sh
echo "apt $*" >> "$COMMAND_LOG"
exit 0'

  write_executable "$tmp/bin/nginx" '#!/bin/sh
echo "nginx $*" >> "$COMMAND_LOG"
exit 0'

  write_executable "$tmp/bin/openssl" '#!/bin/sh
echo "openssl $*" >> "$COMMAND_LOG"
if [ "$1" = "rand" ]; then
  echo "generatedpassword"
  exit 0
fi
if [ "$1" = "passwd" ]; then
  printf "%s\n" "$""apr1$""testhash"
  exit 0
fi
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
  mkdir -p "$tmp/nginx/conf.d"

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
    NETDATA_NGINX_CONF="$tmp/nginx/conf.d/netdata.conf" \
    NETDATA_HTPASSWD="$tmp/nginx/netdata.htpasswd" \
    NETDATA_WEB_USER="admin" \
    NETDATA_DASHBOARD_PORT="19999" \
    NETDATA_STREAM_PORT="19998" \
    PYTHON_BIN=python \
    /bin/bash "$ROOT/script/install_netdata_parent.sh" > "$tmp/stdout" 2> "$tmp/stderr" ||
    fail "parent installer failed: $(cat "$tmp/stderr") $(cat "$tmp/stdout")"

  cmp -s "$tmp/netdata/netdata.conf" - <<'EOF' ||
[web]
    bind to = 127.0.0.1:19999=dashboard|registry|badges|management|netdata.conf *:19998=streaming
EOF
    fail "expected parent installer to own the full netdata.conf"
  grep -q "auth_basic_user_file .*netdata.htpasswd" "$tmp/nginx/conf.d/netdata.conf" ||
    fail "expected parent nginx reverse proxy to enable basic auth"
  grep -q "server 127.0.0.1:19999;" "$tmp/nginx/conf.d/netdata.conf" ||
    fail "expected parent nginx reverse proxy to use the local dashboard port"
  grep -q "listen 67.215.234.162:19999;" "$tmp/nginx/conf.d/netdata.conf" ||
    fail "expected parent nginx reverse proxy to listen on the public parent address"
  ! grep -q "19997" "$tmp/netdata/netdata.conf" "$tmp/nginx/conf.d/netdata.conf" ||
    fail "expected parent installer not to use legacy internal dashboard port 19997"
  grep -q "proxy_pass http://netdata_parent;" "$tmp/nginx/conf.d/netdata.conf" ||
    fail "expected parent nginx reverse proxy to proxy to Netdata"
  grep -q 'admin:$apr1\$testhash' "$tmp/nginx/netdata.htpasswd" ||
    fail "expected parent nginx htpasswd file"
  grep -q "chown root:www-data $tmp/nginx/netdata.htpasswd" "$tmp/commands.log" ||
    fail "expected htpasswd file to be readable by nginx worker group"
  grep -q "nginx -t" "$tmp/commands.log" ||
    fail "expected nginx config validation"
  grep -q "http://admin:generatedpassword@67.215.234.162:19999/" "$tmp/stdout" ||
    fail "expected generated parent dashboard URL to be printed"
  grep -q "generatedpassword" "$tmp/stdout" ||
    fail "expected generated parent dashboard password to be printed"
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
    NETDATA_STREAM_PORT="19998" \
    PYTHON_BIN=python \
    /bin/bash "$ROOT/script/install_netdata_child.sh" > "$tmp/stdout" 2> "$tmp/stderr" ||
    fail "child installer failed: $(cat "$tmp/stderr") $(cat "$tmp/stdout")"

  cmp -s "$tmp/netdata/netdata.conf" - <<'EOF' ||
[web]
    bind to = localhost
EOF
    fail "expected child installer to own the full netdata.conf"
  grep -q "destination = 67.215.234.162:19998" "$tmp/netdata/stream.conf" ||
    fail "expected child to stream to registry parent"
  grep -q "api key = 11111111-2222-3333-4444-555555555555" "$tmp/netdata/stream.conf" ||
    fail "expected child stream API key"
}

test_child_refresh_updates_existing_config_and_is_idempotent() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  setup_common_stubs "$tmp"
  printf '[web]\n    bind to = 0.0.0.0\n' > "$tmp/netdata/netdata.conf"
  printf '[stream]\n    enabled = yes\n    destination = old-parent:19998\n    api key = old\n' > "$tmp/netdata/stream.conf"

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
    NETDATA_ROLE=child \
    NETDATA_STREAM_PORT="19998" \
    PYTHON_BIN=python \
    /bin/bash "$ROOT/script/refresh_netdata.sh" > "$tmp/stdout" 2> "$tmp/stderr" ||
    fail "child refresh failed: $(cat "$tmp/stderr") $(cat "$tmp/stdout")"

  cmp -s "$tmp/netdata/netdata.conf" - <<'EOF' ||
[web]
    bind to = localhost
EOF
    fail "expected child refresh to own netdata.conf"
  grep -q "destination = 67.215.234.162:19998" "$tmp/netdata/stream.conf" ||
    fail "expected child refresh to update stream destination"
  grep -q "api key = 11111111-2222-3333-4444-555555555555" "$tmp/netdata/stream.conf" ||
    fail "expected child refresh to keep stream API key current"
  grep -q "systemctl restart netdata" "$tmp/commands.log" ||
    fail "expected changed child refresh to restart netdata"

  : > "$tmp/commands.log"
  COMMAND_LOG="$tmp/commands.log" \
    PATH="$tmp/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    NETDATA_SECRETS_FILE="$tmp/secrets.conf" \
    NETDATA_CONFIG_DIR="$tmp/netdata" \
    NETDATA_ROLE=child \
    NETDATA_STREAM_PORT="19998" \
    PYTHON_BIN=python \
    /bin/bash "$ROOT/script/refresh_netdata.sh" > "$tmp/stdout2" 2> "$tmp/stderr2" ||
    fail "second child refresh failed: $(cat "$tmp/stderr2") $(cat "$tmp/stdout2")"

  ! grep -q "systemctl restart netdata" "$tmp/commands.log" ||
    fail "expected unchanged child refresh not to restart netdata"
}

test_registry_refresh_runs_netdata_refresh() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  setup_common_stubs "$tmp"

  write_executable "$tmp/bin/python" '#!/bin/sh
if [ "$1" = "script/registry.py" ] && [ "$2" = "refresh" ]; then
  echo "refreshed registry outputs"
  exit 0
fi
if [ "$1" = "script/registry.py" ] && [ "$2" = "netdata-parent" ]; then
  echo "203.0.113.10:19999"
  exit 0
fi
exit 1'

  COMMAND_LOG="$tmp/commands.log" \
    PATH="$tmp/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    NETDATA_SECRETS_FILE="$tmp/secrets.conf" \
    NETDATA_CONFIG_DIR="$tmp/netdata" \
    NETDATA_ROLE=child \
    PYTHON_BIN=python \
    /bin/bash "$ROOT/script/refresh_registry.sh" --reload-nginx > "$tmp/stdout" 2> "$tmp/stderr" ||
    fail "registry refresh failed: $(cat "$tmp/stderr") $(cat "$tmp/stdout")"

  grep -q "destination = 203.0.113.10:19998" "$tmp/netdata/stream.conf" ||
    fail "expected registry refresh to refresh netdata child destination"
}

test_parent_refresh_updates_nginx_proxy_and_reloads_when_requested() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  setup_common_stubs "$tmp"
  mkdir -p "$tmp/nginx/conf.d"
  printf 'old htpasswd\n' > "$tmp/nginx/netdata.htpasswd"
  printf 'old nginx\n' > "$tmp/nginx/conf.d/netdata.conf"

  write_executable "$tmp/bin/python" '#!/bin/sh
if [ "$1" = "script/registry.py" ] && [ "$2" = "netdata-parent" ]; then
  echo "198.51.100.20:19999"
  exit 0
fi
exit 1'

  COMMAND_LOG="$tmp/commands.log" \
    PATH="$tmp/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    NETDATA_SECRETS_FILE="$tmp/secrets.conf" \
    NETDATA_CONFIG_DIR="$tmp/netdata" \
    NETDATA_NGINX_CONF="$tmp/nginx/conf.d/netdata.conf" \
    NETDATA_HTPASSWD="$tmp/nginx/netdata.htpasswd" \
    NETDATA_ROLE=parent \
    PYTHON_BIN=python \
    /bin/bash "$ROOT/script/refresh_netdata.sh" --reload-nginx > "$tmp/stdout" 2> "$tmp/stderr" ||
    fail "parent refresh failed: $(cat "$tmp/stderr") $(cat "$tmp/stdout")"

  grep -q "listen 198.51.100.20:19999;" "$tmp/nginx/conf.d/netdata.conf" ||
    fail "expected parent refresh to update nginx listen host"
  grep -q "auth_basic_user_file $tmp/nginx/netdata.htpasswd;" "$tmp/nginx/conf.d/netdata.conf" ||
    fail "expected parent refresh to preserve htpasswd reference"
  grep -q "\\[11111111-2222-3333-4444-555555555555\\]" "$tmp/netdata/stream.conf" ||
    fail "expected parent refresh to keep stream API key section"
  grep -q "systemctl restart netdata" "$tmp/commands.log" ||
    fail "expected parent refresh to restart netdata after netdata config change"
  grep -q "nginx -t" "$tmp/commands.log" ||
    fail "expected parent refresh to validate nginx after nginx config change"
  grep -q "systemctl reload nginx" "$tmp/commands.log" ||
    fail "expected parent refresh to reload nginx after nginx config change"
  cmp -s "$tmp/nginx/netdata.htpasswd" - <<'EOF' ||
old htpasswd
EOF
    fail "expected parent refresh not to rewrite htpasswd credentials"
}

test_parent_allows_external_web_and_accepts_child_streams
test_child_keeps_local_web_and_streams_to_parent
test_child_refresh_updates_existing_config_and_is_idempotent
test_registry_refresh_runs_netdata_refresh
test_parent_refresh_updates_nginx_proxy_and_reloads_when_requested

echo "install_netdata tests passed"
