#!/bin/bash
# Configure nginx service limits required by high worker_connections values.

set -e

echo "🔧 Configuring nginx file descriptor limit..."

NGINX_SYSTEMD_OVERRIDE_DIR="${NGINX_SYSTEMD_OVERRIDE_DIR:-/etc/systemd/system/nginx.service.d}"
sudo mkdir -p "$NGINX_SYSTEMD_OVERRIDE_DIR"
sudo tee "$NGINX_SYSTEMD_OVERRIDE_DIR/override.conf" >/dev/null <<'EOF'
[Service]
LimitNOFILE=524288
EOF
sudo systemctl daemon-reload

echo "   ✅ Nginx file descriptor limit configured"
