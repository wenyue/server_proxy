#!/bin/bash
# Install nginx, net-tools, cron and other dependencies

set -e

echo "📦 Installing prerequisites..."
sudo apt update -qq

if ! command -v nginx >/dev/null 2>&1; then
  echo "   → Installing nginx web server"
  sudo apt install -y nginx
else
  echo "   ✓ nginx already installed"
fi

if ! command -v ifconfig >/dev/null 2>&1; then
  echo "   → Installing net-tools package"
  sudo apt install -y net-tools
else
  echo "   ✓ net-tools already available"
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
