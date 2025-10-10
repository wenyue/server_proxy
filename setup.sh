#!/bin/bash

set -e

echo "[+] Updating package index..."
sudo apt update

# Install prerequisites
if ! command -v nginx >/dev/null 2>&1; then
  echo "[+] Installing nginx..."
  sudo apt install -y nginx
fi

if ! command -v ifconfig >/dev/null 2>&1; then
  echo "[+] Installing net-tools..."
  sudo apt install -y net-tools
fi

# Copy nginx configuration files
echo "[+] Copying nginx configurations..."
sudo cp -f nginx/nginx.conf /etc/nginx/nginx.conf
sudo mkdir -p /etc/nginx/streams
sudo cp -f nginx/streams/*.conf /etc/nginx/streams/

# Validate and restart nginx
echo "[+] Validating and restarting nginx..."
sudo nginx -t && sudo systemctl enable nginx && sudo systemctl restart nginx

# Print public IPv4/IPv6 using ifconfig (best-effort)
PUB4=$(ifconfig 2>/dev/null \
  | awk '/inet /{print $2}' \
  | sed 's/^addr://;s/[^0-9\.].*$//' \
  | grep -E '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' \
  | grep -v -E '^(127\.|10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)' \
  | head -n1)

PUB6=$(ifconfig 2>/dev/null \
  | awk '/inet6 /{print $2}' \
  | sed 's/^addr://;s/%.*$//' \
  | grep -iE '^[0-9a-f:]+$' \
  | grep -viE '^(::1|fe[89ab]:|fc..:|fd..:)' \
  | head -n1)

echo "Public IPv4: ${PUB4:-N/A}"
echo "Public IPv6: ${PUB6:-N/A}"

echo "[✓] Setup with 4001 schedule completed."
