#!/bin/bash
# Install nginx, net-tools, cron and other dependencies

set -e

echo "📦 Installing prerequisites..."
sudo apt update -qq

if ! command -v nginx >/dev/null 2>&1; then
  echo "   → Installing nginx web server"
  sudo apt install -y nginx-full
else
  echo "   ✓ nginx already installed"
fi

if ! command -v ip >/dev/null 2>&1; then
  echo "   → Installing iproute2 package"
  sudo apt install -y iproute2
else
  echo "   ✓ iproute2 already available"
fi

if ! command -v logrotate >/dev/null 2>&1; then
  echo "   → Installing logrotate"
  sudo apt install -y logrotate
else
  echo "   ✓ logrotate already available"
fi

if ! systemctl list-unit-files | grep -q '^cron\.service'; then
  echo "   → Installing cron scheduler"
  sudo apt install -y cron
else
  echo "   ✓ cron service available"
fi

echo "   → Ensuring cron service is running"
sudo systemctl enable --now cron

echo "   ✅ All prerequisites ready"
