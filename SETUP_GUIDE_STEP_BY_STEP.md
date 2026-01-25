# GPU Cluster LAB Setup - Complete Step-by-Step Guide

**Author:** Eniz Aksoy (CCIE #23970)
**Date:** January 2026
**Hardware:** 2× HYVE G2GPU12, 4× Tesla V100 16GB, Mellanox ConnectX-3 Pro 40GbE

This LAB guide documents every step of building a bare-metal AI training cluster, including commands, actual outputs, and key learnings from hands-on experience.

---

## Table of Contents

0. [Step 0: Identify RDMA Device Name](#step-0-identify-rdma-device-name)
1. [Step 1: Configure RDMA Network (40G Ports)](#step-1-configure-rdma-network-40g-ports)
1.5. [Step 1.5: Configure Leaf Switches (Optional)](#step-15-configure-leaf-switches-optional)
1.6. [Step 1.6: Configure PFC for Lossless RoCE](#step-16-configure-pfc-for-lossless-roce)
2. [Step 2: Test RDMA Performance](#step-2-test-rdma-performance)
3. [Step 3: Compare TCP vs RDMA](#step-3-compare-tcp-vs-rdma)
4. [Step 4: Install NVIDIA Drivers](#step-4-install-nvidia-drivers)
5. [Step 5: Install CUDA Toolkit](#step-5-install-cuda-toolkit)
6. [Step 6: Install NCCL Library](#step-6-install-nccl-library)
7. [Step 7: Build NCCL-Tests](#step-7-build-nccl-tests)
8. [Step 8: Test Intra-Node NCCL](#step-8-test-intra-node-nccl)
9. [Step 9: Install OpenMPI](#step-9-install-openmpi)
10. [Step 10: Set Up Passwordless SSH](#step-10-set-up-passwordless-ssh)
11. [Step 11: Rebuild NCCL-Tests with MPI](#step-11-rebuild-nccl-tests-with-mpi)
12. [Step 12: Test Multi-Node NCCL](#step-12-test-multi-node-nccl)
13. [Understanding the Results](#understanding-the-results)
14. [Network Upgrade Path](#network-upgrade-path)

---

## Step 0: Identify RDMA Device Name

### Goal
Find the correct RDMA device name before running any tests. Device names can vary based on kernel version and driver configuration.

### Commands

```bash
# List all RDMA devices
ibv_devices

# Show detailed device info (ports, state, speed)
ibstat
```

### Example Output

```
$ ibv_devices
    device              node GUID
    ------              ----------------
    rocep130s0          248a070300685ac0

$ ibstat
CA 'rocep130s0'
    CA type: MT4103
    Number of ports: 2
    Firmware version: 2.38.5000
    Port 1:
        State: Active
        Physical state: LinkUp
        Rate: 40
        Link layer: Ethernet
    Port 2:
        State: Active
        Physical state: LinkUp
        Rate: 40
        Link layer: Ethernet
```

### Device Naming Convention

| Naming Style | Example | When Used |
|--------------|---------|-----------|
| Legacy IB | `mlx4_0` | Older kernels, InfiniBand mode |
| RoCE/PCIe | `rocep130s0` | Newer kernels, RoCE mode |

> **Important:** The device name `rocep130s0` means: `roce` (RoCE device) + `p130` (PCIe bus 130) + `s0` (slot 0). Your device name may differ based on PCIe topology.

### Port to Interface Mapping

| IB Port | Linux Interface | IP Subnet | VLAN |
|---------|-----------------|-----------|------|
| Port 1 | ens6 | 10.0.1.0/24 | 101 |
| Port 2 | ens6d1 | 10.0.0.0/24 | 100 |

---

## Step 1: Configure RDMA Network (40G Ports)

### Goal
Configure both 40GbE ports on the ConnectX-3 Pro with persistent IP addresses for RDMA communication.

### Server Reference

| Server | Management IP | IPMI IP | Port1/ens6 (VLAN 101) | Port2/ens6d1 (VLAN 100) |
|--------|--------------|---------|----------------------|------------------------|
| gpuserver1 | 192.168.1.73 | 192.168.1.72 | 10.0.1.1 | 10.0.0.1 |
| gpuserver2 | 192.168.1.71 | 192.168.1.70 | 10.0.1.2 | 10.0.0.2 |

### Switch Port Connections

| Server | Interface | Switch | Port | VLAN |
|--------|-----------|--------|------|------|
| gpuserver1 | ens6 | Leaf 1 | Eth1/28 | 101 |
| gpuserver1 | ens6d1 | Leaf 2 | Eth1/28 | 100 |
| gpuserver2 | ens6 | Leaf 1 | Eth1/27 | 101 |
| gpuserver2 | ens6d1 | Leaf 2 | Eth1/27 | 100 |

### Configuration

Edit `/etc/netplan/01-network.yaml` on **gpuserver1**:

```yaml
network:
  version: 2
  ethernets:
    enp5s0:
      dhcp4: true
    enp6s0:
      dhcp4: true
      optional: true
    ens6:
      dhcp4: false
      addresses:
        - 10.0.1.1/24
      mtu: 9000
      optional: true
    ens6d1:
      dhcp4: false
      addresses:
        - 10.0.0.1/24
      mtu: 9000
      optional: true
```

Edit `/etc/netplan/01-network.yaml` on **gpuserver2**:

```yaml
network:
  version: 2
  ethernets:
    enp5s0:
      dhcp4: true
    enp6s0:
      dhcp4: true
      optional: true
    ens6:
      dhcp4: false
      addresses:
        - 10.0.1.2/24
      mtu: 9000
      optional: true
    ens6d1:
      dhcp4: false
      addresses:
        - 10.0.0.2/24
      mtu: 9000
      optional: true
```

### Commands

```bash
# Apply configuration
sudo netplan apply

# Verify interfaces
ip addr show ens6
ip addr show ens6d1

# Test connectivity
ping -c 3 10.0.0.2   # From gpuserver1
ping -c 3 10.0.1.2   # From gpuserver1
```

### Key Learning

> **Why MTU 9000?** Jumbo frames (9000 bytes) reduce CPU overhead by sending fewer, larger packets. This is especially important for RDMA where we want maximum throughput with minimum CPU involvement.

---

## Step 1.5: Configure Leaf Switches (Optional)

### Goal
Configure Cisco Nexus leaf switches for RoCE/RDMA traffic. Skip this if using back-to-back direct connections.

### Network Topology

```
                 ┌─────────────────┐     ┌─────────────────┐
                 │     Leaf 1      │◄───►│     Leaf 2      │
                 │   (10.2.0.2)    │     │   (10.2.0.3)    │
                 │ Cisco N9K-9332  │     │ Cisco N9K-9332  │
                 └───┬────────┬────┘     └───┬────────┬────┘
                 Eth1/27  Eth1/28        Eth1/27  Eth1/28
                     │        │              │        │
                     │        └──────────────┼────────┘
                     │                       │
                     ▼                       ▼
              ┌─────────────┐         ┌─────────────┐
              │ gpuserver2  │         │ gpuserver1  │
              │ens6  ens6d1 │         │ens6  ens6d1 │
              └─────────────┘         └─────────────┘
```

### Switch Credentials

| Device | IP | Username | Password |
|--------|-----|----------|----------|
| Leaf 1 | 10.2.0.2 | cisco | cisco |
| Leaf 2 | 10.2.0.3 | cisco | cisco |

### VLAN Configuration

| VLAN | Subnet | Purpose | Server Interface |
|------|--------|---------|------------------|
| 100 | 10.0.0.0/24 | RDMA Network 1 | ens6d1 (Port 2) |
| 101 | 10.0.1.0/24 | RDMA Network 2 | ens6 (Port 1) |

### Switch Port Configuration (NX-OS)

```
! Create VLANs
vlan 100
  name RDMA_Network_1
vlan 101
  name RDMA_Network_2

! Configure GPU server ports
interface Ethernet1/27
  description GPU_Server_Port
  switchport
  switchport mode trunk
  switchport trunk allowed vlan 100,101
  mtu 9216
  no shutdown

interface Ethernet1/28
  description GPU_Server_Port
  switchport
  switchport mode trunk
  switchport trunk allowed vlan 100,101
  mtu 9216
  no shutdown

! Inter-switch link (trunk all VLANs)
interface Ethernet1/10
  description Inter_Leaf_Link
  switchport
  switchport mode trunk
  mtu 9216
  no shutdown
```

### Enable LLDP on Linux Servers

LLDP helps identify which server port connects to which switch port:

```bash
# Install LLDP daemon
sudo apt install -y lldpd

# Enable and start
sudo systemctl enable --now lldpd

# View neighbors (shows connected switch ports)
sudo lldpcli show neighbors
```

### Verify Connectivity

```bash
# From gpuserver1
ping -c 3 10.0.0.2   # Test VLAN 100
ping -c 3 10.0.1.2   # Test VLAN 101

# Check switch MAC tables (from switch CLI)
show mac address-table dynamic
show lldp neighbors
```

### Key Learning

> **Back-to-Back vs Switched:** Direct connections give lowest latency (~0.85 µs) but limit you to 2 nodes. Switches add ~2-3 µs latency but enable scaling to many nodes. For production clusters, switches are essential.

> **VLAN Separation:** Using separate VLANs (100 and 101) for each RDMA network allows for traffic isolation and easier troubleshooting.

---

## Step 1.6: Configure PFC for Lossless RoCE

### Goal
Enable Priority Flow Control (PFC) to achieve lossless Ethernet for RoCE/RDMA traffic. Without PFC, large RDMA transfers can experience packet drops causing "protection errors."

### Check Current State (Before Configuration)

First, verify PFC and DSCP mapping are not configured:

**On Servers:**
```bash
# Check PFC status
dcb pfc show dev ens6

# Check DSCP to priority mapping
dcb app show dev ens6
```

**On Switch (NX-OS):**
```
show interface Eth1/27 priority-flow-control
```

### Actual Output (Before Configuration)

**gpuserver1:**
```
--- PFC Status ---
pfc-cap 8 macsec-bypass off delay 0
prio-pfc 0:off 1:off 2:off 3:off 4:off 5:off 6:off 7:off

--- DSCP/Priority Mapping ---
(empty = no mapping configured)

--- Pause Frame Counters ---
     rx_pause: 0
     tx_pause: 0
```

**gpuserver2:**
```
--- PFC Status ---
pfc-cap 8 macsec-bypass off delay 0
prio-pfc 0:off 1:off 2:off 3:off 4:off 5:off 6:off 7:off

--- DSCP/Priority Mapping ---
(empty = no mapping configured)

--- Pause Frame Counters ---
     rx_pause: 0
     tx_pause: 0
```

**Leaf 1 Switch:**
```
============================================================
Port               Mode Oper(VL bmap)  RxPPP      TxPPP
============================================================
Ethernet1/27       Auto Off           0          0
Ethernet1/28       Auto Off           0          0
```

### The Problem

| Component | Current State | Issue |
|-----------|---------------|-------|
| Server PFC | All priorities OFF | No PAUSE frames will be sent/honored |
| Server DSCP Mapping | Empty | NCCL's DSCP 26 packets go to default queue |
| Switch PFC | Mode: Auto, Oper: Off | Switch won't send/honor PAUSE frames |
| Pause Counters | 0 | Confirms no flow control happening |

> **Result:** When buffers fill during large RDMA transfers, packets are DROPPED instead of paused, causing "Completion with error, Failed status 12" errors.

### Why PFC is Required

```
┌─────────────────────────────────────────────────────────────────┐
│                    WITHOUT PFC (LOSSY)                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   Large RDMA Transfer → Switch Buffer Fills → PACKETS DROPPED   │
│                                              → RDMA Error!       │
│                                                                  │
│   Result: "Completion with error, Failed status 12"             │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                    WITH PFC (LOSSLESS)                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   Large RDMA Transfer → Buffer Fills → PAUSE Frame Sent         │
│                                      → Sender Pauses            │
│                                      → Buffer Drains            │
│                                      → Resume → SUCCESS!        │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Traffic Flow: DSCP → Priority → PFC

Understanding how packets get mapped to PFC priorities:

```
┌──────────────────────────────────────────────────────────────────────────┐
│                     LOSSLESS RoCE PACKET FLOW                             │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                           │
│   1. APPLICATION (NCCL)                                                   │
│      └── Marks packets with DSCP 26 (AF31) in IP header                  │
│                                                                           │
│   2. LINUX OS (tc qdisc / dcb)                                           │
│      └── Maps DSCP 26 → Priority 3 (802.1p CoS)                          │
│                                                                           │
│   3. NIC (ConnectX)                                                       │
│      └── PFC enabled on Priority 3                                        │
│      └── Sends PAUSE frames when RX buffer fills                         │
│                                                                           │
│   4. SWITCH (Nexus)                                                       │
│      └── PFC enabled on Priority 3                                        │
│      └── Honors incoming PAUSE frames                                     │
│      └── Sends PAUSE frames when egress congested                        │
│                                                                           │
└──────────────────────────────────────────────────────────────────────────┘
```

### Priority Assignment (Best Practice)

| Traffic Type | DSCP | Priority (CoS) | PFC Enabled |
|--------------|------|----------------|-------------|
| GPU/NCCL (RoCE) | 26 (AF31) | 3 | ✅ Yes |
| Storage/NVMe-oF (RoCE) | 24 (CS3) | 4 | ✅ Yes |
| Management/Default | 0 | 0 | ❌ No |

> **Why separate priorities?** GPU traffic is bursty and latency-sensitive. Storage traffic is continuous and throughput-sensitive. Separating them prevents storage congestion from pausing GPU sync operations.

### Part A: Switch Configuration (Nexus 9332)

Configure PFC and QoS on the Nexus switches:

```
! Enable QoS globally
feature qos

! Create class-map to match RoCE traffic (DSCP 26)
class-map type qos match-all ROCE_TRAFFIC
  match dscp 26

! Create policy-map to set CoS priority
policy-map type qos ROCE_POLICY
  class ROCE_TRAFFIC
    set qos-group 3

! Create network-qos policy for PFC
policy-map type network-qos ROCE_NET_POLICY
  class type network-qos class-default
    mtu 9216
  class type network-qos c-out-8q-q3
    pause pfc-cos 3
    mtu 9216

! Apply policies globally
system qos
  service-policy type qos input ROCE_POLICY
  service-policy type network-qos ROCE_NET_POLICY

! Enable PFC on GPU server interfaces
interface Ethernet1/27
  priority-flow-control mode on

interface Ethernet1/28
  priority-flow-control mode on
```

### Part B: Server Configuration (Ubuntu + ConnectX-3)

#### Using Linux DCB Tools (Inbox Driver - Recommended)

For ConnectX-3 with inbox mlx4 driver, use the `dcb` tool:

```bash
# 1. Enable PFC on Priority 3 for both interfaces
sudo dcb pfc set dev ens6 prio-pfc 0:off 1:off 2:off 3:on 4:off 5:off 6:off 7:off
sudo dcb pfc set dev ens6d1 prio-pfc 0:off 1:off 2:off 3:on 4:off 5:off 6:off 7:off

# 2. Map DSCP 26 (AF31) to Priority 3 (may fail on inbox mlx4 - OK if switch does it)
sudo dcb app add dev ens6 dscp-prio 26:3
sudo dcb app add dev ens6d1 dscp-prio 26:3

# 3. Verify configuration
dcb pfc show dev ens6
dcb app show dev ens6
```

#### Actual Output (After Configuration)

```
$ dcb pfc show dev ens6
pfc-cap 8 macsec-bypass off delay 0
prio-pfc 0:off 1:off 2:off 3:on 4:off 5:off 6:off 7:off

$ dcb app show dev ens6
dscp-prio AF31:3
```

> **Note on DSCP Mapping:** The `dcb app add` command may return "Error 239" with inbox mlx4 driver. This is OK - the switch can do DSCP→Priority mapping instead. PFC (`dcb pfc set`) works reliably.

#### Make Configuration Persistent (Systemd Service)

Create a startup service so PFC survives reboot:

```bash
# Create the configuration script
sudo tee /usr/local/bin/configure-roce-qos.sh << 'EOF'
#!/bin/bash
# Configure PFC and DSCP mapping for RoCE/RDMA

# Wait for interfaces
sleep 5

# ens6 (VLAN 101)
dcb app add dev ens6 dscp-prio 26:3 2>/dev/null
dcb pfc set dev ens6 prio-pfc 0:off 1:off 2:off 3:on 4:off 5:off 6:off 7:off

# ens6d1 (VLAN 100)
dcb app add dev ens6d1 dscp-prio 26:3 2>/dev/null
dcb pfc set dev ens6d1 prio-pfc 0:off 1:off 2:off 3:on 4:off 5:off 6:off 7:off

# Enable ECN
sysctl -w net.ipv4.tcp_ecn=1

logger "RoCE QoS configured: PFC on priority 3, DSCP 26 mapped"
EOF

sudo chmod +x /usr/local/bin/configure-roce-qos.sh

# Create systemd service
sudo tee /etc/systemd/system/roce-qos.service << 'EOF'
[Unit]
Description=Configure RoCE QoS (PFC + DSCP mapping)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/configure-roce-qos.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Enable the service
sudo systemctl daemon-reload
sudo systemctl enable roce-qos.service
```

#### Alternative: Using mlnx_qos (Requires MLNX_OFED)

If you have MLNX_OFED installed (ConnectX-4 or newer):

```bash
mlnx_qos -i ens6 --pfc 0,0,0,1,0,0,0,0
mlnx_qos -i ens6
```

> **Note:** MLNX_OFED 5.x does NOT support ConnectX-3. Use inbox driver with `dcb` tool instead.

### Part C: NCCL Environment Variables

NCCL uses DSCP 26 by default, but you can customize:

```bash
# Use default RoCE traffic class (DSCP 26)
export NCCL_IB_TC=106

# Or explicitly set DSCP value (26 = 0x1a)
export NCCL_IB_SL=3

# Enable ECN marking (optional, for congestion notification)
export NCCL_IB_GID_INDEX=2
export NCCL_IB_DISABLE=0
```

### Verification Commands

#### On Switches (NX-OS):

```
! Check PFC status on interface
show interface Ethernet1/27 priority-flow-control

! Check PFC counters (pause frames sent/received)
show interface Ethernet1/27 counters detailed | grep -i pfc

! Verify QoS policy is applied
show policy-map interface Ethernet1/27

! Check buffer usage
show queuing interface Ethernet1/27
```

#### On Servers (Linux):

```bash
# Check if PFC is enabled on NIC
ethtool -S ens6 | grep -i pfc

# Check DCBX status
lldptool -t -i ens6 -V PFC

# Monitor PFC pause frames
watch -n 1 'ethtool -S ens6 | grep -E "(pause|pfc)"'

# Check tc qdisc configuration
tc qdisc show dev ens6
tc filter show dev ens6
```

### ECN Configuration (Optional)

ECN (Explicit Congestion Notification) can mark packets before buffers fill, reducing the need for PFC pauses:

#### On Switch:

```
! Enable ECN marking at 70% buffer threshold
policy-map type network-qos ROCE_NET_POLICY
  class type network-qos c-out-8q-q3
    pause pfc-cos 3
    congestion-control ecn
    ecn-threshold 70
```

#### On Server:

```bash
# Enable ECN in Linux TCP/IP stack
sudo sysctl -w net.ipv4.tcp_ecn=1

# Make persistent
echo "net.ipv4.tcp_ecn = 1" | sudo tee -a /etc/sysctl.conf
```

### Troubleshooting PFC

| Symptom | Cause | Solution |
|---------|-------|----------|
| RDMA bandwidth test fails | PFC not enabled | Enable PFC on switch + NIC |
| High PFC pause count | Congestion or slow receiver | Check buffer allocation, add ECN |
| No PFC pause frames | DSCP not mapped to priority | Verify tc/dcb mapping |
| Latency spikes | Excessive PFC pauses | Tune ECN thresholds, check for oversubscription |

### Key Learning

> **PFC is End-to-End:** Every device in the path (NIC → Switch → NIC) must have PFC enabled on the same priority. If any device doesn't honor PFC, packets can still be dropped.

> **DCBX Auto-Negotiation:** With MLNX_OFED and proper switch config, DCBX can auto-negotiate PFC settings. The switch "advertises" PFC requirements, and the NIC accepts them. With inbox drivers, manual configuration is usually required.

> **Separate GPU and Storage:** If running both NCCL and NVMe-oF over RoCE, use different priorities (e.g., 3 for GPU, 4 for storage) to prevent interference.

---

## Step 2: Test RDMA Performance

### Goal
Verify RDMA is working and measure bandwidth/latency.

### Prerequisites
1. Run `ibv_devices` to confirm your device name (e.g., `rocep130s0`)
2. Run `ibstat` to verify ports are Active and LinkUp
3. Ensure IP connectivity with `ping`

### Commands

> **Note:** Replace `rocep130s0` with your actual device name from `ibv_devices`

**Test on VLAN 101 (10.0.1.x network via Port 1/ens6):**

```bash
# On gpuserver2 (server - start first):
ib_write_bw --ib-dev=rocep130s0 --ib-port=1 --gid-index=2

# On gpuserver1 (client):
ib_write_bw --ib-dev=rocep130s0 --ib-port=1 --gid-index=2 10.0.1.2
```

**Test on VLAN 100 (10.0.0.x network via Port 2/ens6d1):**

```bash
# On gpuserver2 (server - start first):
ib_write_bw --ib-dev=rocep130s0 --ib-port=2 --gid-index=2

# On gpuserver1 (client):
ib_write_bw --ib-dev=rocep130s0 --ib-port=2 --gid-index=2 10.0.0.2
```

**Latency Test (ib_write_lat):**

```bash
# On gpuserver2 (server):
ib_write_lat --ib-dev=rocep130s0 --ib-port=1 --gid-index=2

# On gpuserver1 (client):
ib_write_lat --ib-dev=rocep130s0 --ib-port=1 --gid-index=2 10.0.1.2
```

### Actual Output

```
---------------------------------------------------------------------------------------
                    RDMA_Write BW Test
---------------------------------------------------------------------------------------
 #bytes     #iterations    BW peak[MB/sec]    BW average[MB/sec]   MsgRate[Mpps]
 65536      5000           4555.12            4554.89              0.072878
---------------------------------------------------------------------------------------
```

```
---------------------------------------------------------------------------------------
                    RDMA_Write Latency Test
---------------------------------------------------------------------------------------
 #bytes        #iterations       t_avg[usec]    t_stdev[usec]
 2             1000              0.85           0.05
---------------------------------------------------------------------------------------
```

### Results Summary

| Metric | Result |
|--------|--------|
| **Bandwidth** | 4554 MB/s (36.4 Gbps) |
| **Latency** | 0.85 µs (850 nanoseconds) |
| **Link Speed** | 40 Gbps |

### Key Learning

> **Why --gid-index=2?** RoCE (RDMA over Converged Ethernet) uses GID (Global Identifier) instead of InfiniBand's LID. GID index 2 corresponds to the RoCEv2 IPv4 configuration on ConnectX-3. Without this flag, the test fails with "Unable to find GID".

> **Why --ib-port=2?** The physical cable was connected to port 2 of the dual-port NIC. Always verify which port has the cable!

---

## Step 3: Compare TCP vs RDMA

### Goal
Quantify how much faster RDMA is compared to TCP.

### Commands

**TCP Bandwidth (iperf3):**

```bash
# On gpuserver2:
iperf3 -s

# On gpuserver1:
iperf3 -c 10.0.0.2 -t 10
```

**TCP Latency (sockperf):**

```bash
# Install
sudo apt install sockperf -y

# On gpuserver2:
sockperf sr --tcp -p 12345

# On gpuserver1:
sockperf pp --tcp -i 10.0.0.2 -p 12345 -t 10
```

### Results Comparison

| Metric | TCP | RDMA | RDMA Advantage |
|--------|-----|------|----------------|
| **Bandwidth** | 27.4 Gbps (3.4 GB/s) | 36.4 Gbps (4.55 GB/s) | 33% faster |
| **Latency** | 21.9 µs | 0.85 µs | **26× faster!** |

### Key Learning

> **Why is latency improvement so dramatic?** TCP requires kernel involvement for every packet - context switches, buffer copies, protocol processing. RDMA bypasses the kernel entirely, allowing the NIC to read/write directly to application memory. For AI training where GPUs sync thousands of times per second, this 26× latency reduction is huge!

---

## Step 4: Install NVIDIA Drivers

### Goal
Install NVIDIA drivers to enable V100 GPU usage.

### Commands

```bash
# Add NVIDIA repository
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
sudo dpkg -i cuda-keyring_1.1-1_all.deb
sudo apt update

# Install driver
sudo apt install nvidia-driver-535 -y

# Reboot
sudo reboot

# Verify
nvidia-smi
```

### Actual Output

```
+-----------------------------------------------------------------------------------------+
| NVIDIA-SMI 580.126.09             Driver Version: 580.126.09     CUDA Version: 13.0    |
|-----------------------------------------+------------------------+----------------------+
| GPU  Name                 Persistence-M | Bus-Id          Disp.A | Volatile Uncorr. ECC |
|=========================================+========================+======================|
|   0  Tesla V100-PCIE-16GB           Off | 00000000:02:00.0   Off |                    0 |
| N/A   30C    P0              25W / 250W |       0MiB / 16384MiB  |      0%      Default |
+-----------------------------------------+------------------------+----------------------+
|   1  Tesla V100-PCIE-16GB           Off | 00000000:03:00.0   Off |                    0 |
| N/A   30C    P0              24W / 250W |       0MiB / 16384MiB  |      0%      Default |
+-----------------------------------------+------------------------+----------------------+
```

### Key Learning

> **Driver vs CUDA Toolkit:** The NVIDIA driver allows the system to use GPUs (nvidia-smi works). The CUDA Toolkit adds the nvcc compiler and development libraries needed to build GPU applications. You can have the driver without the toolkit, but not vice versa.

---

## Step 5: Install CUDA Toolkit

### Goal
Install CUDA compiler (nvcc) needed to build GPU applications like nccl-tests.

### Commands

```bash
# Install CUDA 12.6 toolkit
sudo apt install cuda-toolkit-12-6 -y

# Add to PATH
echo 'export PATH=/usr/local/cuda-12.6/bin:$PATH' >> ~/.bashrc
echo 'export LD_LIBRARY_PATH=/usr/local/cuda-12.6/lib64:$LD_LIBRARY_PATH' >> ~/.bashrc
source ~/.bashrc

# Verify
nvcc --version
```

### Actual Output

```
nvcc: NVIDIA (R) Cuda compiler driver
Copyright (c) 2005-2024 NVIDIA Corporation
Built on Tue_Oct_29_23:50:19_PDT_2024
Cuda compilation tools, release 12.6, V12.6.85
Build cuda_12.6.r12.6/compiler.35059454_0
```

### Troubleshooting Note

> **Don't use Ubuntu's nvidia-cuda-toolkit package!** It's outdated and causes version mismatches with newer NCCL. Always use NVIDIA's official cuda-toolkit-12-x packages from their repository.

---

## Step 6: Install NCCL Library

### Goal
Install NCCL (NVIDIA Collective Communications Library) for multi-GPU communication.

### Commands

```bash
# Install NCCL matching CUDA version
sudo apt install libnccl2=2.21.5-1+cuda12.4 libnccl-dev=2.21.5-1+cuda12.4 -y

# Verify
dpkg -l | grep nccl
```

### Actual Output

```
ii  libnccl-dev   2.21.5-1+cuda12.4   amd64   NVIDIA Collective Communication Library (NCCL) Development Files
ii  libnccl2      2.21.5-1+cuda12.4   amd64   NVIDIA Collective Communication Library (NCCL) Runtime
```

### Key Learning

> **Version Matching is Critical!** NCCL must match your CUDA version. NCCL 2.21.5+cuda12.4 works with CUDA 12.x. If you install NCCL for CUDA 13 with CUDA 12 toolkit, you'll get "named symbol not found" errors at runtime.

---

## Step 7: Build NCCL-Tests

### Goal
Build the official NCCL performance testing tools.

### Commands

```bash
# Clone repository
git clone https://github.com/NVIDIA/nccl-tests.git
cd nccl-tests

# Build without MPI (single-node testing)
make MPI=0 CUDA_HOME=/usr/local/cuda-12.6 NCCL_HOME=/usr

# Verify build
ls build/
```

### Actual Output

```
all_reduce_perf   broadcast_perf    reduce_perf      scatter_perf
all_gather_perf   gather_perf       reduce_scatter_perf  sendrecv_perf
alltoall_perf     hypercube_perf
```

### What Each Test Does

| Test | NCCL Operation | When Used in AI Training |
|------|----------------|-------------------------|
| `all_reduce_perf` | AllReduce | Gradient sync (most important!) |
| `all_gather_perf` | AllGather | Collect results from all GPUs |
| `broadcast_perf` | Broadcast | Send model to all GPUs (init) |
| `reduce_scatter_perf` | ReduceScatter | Large model parallel training |

---

## Step 8: Test Intra-Node NCCL

### Goal
Test NCCL communication between 2 GPUs on the same server.

### Commands

```bash
cd ~/nccl-tests/build
./all_reduce_perf -b 8 -e 128M -f 2 -g 2
```

**Parameters:**
- `-b 8` = start with 8 bytes
- `-e 128M` = end with 128 MB
- `-f 2` = multiply size by 2 each step
- `-g 2` = use 2 GPUs

### Actual Output

```
# nccl-tests version 2.17.8
# Using devices
#  Rank  0 Group  0 Pid  11155 on gpuserver2 device  0 [0000:02:00] Tesla V100-PCIE-16GB
#  Rank  1 Group  0 Pid  11155 on gpuserver2 device  1 [0000:03:00] Tesla V100-PCIE-16GB
#
#       size         count    type   redop     time   algbw   busbw  #wrong
#        (B)    (elements)                     (us)  (GB/s)  (GB/s)
           8             2   float     sum    10.09    0.00    0.00       0
        1024           256   float     sum    10.29    0.10    0.10       0
       65536         16384   float     sum    29.63    2.21    2.21       0
     1048576        262144   float     sum   165.33    6.34    6.34       0
     8388608       2097152   float     sum  1201.02    6.98    6.98       0
   134217728      33554432   float     sum  18927.2    7.09    7.09       0
# Avg bus bandwidth    : 2.97489
```

### Results

| Data Size | Bus Bandwidth | Notes |
|-----------|---------------|-------|
| 8 B - 1 KB | ~0.1 GB/s | Latency dominated |
| 64 KB | 2.2 GB/s | Bandwidth scaling |
| 1 MB | 6.3 GB/s | Near peak |
| **128 MB** | **7.09 GB/s** | **Peak PCIe bandwidth!** |

### Key Learning

> **Understanding the Columns:**
> - `time (us)` = How long the operation took in microseconds
> - `algbw (GB/s)` = Algorithm bandwidth (size ÷ time)
> - `busbw (GB/s)` = Bus bandwidth (accounts for algorithm efficiency)
> - `#wrong` = Data errors (should always be 0!)

> **7 GB/s is excellent!** V100s on PCIe Gen3 x16 have theoretical max ~12 GB/s. Getting 7 GB/s for AllReduce (which sends data both directions) is ~60% efficiency - very good!

---

## Step 9: Install OpenMPI

### Goal
Install MPI for launching distributed applications across multiple servers.

### Commands

```bash
# Install OpenMPI
sudo apt install openmpi-bin libopenmpi-dev -y

# Verify
mpirun --version
```

### Actual Output

```
mpirun (Open MPI) 4.1.2
```

### Key Learning

> **What is MPI?** MPI (Message Passing Interface) is a "launcher" for distributed programs. It SSHs into each server, starts processes, and coordinates them. Think of it as the foreman who tells workers where to go. NCCL is the truck that moves the actual GPU data.

```
MPI's Job:
├── "SSH into server1, start 2 processes"
├── "SSH into server2, start 2 processes"
├── "Tell each process: you are Rank 0, 1, 2, 3"
└── "Coordinate start/stop"

NCCL's Job:
├── "Move 128MB of gradients between GPUs"
├── "Use RDMA for fastest path"
└── "AllReduce across all 4 GPUs"
```

---

## Step 10: Set Up Passwordless SSH

### Goal
Enable MPI to launch processes on remote servers without password prompts.

### Commands

```bash
# Generate SSH key without passphrase (press Enter for all prompts)
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa_mpi -N ""

# Copy key to other server
# From gpuserver1:
ssh-copy-id -i ~/.ssh/id_rsa_mpi eniz@192.168.1.71

# From gpuserver2:
ssh-copy-id -i ~/.ssh/id_rsa_mpi eniz@192.168.1.73

# Create SSH config (~/.ssh/config) on BOTH servers:
cat >> ~/.ssh/config << 'EOF'
Host 192.168.1.71
    IdentityFile ~/.ssh/id_rsa_mpi
    StrictHostKeyChecking no

Host 192.168.1.73
    IdentityFile ~/.ssh/id_rsa_mpi
    StrictHostKeyChecking no
EOF
chmod 600 ~/.ssh/config

# Test (should NOT ask for password!)
ssh 192.168.1.71 hostname
ssh 192.168.1.73 hostname
```

### Actual Output

```
eniz@gpuserver1:~$ ssh 192.168.1.71 hostname
gpuserver2
```

### Key Learning

> **Why no passphrase?** When you run `mpirun --host server1,server2 ./program`, MPI internally does `ssh server2 ./program`. If SSH asks for a password/passphrase, MPI hangs forever waiting for input it can't provide. For cluster-internal communication, passphrase-less keys are standard practice.

---

## Step 11: Rebuild NCCL-Tests with MPI

### Goal
Enable multi-node testing by rebuilding nccl-tests with MPI support.

### Commands

```bash
cd ~/nccl-tests
make clean
make MPI=1 CUDA_HOME=/usr/local/cuda-12.6 NCCL_HOME=/usr MPI_HOME=/usr/lib/x86_64-linux-gnu/openmpi
```

**Note:** Changed `MPI=0` to `MPI=1` and added `MPI_HOME` path.

### Actual Output

```
Compiling  all_reduce.cu  > build/all_reduce.o
Linking  build/all_reduce.o > build/all_reduce_perf
...
make[1]: Leaving directory '/home/eniz/nccl-tests/src'
```

### Troubleshooting

If you get `mpi.h: No such file or directory`:
```bash
# Find MPI include path
dpkg -L libopenmpi-dev | grep mpi.h

# Add MPI_HOME to make command
make MPI=1 ... MPI_HOME=/usr/lib/x86_64-linux-gnu/openmpi
```

---

## Step 12: Test Multi-Node NCCL

### Goal
Test NCCL communication across all 4 GPUs (2 servers × 2 GPUs).

### Commands

```bash
cd ~/nccl-tests/build

# Set environment variables
export NCCL_DEBUG=INFO
export NCCL_IB_DISABLE=0

# Run 4-GPU test across 2 servers
mpirun -np 4 --host 192.168.1.73:2,192.168.1.71:2 \
  -x NCCL_DEBUG=INFO \
  -x NCCL_IB_DISABLE=0 \
  -x LD_LIBRARY_PATH \
  ./all_reduce_perf -b 8 -e 128M -f 2 -g 1
```

**Parameters:**
- `-np 4` = 4 total processes
- `--host server1:2,server2:2` = 2 processes per server
- `-g 1` = each process uses 1 GPU
- `-x VAR` = export environment variable to remote hosts

### Actual Output (Key Parts)

```
# Using devices
#  Rank  0 Group  0 Pid  15326 on gpuserver1 device  0 Tesla V100-PCIE-16GB
#  Rank  1 Group  0 Pid  15327 on gpuserver1 device  1 Tesla V100-PCIE-16GB
#  Rank  2 Group  0 Pid  14869 on gpuserver2 device  0 Tesla V100-PCIE-16GB
#  Rank  3 Group  0 Pid  14871 on gpuserver2 device  1 Tesla V100-PCIE-16GB

gpuserver1:15326 [0] NCCL INFO NET/IB : Using [0]={[0] rocep130s0:1/RoCE, [1] rocep130s0:2/RoCE}
gpuserver1:15326 [0] NCCL INFO Using network IB

gpuserver1:15326 [0] NCCL INFO Channel 00 : 0[0] -> 1[1] via SHM/direct/direct
gpuserver1:15327 [1] NCCL INFO Channel 00/0 : 1[1] -> 2[0] [send] via NET/IB/0

#       size      time   algbw   busbw  #wrong
   134217728   107800    1.25    1.87       0
```

### Results

| Data Size | Bus Bandwidth | Notes |
|-----------|---------------|-------|
| 8 B - 1 KB | ~0.0 GB/s | Latency dominated |
| 128 KB | 0.9 GB/s | RDMA warming up |
| 8 MB | 1.8 GB/s | Good scaling |
| **128 MB** | **~2.0 GB/s** | **Peak cross-server** |

### Communication Paths (from NCCL debug)

```
Intra-server (same machine):
  GPU0 ↔ GPU1: "via SHM/direct/direct" (shared memory, ~7 GB/s)

Inter-server (across network):
  GPU1(srv1) → GPU0(srv2): "via NET/IB/0" (RDMA/RoCE, ~2 GB/s)
```

### Key Learning

> **Why only 2 GB/s when raw RDMA is 4.5 GB/s?** ConnectX-3 doesn't support GPUDirect RDMA. Data path is:
> ```
> GPU → PCIe → CPU Memory → RDMA NIC → Network → RDMA NIC → CPU Memory → PCIe → GPU
> ```
> Those extra memory copies cut effective bandwidth roughly in half. ConnectX-4+ with GPUDirect would give ~4 GB/s.

---

## Understanding the Results

### Performance Summary

| Test | Configuration | Peak Bandwidth |
|------|---------------|----------------|
| Raw RDMA (ib_write_bw) | NIC to NIC | 4.55 GB/s |
| Intra-node NCCL | 2 GPUs, same server | 7.09 GB/s |
| Multi-node NCCL | 4 GPUs, 2 servers | ~2.0 GB/s |

### Why Different Speeds?

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                    BANDWIDTH BREAKDOWN                                          │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│   Intra-Node (7 GB/s):                                                         │
│   GPU ←──── PCIe + Shared Memory ────→ GPU                                     │
│   Fast! Both GPUs on same CPU memory bus                                       │
│                                                                                 │
│   Inter-Node with GPUDirect (~4 GB/s, ConnectX-4+):                           │
│   GPU ←──── PCIe ────→ RDMA NIC ←──── Network ────→ RDMA NIC ←── PCIe ──→ GPU │
│   Good! NIC can read GPU memory directly                                       │
│                                                                                 │
│   Inter-Node without GPUDirect (~2 GB/s, ConnectX-3):                         │
│   GPU → CPU Mem → RDMA NIC → Network → RDMA NIC → CPU Mem → GPU               │
│   Slower! Extra copies through CPU memory                                      │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### Is 2 GB/s Enough?

| Model | Gradient Size | Time @ 2 GB/s | Bottleneck? |
|-------|--------------|---------------|-------------|
| ResNet-50 | 100 MB | 50 ms | ✅ No (compute is 100ms) |
| BERT-Base | 440 MB | 220 ms | ⚠️ Borderline |
| BERT-Large | 1.4 GB | 700 ms | ❌ Yes (compute is 300ms) |

**For V100 16GB GPUs, 2 GB/s handles most realistic models!**

---

## Network Upgrade Path

### Current Limitation

ConnectX-3 Pro lacks GPUDirect RDMA, limiting NCCL to ~2 GB/s.

### Recommended Upgrade

| Component | Current | Upgrade To | Cost |
|-----------|---------|------------|------|
| NICs | ConnectX-3 Pro | ConnectX-4 EN (MCX416A-CCAT) | ~$50-80 each |
| Switch | Cisco 9332 (keep!) | No change needed | $0 |
| Cables | QSFP+ DAC (keep!) | No change needed | $0 |

**Total upgrade cost: ~$100-160**

### Expected Improvement

| Metric | ConnectX-3 | ConnectX-4 (GPUDirect) |
|--------|------------|------------------------|
| NCCL bandwidth | ~2 GB/s | ~4 GB/s |
| Improvement | baseline | **2× faster!** |

### Future Architecture (Separate Networks)

```
GPU Network (Cisco 9332 + ConnectX-4):
├── NCCL traffic only
├── GPUDirect RDMA enabled
└── ~4 GB/s gradient sync

Storage Network (Separate switch + ConnectX-3):
├── NVMe-oF / NFS traffic
├── Reuse old NICs!
└── No interference with GPU traffic
```

---

## Quick Reference Commands

### Find RDMA Device
```bash
# List devices
ibv_devices

# Detailed status
ibstat
```

### RDMA Testing
```bash
# Find your device name first!
RDMA_DEV=$(ibv_devices | grep -v device | awk '{print $1}')
echo "Your RDMA device: $RDMA_DEV"

# Bandwidth (VLAN 101 / Port 1)
ib_write_bw --ib-dev=rocep130s0 --ib-port=1 --gid-index=2 10.0.1.2

# Bandwidth (VLAN 100 / Port 2)
ib_write_bw --ib-dev=rocep130s0 --ib-port=2 --gid-index=2 10.0.0.2

# Latency
ib_write_lat --ib-dev=rocep130s0 --ib-port=1 --gid-index=2 10.0.1.2
```

### NCCL Testing
```bash
# Single node (2 GPUs)
./all_reduce_perf -b 8 -e 128M -f 2 -g 2

# Multi-node (4 GPUs)
mpirun -np 4 --host srv1:2,srv2:2 -x NCCL_DEBUG=INFO -x NCCL_IB_DISABLE=0 -x LD_LIBRARY_PATH ./all_reduce_perf -b 8 -e 128M -f 2 -g 1
```

### GPU Status
```bash
nvidia-smi
nvcc --version
```

---

## Lessons Learned

1. **Version matching is critical** - CUDA, NCCL, and drivers must be compatible
2. **GID index matters for RoCE** - Always use `--gid-index=2` on ConnectX-3
3. **MPI needs passwordless SSH** - Set up SSH keys before multi-node tests
4. **Separate networks = better performance** - GPU and storage traffic shouldn't compete
5. **GPUDirect makes a big difference** - 2× improvement for ~$150 upgrade
6. **Test before production** - NCCL-tests reveals issues before real training
7. **Device names can change!** - Always run `ibv_devices` to find the correct RDMA device name. It may be `mlx4_0` or `rocep130s0` depending on kernel/driver version
8. **LLDP is your friend** - Install `lldpd` on servers to easily identify switch port connections
9. **Switches add latency** - Back-to-back: ~0.85 µs, Through switches: ~3.5 µs (still excellent for RDMA)
10. **VLANs organize traffic** - Use separate VLANs (100, 101) for each RDMA subnet for easier management

---

*Guide created during hands-on cluster setup session, January 2026*
*Built with the assistance of Claude Code*
