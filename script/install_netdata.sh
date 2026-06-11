#!/bin/bash
# Install Netdata Agent using the official kickstart script.

set -e

echo "📈 Installing Netdata..."

if systemctl list-unit-files 2>/dev/null | grep -q '^netdata\.service'; then
  echo "   ✓ Netdata service already installed"
else
  if ! command -v curl >/dev/null 2>&1; then
    echo "   → Installing curl"
    sudo apt update -qq
    sudo apt install -y curl
  fi

  echo "   → Downloading Netdata kickstart installer"
  curl -fsSL https://get.netdata.cloud/kickstart.sh -o /tmp/netdata-kickstart.sh

  echo "   → Running Netdata installer"
  sudo env DISABLE_TELEMETRY=1 sh /tmp/netdata-kickstart.sh --non-interactive --release-channel stable
fi

echo "   → Ensuring Netdata service is running"
sudo systemctl enable --now netdata

echo "   ✅ Netdata installed"
