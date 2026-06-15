#!/bin/bash
# Setup script for the main Netdata Parent server.

set -e
PYTHON_BIN="${PYTHON_BIN:-python3}"

echo "🚀 Setting up main monitoring server..."
echo ""

echo "📦 Updating package indexes..."
sudo apt update -qq
echo ""

if ! command -v python3 >/dev/null 2>&1; then
	echo "   → Installing Python 3"
	sudo apt install -y python3
	echo ""
fi

if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
	if command -v python >/dev/null 2>&1; then
		PYTHON_BIN="python"
	else
		echo "✗ Python is required to read the public network registry" >&2
		exit 1
	fi
fi

# Install Shadowsocks service
bash script/install_shadowsocks.sh
echo ""

# Install and start local iperf3 server
bash script/install_iperf_server.sh
echo ""

# Install and configure Netdata as a Parent node
bash script/install_netdata_parent.sh
echo ""

NETDATA_PARENT="$("$PYTHON_BIN" script/registry.py netdata-parent)"

# Display network information
bash script/print_public_ip.sh
echo ""

echo "🎉 Main setup completed successfully!"
echo ""
echo "📝 Next steps:"
echo "   • Check Netdata: systemctl status netdata"
echo "   • Check iPerf3: systemctl status iperf3-server"
echo "   • Check Shadowsocks: sudo docker ps --filter name=otaku-shadowsocks"
echo "   • Open Netdata: http://$NETDATA_PARENT"
