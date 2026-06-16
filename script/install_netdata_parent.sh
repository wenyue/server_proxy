#!/bin/bash
# Install Netdata and configure it to receive metrics from Children.

set -e

SECRETS_FILE="${NETDATA_SECRETS_FILE:-config/secrets.conf}"

echo "📊 Configuring Netdata Parent..."

if [ ! -f "$SECRETS_FILE" ]; then
  echo "   ✗ Missing $SECRETS_FILE (copy config/secrets.example.conf and fill NETDATA_API_KEY)" >&2
  exit 1
fi

# shellcheck disable=SC1090
. "$SECRETS_FILE"

: "${NETDATA_API_KEY:?NETDATA_API_KEY must be set in $SECRETS_FILE}"

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

echo "   → Writing Parent web configuration to $NETDATA_CONF"
sudo tee "$NETDATA_CONF" >/dev/null <<EOF
[web]
    bind to = *
EOF

echo "   → Writing Parent stream configuration to $STREAM_CONF"
sudo tee "$STREAM_CONF" >/dev/null <<EOF
[$NETDATA_API_KEY]
    enabled = yes
EOF

echo "   → Restarting Netdata"
sudo systemctl restart netdata

echo "   ✅ Netdata Parent accepts Child streams"
