#!/bin/bash
# Install and run iperf3 as a local server.

set -e

echo "📶 Installing iPerf3 server..."

if ! command -v iperf3 >/dev/null 2>&1; then
  echo "   → Installing iperf3"
  sudo apt update -qq
  sudo env DEBIAN_FRONTEND=noninteractive apt install -y iperf3
else
  echo "   ✓ iperf3 already installed"
fi

IPERF3_BIN="$(command -v iperf3)"

echo "   → Installing systemd service"
sudo tee /etc/systemd/system/iperf3-server.service >/dev/null <<EOF
[Unit]
Description=iPerf3 Server
After=network.target

[Service]
ExecStart=$IPERF3_BIN -s
Restart=always
RestartSec=5
User=nobody

[Install]
WantedBy=multi-user.target
EOF

echo "   → Starting iPerf3 service"
sudo systemctl daemon-reload
sudo systemctl enable --now iperf3-server

echo "   ✅ iPerf3 server ready on port 5201"
