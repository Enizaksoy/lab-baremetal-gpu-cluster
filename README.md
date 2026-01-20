# Building a Bare Metal AI Training Cluster with V100 GPUs

A comprehensive guide to setting up a multi-node GPU cluster with RDMA networking for distributed AI training.

**Author:** Eniz Aksoy (CCIE #23970)
**Hardware:** HYVE G2GPU12 GPU Servers, NVIDIA Tesla V100, Mellanox ConnectX-3 Pro
**OS:** Ubuntu 22.04.5 LTS

---

## Table of Contents

1. [Overview](#overview)
2. [Hardware Specifications](#hardware-specifications)
3. [Network Architecture](#network-architecture)
4. [IPMI/BMC Setup](#ipmibmc-setup)
5. [Ubuntu Installation](#ubuntu-installation)
6. [Network Configuration](#network-configuration)
7. [Serial Console (SOL) Setup](#serial-console-sol-setup)
8. [NVIDIA Driver Installation](#nvidia-driver-installation)
9. [NCCL Setup for Distributed Training](#nccl-setup-for-distributed-training)
10. [RDMA/RoCEv2 Configuration](#rdmarocev2-configuration)
11. [Network Upgrade Plan](#network-upgrade-plan)
12. [Troubleshooting](#troubleshooting)

---

## Overview

This guide documents the setup of a 2-node GPU cluster designed for distributed AI training workloads. The cluster features:

- **4x NVIDIA Tesla V100 16GB GPUs** (2 per node)
- **40GbE RDMA networking** via Mellanox ConnectX-3 Pro
- **Out-of-band management** via IPMI Serial Over LAN (SOL)
- **High-speed storage** connectivity ready for NVMe-oF

### Why Bare Metal for AI?

| Aspect | Bare Metal | Cloud VMs |
|--------|------------|-----------|
| GPU Performance | Native PCIe, no virtualization overhead | Hypervisor overhead |
| RDMA Support | Full hardware RDMA | Limited or unavailable |
| Cost (long-term) | Lower TCO | Pay-per-use adds up |
| Customization | Full control | Limited options |
| Network Latency | Microseconds | Milliseconds |

---

## Hardware Specifications

### GPU Servers (HYVE G2GPU12)

| Component | Specification |
|-----------|---------------|
| **Motherboard** | ASUS Z10PG-D16 Series |
| **CPU** | Dual Intel Xeon (up to 72 cores total) |
| **RAM** | 64GB DDR4 (expandable to 1TB) |
| **GPUs** | 2x NVIDIA Tesla V100 PCIe 16GB |
| **Network** | 2x Intel I210 1GbE + 1x Mellanox ConnectX-3 Pro 40GbE |
| **Storage** | 256GB NVMe (OS) |
| **BMC** | ASUS ASMB8-iKVM |
| **PCIe Slots** | 8x PCIe 3.0 x16, plus x8 and x4 slots |

### Why HYVE G2GPU12?

- **Purpose-built for deep learning** - Designed for multi-GPU workloads
- **Excellent PCIe density** - Up to 8 GPUs per node
- **Flexible expansion** - Add NVMe, NICs, or more GPUs
- **Cost-effective** - Available on secondary market at reasonable prices

---

## Network Architecture

### Complete Cluster Topology

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                         MANAGEMENT NETWORK (1GbE)                               │
│                            192.168.1.0/24                                       │
├─────────────────────────────────────────────────────────────────────────────────┤
│         │              │                    │              │                    │
│    ┌────┴────┐    ┌────┴────┐          ┌────┴────┐   ┌────┴────┐               │
│    │  IPMI   │    │  Mgmt   │          │  Mgmt   │   │  IPMI   │               │
│    │  .72    │    │  .73    │          │  .71    │   │  .70    │               │
│    └─────────┘    └─────────┘          └─────────┘   └─────────┘               │
└─────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│                              GPU SERVERS                                        │
├───────────────────────────────────┬─────────────────────────────────────────────┤
│         gpuserver1                │              gpuserver2                     │
│        192.168.1.73               │             192.168.1.71                    │
│  ┌─────────────────────────────┐  │  ┌─────────────────────────────┐           │
│  │    ┌───────┐   ┌───────┐    │  │  │    ┌───────┐   ┌───────┐    │           │
│  │    │ V100  │   │ V100  │    │  │  │    │ V100  │   │ V100  │    │           │
│  │    │ GPU 0 │   │ GPU 1 │    │  │  │    │ GPU 0 │   │ GPU 1 │    │           │
│  │    │ 16GB  │   │ 16GB  │    │  │  │    │ 16GB  │   │ 16GB  │    │           │
│  │    └───┬───┘   └───┬───┘    │  │  │    └───┬───┘   └───┬───┘    │           │
│  │        │           │        │  │  │        │           │        │           │
│  │        └─────┬─────┘        │  │  │        └─────┬─────┘        │           │
│  │              │ PCIe         │  │  │              │ PCIe         │           │
│  │        ┌─────┴─────┐        │  │  │        ┌─────┴─────┐        │           │
│  │        │  NVMe SSD │        │  │  │        │  NVMe SSD │        │           │
│  │        │  256GB    │        │  │  │        │  256GB    │        │           │
│  │        │  2.2 GB/s │        │  │  │        │  2.2 GB/s │        │           │
│  │        └───────────┘        │  │  │        └───────────┘        │           │
│  │                             │  │  │                             │           │
│  │  ┌───────────────────────┐  │  │  │  ┌───────────────────────┐  │           │
│  │  │   ConnectX-3 Pro      │  │  │  │  │   ConnectX-3 Pro      │  │           │
│  │  │   Dual-Port 40GbE     │  │  │  │  │   Dual-Port 40GbE     │  │           │
│  │  │  ┌─────────────────┐  │  │  │  │  │  ┌─────────────────┐  │  │           │
│  │  │  │ Port1    Port2  │  │  │  │  │  │  │ Port1    Port2  │  │  │           │
│  │  │  │ (ens6)  (ens6d1)│  │  │  │  │  │  │ (ens6)  (ens6d1)│  │  │           │
│  │  │  └───┬───────┬─────┘  │  │  │  │  │  └───┬───────┬─────┘  │  │           │
│  │  └──────┼───────┼────────┘  │  │  │  └──────┼───────┼────────┘  │           │
│  └─────────┼───────┼───────────┘  │  └─────────┼───────┼───────────┘           │
│            │       │              │            │       │                        │
└────────────┼───────┼──────────────┴────────────┼───────┼────────────────────────┘
             │       │                           │       │
             │       │    RDMA FABRIC (40GbE)    │       │
             │       │    Back-to-Back Direct    │       │
             │       │                           │       │
             │       └───────────────────────────┘       │
             │         Link 2: 10.0.0.0/24               │
             │         (Port2 ↔ Port2)                   │
             │         4554 MB/s | 0.85 µs               │
             │                                           │
             └───────────────────────────────────────────┘
               Link 1: 10.0.1.0/24
               (Port1 ↔ Port1)
               4554 MB/s | 0.85 µs
```

### RDMA Fabric Summary

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           RDMA FABRIC DETAILS                                   │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│   Link 1 (ens6):     gpuserver1 ◄══════════════════► gpuserver2                │
│                      10.0.1.1        40 Gbps          10.0.1.2                  │
│                                                                                 │
│   Link 2 (ens6d1):   gpuserver1 ◄══════════════════► gpuserver2                │
│                      10.0.0.1        40 Gbps          10.0.0.2                  │
│                                                                                 │
│                      ═══════════════════════════════════                        │
│                      Total Bandwidth: 80 Gbps (9.1 GB/s)                        │
│                      RDMA Latency: 0.85 µs (sub-microsecond!)                   │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### IP Address Summary

| Server | Management | IPMI | RDMA Link 1 (ens6) | RDMA Link 2 (ens6d1) |
|--------|------------|------|--------------------|-----------------------|
| gpuserver1 | 192.168.1.73 | 192.168.1.72 | 10.0.1.1 | 10.0.0.1 |
| gpuserver2 | 192.168.1.71 | 192.168.1.70 | 10.0.1.2 | 10.0.0.2 |

### Network Segments

| Network | Purpose | Speed | Subnet |
|---------|---------|-------|--------|
| Management | SSH, IPMI, general traffic | 1GbE | 192.168.1.0/24 |
| RDMA Link 1 | GPU-to-GPU (NCCL) | 40GbE | 10.0.1.0/24 |
| RDMA Link 2 | GPU-to-GPU (NCCL) | 40GbE | 10.0.0.0/24 |
| Storage | NVMe-oF targets (future) | TBD | TBD |

### Performance Metrics

| Metric | Result |
|--------|--------|
| RDMA Bandwidth (per link) | 4554 MB/s (36.4 Gbps) |
| RDMA Latency | 0.85 µs |
| Total RDMA Bandwidth | 80 Gbps (2 links) |
| TCP Bandwidth | 27.4 Gbps |
| TCP Latency | 21.9 µs |

---

## IPMI/BMC Setup

The ASUS ASMB8 BMC provides out-of-band management capabilities.

### IPMI Access Methods

#### 1. ipmitool (Recommended)

```bash
# Install ipmitool
sudo apt install -y ipmitool

# Check power status
ipmitool -I lanplus -H <IPMI_IP> -U admin -P admin chassis status

# Power on
ipmitool -I lanplus -H <IPMI_IP> -U admin -P admin chassis power on

# Power off (graceful)
ipmitool -I lanplus -H <IPMI_IP> -U admin -P admin chassis power soft

# Reboot
ipmitool -I lanplus -H <IPMI_IP> -U admin -P admin chassis power reset

# Read sensors
ipmitool -I lanplus -H <IPMI_IP> -U admin -P admin sdr type temperature
```

#### 2. SSH (SMASH CLP)

```bash
# Connect (requires legacy algorithms)
ssh -o HostKeyAlgorithms=+ssh-rsa \
    -o KexAlgorithms=+diffie-hellman-group14-sha1 \
    admin@<IPMI_IP>

# Available commands
show /admin1/system1           # System info
start /admin1/system1          # Power on
stop /admin1/system1           # Power off
reset /admin1/system1          # Reboot
show /admin1/system1/sensors1  # Sensor readings
```

#### 3. Web Interface

- URL: `https://<IPMI_IP>`
- Provides Java-based KVM (requires onboard VGA, not compatible with add-on GPUs)

### Default Credentials

| Interface | Username | Password |
|-----------|----------|----------|
| IPMI | admin | admin |

> ⚠️ **Security Note:** Change default passwords in production environments!

---

## Ubuntu Installation

### Recommended Version

- **Ubuntu 22.04.5 LTS Server** (Jammy Jellyfish)
- Kernel: 5.15.x (good V100 support)
- Image: `ubuntu-22.04.5-live-server-amd64.iso`

### Installation Notes

1. Boot from USB/ISO via IPMI virtual media or physical USB
2. Select minimal server installation
3. Configure network during installation (DHCP recommended initially)
4. Create user account (e.g., `eniz`)
5. Enable OpenSSH server during installation

### Post-Installation

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install essential tools
sudo apt install -y \
    build-essential \
    net-tools \
    htop \
    nvtop \
    ipmitool \
    rdma-core \
    ibverbs-utils \
    perftest
```

---

## Network Configuration

Ubuntu 22.04 uses **Netplan** for network configuration.

### Create Netplan Configuration

```bash
sudo nano /etc/netplan/01-network.yaml
```

**gpuserver1:**
```yaml
network:
  version: 2
  ethernets:
    # Management interface (1GbE)
    enp5s0:
      dhcp4: true

    # Secondary 1GbE (optional)
    enp6s0:
      dhcp4: true
      optional: true

    # ConnectX-3 Pro 40GbE Port 1 (unused)
    ens6:
      dhcp4: false
      optional: true

    # ConnectX-3 Pro 40GbE Port 2 (RDMA)
    ens6d1:
      dhcp4: false
      addresses:
        - 10.0.0.1/24
      mtu: 9000
      optional: true
```

**gpuserver2:** Same but with `10.0.0.2/24` for ens6d1.

### Apply Configuration

```bash
# Disable cloud-init network management
echo "network: {config: disabled}" | sudo tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg

# Remove cloud-init generated config
sudo rm -f /etc/netplan/50-cloud-init.yaml

# Apply new configuration
sudo netplan apply
```

---

## Serial Console (SOL) Setup

Serial Over LAN provides console access via IPMI, essential for:
- Headless server management
- BIOS/UEFI access
- Boot troubleshooting
- Emergency recovery

### Why SOL Instead of Java KVM?

The ASMB8's Java KVM requires **onboard VGA output**. With V100 GPUs installed, the GPU takes over display output, making Java KVM show a blank screen. SOL uses the serial port instead.

### Enable Serial Console in Ubuntu

#### 1. Enable Serial Getty Service

```bash
sudo systemctl enable serial-getty@ttyS1.service
sudo systemctl start serial-getty@ttyS1.service
```

#### 2. Configure GRUB for Serial Output

Edit `/etc/default/grub`:

```bash
sudo nano /etc/default/grub
```

Add/modify these lines:

```bash
GRUB_CMDLINE_LINUX="console=tty0 console=ttyS1,9600n8"
GRUB_TERMINAL="console serial"
GRUB_SERIAL_COMMAND="serial --speed=9600 --unit=1 --word=8 --parity=no --stop=1"
```

Update GRUB:

```bash
sudo update-grub
```

#### 3. Configure IPMI SOL Baud Rate

```bash
# Set baud rate to 9600 to match GRUB
ipmitool -I lanplus -H <IPMI_IP> -U admin -P admin sol set volatile-bit-rate 9.6 1
ipmitool -I lanplus -H <IPMI_IP> -U admin -P admin sol set non-volatile-bit-rate 9.6 1
```

### Connecting via SOL

```bash
# Connect
ipmitool -I lanplus -H <IPMI_IP> -U admin -P admin sol activate

# Disconnect: Type ~. (tilde, then period)

# If "already active" error:
ipmitool -I lanplus -H <IPMI_IP> -U admin -P admin sol deactivate
```

---

## NVIDIA Driver Installation

### Install NVIDIA Drivers

```bash
# Add NVIDIA repository
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
sudo dpkg -i cuda-keyring_1.1-1_all.deb
sudo apt update

# Install driver (installs latest compatible version)
sudo apt install -y nvidia-driver-535

# Reboot required
sudo reboot
```

### Verify Installation

```bash
nvidia-smi
```

**Expected Output:**
```
+-----------------------------------------------------------------------------------------+
| NVIDIA-SMI 580.126.09             Driver Version: 580.126.09     CUDA Version: 13.0    |
|-----------------------------------------+------------------------+----------------------+
| GPU  Name                 Persistence-M | Bus-Id          Disp.A | Volatile Uncorr. ECC |
| Fan  Temp   Perf          Pwr:Usage/Cap |           Memory-Usage | GPU-Util  Compute M. |
|=========================================+========================+======================|
|   0  Tesla V100-PCIE-16GB           Off | 00000000:02:00.0   Off |                    0 |
| N/A   30C    P0              25W / 250W |       0MiB / 16384MiB  |      0%      Default |
+-----------------------------------------+------------------------+----------------------+
|   1  Tesla V100-PCIE-16GB           Off | 00000000:03:00.0   Off |                    0 |
| N/A   30C    P0              25W / 250W |       0MiB / 16384MiB  |      0%      Default |
+-----------------------------------------+------------------------+----------------------+
```

### Install CUDA Toolkit

```bash
# Install CUDA 12.6 toolkit (includes nvcc compiler)
sudo apt install cuda-toolkit-12-6 -y

# Add to PATH
echo 'export PATH=/usr/local/cuda-12.6/bin:$PATH' >> ~/.bashrc
echo 'export LD_LIBRARY_PATH=/usr/local/cuda-12.6/lib64:$LD_LIBRARY_PATH' >> ~/.bashrc
source ~/.bashrc

# Verify
nvcc --version
```

---

## NCCL Setup for Distributed Training

NCCL (NVIDIA Collective Communications Library) enables efficient multi-GPU and multi-node communication for distributed AI training.

### Install NCCL

```bash
# Install NCCL matching CUDA version
sudo apt install libnccl2=2.21.5-1+cuda12.4 libnccl-dev=2.21.5-1+cuda12.4 -y
```

### Install OpenMPI (for multi-node)

```bash
sudo apt install openmpi-bin libopenmpi-dev -y
```

### Build NCCL-Tests

```bash
# Clone nccl-tests
git clone https://github.com/NVIDIA/nccl-tests.git
cd nccl-tests

# Build with MPI support
make MPI=1 CUDA_HOME=/usr/local/cuda-12.6 NCCL_HOME=/usr MPI_HOME=/usr/lib/x86_64-linux-gnu/openmpi
```

### Set Up Passwordless SSH (Required for MPI)

```bash
# Generate key without passphrase
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa_mpi -N ""

# Copy to other server
ssh-copy-id -i ~/.ssh/id_rsa_mpi eniz@<other_server_ip>

# Create SSH config (~/.ssh/config)
cat >> ~/.ssh/config << 'EOF'
Host 192.168.1.71
    IdentityFile ~/.ssh/id_rsa_mpi
    StrictHostKeyChecking no

Host 192.168.1.73
    IdentityFile ~/.ssh/id_rsa_mpi
    StrictHostKeyChecking no
EOF
chmod 600 ~/.ssh/config
```

### NCCL Performance Results (January 2026)

#### Intra-Node Test (2 GPUs, same server)

```bash
cd ~/nccl-tests/build
./all_reduce_perf -b 8 -e 128M -f 2 -g 2
```

| Data Size | Bus Bandwidth | Notes |
|-----------|---------------|-------|
| 8 B - 4 KB | 0.0 - 0.4 GB/s | Latency dominated |
| 8 KB - 128 KB | 0.7 - 2.9 GB/s | Transitioning |
| 1 MB - 128 MB | 6.3 - 7.1 GB/s | **Peak PCIe bandwidth** |

**Peak Performance:** 7.09 GB/s at 128MB (GPU-to-GPU via PCIe)

#### Multi-Node Test (4 GPUs across 2 servers)

```bash
# Run from either server
mpirun -np 4 --host 192.168.1.73:2,192.168.1.71:2 \
  -x NCCL_DEBUG=INFO \
  -x NCCL_IB_DISABLE=0 \
  -x LD_LIBRARY_PATH \
  ./all_reduce_perf -b 8 -e 128M -f 2 -g 1
```

| Data Size | Bus Bandwidth | Notes |
|-----------|---------------|-------|
| 8 B - 4 KB | 0.0 - 0.1 GB/s | Latency dominated |
| 32 KB - 512 KB | 0.5 - 1.1 GB/s | RDMA warming up |
| 1 MB - 128 MB | 1.4 - 2.0 GB/s | **Cross-server RDMA** |

**Peak Performance:** ~2.0 GB/s busbw at 128MB (via RDMA)

### NCCL Communication Paths

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                    NCCL DATA PATHS                                              │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│   INTRA-NODE (same server):                                                    │
│   GPU0 ◄──── PCIe/SHM ────► GPU1                                              │
│   Bandwidth: ~7 GB/s                                                           │
│   Path: via SHM/direct/direct                                                  │
│                                                                                 │
│   INTER-NODE (across servers):                                                 │
│   GPU0(srv1) ◄──── RDMA (RoCE) ────► GPU0(srv2)                               │
│   Bandwidth: ~2 GB/s                                                           │
│   Path: via NET/IB/0                                                           │
│                                                                                 │
│   Note: ConnectX-3 doesn't support GPUDirect RDMA                             │
│   Data path: GPU → CPU Memory → RDMA → CPU Memory → GPU                       │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### NCCL Environment Variables

```bash
# Enable RDMA
export NCCL_IB_DISABLE=0
export NCCL_NET=IB

# Specify RDMA device (optional)
export NCCL_IB_HCA=mlx4_0:1,mlx4_0:2

# RoCE GID index
export NCCL_IB_GID_INDEX=2

# Debug output
export NCCL_DEBUG=INFO
```

---

## RDMA/RoCEv2 Configuration

The Mellanox ConnectX-3 Pro supports RDMA over Converged Ethernet (RoCE), enabling low-latency GPU-to-GPU communication for distributed training with NCCL.

### Verified Performance (January 2026)

| Metric | Result |
|--------|--------|
| **Bandwidth** | 4555 MB/sec (36.4 Gbps) |
| **Latency** | 0.88 µs (880 nanoseconds) |
| **Link Speed** | 40 Gbps |
| **MTU** | 9000 (Jumbo Frames) |

> 💡 Sub-microsecond latency is critical for distributed training where GPUs need to synchronize gradients thousands of times per second.

### Installation

The inbox mlx4 driver in Ubuntu 22.04 works perfectly - no need for Mellanox OFED.

```bash
# Install RDMA packages
sudo apt install -y rdma-core ibverbs-utils perftest

# Verify RDMA devices
ibv_devices
# Expected output:
#     device          node GUID
#     ------          ----------------
#     mlx4_0          248a07030052aab0

# Check detailed device info
ibv_devinfo
```

### Network Configuration

RDMA runs on a separate subnet (10.0.0.0/24) from management traffic.

**gpuserver1:**
```bash
sudo ip addr add 10.0.0.1/24 dev ens6d1
sudo ip link set ens6d1 mtu 9000
sudo ip link set ens6d1 up
```

**gpuserver2:**
```bash
sudo ip addr add 10.0.0.2/24 dev ens6d1
sudo ip link set ens6d1 mtu 9000
sudo ip link set ens6d1 up
```

To make permanent, add to `/etc/netplan/01-network.yaml` (see Network Configuration section above).

### Understanding RoCE and GID Index

ConnectX-3 supports both RoCEv1 (uses Ethernet + GRH) and RoCEv2 (uses UDP/IP). For RoCEv2:

```bash
# Check current mode
cat /sys/class/infiniband/mlx4_0/ports/2/gid_attrs/types/2

# Enable RoCEv2 for IPv4
echo eth | sudo tee /sys/class/infiniband/mlx4_0/ports/2/gid_attrs/types/0
```

**GID Index** is how RoCE identifies endpoints over Ethernet. Unlike InfiniBand which uses LIDs, RoCE uses GIDs derived from IP addresses:

```bash
# List all GIDs on port 2
for i in $(seq 0 15); do
  gid=$(cat /sys/class/infiniband/mlx4_0/ports/2/gids/$i 2>/dev/null)
  if [ "$gid" != "0000:0000:0000:0000:0000:0000:0000:0000" ]; then
    echo "GID $i: $gid"
  fi
done
```

For this cluster, **GID index 2** corresponds to the RoCEv2 IPv4 configuration.

### RDMA Testing

**Critical Parameters for ConnectX-3 Pro:**
- `--ib-dev=mlx4_0` - The RDMA device name
- `--ib-port=2` - Port 2 (where the cable is connected)
- `--gid-index=2` - Required for RoCE over Ethernet

#### Bandwidth Test (ib_write_bw)

```bash
# On gpuserver2 (server - run first):
ib_write_bw --ib-dev=mlx4_0 --ib-port=2 --gid-index=2

# On gpuserver1 (client):
ib_write_bw --ib-dev=mlx4_0 --ib-port=2 --gid-index=2 10.0.0.2
```

**Expected Output:**
```
---------------------------------------------------------------------------------------
 #bytes     #iterations    BW peak[MB/sec]    BW average[MB/sec]   MsgRate[Mpps]
 65536      5000           4555.12            4554.89              0.072878
---------------------------------------------------------------------------------------
```

#### Latency Test (ib_write_lat)

```bash
# On gpuserver2 (server):
ib_write_lat --ib-dev=mlx4_0 --ib-port=2 --gid-index=2

# On gpuserver1 (client):
ib_write_lat --ib-dev=mlx4_0 --ib-port=2 --gid-index=2 10.0.0.2
```

**Expected Output:**
```
---------------------------------------------------------------------------------------
 #bytes        #iterations       t_avg[usec]    t_stdev[usec]
 2             1000              0.88           0.05
---------------------------------------------------------------------------------------
```

#### Simple RDMA Ping (rping)

Quick connectivity test:

```bash
# On gpuserver2 (server - must start first!):
rping -s -a 10.0.0.2 -v

# On gpuserver1 (client):
rping -c -a 10.0.0.2 -v
```

### Troubleshooting RDMA

| Issue | Cause | Solution |
|-------|-------|----------|
| "Port number X state is Down" | Wrong port or no cable | Check cable, use correct `--ib-port` |
| "Unable to find GID" | Missing GID index for RoCE | Add `--gid-index=2` |
| Low bandwidth (~1139 MB/sec = 10G) | Bad cable or 10G negotiation | Replace QSFP+ cable/DAC |
| rping "RDMA_CM_EVENT_REJECTED, error 8" | Server not running | Start server (`-s`) before client |
| "No RDMA devices found" | Driver not loaded | `modprobe mlx4_ib` |

### Cable Notes

We tested with a **Wiitek 2M QSFP+ DAC** cable. Initially saw 10G speeds due to a bad cable - swapping to a known-good cable achieved full 40G.

---

## Network Upgrade Plan

### Current Limitations

The ConnectX-3 Pro doesn't support **GPUDirect RDMA**, meaning data must be staged through CPU memory:

```
Current Path:  GPU → CPU Memory → RDMA NIC → Network → RDMA NIC → CPU Memory → GPU
Ideal Path:    GPU → RDMA NIC → Network → RDMA NIC → GPU (with GPUDirect)
```

This reduces effective NCCL bandwidth from ~4.5 GB/s (raw RDMA) to ~2 GB/s.

### Recommended Upgrade: ConnectX-4 EN

| Current | Upgrade |
|---------|---------|
| ConnectX-3 Pro (MCX354A) | ConnectX-4 EN (MCX416A-CCAT) |
| No GPUDirect RDMA | ✅ GPUDirect RDMA |
| mlx4 driver | mlx5 driver (better NCCL support) |
| QSFP+ 40GbE | QSFP28 (backward compatible with 40G) |
| ~2 GB/s NCCL | ~4 GB/s NCCL (estimated) |

**eBay Search:** `MCX416A-CCAT` or `MCX516A-CCAT` (~$50-100 each)

### Future Architecture (Separate GPU + Storage Networks)

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                    RECOMMENDED: SEPARATE NETWORKS                               │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│   gpuserver1                              gpuserver2                           │
│   ┌────────────────────────┐             ┌────────────────────────┐            │
│   │  V100      V100        │             │  V100      V100        │            │
│   │    │        │          │             │    │        │          │            │
│   │  ┌─┴────────┴─┐        │             │  ┌─┴────────┴─┐        │            │
│   │  │ ConnectX-4 │ (NEW)  │             │  │ ConnectX-4 │ (NEW)  │            │
│   │  │ GPU Traffic│        │             │  │ GPU Traffic│        │            │
│   │  │ GPUDirect ✅│        │             │  │ GPUDirect ✅│        │            │
│   │  └─────┬──────┘        │             │  └─────┬──────┘        │            │
│   │        │               │             │        │               │            │
│   │  ┌─────┴──────┐        │             │  ┌─────┴──────┐        │            │
│   │  │ ConnectX-3 │ (OLD)  │             │  │ ConnectX-3 │ (OLD)  │            │
│   │  │ Storage    │        │             │  │ Storage    │        │            │
│   │  └─────┬──────┘        │             │  └─────┬──────┘        │            │
│   └────────┼───────────────┘             └────────┼───────────────┘            │
│            │                                      │                            │
│   ═════════╪══════════════════════════════════════╪═════════════════           │
│            │         GPU NETWORK (40GbE)          │                            │
│            │         Cisco 9332 Switch            │                            │
│            │         NCCL Traffic Only            │                            │
│   ═════════╪══════════════════════════════════════╪═════════════════           │
│            │                                      │                            │
│   ─────────┼──────────────────────────────────────┼─────────────────           │
│            │      STORAGE NETWORK (40GbE)         │                            │
│            │      Separate Switch/VLAN            │                            │
│            │      NVMe-oF / NFS Traffic           │                            │
│            └──────────────┬───────────────────────┘                            │
│                           │                                                    │
│                   ┌───────┴───────┐                                           │
│                   │ Storage Server │                                          │
│                   │ (NAS/SAN)      │                                          │
│                   └────────────────┘                                          │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### Why Separate Networks?

| Traffic Type | Pattern | Requirement |
|--------------|---------|-------------|
| **GPU/NCCL** | Bursty, synchronized | Low latency critical |
| **Storage** | Continuous streaming | High throughput critical |

Mixing them causes GPU sync delays when storage I/O competes for bandwidth.

### Network Speed Requirements by Model Size

| Model | Gradient Size | Min Network Needed | Your 40G + GPUDirect |
|-------|--------------|--------------------|-----------------------|
| ResNet-50 | 100 MB | ~1 GB/s | ✅ More than enough |
| BERT-Base | 440 MB | ~3 GB/s | ✅ Good |
| BERT-Large | 1.4 GB | ~4.5 GB/s | ⚠️ Borderline |
| GPT-2 | 6 GB | ~7.5 GB/s | ❌ Need 100G |

> 💡 For V100 16GB GPUs, 40GbE with GPUDirect covers most realistic training scenarios.

### Upgrade Shopping List

```
MINIMAL UPGRADE (GPUDirect only):
├── 2× ConnectX-4 EN (MCX416A-CCAT)     ~$100-160 total
└── Keep existing switch + cables

FULL UPGRADE (Separate GPU + Storage):
├── 2× ConnectX-4 EN (for GPU)          ~$100-160 total
├── Keep 2× ConnectX-3 (for storage)    $0 (reuse!)
├── 1× Small 40G switch (storage)       ~$50-100 used
└── Cisco 9332 for GPU network          (already owned)

Total: ~$150-260 for significant improvement
```

---

## Troubleshooting

### SOL Shows Blank Screen

| Cause | Solution |
|-------|----------|
| Serial getty not running | `sudo systemctl start serial-getty@ttyS1` |
| Wrong serial port | Try `ttyS0` instead of `ttyS1` |
| Baud rate mismatch | Ensure IPMI and GRUB both use 9600 |
| Service not enabled | `sudo systemctl enable serial-getty@ttyS1` |

### SOL "Already Active on Another Session"

```bash
ipmitool -I lanplus -H <IPMI_IP> -U admin -P admin sol deactivate
```

### SSH Permission Denied to IPMI

The IPMI SSH interface uses **SMASH CLP**, not a Linux shell:
- Username: `admin` (not your Linux user)
- It's a command-line management interface, not bash

### Java KVM Shows Blank/Recording Tool

- This happens when add-on GPUs (like V100) override onboard VGA
- **Solution:** Use SOL instead of Java KVM
- Java KVM only works with onboard graphics

### Network Interface Not Coming Up

```bash
# Check if interface exists
ip link show

# Check for carrier (cable connected)
cat /sys/class/net/<interface>/carrier

# Manually bring up
sudo ip link set <interface> up
sudo dhclient <interface>
```

### RDMA Troubleshooting

See the [RDMA/RoCEv2 Configuration](#rdmarocev2-configuration) section for RDMA-specific troubleshooting.

---

## References

- [ASUS ASMB8-iKVM Manual](https://dlcdnets.asus.com/pub/ASUS/server/accessory/ASMB8/E10970_ASMB8-iKVM_UM_V2_WEB.pdf)
- [Ubuntu 22.04 Server Guide](https://ubuntu.com/server/docs)
- [NVIDIA CUDA Installation Guide](https://docs.nvidia.com/cuda/)
- [Mellanox OFED Documentation](https://docs.nvidia.com/networking/)
- [NCCL Documentation](https://docs.nvidia.com/deeplearning/nccl/)

---

## License

This guide is released under [MIT License](LICENSE).

---

## Contributing

Found an error or want to add content? Pull requests welcome!

---

*Built with the assistance of Claude Code*
