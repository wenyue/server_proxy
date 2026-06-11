#!/bin/bash
# Install and run Shadowsocks with Docker

set -e

CONTAINER_NAME="otaku-shadowsocks"
IMAGE_NAME="shadowsocks/shadowsocks-libev"
SS_PORT="8388"
SS_PASSWORD="85888361"
SS_METHOD="aes-256-gcm"

echo "🔐 Installing Shadowsocks..."

if ! command -v docker >/dev/null 2>&1; then
  echo "   → Installing Docker"
  sudo apt install -y docker.io
else
  echo "   ✓ Docker already installed"
fi

echo "   → Ensuring Docker service is running"
sudo systemctl enable --now docker

if sudo docker ps -a --format '{{.Names}}' | grep -Fxq "$CONTAINER_NAME"; then
  echo "   → Removing existing $CONTAINER_NAME container"
  sudo docker rm -f "$CONTAINER_NAME"
fi

echo "   → Starting $CONTAINER_NAME on TCP/UDP $SS_PORT"
sudo docker run -d \
  --name "$CONTAINER_NAME" \
  --restart unless-stopped \
  -e PASSWORD="$SS_PASSWORD" \
  -e METHOD="$SS_METHOD" \
  -p "$SS_PORT:$SS_PORT/tcp" \
  -p "$SS_PORT:$SS_PORT/udp" \
  "$IMAGE_NAME"

echo "   ✅ Shadowsocks ready on port $SS_PORT (tcp/udp)"
