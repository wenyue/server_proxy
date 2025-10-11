#!/bin/bash
# Display public IPv4/IPv6 addresses

echo "🌐 Detecting public IP addresses..."

PUB4=$(ip -4 -o addr show scope global 2>/dev/null \
  | awk '{print $4}' \
  | cut -d/ -f1 \
  | grep -E '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' \
  | grep -v -E '^(127\.|10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|169\.254\.)' \
  | head -n1)

PUB6=$(ip -6 -o addr show scope global 2>/dev/null \
  | awk '{print $4}' \
  | cut -d/ -f1 \
  | grep -iE '^[0-9a-f:]+$' \
  | grep -viE '^(fc..:|fd..:|::1$)' \
  | head -n1)

echo "   → Public IPv4: ${PUB4:-Not detected}"
echo "   → Public IPv6: ${PUB6:-Not detected}"
