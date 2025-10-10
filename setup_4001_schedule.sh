#!/bin/bash
# Setup nginx proxy server with port 4001 time-based scheduling

set -e

echo "🚀 Setting up nginx proxy with 4001 scheduler..."
echo ""

# Install system dependencies  
bash script/install_prerequisites.sh
echo ""

# Configure nginx (excluding port 4001)
bash script/copy_nginx_config.sh 4001.conf
echo ""

# Setup port 4001 scheduler
bash script/setup_cron_4001.sh
echo ""

# Start nginx service
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
echo "   • Check 4001 status: ls -la /etc/nginx/streams/4001*"
echo "   • View cron jobs: sudo crontab -l"
