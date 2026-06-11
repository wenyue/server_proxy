#!/bin/bash
# Setup script for the main Netdata Parent server.

set -e

CONFIG_FILE="${NETDATA_CONFIG_FILE:-config/netdata.conf}"

if [ ! -f "$CONFIG_FILE" ]; then
	echo "✗ Missing $CONFIG_FILE" >&2
	exit 1
fi

# shellcheck disable=SC1090
. "$CONFIG_FILE"
: "${NETDATA_API_KEY:?NETDATA_API_KEY must be set in $CONFIG_FILE}"

echo "🚀 Setting up main monitoring server..."
echo ""

echo "📦 Updating package indexes..."
sudo apt update -qq
echo ""

# Install Shadowsocks service
bash script/install_shadowsocks.sh
echo ""

# Install and start local iperf3 server
bash script/install_iperf_server.sh
echo ""

# Install and configure Netdata as a Parent node
bash script/install_netdata_parent.sh
echo ""

# Display network information
bash script/print_public_ip.sh
echo ""

echo "🎉 Main setup completed successfully!"
echo ""
echo "📝 Next steps:"
echo "   • Check Netdata: systemctl status netdata"
echo "   • Check iPerf3: systemctl status iperf3-server"
echo "   • Check Shadowsocks: sudo docker ps --filter name=otaku-shadowsocks"
echo "   • Open Netdata: http://ipfs.otakuroom.net:19999"
