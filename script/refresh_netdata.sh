#!/bin/bash
# Refresh deployed Netdata configuration from the public network registry.

set -euo pipefail

PYTHON_BIN="${PYTHON_BIN:-python}"
SECRETS_FILE="${NETDATA_SECRETS_FILE:-config/secrets.conf}"
NETDATA_DASHBOARD_PORT="${NETDATA_DASHBOARD_PORT:-19999}"
NETDATA_STREAM_PORT="${NETDATA_STREAM_PORT:-19998}"
NETDATA_NGINX_CONF="${NETDATA_NGINX_CONF:-/etc/nginx/conf.d/netdata.conf}"
NETDATA_HTPASSWD="${NETDATA_HTPASSWD:-/etc/nginx/netdata.htpasswd}"
NETDATA_ROLE="${NETDATA_ROLE:-auto}"
RELOAD_NGINX=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --reload-nginx)
      RELOAD_NGINX=1
      shift
      ;;
    --role)
      NETDATA_ROLE="${2:-}"
      shift 2
      ;;
    -h|--help)
      echo "Usage: bash script/refresh_netdata.sh [--reload-nginx] [--role auto|parent|child]"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
  if command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
  else
    echo "Python is required to refresh Netdata configuration." >&2
    exit 1
  fi
fi

if [ -n "${NETDATA_CONFIG_DIR:-}" ]; then
  :
elif [ -d /etc/netdata ]; then
  NETDATA_CONFIG_DIR="/etc/netdata"
elif [ -d /opt/netdata/etc/netdata ]; then
  NETDATA_CONFIG_DIR="/opt/netdata/etc/netdata"
else
  echo "Netdata config directory not found; skipping Netdata refresh."
  exit 0
fi

if [ ! -f "$SECRETS_FILE" ]; then
  echo "Missing $SECRETS_FILE; cannot refresh Netdata stream credentials." >&2
  exit 1
fi

# shellcheck disable=SC1090
. "$SECRETS_FILE"
: "${NETDATA_API_KEY:?NETDATA_API_KEY must be set in $SECRETS_FILE}"

NETDATA_CONF="$NETDATA_CONFIG_DIR/netdata.conf"
STREAM_CONF="$NETDATA_CONFIG_DIR/stream.conf"

if [ "$NETDATA_ROLE" = "auto" ]; then
  if [ -f "$NETDATA_NGINX_CONF" ]; then
    NETDATA_ROLE="parent"
  else
    NETDATA_ROLE="child"
  fi
fi

if [ "$NETDATA_ROLE" != "parent" ] && [ "$NETDATA_ROLE" != "child" ]; then
  echo "NETDATA_ROLE must be auto, parent, or child." >&2
  exit 2
fi

write_if_changed() {
  local target="$1"
  local tmp
  tmp="$(mktemp)"
  cat > "$tmp"

  if [ -f "$target" ] && cmp -s "$tmp" "$target"; then
    rm -f "$tmp"
    return 1
  fi

  sudo mkdir -p "$(dirname "$target")"
  sudo cp "$tmp" "$target"
  sudo chmod 0644 "$target"
  rm -f "$tmp"
  return 0
}

netdata_changed=0
nginx_changed=0

if [ "$NETDATA_ROLE" = "child" ]; then
  NETDATA_PARENT="$("$PYTHON_BIN" script/registry.py netdata-parent)"
  NETDATA_PARENT="${NETDATA_PARENT%:*}:$NETDATA_STREAM_PORT"

  if write_if_changed "$NETDATA_CONF" <<EOF
[web]
    bind to = localhost
EOF
  then
    netdata_changed=1
  fi

  if write_if_changed "$STREAM_CONF" <<EOF
[stream]
    enabled = yes
    destination = $NETDATA_PARENT
    api key = $NETDATA_API_KEY
EOF
  then
    netdata_changed=1
  fi
else
  NETDATA_PARENT="$("$PYTHON_BIN" script/registry.py netdata-parent)"
  NETDATA_PROXY_HOST="${NETDATA_PROXY_HOST:-${NETDATA_PARENT%:*}}"
  NETDATA_NGINX_LISTEN_HOST="${NETDATA_NGINX_LISTEN_HOST:-$NETDATA_PROXY_HOST}"

  if write_if_changed "$NETDATA_CONF" <<EOF
[web]
    bind to = 127.0.0.1:$NETDATA_DASHBOARD_PORT=dashboard|registry|badges|management|netdata.conf *:$NETDATA_STREAM_PORT=streaming
EOF
  then
    netdata_changed=1
  fi

  if write_if_changed "$STREAM_CONF" <<EOF
[$NETDATA_API_KEY]
    enabled = yes
EOF
  then
    netdata_changed=1
  fi

  if write_if_changed "$NETDATA_NGINX_CONF" <<EOF
upstream netdata_parent {
    server 127.0.0.1:$NETDATA_DASHBOARD_PORT;
    keepalive 64;
}

server {
    listen $NETDATA_NGINX_LISTEN_HOST:$NETDATA_DASHBOARD_PORT;
    server_name _;

    auth_basic "Netdata";
    auth_basic_user_file $NETDATA_HTPASSWD;

    location / {
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Server \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_pass http://netdata_parent;
        proxy_http_version 1.1;
        proxy_pass_request_headers on;
        proxy_set_header Connection "keep-alive";
        proxy_store off;
    }
}
EOF
  then
    nginx_changed=1
  fi
fi

if [ "$netdata_changed" -eq 1 ]; then
  sudo systemctl restart netdata
fi

if [ "$nginx_changed" -eq 1 ] && [ "$RELOAD_NGINX" -eq 1 ]; then
  sudo nginx -t
  sudo systemctl reload nginx
fi

if [ "$netdata_changed" -eq 0 ] && [ "$nginx_changed" -eq 0 ]; then
  echo "Netdata configuration unchanged"
else
  echo "Netdata configuration refreshed"
fi
