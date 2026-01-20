#!/bin/bash
# sol-connect.sh - Connect to server console via IPMI SOL
# Usage: ./sol-connect.sh <server_name>
# Example: ./sol-connect.sh gpuserver1

# Configuration - Edit these for your cluster
declare -A IPMI=(
    ["gpuserver1"]="192.168.1.72"
    ["gpuserver2"]="192.168.1.70"
)

IPMI_USER="admin"
IPMI_PASS="admin"

if [ -z "$1" ]; then
    echo "Usage: $0 <server_name>"
    echo ""
    echo "Available servers:"
    for server in "${!IPMI[@]}"; do
        echo "  - $server (IPMI: ${IPMI[$server]})"
    done
    exit 1
fi

SERVER=$1
IPMI_IP=${IPMI[$SERVER]}

if [ -z "$IPMI_IP" ]; then
    echo "Error: Unknown server '$SERVER'"
    echo ""
    echo "Available servers:"
    for server in "${!IPMI[@]}"; do
        echo "  - $server"
    done
    exit 1
fi

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              IPMI Serial Over LAN (SOL)                      ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  Server:     $SERVER"
echo "  IPMI IP:    $IPMI_IP"
echo ""
echo "  ESCAPE SEQUENCES:"
echo "    ~.  - Disconnect SOL session"
echo "    ~B  - Send Break to remote"
echo "    ~~  - Send ~ character"
echo ""
echo "  Press ENTER to connect..."
read

# Deactivate any existing session first
ipmitool -I lanplus -H $IPMI_IP -U $IPMI_USER -P $IPMI_PASS sol deactivate 2>/dev/null

# Connect
ipmitool -I lanplus -H $IPMI_IP -U $IPMI_USER -P $IPMI_PASS sol activate

echo ""
echo "SOL session ended."
