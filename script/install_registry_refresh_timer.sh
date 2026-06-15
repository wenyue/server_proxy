#!/bin/bash
# Install an hourly systemd timer to refresh registry-derived configs.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "⏲️ Installing registry refresh systemd timer..."

sudo tee /etc/systemd/system/otaku-registry-refresh.service >/dev/null <<EOF
[Unit]
Description=Refresh OtakuRoom registry-derived configs

[Service]
Type=oneshot
WorkingDirectory=$REPO_DIR
ExecStart=/bin/bash $REPO_DIR/script/refresh_registry.sh --reload-nginx
EOF

sudo tee /etc/systemd/system/otaku-registry-refresh.timer >/dev/null <<EOF
[Unit]
Description=Run OtakuRoom registry refresh hourly

[Timer]
OnBootSec=5min
OnUnitActiveSec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now otaku-registry-refresh.timer

echo "   ✅ Registry refresh timer installed"
