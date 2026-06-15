#!/bin/bash
# Setup log rotation for nginx bandwidth monitoring logs

set -e

echo "📋 Setting up log rotation..."

echo "   → Installing logrotate configuration"
sudo cp -f config/logrotate.conf /etc/logrotate.d/nginx-bandwidth

echo "   → Testing configuration syntax"
if command -v logrotate >/dev/null 2>&1; then
	sudo logrotate -d /etc/logrotate.d/nginx-bandwidth >/dev/null 2>&1
	echo "     ✓ logrotate is available"
else
	echo "     ⚠️  logrotate not found. It will be installed by install_prerequisites.sh"
fi

echo "   → Preparing log directories"
sudo mkdir -p /var/log/nginx
sudo chown www-data:www-data /var/log/nginx
sudo chmod 755 /var/log/nginx

echo "   ✅ Log rotation configured successfully"
echo ""
echo "   📊 Rotation policy:"
echo "      • Size-based rotation: 100MB per file"
echo "      • Retain 10 rotated files"
echo "      • Automatic compression (with delayed compression)"
echo "      • Shared post-rotate script for all files"
echo "      • Graceful nginx reload after rotation"
echo ""
echo "   🔧 Manual test command:"
echo "      sudo logrotate -f /etc/logrotate.d/nginx-bandwidth"
