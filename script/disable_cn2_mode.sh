#!/bin/bash
# Disable CN2 scheduled mode and restore default state

set -e

echo "🧹 Disabling CN2 scheduled mode..."

# Remove CN2 cron schedule if present
if [ -f "/etc/cron.d/cn2_schedule" ]; then
  echo "   → Removing /etc/cron.d/cn2_schedule"
  sudo rm -f /etc/cron.d/cn2_schedule
  # Reload cron to apply removal (best-effort across distros)
  sudo systemctl restart cron 2>/dev/null || sudo service cron restart 2>/dev/null || true
else
  echo "   → No cn2_schedule cron file found"
fi

# Ensure pin-server is active under default mode
if [ -f "/etc/nginx/streams/pin-server.off" ]; then
  echo "   → Removing /etc/nginx/streams/pin-server.off to reactivate pin-server"
  sudo rm -f /etc/nginx/streams/pin-server.off
fi

echo "   ✅ CN2 scheduled mode disabled"
