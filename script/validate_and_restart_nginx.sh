#!/bin/bash
# Validate and restart nginx service

set -e

echo "🔄 Starting nginx service..."

echo "   → Validating nginx configuration"
sudo nginx -t

echo "   → Enabling nginx service"
sudo systemctl enable nginx

echo "   → Restarting nginx service"
sudo systemctl restart nginx

echo "   ✅ Nginx service is running"
