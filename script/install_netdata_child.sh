#!/bin/bash
# Install Netdata and configure it to stream metrics to the Parent.

set -e

SECRETS_FILE="${NETDATA_SECRETS_FILE:-config/secrets.conf}"
PYTHON_BIN="${PYTHON_BIN:-python}"

echo "📡 Configuring Netdata Child..."

if [ ! -f "$SECRETS_FILE" ]; then
  echo "   ✗ Missing $SECRETS_FILE (copy config/secrets.example.conf and fill NETDATA_API_KEY)" >&2
  exit 1
fi

# shellcheck disable=SC1090
. "$SECRETS_FILE"

: "${NETDATA_API_KEY:?NETDATA_API_KEY must be set in $SECRETS_FILE}"

if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
  if command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
  else
    echo "   ✗ Python is required to read the public network registry" >&2
    exit 1
  fi
fi

NETDATA_PARENT="$("$PYTHON_BIN" script/registry.py netdata-parent)"

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

echo "   → Writing Child stream configuration to $STREAM_CONF"
sudo tee "$STREAM_CONF" >/dev/null <<EOF
[stream]
    enabled = yes
    destination = $NETDATA_PARENT
    api key = $NETDATA_API_KEY
EOF

echo "   → Restarting Netdata"
sudo systemctl restart netdata

echo "   ✅ Netdata Child streaming to $NETDATA_PARENT"
