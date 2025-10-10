#!/bin/bash
# Display public IPv4/IPv6 addresses

echo "🌐 Detecting public IP addresses..."

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

echo "   → Public IPv4: ${PUB4:-Not detected}"
echo "   → Public IPv6: ${PUB6:-Not detected}"
