#!/bin/bash
# power-control.sh - Control power for GPU servers via IPMI
# Usage: ./power-control.sh <server_name|all> <on|off|reset|status>

# Configuration - Edit these for your cluster
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
NC='\033[0m'

usage() {
    echo "Usage: $0 <server_name|all> <on|off|soft|reset|status>"
    echo ""
    echo "Commands:"
    echo "  on      - Power on"
    echo "  off     - Hard power off (immediate)"
    echo "  soft    - Graceful shutdown"
    echo "  reset   - Reboot"
    echo "  status  - Show power status"
    echo ""
    echo "Available servers:"
    for server in "${!IPMI[@]}"; do
        echo "  - $server (IPMI: ${IPMI[$server]})"
    done
    echo "  - all (all servers)"
    exit 1
}

power_action() {
    local server=$1
    local action=$2
    local ipmi_ip=${IPMI[$server]}

    if [ -z "$ipmi_ip" ]; then
        echo -e "${RED}Error: Unknown server '$server'${NC}"
        return 1
    fi

    case $action in
        on)
            echo -n "  $server: Powering ON... "
            result=$(ipmitool -I lanplus -H $ipmi_ip -U $IPMI_USER -P $IPMI_PASS chassis power on 2>&1)
            echo -e "${GREEN}Done${NC}"
            ;;
        off)
            echo -n "  $server: Powering OFF (hard)... "
            result=$(ipmitool -I lanplus -H $ipmi_ip -U $IPMI_USER -P $IPMI_PASS chassis power off 2>&1)
            echo -e "${RED}Done${NC}"
            ;;
        soft)
            echo -n "  $server: Graceful shutdown... "
            result=$(ipmitool -I lanplus -H $ipmi_ip -U $IPMI_USER -P $IPMI_PASS chassis power soft 2>&1)
            echo -e "${YELLOW}Done${NC}"
            ;;
        reset)
            echo -n "  $server: Resetting... "
            result=$(ipmitool -I lanplus -H $ipmi_ip -U $IPMI_USER -P $IPMI_PASS chassis power reset 2>&1)
            echo -e "${YELLOW}Done${NC}"
            ;;
        status)
            status=$(ipmitool -I lanplus -H $ipmi_ip -U $IPMI_USER -P $IPMI_PASS chassis power status 2>&1)
            if [[ $status == *"on"* ]]; then
                echo -e "  $server: ${GREEN}ON${NC}"
            else
                echo -e "  $server: ${RED}OFF${NC}"
            fi
            ;;
        *)
            echo "Unknown action: $action"
            return 1
            ;;
    esac
}

if [ $# -lt 2 ]; then
    usage
fi

SERVER=$1
ACTION=$2

echo ""
echo "GPU Cluster Power Control"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$SERVER" == "all" ]; then
    for server in "${!IPMI[@]}"; do
        power_action "$server" "$ACTION"
    done
else
    power_action "$SERVER" "$ACTION"
fi

echo ""
