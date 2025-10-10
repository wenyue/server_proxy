#!/bin/bash
# Setup log rotation for nginx bandwidth monitoring logs

set -e

echo "📋 Setting up log rotation..."

echo "   → Installing logrotate configuration"
sudo cp nginx/logrotate.conf /etc/logrotate.d/nginx-bandwidth

echo "   → Testing configuration syntax"
sudo logrotate -d /etc/logrotate.d/nginx-bandwidth >/dev/null 2>&1

echo "   → Preparing log directories"
sudo mkdir -p /var/log/nginx
sudo chown www-data:www-data /var/log/nginx
sudo chmod 755 /var/log/nginx

echo "   ✅ Log rotation configured successfully"
echo ""
echo "   📊 Rotation policy:"
echo "      • Daily rotation schedule"
echo "      • 30 days retention period" 
echo "      • Automatic compression"
echo "      • Graceful nginx reload"
echo ""
echo "   🔧 Manual test command:"
echo "      sudo logrotate -f /etc/logrotate.d/nginx-bandwidth"
