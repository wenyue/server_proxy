#!/bin/bash
# Install Netdata and configure it to receive metrics from Children.

set -e

CONFIG_FILE="${NETDATA_CONFIG_FILE:-config/netdata.conf}"

echo "📊 Configuring Netdata Parent..."

if [ ! -f "$CONFIG_FILE" ]; then
  echo "   ✗ Missing $CONFIG_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
. "$CONFIG_FILE"

: "${NETDATA_API_KEY:?NETDATA_API_KEY must be set in $CONFIG_FILE}"

bash script/install_netdata.sh

if [ -d /etc/netdata ]; then
  NETDATA_CONFIG_DIR="/etc/netdata"
elif [ -d /opt/netdata/etc/netdata ]; then
  NETDATA_CONFIG_DIR="/opt/netdata/etc/netdata"
else
  echo "   ✗ Netdata config directory not found" >&2
  exit 1
fi

STREAM_CONF="$NETDATA_CONFIG_DIR/stream.conf"

echo "   → Writing Parent stream configuration to $STREAM_CONF"
sudo tee "$STREAM_CONF" >/dev/null <<EOF
[$NETDATA_API_KEY]
    enabled = yes
EOF

echo "   → Restarting Netdata"
sudo systemctl restart netdata

echo "   ✅ Netdata Parent accepts Child streams"
