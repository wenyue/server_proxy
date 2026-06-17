#!/bin/bash
# Install an hourly systemd timer to refresh registry-derived configs.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "⏲️ Installing registry refresh systemd timer..."

if ! command -v python3 >/dev/null 2>&1; then
  echo "   → Installing Python 3"
  sudo apt update -qq
  sudo apt install -y python3
fi

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
OnUnitActiveSec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now otaku-registry-refresh.timer

echo "   ✅ Registry refresh timer installed"
