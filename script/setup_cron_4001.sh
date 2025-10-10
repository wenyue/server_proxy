#!/bin/bash
# Setup scheduled switching for port 4001 proxy

set -e

echo "⏰ Configuring port 4001 scheduler..."

STREAMS_SRC_DIR="nginx/streams"
SRC_4001="$STREAMS_SRC_DIR/4001.conf"
HOUR_SH=$(TZ=Asia/Shanghai date +%H)

echo "   → Current Beijing time: $(TZ=Asia/Shanghai date '+%H:%M')"

# Active between 18:00-01:59 (Beijing time)
if [ "$HOUR_SH" -ge 18 ] || [ "$HOUR_SH" -lt 2 ]; then
  echo "   → Port 4001 is currently ACTIVE (18:00-02:00 window)"
  sudo cp -f "$SRC_4001" /etc/nginx/streams/4001.conf
  sudo rm -f /etc/nginx/streams/4001.off 2>/dev/null || true
else
  echo "   → Port 4001 is currently INACTIVE (outside 18:00-02:00 window)"
  sudo cp -f "$SRC_4001" /etc/nginx/streams/4001.off
  sudo rm -f /etc/nginx/streams/4001.conf 2>/dev/null || true
fi

echo "   → Installing cron scheduler"
CRON_SRC="cron/4001_schedule"
CRON_FILE="/etc/cron.d/4001_schedule"
sudo cp -f "$CRON_SRC" "$CRON_FILE"
sudo chmod 0644 "$CRON_FILE"
sudo chown root:root "$CRON_FILE"

echo "   ✅ Port 4001 scheduler configured"
