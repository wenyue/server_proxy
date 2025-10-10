#!/bin/bash
# Monitor nginx bandwidth log files size and status

LOG_DIR="/var/log/nginx"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}📊 Nginx Bandwidth Logs Monitor${NC}"
echo "   $(date)"
echo ""

# Check if log directory exists
if [ ! -d "$LOG_DIR" ]; then
    echo -e "${RED}❌ Error: Log directory $LOG_DIR does not exist${NC}"
    exit 1
fi

# Convert bytes to human readable format
human_readable_size() {
    local size=$1
    if [ $size -lt 1024 ]; then
        echo "${size}B"
    elif [ $size -lt $((1024*1024)) ]; then
        echo "$((size/1024))KB"
    elif [ $size -lt $((1024*1024*1024)) ]; then
        echo "$((size/(1024*1024)))MB"
    else
        echo "$((size/(1024*1024*1024)))GB"
    fi
}

# Check log file size and display status
check_log_size() {
    local file=$1
    if [ -f "$file" ]; then
        local size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)
        local readable_size=$(human_readable_size $size)
        
        if [ $size -gt $((100*1024*1024)) ]; then  # 100MB
            echo -e "     📏 Size: ${RED}$readable_size (⚠️  Large file!)${NC}"
        elif [ $size -gt $((10*1024*1024)) ]; then  # 10MB
            echo -e "     📏 Size: ${YELLOW}$readable_size (⚡ Getting large)${NC}"
        else
            echo -e "     📏 Size: ${GREEN}$readable_size${NC}"
        fi
        
        echo "     🕒 Modified: $(ls -l "$file" | awk '{print $6, $7, $8}')"
        
        # Show line count with timeout protection
        timeout 5s wc -l "$file" 2>/dev/null | awk '{print "     📄 Lines: " $1}' || echo "     📄 Lines: [timeout - file too large]"
    else
        echo -e "     ${YELLOW}📭 File not found${NC}"
    fi
}

# Check each bandwidth log file
echo -e "${BLUE}🗂️  Log files status:${NC}"
echo ""

for port in 2053 2083 4001 5001; do
    echo -e "${GREEN}📡 Port $port${NC}"
    echo "   🔗 TCP bandwidth log:"
    check_log_size "$LOG_DIR/stream_${port}_tcp_bandwidth.log"
    echo ""
    echo "   📡 UDP bandwidth log:"
    check_log_size "$LOG_DIR/stream_${port}_udp_bandwidth.log"
    echo ""
done

# Check total disk usage of log directory
echo -e "${BLUE}💾 Storage information:${NC}"
if command -v du >/dev/null 2>&1; then
    total_size=$(du -sh "$LOG_DIR" 2>/dev/null | awk '{print $1}' || echo "Unknown")
    echo "   📁 Total logs size: $total_size"
else
    echo "   📁 Total logs size: Unable to calculate"
fi

if command -v df >/dev/null 2>&1; then
    disk_info=$(df -h "$LOG_DIR" 2>/dev/null | tail -1 || echo "N/A N/A N/A N/A")
    echo "   💿 Disk usage: $(echo $disk_info | awk '{print $5 " (" $3 "/" $2 ")"}')"
else
    echo "   💿 Disk usage: Unable to determine"
fi

echo ""
echo -e "${BLUE}💡 Recommendations:${NC}"
echo "   • Large files? Consider log rotation: script/setup_logrotate.sh"
echo "   • Real-time monitoring: tail -f $LOG_DIR/stream_*_bandwidth.log"
echo "   • Archive old logs to external storage periodically"
echo "   • Monitor disk space regularly to prevent issues"