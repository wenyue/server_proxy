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

# Ensure 4001 is active under default mode
if [ -f "/etc/nginx/streams/4001.off" ]; then
  echo "   → Removing /etc/nginx/streams/4001.off to reactivate 4001"
  sudo rm -f /etc/nginx/streams/4001.off
fi

# Make sure 4001.conf exists (in case it was missing)
if [ ! -f "/etc/nginx/streams/4001.conf" ] && [ -f "nginx/streams/4001.conf" ]; then
  echo "   → Restoring /etc/nginx/streams/4001.conf from repository"
  sudo cp -f nginx/streams/4001.conf /etc/nginx/streams/4001.conf
fi

echo "   ✅ CN2 scheduled mode disabled"
