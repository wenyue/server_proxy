#!/bin/bash
# Make all scripts executable

set -e

echo "🔧 Setting executable permissions..."

# Main setup scripts
chmod +x setup.sh
chmod +x setup_4001_schedule.sh
chmod +x monitor_logs.sh

# Script directory
chmod +x script/*.sh

echo "   ✅ All scripts are now executable"
echo ""
echo "📋 Available scripts:"
echo "   • ./setup.sh - Standard nginx proxy setup"
echo "   • ./setup_4001_schedule.sh - Setup with port 4001 scheduler"
echo "   • ./monitor_logs.sh - Monitor bandwidth logs"
echo ""
echo "🏃‍♂️ Ready to run!"