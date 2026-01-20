#!/bin/bash
# cluster-status.sh - Check status of all GPU servers in the cluster
# Usage: ./cluster-status.sh

# Configuration - Edit these for your cluster
declare -A SERVERS=(
    ["gpuserver1"]="192.168.1.73"
    ["gpuserver2"]="192.168.1.71"
)

declare -A IPMI=(
    ["gpuserver1"]="192.168.1.72"
    ["gpuserver2"]="192.168.1.70"
)

IPMI_USER="admin"
IPMI_PASS="admin"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              GPU CLUSTER STATUS                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

for server in "${!SERVERS[@]}"; do
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${YELLOW}$server${NC} (Ubuntu: ${SERVERS[$server]} | IPMI: ${IPMI[$server]})"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Check IPMI power status
    power_status=$(ipmitool -I lanplus -H ${IPMI[$server]} -U $IPMI_USER -P $IPMI_PASS chassis power status 2>/dev/null)
    if [[ $power_status == *"on"* ]]; then
        echo -e "  Power:     ${GREEN}ON${NC}"
    else
        echo -e "  Power:     ${RED}OFF${NC}"
    fi

    # Check SSH connectivity
    if nc -z -w2 ${SERVERS[$server]} 22 2>/dev/null; then
        echo -e "  SSH:       ${GREEN}Reachable${NC}"

        # Get uptime if SSH works
        uptime=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no eniz@${SERVERS[$server]} "uptime -p" 2>/dev/null)
        if [ -n "$uptime" ]; then
            echo "  Uptime:    $uptime"
        fi

        # Get GPU status if nvidia-smi is available
        gpu_status=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no eniz@${SERVERS[$server]} "nvidia-smi --query-gpu=name,temperature.gpu,utilization.gpu --format=csv,noheader 2>/dev/null" 2>/dev/null)
        if [ -n "$gpu_status" ]; then
            echo "  GPUs:"
            echo "$gpu_status" | while read line; do
                echo "    - $line"
            done
        fi
    else
        echo -e "  SSH:       ${RED}Unreachable${NC}"
    fi

    # Get temperatures from IPMI
    cpu_temps=$(ipmitool -I lanplus -H ${IPMI[$server]} -U $IPMI_USER -P $IPMI_PASS sdr type temperature 2>/dev/null | grep "CPU" | head -2)
    if [ -n "$cpu_temps" ]; then
        echo "  CPU Temps:"
        echo "$cpu_temps" | while read line; do
            temp=$(echo "$line" | awk -F'|' '{print $NF}' | xargs)
            name=$(echo "$line" | awk -F'|' '{print $1}' | xargs)
            echo "    - $name: $temp"
        done
    fi

    echo ""
done

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              CLUSTER SUMMARY                                 ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo "  Total Servers: ${#SERVERS[@]}"
echo "  Total GPUs:    $((${#SERVERS[@]} * 2)) x V100"
echo ""
