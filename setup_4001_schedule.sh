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

if ! systemctl list-unit-files | grep -q '^cron\.service'; then
  echo "[+] Installing cron..."
  sudo apt install -y cron
fi

echo "[+] Ensuring cron is enabled and running..."
sudo systemctl enable --now cron

# Copy nginx configuration files
echo "[+] Copying nginx configurations..."
STREAMS_SRC_DIR="nginx/streams"
sudo cp -f nginx/nginx.conf /etc/nginx/nginx.conf
sudo mkdir -p /etc/nginx/streams
shopt -s nullglob
for f in "$STREAMS_SRC_DIR"/*.conf; do
  base=$(basename "$f")
  if [ "$base" = "4001.conf" ]; then
    continue
  fi
  sudo cp -f "$f" "/etc/nginx/streams/$base"
done
shopt -u nullglob

# Prepare 4001 stream file and schedule
echo "[+] Setting initial state for 4001 based on Beijing time..."
SRC_4001="$STREAMS_SRC_DIR/4001.conf"
HOUR_SH=$(TZ=Asia/Shanghai date +%H)
# Active between 18:00-23:59 and 00:00-01:59 (Beijing time)
if [ "$HOUR_SH" -ge 18 ] || [ "$HOUR_SH" -lt 2 ]; then
  echo "    -> Within 18:00-02:00 window: enabling 4001"
  sudo cp -f "$SRC_4001" /etc/nginx/streams/4001.conf
  # Remove .off if exists to avoid duplicates
  if [ -f /etc/nginx/streams/4001.off ]; then sudo rm -f /etc/nginx/streams/4001.off; fi
else
  echo "    -> Outside window: disabling 4001"
  sudo cp -f "$SRC_4001" /etc/nginx/streams/4001.off
  # Remove active .conf if exists
  if [ -f /etc/nginx/streams/4001.conf ]; then sudo rm -f /etc/nginx/streams/4001.conf; fi
fi

echo "[+] Installing cron schedule for 4001 toggle..."
CRON_SRC="cron/4001_schedule"
CRON_FILE="/etc/cron.d/4001_schedule"
sudo cp -f "$CRON_SRC" "$CRON_FILE"
sudo chmod 0644 "$CRON_FILE"
sudo chown root:root "$CRON_FILE"

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
