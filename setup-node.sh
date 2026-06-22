#!/bin/bash
# Setup script for ordinary proxy nodes.

set -e

MODE=${1:-default}
PYTHON_BIN="${PYTHON_BIN:-python3}"

if [ "$MODE" = "cn2" ]; then
	echo "🚀 Setting up nginx proxy node with CN2 mode..."
else
	echo "🚀 Setting up nginx proxy node..."
fi
echo ""

# Install system dependencies
bash script/install_prerequisites.sh
echo ""

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

STREAMS_TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$STREAMS_TMP_DIR"' EXIT

# Generate nginx stream configs from the public network registry
"$PYTHON_BIN" script/registry.py write-nginx-streams --output-dir "$STREAMS_TMP_DIR"
echo ""

if [ "$MODE" = "cn2" ]; then
	# Configure nginx excluding pin-server; it will be toggled by scheduler
	bash script/copy_nginx_config.sh "$STREAMS_TMP_DIR" pin-server.conf
	echo ""
else
	# Configure nginx (all streams)
	bash script/copy_nginx_config.sh "$STREAMS_TMP_DIR"
	echo ""
fi

# Configure nginx service limits required by high worker_connections values
bash script/configure_nginx_limits.sh
echo ""

if [ "$MODE" = "cn2" ]; then
	# Setup CN2 scheduler before (re)starting nginx, then (re)start nginx
	bash script/enable_cn2_mode.sh "$STREAMS_TMP_DIR"
	echo ""
else
	# If previously in CN2 mode, disable its cron scheduler and clean up
	bash script/disable_cn2_mode.sh
	echo ""
fi

# Start/restart nginx service
bash script/validate_and_restart_nginx.sh
echo ""

# Setup log management
bash script/setup_logrotate.sh
echo ""

# Install and configure Netdata as a Child node
bash script/install_netdata_child.sh
echo ""

# Install registry refresh timer after Netdata is available for refresh hooks
bash script/install_registry_refresh_timer.sh
echo ""

# Display network information
bash script/print_public_ip.sh
echo ""

echo "🎉 Node setup completed successfully!"
echo ""
echo "📝 Next steps:"
echo "   • Monitor logs: bash monitor_logs.sh"
echo "   • Check nginx: systemctl status nginx"
echo "   • Check Netdata: systemctl status netdata"
echo "   • Check Shadowsocks: sudo docker ps --filter name=otaku-shadowsocks"
if [ "$MODE" = "cn2" ]; then
	echo "   • View CN2 cron: ls -l /etc/cron.d && cat /etc/cron.d/cn2_schedule"
fi
echo "   • View nginx config: nginx -T"
