#!/bin/bash
# Setup script for ordinary proxy nodes.

set -e

MODE=${1:-default}
CONFIG_FILE="${NETDATA_CONFIG_FILE:-config/netdata.conf}"

if [ ! -f "$CONFIG_FILE" ]; then
	echo "✗ Missing $CONFIG_FILE" >&2
	exit 1
fi

# shellcheck disable=SC1090
. "$CONFIG_FILE"
: "${NETDATA_PARENT:?NETDATA_PARENT must be set in $CONFIG_FILE}"
: "${NETDATA_API_KEY:?NETDATA_API_KEY must be set in $CONFIG_FILE}"

if [ "$MODE" = "cn2" ]; then
	echo "🚀 Setting up nginx proxy node with CN2 mode..."
else
	echo "🚀 Setting up nginx proxy node..."
fi
echo ""

# Install system dependencies
bash script/install_prerequisites.sh
echo ""

# Install Shadowsocks service
bash script/install_shadowsocks.sh
echo ""

if [ "$MODE" = "cn2" ]; then
	# Configure nginx excluding pin-server; it will be toggled by scheduler
	bash script/copy_nginx_config.sh pin-server.conf
	echo ""
else
	# Configure nginx (all streams)
	bash script/copy_nginx_config.sh
	echo ""
fi

if [ "$MODE" = "cn2" ]; then
	# Setup CN2 scheduler before (re)starting nginx, then (re)start nginx
	bash script/enable_cn2_mode.sh
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
