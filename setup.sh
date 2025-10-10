#!/bin/bash
# Main setup script for nginx proxy server

set -e

echo "🚀 Setting up nginx proxy server..."
echo ""

# Install system dependencies
bash script/install_prerequisites.sh
echo ""

# Configure nginx
bash script/copy_nginx_config.sh
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
echo "   • Check status: systemctl status nginx"
echo "   • View config: nginx -T"
