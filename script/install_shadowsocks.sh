#!/bin/bash
# Install and run Shadowsocks with Docker

set -e

CONTAINER_NAME="otaku-shadowsocks"
IMAGE_NAME="shadowsocks/shadowsocks-libev"
SS_PORT="${SS_PORT:-8388}"
SS_CONTAINER_PORT="8388"
SS_PASSWORD="85888361"
SS_METHOD="aes-256-gcm"

port_in_use() {
  sudo ss -H -lntup 2>/dev/null | grep -Eq "[:.]${SS_PORT}[[:space:]]"
}

echo "🔐 Installing Shadowsocks..."

if ! command -v docker >/dev/null 2>&1; then
  echo "   → Installing Docker"
  sudo apt install -y docker.io
else
  echo "   ✓ Docker already installed"
fi

echo "   → Ensuring Docker service is running"
sudo systemctl enable --now docker

if ! command -v ss >/dev/null 2>&1; then
  echo "   → Installing iproute2 for port checks"
  sudo apt install -y iproute2
fi

if sudo docker ps -a --format '{{.Names}}' | grep -Fxq "$CONTAINER_NAME"; then
  echo "   → Removing existing $CONTAINER_NAME container"
  sudo docker rm -f "$CONTAINER_NAME"
fi

CONFLICTING_CONTAINERS="$(sudo docker ps --filter "publish=$SS_PORT" --format '{{.ID}} {{.Names}}' || true)"
if [ -n "$CONFLICTING_CONTAINERS" ]; then
  echo "   → Removing Docker container(s) already publishing port $SS_PORT"
  echo "$CONFLICTING_CONTAINERS" | while read -r CONFLICTING_ID CONFLICTING_NAME; do
    if [ -n "$CONFLICTING_ID" ]; then
      echo "      - $CONFLICTING_NAME ($CONFLICTING_ID)"
      sudo docker rm -f "$CONFLICTING_ID"
    fi
  done
fi

if port_in_use; then
  echo "   → Freeing non-Docker process(es) using TCP/UDP $SS_PORT"
  if ! command -v fuser >/dev/null 2>&1; then
    echo "   → Installing psmisc for fuser"
    sudo apt install -y psmisc
  fi

  if command -v fuser >/dev/null 2>&1; then
    sudo fuser -k "$SS_PORT/tcp" 2>/dev/null || true
    sudo fuser -k "$SS_PORT/udp" 2>/dev/null || true
    sleep 1
  fi
fi

if port_in_use; then
  echo "✗ Port $SS_PORT is still in use after cleanup:" >&2
  sudo ss -lntup 2>/dev/null | grep -E "[:.]${SS_PORT}[[:space:]]" >&2 || true
  exit 1
fi

echo "   → Starting $CONTAINER_NAME on TCP/UDP $SS_PORT"
sudo docker run -d \
  --name "$CONTAINER_NAME" \
  --restart unless-stopped \
  -e PASSWORD="$SS_PASSWORD" \
  -e METHOD="$SS_METHOD" \
  -p "$SS_PORT:$SS_CONTAINER_PORT/tcp" \
  -p "$SS_PORT:$SS_CONTAINER_PORT/udp" \
  "$IMAGE_NAME"

echo "   ✅ Shadowsocks ready on port $SS_PORT (tcp/udp)"
