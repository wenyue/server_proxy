#!/bin/bash
# Copy nginx main configuration and stream configurations

set -e

echo "📁 Configuring nginx..."

STREAMS_SRC_DIR="nginx/streams"

echo "   → Copying main nginx configuration"
sudo cp -f nginx/nginx.conf /etc/nginx/nginx.conf
sudo mkdir -p /etc/nginx/streams

echo "   → Cleaning up old stream configurations"
sudo rm -f /etc/nginx/streams/* 2>/dev/null || true

if [ -z "$1" ]; then
  # Copy all stream configurations by default
  echo "   → Copying all stream configurations"
  sudo cp -f $STREAMS_SRC_DIR/*.conf /etc/nginx/streams/
else
  # Support excluding specific files
  echo "   → Copying stream configurations (excluding: $*)"
  shopt -s nullglob
  for f in $STREAMS_SRC_DIR/*.conf; do
    base=$(basename "$f")
    skip=0
    for excl in "$@"; do
      if [ "$base" = "$excl" ]; then
        skip=1
        break
      fi
    done
    if [ $skip -eq 0 ]; then
      sudo cp -f "$f" "/etc/nginx/streams/$base"
      echo "     ✓ $base"
    else
      echo "     ⊘ $base (excluded)"
    fi
  done
  shopt -u nullglob
fi

echo "   ✅ Nginx configuration updated"
