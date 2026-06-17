#!/bin/bash
# Install Netdata and configure it to receive metrics from Children.

set -e

SECRETS_FILE="${NETDATA_SECRETS_FILE:-config/secrets.conf}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
NETDATA_DASHBOARD_PORT="${NETDATA_DASHBOARD_PORT:-19999}"
NETDATA_STREAM_PORT="${NETDATA_STREAM_PORT:-19998}"
NETDATA_WEB_USER="${NETDATA_WEB_USER:-netdata}"
NETDATA_NGINX_CONF="${NETDATA_NGINX_CONF:-/etc/nginx/conf.d/netdata.conf}"
NETDATA_HTPASSWD="${NETDATA_HTPASSWD:-/etc/nginx/netdata.htpasswd}"
NETDATA_WEB_PASSWORD_FILE="${NETDATA_WEB_PASSWORD_FILE:-$NETDATA_HTPASSWD.password}"

echo "📊 Configuring Netdata Parent..."

if [ ! -f "$SECRETS_FILE" ]; then
  echo "   ✗ Missing $SECRETS_FILE (copy config/secrets.example.conf and fill NETDATA_API_KEY)" >&2
  exit 1
fi

# shellcheck disable=SC1090
. "$SECRETS_FILE"

: "${NETDATA_API_KEY:?NETDATA_API_KEY must be set in $SECRETS_FILE}"

if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
  if command -v python >/dev/null 2>&1; then
    PYTHON_BIN="python"
  else
    echo "   ✗ Python is required to read the public network registry" >&2
    exit 1
  fi
fi

if ! command -v nginx >/dev/null 2>&1; then
  echo "   → Installing nginx web server"
  sudo apt update -qq
  sudo apt install -y nginx-full
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "   → Installing openssl"
  sudo apt update -qq
  sudo apt install -y openssl
fi

GENERATED_NETDATA_WEB_PASSWORD=0
if [ -n "${NETDATA_WEB_PASSWORD:-}" ]; then
  :
elif [ -s "$NETDATA_WEB_PASSWORD_FILE" ]; then
  if [ -r "$NETDATA_WEB_PASSWORD_FILE" ]; then
    IFS= read -r NETDATA_WEB_PASSWORD < "$NETDATA_WEB_PASSWORD_FILE"
  else
    NETDATA_WEB_PASSWORD="$(sudo sed -n '1p' "$NETDATA_WEB_PASSWORD_FILE")"
  fi
  if [ -z "$NETDATA_WEB_PASSWORD" ]; then
    echo "   ✗ Netdata dashboard password file is empty: $NETDATA_WEB_PASSWORD_FILE" >&2
    exit 1
  fi
elif [ -s "$NETDATA_HTPASSWD" ]; then
  echo "   ✗ Existing Netdata htpasswd found at $NETDATA_HTPASSWD, but the plaintext password is not available." >&2
  echo "     Set NETDATA_WEB_PASSWORD or create $NETDATA_WEB_PASSWORD_FILE so the current password can be printed." >&2
  exit 1
else
  NETDATA_WEB_PASSWORD="$(openssl rand -hex 16)"
  GENERATED_NETDATA_WEB_PASSWORD=1
fi

bash script/install_netdata.sh

if [ -n "${NETDATA_CONFIG_DIR:-}" ]; then
  :
elif [ -d /etc/netdata ]; then
  NETDATA_CONFIG_DIR="/etc/netdata"
elif [ -d /opt/netdata/etc/netdata ]; then
  NETDATA_CONFIG_DIR="/opt/netdata/etc/netdata"
fi

if [ ! -d "${NETDATA_CONFIG_DIR:-}" ]; then
  echo "   ✗ Netdata config directory not found" >&2
  exit 1
fi

NETDATA_CONF="$NETDATA_CONFIG_DIR/netdata.conf"
STREAM_CONF="$NETDATA_CONFIG_DIR/stream.conf"
NETDATA_PARENT="$("$PYTHON_BIN" script/registry.py netdata-parent)"
NETDATA_PROXY_HOST="${NETDATA_PROXY_HOST:-${NETDATA_PARENT%:*}}"
NETDATA_NGINX_LISTEN_HOST="${NETDATA_NGINX_LISTEN_HOST:-$NETDATA_PROXY_HOST}"

echo "   → Writing Parent web configuration to $NETDATA_CONF"
sudo tee "$NETDATA_CONF" >/dev/null <<EOF
[web]
    bind to = 127.0.0.1:$NETDATA_DASHBOARD_PORT=dashboard|registry|badges|management|netdata.conf *:$NETDATA_STREAM_PORT=streaming
EOF

echo "   → Writing Parent stream configuration to $STREAM_CONF"
sudo tee "$STREAM_CONF" >/dev/null <<EOF
[$NETDATA_API_KEY]
    enabled = yes
EOF

echo "   → Writing nginx Basic Auth credentials to $NETDATA_HTPASSWD"
sudo mkdir -p "$(dirname "$NETDATA_HTPASSWD")"
printf '%s:%s\n' "$NETDATA_WEB_USER" "$(openssl passwd -apr1 "$NETDATA_WEB_PASSWORD")" | sudo tee "$NETDATA_HTPASSWD" >/dev/null
sudo chown root:www-data "$NETDATA_HTPASSWD"
sudo chmod 640 "$NETDATA_HTPASSWD"

echo "   → Saving Netdata dashboard password to $NETDATA_WEB_PASSWORD_FILE"
sudo mkdir -p "$(dirname "$NETDATA_WEB_PASSWORD_FILE")"
printf '%s\n' "$NETDATA_WEB_PASSWORD" | sudo tee "$NETDATA_WEB_PASSWORD_FILE" >/dev/null
sudo chown root:root "$NETDATA_WEB_PASSWORD_FILE"
sudo chmod 600 "$NETDATA_WEB_PASSWORD_FILE"

echo "   → Writing nginx reverse proxy configuration to $NETDATA_NGINX_CONF"
sudo mkdir -p "$(dirname "$NETDATA_NGINX_CONF")"
sudo tee "$NETDATA_NGINX_CONF" >/dev/null <<EOF
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

echo "   → Restarting Netdata"
sudo systemctl restart netdata

echo "   → Restarting nginx"
sudo systemctl enable nginx
sudo nginx -t
sudo systemctl restart nginx

echo "   ✅ Netdata Parent accepts Child streams on port $NETDATA_STREAM_PORT and serves the dashboard through nginx on port $NETDATA_DASHBOARD_PORT"
echo "      Netdata dashboard user: $NETDATA_WEB_USER"
echo "      Netdata dashboard URL: http://$NETDATA_WEB_USER:$NETDATA_WEB_PASSWORD@$NETDATA_PROXY_HOST:$NETDATA_DASHBOARD_PORT/"
if [ "$GENERATED_NETDATA_WEB_PASSWORD" -eq 1 ]; then
  echo "      Netdata dashboard generated password: $NETDATA_WEB_PASSWORD"
else
  echo "      Netdata dashboard password: $NETDATA_WEB_PASSWORD"
fi
