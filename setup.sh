#!/bin/bash
# Main setup script for nginx proxy server

set -e

MODE=${1:-default}

if [ "$MODE" = "cn2" ]; then
	echo "🚀 Setting up nginx proxy with CN2 mode..."
else
	echo "🚀 Setting up nginx proxy server..."
fi
echo ""

# Install system dependencies
bash script/install_prerequisites.sh
echo ""

if [ "$MODE" = "cn2" ]; then
	# Configure nginx excluding 4001; it will be toggled by scheduler
	bash script/copy_nginx_config.sh 4001.conf
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

# Display network information
bash script/print_public_ip.sh
echo ""

echo "🎉 Setup completed successfully!"
echo ""
echo "📝 Next steps:"
echo "   • Monitor logs: bash monitor_logs.sh"
echo "   • Check status: systemctl status nginx"
if [ "$MODE" = "cn2" ]; then
	echo "   • View CN2 cron: ls -l /etc/cron.d && cat /etc/cron.d/cn2_schedule"
fi
echo "   • View config: nginx -T"
