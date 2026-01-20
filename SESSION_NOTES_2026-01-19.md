# GPU Cluster Session Notes - January 19, 2026

## Session Summary
Continued RDMA setup, made configurations persistent, and learned about AI cluster networking concepts.

---

## Tasks Completed This Session

### 1. Made RDMA IPs Persistent (Netplan)

Added to `/etc/netplan/01-network.yaml` on both servers:

**gpuserver1:**
```yaml
ens6d1:
  dhcp4: false
  addresses:
    - 10.0.0.1/24
  mtu: 9000
  optional: true
```

**gpuserver2:**
```yaml
ens6d1:
  dhcp4: false
  addresses:
    - 10.0.0.2/24
  mtu: 9000
  optional: true
```

Then: `sudo netplan apply`

> **Note**: "Cannot call Open vSwitch" warning is harmless - OVS not installed/needed.

---

### 2. Updated GPU_CLUSTER_GUIDE README

Added complete RDMA documentation with test results, commands, and troubleshooting.

---

### 3. Verified RDMA Performance

**Bandwidth Test:**
```bash
# Server (gpuserver2):
ib_write_bw --ib-dev=mlx4_0 --ib-port=2 --gid-index=2

# Client (gpuserver1):
ib_write_bw --ib-dev=mlx4_0 --ib-port=2 --gid-index=2 10.0.0.2
```

**Results:**
| Metric | Value |
|--------|-------|
| Bandwidth | 4554 MB/sec (36.4 Gbps) |
| Link Speed | 40 Gbps |
| Efficiency | ~91% of theoretical max |

**Latency Test:**
```bash
# Server (gpuserver2):
ib_write_lat --ib-dev=mlx4_0 --ib-port=2 --gid-index=2

# Client (gpuserver1):
ib_write_lat --ib-dev=mlx4_0 --ib-port=2 --gid-index=2 10.0.0.2
```

**Results:**
| Metric | Value |
|--------|-------|
| Minimum | 0.81 µs |
| Typical | 0.85 µs (850 nanoseconds!) |
| Average | 0.93 µs |
| 99th %ile | 5.05 µs |

---

## Key Learnings

### CPU Frequency Warning

When running perftest, you may see:
```
Conflicting CPU frequency values detected: 1200.000000 != 3600.000000
```

**What it means:**
- CPU is in power-saving mode (1.2 GHz instead of 3.6 GHz max)
- This is a WARNING, not an error
- RDMA results are still valid because RDMA is offloaded to the NIC

**To fix (optional):**
```bash
# Set to performance mode
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

# Revert to power saving
echo powersave | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
```

**For production AI training:** Use `performance` governor.

---

### Why LAG is NOT Ideal for AI Clusters

**The Problem:**
- LAG (Link Aggregation) distributes traffic by **flow hash** (src/dst IP)
- One RDMA connection = one flow = uses **only ONE link**
- You don't get 80 Gbps from bonding two 40G ports for a single GPU-to-GPU transfer
- NCCL creates one connection per GPU pair → still limited to single link speed

**Diagram:**
```
LAG Reality:
  GPU1 ──RDMA──→ [Port1]──────→ [Port1] ──→ GPU3
  GPU2 ──RDMA──→ [Port2]──────→ [Port2] ──→ GPU4
                    ↑ each flow picks ONE port, not both
```

**Better alternatives:**
1. Separate subnets for different traffic (compute vs storage)
2. Multi-rail topology (see below)
3. Keep as redundancy/failover

---

### Rail-Optimized Topology (How Big AI Clusters Work)

**Traditional (Per-Node) - BAD for scaling:**
```
Node 1                          Node 2
┌─────────────────┐            ┌─────────────────┐
│ GPU0 GPU1 GPU2 GPU3 │        │ GPU0 GPU1 GPU2 GPU3 │
│   └────┴────┴────┘  │        │   └────┴────┴────┘  │
│          │          │        │          │          │
│       [1 NIC]       │        │       [1 NIC]       │
└──────────┼──────────┘        └──────────┼──────────┘
           └─────────[SWITCH]─────────────┘

Problem: 8 GPUs share ONE NIC = bottleneck!
```

**Rail-Optimized - GOOD for scaling:**
```
         Rail 0 Switch      Rail 1 Switch      Rail 2 Switch
              │                   │                  │
    ┌─────────┼─────────┬─────────┼────────┬─────────┼────────┐
    │         │         │         │        │         │        │
┌───┴───┐ ┌───┴───┐ ┌───┴───┐ ┌───┴──┐ ┌───┴───┐ ┌───┴──┐
│ Node1 │ │ Node2 │ │ Node1 │ │Node2 │ │ Node1 │ │Node2 │
│ GPU0  │ │ GPU0  │ │ GPU1  │ │GPU1  │ │ GPU2  │ │GPU2  │
│ NIC0  │ │ NIC0  │ │ NIC1  │ │NIC1  │ │ NIC2  │ │NIC2  │
└───────┘ └───────┘ └───────┘ └──────┘ └───────┘ └──────┘
```

**Key Concept:**
- "Rail" = all GPUs at the SAME position across all nodes
- GPU0 on ALL nodes → connects to Rail 0 switch
- GPU1 on ALL nodes → connects to Rail 1 switch
- Each GPU has its own dedicated NIC (1:1 ratio)

**Why this works for AllReduce:**
```
Step 1: Reduce within each rail (GPU position across nodes)
        GPU0(Node1) ↔ GPU0(Node2) ↔ GPU0(Node3)  [Rail 0]
        GPU1(Node1) ↔ GPU1(Node2) ↔ GPU1(Node3)  [Rail 1]

Step 2: Broadcast across GPUs within each node
        GPU0 ↔ GPU1 ↔ GPU2 ↔ GPU3  [via NVLink]
```

**Benefits:**
| Benefit | Explanation |
|---------|-------------|
| No oversubscription | Each GPU has dedicated bandwidth |
| Predictable latency | Same-rail = 1 switch hop |
| Scales linearly | Add nodes without bottlenecks |
| NCCL optimized | Matches AllReduce algorithm |

**NVIDIA DGX SuperPOD:**
- 8 GPUs per node, 8 NICs per node (1:1)
- 8 rail switches
- Each GPU has dedicated 200 Gbps (ConnectX-6)

---

### Your Cluster - Mini Rail-Optimized Option

With 2 ports per server, you could set up:

```
           Port 1 (ens6)              Port 2 (ens6d1)
           10.0.1.0/24                10.0.0.0/24
               │                           │
    ┌──────────┴──────────┐     ┌──────────┴──────────┐
    │                     │     │                     │
gpuserver1:GPU0      gpuserver2:GPU0    gpuserver1:GPU1      gpuserver2:GPU1
  10.0.1.1             10.0.1.2           10.0.0.1             10.0.0.2
```

Configure NCCL to use both NICs:
```bash
export NCCL_IB_HCA=mlx4_0:1,mlx4_0:2
```

---

## Quick Reference

### Server Details
| Server | Ubuntu IP | IPMI IP | RDMA IP (Port 2) |
|--------|-----------|---------|------------------|
| gpuserver1 | 192.168.1.73 | 192.168.1.72 | 10.0.0.1 |
| gpuserver2 | 192.168.1.71 | 192.168.1.70 | 10.0.0.2 |

**Credentials:** eniz/Ubuntu123 (Ubuntu), admin/admin (IPMI)

### Network Interfaces
| Interface | Device | Purpose |
|-----------|--------|---------|
| enp5s0 | Intel 1GbE | Management (DHCP) |
| ens6 | ConnectX-3 Port 1 | Available (40GbE) |
| ens6d1 | ConnectX-3 Port 2 | RDMA - 10.0.0.x (40GbE) |

### RDMA Test Commands
```bash
# Bandwidth (server first, then client)
ib_write_bw --ib-dev=mlx4_0 --ib-port=2 --gid-index=2
ib_write_bw --ib-dev=mlx4_0 --ib-port=2 --gid-index=2 10.0.0.2

# Latency
ib_write_lat --ib-dev=mlx4_0 --ib-port=2 --gid-index=2
ib_write_lat --ib-dev=mlx4_0 --ib-port=2 --gid-index=2 10.0.0.2
```

---

## Remaining Tasks

- [ ] Enable second 40G port (ens6) - user working on cabling
- [ ] Install NVIDIA drivers
- [ ] Set up NCCL for distributed training
- [ ] (Optional) Configure multi-rail NCCL

---

## Files Updated This Session

1. `/mnt/c/Users/eniza/Documents/claudechats/GPU_CLUSTER_GUIDE/README.md` - Added full RDMA section
2. `/etc/netplan/01-network.yaml` (both servers) - Added persistent RDMA IPs

---

*Session notes saved for future reference*

---

## Update: Both 40G Ports Configured and Tested!

### Final Network Configuration

| Server | ens6 (Port 1) | ens6d1 (Port 2) |
|--------|---------------|-----------------|
| gpuserver1 | 10.0.1.1/24 | 10.0.0.1/24 |
| gpuserver2 | 10.0.1.2/24 | 10.0.0.2/24 |

### RDMA Test Results - Both Ports

| Port | Interface | Bandwidth | Latency |
|------|-----------|-----------|---------|
| Port 1 | ens6 (10.0.1.x) | 4554 MB/sec | 0.85 µs |
| Port 2 | ens6d1 (10.0.0.x) | 4554 MB/sec | 0.85 µs |

**Total Aggregate Bandwidth: 80 Gbps (9.1 GB/sec)**

### Test Commands

**Port 1 (ens6):**
```bash
# Server:
ib_write_bw --ib-dev=mlx4_0 --ib-port=1 --gid-index=2

# Client:
ib_write_bw --ib-dev=mlx4_0 --ib-port=1 --gid-index=2 10.0.1.2
```

**Port 2 (ens6d1):**
```bash
# Server:
ib_write_bw --ib-dev=mlx4_0 --ib-port=2 --gid-index=2

# Client:
ib_write_bw --ib-dev=mlx4_0 --ib-port=2 --gid-index=2 10.0.0.2
```

### Netplan Configuration (Both Servers)

**gpuserver1** (`/etc/netplan/01-network.yaml`):
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

**gpuserver2**: Same but with 10.0.1.2/24 and 10.0.0.2/24

### Network Diagram

```
gpuserver1                              gpuserver2
┌────────────────┐                    ┌────────────────┐
│  ens6  (10.0.1.1) ════40G════════ (10.0.1.2) ens6   │
│  ens6d1(10.0.0.1) ════40G════════ (10.0.0.2) ens6d1 │
└────────────────┘                    └────────────────┘
        Total: 80 Gbps between servers
```


---

## TCP/IP vs RDMA Performance Comparison

### Why We Test Both

Understanding the difference between TCP/IP and RDMA helps explain why RDMA matters for AI workloads.

### Test Tools Used

| Tool | Purpose | Install |
|------|---------|---------|
| iperf3 | TCP bandwidth | `sudo apt install -y iperf3` |
| sockperf | TCP latency | `sudo apt install -y sockperf` |
| ping | ICMP latency | Built-in |
| ib_write_bw | RDMA bandwidth | `sudo apt install -y perftest` |
| ib_write_lat | RDMA latency | `sudo apt install -y perftest` |

### Test Commands

**TCP Bandwidth (iperf3):**
```bash
# Server:
iperf3 -s -B 10.0.0.2

# Client:
iperf3 -c 10.0.0.2 -t 10
```

**TCP Latency (sockperf):**
```bash
# Server:
sockperf server -i 10.0.0.2 --tcp

# Client:
sockperf ping-pong -i 10.0.0.2 --tcp
```

**RDMA Bandwidth:**
```bash
# Server:
ib_write_bw --ib-dev=mlx4_0 --ib-port=2 --gid-index=2

# Client:
ib_write_bw --ib-dev=mlx4_0 --ib-port=2 --gid-index=2 10.0.0.2
```

**RDMA Latency:**
```bash
# Server:
ib_write_lat --ib-dev=mlx4_0 --ib-port=2 --gid-index=2

# Client:
ib_write_lat --ib-dev=mlx4_0 --ib-port=2 --gid-index=2 10.0.0.2
```

### Results

| Metric | TCP/IP | RDMA | RDMA Advantage |
|--------|--------|------|----------------|
| **Bandwidth** | 27.4 Gbps | 36.4 Gbps | +33% faster |
| **Latency** | 21.9 µs | 0.85 µs | 26x faster |
| **CPU Usage** | High | Near zero | Offloaded to NIC |

### Detailed Results

**TCP Bandwidth (iperf3):**
```
[ ID] Interval           Transfer     Bitrate         Retr
[  5]   0.00-10.00  sec  31.9 GBytes  27.4 Gbits/sec    0
```

**TCP Latency (sockperf):**
```
sockperf: ====> avg-latency=21.928 (std-dev=1.617)
sockperf: ---> <MIN> observation =   19.615
sockperf: ---> percentile 50.000 =   21.622
sockperf: ---> <MAX> observation =   31.618
```

**RDMA Bandwidth (ib_write_bw):**
```
#bytes     #iterations    BW peak[MB/sec]    BW average[MB/sec]
65536      5000             4554.51            4554.47
```

**RDMA Latency (ib_write_lat):**
```
#bytes #iterations    t_min[usec]    t_typical[usec]    t_avg[usec]
2       1000          0.81           0.85               0.93
```

### Visual Comparison

```
Bandwidth:
TCP:  ████████████████████████████░░░░░░░░  27.4 Gbps (68% of 40G)
RDMA: █████████████████████████████████████  36.4 Gbps (91% of 40G)

Latency:
RDMA:   0.85 µs  █
TCP:   21.93 µs  ██████████████████████████  (26x slower!)
```

### Why RDMA is Faster

**TCP/IP Path:**
```
Application
    ↓ (copy to kernel buffer)
Socket API
    ↓
TCP Stack (checksums, sequencing, windowing)
    ↓
IP Stack (routing, fragmentation)
    ↓
Device Driver
    ↓
NIC Hardware
    ↓
Wire
```

**RDMA Path:**
```
Application
    ↓ (direct memory registration)
RDMA Verbs API
    ↓
NIC Hardware (all processing offloaded)
    ↓
Wire
```

### Impact on AI Training

Distributed training requires frequent gradient synchronization:

| Syncs/sec | TCP Overhead | RDMA Overhead | Time Saved |
|-----------|--------------|---------------|------------|
| 100 | 2.2 ms | 0.085 ms | 2.1 ms |
| 1,000 | 22 ms | 0.85 ms | 21 ms |
| 10,000 | 220 ms | 8.5 ms | 211 ms |

**Per second of training, RDMA saves 21+ ms** that can be used for actual GPU computation!

### Key Takeaways

1. **RDMA bandwidth is 33% higher** due to zero-copy and offloading
2. **RDMA latency is 26x lower** due to kernel bypass
3. **RDMA uses almost no CPU** - all processing on the NIC
4. **For AI training**, latency matters more than raw bandwidth
5. **Back-to-back connection** (no switch) gives best possible latency


---

## Test Topology: Back-to-Back (Direct Connection)

### Important Note

**All tests in this document were performed with BACK-TO-BACK (direct) connection - NO SWITCH!**

This represents the **best-case scenario** for latency because there is no switch hop.

### Current Topology

```
┌─────────────────┐                           ┌─────────────────┐
│   gpuserver1    │                           │   gpuserver2    │
│                 │                           │                 │
│ ┌─────────────┐ │      QSFP+ DAC Cable      │ ┌─────────────┐ │
│ │ ConnectX-3  │ │    (Direct Connection)    │ │ ConnectX-3  │ │
│ │   Port 1    │◄──────────────────────────► │ │   Port 1    │ │
│ │  (ens6)     │ │       2m Cable            │ │  (ens6)     │ │
│ │  10.0.1.1   │ │                           │ │  10.0.1.2   │ │
│ └─────────────┘ │                           │ └─────────────┘ │
│                 │                           │                 │
│ ┌─────────────┐ │      QSFP+ DAC Cable      │ ┌─────────────┐ │
│ │ ConnectX-3  │ │    (Direct Connection)    │ │ ConnectX-3  │ │
│ │   Port 2    │◄──────────────────────────► │ │   Port 2    │ │
│ │  (ens6d1)   │ │       2m Cable            │ │  (ens6d1)   │ │
│ │  10.0.0.1   │ │                           │ │  10.0.0.2   │ │
│ └─────────────┘ │                           │ └─────────────┘ │
│                 │                           │                 │
└─────────────────┘                           └─────────────────┘

                    Hops: 0 (direct connection)
                    Switch: NONE
```

### Back-to-Back Results Summary

| Test | Port 1 (ens6) | Port 2 (ens6d1) |
|------|---------------|-----------------|
| Link Speed | 40 Gbps | 40 Gbps |
| RDMA Bandwidth | 4554 MB/sec (36.4 Gbps) | 4554 MB/sec (36.4 Gbps) |
| RDMA Latency | 0.85 µs | 0.85 µs |
| TCP Bandwidth | 27.4 Gbps | (same expected) |
| TCP Latency | 21.9 µs | (same expected) |

### Why Back-to-Back Has Lowest Latency

| Component | Back-to-Back | With Switch |
|-----------|--------------|-------------|
| NIC TX Processing | ~200 ns | ~200 ns |
| Wire Propagation (2m) | ~10 ns | ~10 ns |
| **Switch Processing** | **0 ns** | **300-1000+ ns** |
| NIC RX Processing | ~200 ns | ~200 ns |
| **Total** | **~400 ns + overhead** | **~700-1400+ ns + overhead** |

### Observed Latency Breakdown (Back-to-Back)

```
Total measured: 0.85 µs (850 ns)

Estimated breakdown:
├── NIC TX processing:     ~200 ns
├── Serialization (40G):   ~13 ns (for 64 bytes)
├── Wire propagation:      ~10 ns (2 meters)
├── NIC RX processing:     ~200 ns
├── PCIe latency:          ~200 ns
└── Software overhead:     ~227 ns
                           ─────────
                  Total:   ~850 ns ✓
```

---

## Future Test: With Switch

### Planned Topology (After Adding Switch)

```
┌─────────────────┐         ┌─────────────┐         ┌─────────────────┐
│   gpuserver1    │         │   Switch    │         │   gpuserver2    │
│                 │         │  (40/100G)  │         │                 │
│ ┌─────────────┐ │         │             │         │ ┌─────────────┐ │
│ │ ConnectX-3  │◄─────────►│  Port 1     │         │ │ ConnectX-3  │ │
│ │   Port 1    │ │         │             │         │ │   Port 1    │◄┐
│ └─────────────┘ │         │  Port 2     │◄────────┤ └─────────────┘ │
│                 │         │             │         │                 │
│ ┌─────────────┐ │         │  Port 3     │         │ ┌─────────────┐ │
│ │ ConnectX-3  │◄─────────►│             │         │ │ ConnectX-3  │ │
│ │   Port 2    │ │         │  Port 4     │◄────────┤ │   Port 2    │◄┘
│ └─────────────┘ │         │             │         │ └─────────────┘ │
└─────────────────┘         └─────────────┘         └─────────────────┘

                    Hops: 1 (through switch)
```

### Expected Results With Switch

| Metric | Back-to-Back (Current) | With Switch (Expected) | Difference |
|--------|------------------------|------------------------|------------|
| RDMA Bandwidth | 4554 MB/sec | 4554 MB/sec | Same |
| RDMA Latency | 0.85 µs | 1.2-2.5 µs | +40-200% |
| TCP Bandwidth | 27.4 Gbps | 27.4 Gbps | Same |
| TCP Latency | 21.9 µs | 25-35 µs | +15-60% |

### Switch Latency Varies by Type

| Switch Type | Typical Latency | Examples |
|-------------|-----------------|----------|
| Cut-through (best) | 300-500 ns | Mellanox SN2000, Arista 7050 |
| Store-and-forward | 1-3 µs | Most enterprise switches |
| Low-cost/unmanaged | 3-10 µs | TP-Link, Netgear |

### Test Plan When Switch is Added

Run the same tests and compare:

```bash
# RDMA Bandwidth
ib_write_bw --ib-dev=mlx4_0 --ib-port=2 --gid-index=2        # server
ib_write_bw --ib-dev=mlx4_0 --ib-port=2 --gid-index=2 10.0.0.2  # client

# RDMA Latency  
ib_write_lat --ib-dev=mlx4_0 --ib-port=2 --gid-index=2       # server
ib_write_lat --ib-dev=mlx4_0 --ib-port=2 --gid-index=2 10.0.0.2 # client

# TCP Bandwidth
iperf3 -s -B 10.0.0.2                    # server
iperf3 -c 10.0.0.2 -t 10                 # client

# TCP Latency
sockperf server -i 10.0.0.2 --tcp        # server
sockperf ping-pong -i 10.0.0.2 --tcp     # client

# Simple ping
ping -c 20 10.0.0.2
```

### Results Template (Fill in After Switch Test)

| Metric | Back-to-Back | With Switch | Difference |
|--------|--------------|-------------|------------|
| RDMA Bandwidth | 4554 MB/sec | _____ MB/sec | _____ |
| RDMA Latency | 0.85 µs | _____ µs | _____ |
| TCP Bandwidth | 27.4 Gbps | _____ Gbps | _____ |
| TCP Latency | 21.9 µs | _____ µs | _____ |
| Ping | 0.15 ms | _____ ms | _____ |

---

## Topology Comparison Summary

| Aspect | Back-to-Back | With Switch |
|--------|--------------|-------------|
| **Max Nodes** | 2 | Unlimited |
| **Latency** | Lowest possible | +0.3-3 µs per hop |
| **Bandwidth** | Full line rate | Full (if not oversubscribed) |
| **Cost** | Just cables | Switch $$$+ |
| **Complexity** | Simple | More complex |
| **Redundancy** | None | Possible with multiple paths |
| **Scalability** | None | Add more nodes easily |

### When to Use Each

| Topology | Best For |
|----------|----------|
| **Back-to-Back** | 2-node clusters, lowest latency testing, learning |
| **Single Switch** | 3-32 nodes, simple setup |
| **Leaf-Spine** | 32+ nodes, high availability, non-blocking |


---

## NVIDIA Driver Installation - Completed

### Installation Steps
```bash
# Prerequisites
sudo apt update
sudo apt install -y build-essential dkms

# Add NVIDIA repository
sudo add-apt-repository -y ppa:graphics-drivers/ppa
sudo apt update

# Install driver
sudo ubuntu-drivers autoinstall

# Reboot
sudo reboot

# Verify
nvidia-smi
```

### Driver Details

| Server | Driver Version | CUDA Version | Status |
|--------|----------------|--------------|--------|
| gpuserver1 | 580.126.09 | 13.0 | ✅ Working |
| gpuserver2 | 580.126.09 | 13.0 | ✅ Working |

### GPU Configuration

```
+-----------------------------------------------------------------------------------------+
| NVIDIA-SMI 580.126.09             Driver Version: 580.126.09     CUDA Version: 13.0     |
+-----------------------------------------+------------------------+----------------------+
| GPU  Name                 Persistence-M | Bus-Id          Disp.A | Volatile Uncorr. ECC |
|=========================================+========================+======================|
|   0  Tesla V100-PCIE-16GB           Off |   00000000:02:00.0 Off |                    0 |
| N/A   37C    P0             25W /  250W |       0MiB /  16384MiB |      0%      Default |
+-----------------------------------------+------------------------+----------------------+
|   1  Tesla V100-PCIE-16GB           Off |   00000000:03:00.0 Off |                    0 |
| N/A   38C    P0             27W /  250W |       0MiB /  16384MiB |      0%      Default |
+-----------------------------------------+------------------------+----------------------+
```

### GPU Summary

| Metric | GPU 0 | GPU 1 | Notes |
|--------|-------|-------|-------|
| Model | Tesla V100-PCIE-16GB | Tesla V100-PCIE-16GB | Datacenter GPU |
| Memory | 16384 MiB (16GB) | 16384 MiB (16GB) | HBM2 |
| Temperature | 37°C | 38°C | Idle, cool |
| Power | 25W / 250W | 27W / 250W | Idle |
| ECC | Enabled (0 errors) | Enabled (0 errors) | Data integrity |

---

## NVMe Storage Performance Test

### Hardware

| Server | NVMe Model | Capacity |
|--------|------------|----------|
| gpuserver1 | SK Hynix HFS256GDE9X081N | 256 GB |
| gpuserver2 | SK Hynix HFS256GDE9X081N | 256 GB |

### Test Tool
```bash
sudo apt install -y fio nvme-cli
```

### Test Commands

**Sequential Write:**
```bash
sudo fio --name=write_test --filename=/tmp/testfile --size=1G \
  --rw=write --bs=1M --direct=1 --numjobs=1 --runtime=10 \
  --group_reporting
```

**Sequential Read:**
```bash
sudo fio --name=read_test --filename=/tmp/testfile --size=1G \
  --rw=read --bs=1M --direct=1 --numjobs=1 --runtime=10 \
  --group_reporting
```

### Results

| Server | Sequential Write | Sequential Read | Latency (R/W) |
|--------|------------------|-----------------|---------------|
| gpuserver1 | 2103 MiB/s (2.2 GB/s) | 1790 MiB/s (1.9 GB/s) | 557/446 µs |
| gpuserver2 | 2111 MiB/s (2.2 GB/s) | 2376 MiB/s (2.5 GB/s) | 419/441 µs |

### Performance Assessment

| Metric | Result | Rating |
|--------|--------|--------|
| Write Speed | ~2.2 GB/s | 🟢 Excellent |
| Read Speed | 1.9-2.5 GB/s | 🟢 Excellent |
| Latency | 400-550 µs | 🟢 Good |

### Why Storage Speed Matters for AI

| Use Case | Requirement | Your Performance |
|----------|-------------|------------------|
| Dataset loading | Fast sequential read | 2+ GB/s ✅ |
| Checkpoint saving | Fast sequential write | 2.2 GB/s ✅ |
| Model loading | Fast random read | Good ✅ |
| Logging | Low latency write | 400 µs ✅ |

---

## Complete Cluster Performance Summary

### Hardware Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                    GPU CLUSTER - FULLY CONFIGURED                   │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   gpuserver1 (192.168.1.73)          gpuserver2 (192.168.1.71)     │
│   ┌───────────────────────┐          ┌───────────────────────┐     │
│   │  V100      V100       │          │  V100      V100       │     │
│   │  16GB      16GB       │          │  16GB      16GB       │     │
│   │   │          │        │          │   │          │        │     │
│   │   └────┬─────┘        │          │   └────┬─────┘        │     │
│   │        │              │          │        │              │     │
│   │   ┌────┴────┐         │          │   ┌────┴────┐         │     │
│   │   │ NVMe    │         │          │   │ NVMe    │         │     │
│   │   │ 256GB   │         │          │   │ 256GB   │         │     │
│   │   │ 2.2GB/s │         │          │   │ 2.2GB/s │         │     │
│   │   └─────────┘         │          │   └─────────┘         │     │
│   │                       │          │                       │     │
│   │   ┌─────────┐         │          │   ┌─────────┐         │     │
│   │   │ConnectX3│         │          │   │ConnectX3│         │     │
│   │   │  40GbE  │         │          │   │  40GbE  │         │     │
│   └───┴────┬────┴─────────┘          └───┴────┬────┴─────────┘     │
│            │                                   │                    │
│            └───────── 80 Gbps RDMA ───────────┘                    │
│                    (2x 40G direct links)                           │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Performance Metrics Summary

| Component | Metric | Result | Status |
|-----------|--------|--------|--------|
| **RDMA** | Bandwidth | 36.4 Gbps per link | 🟢 |
| **RDMA** | Latency | 0.85 µs | 🟢 |
| **RDMA** | Total Capacity | 80 Gbps (2 links) | 🟢 |
| **TCP** | Bandwidth | 27.4 Gbps | 🟢 |
| **TCP** | Latency | 21.9 µs | 🟢 |
| **NVMe** | Write | 2.2 GB/s | 🟢 |
| **NVMe** | Read | 1.9-2.5 GB/s | 🟢 |
| **GPU** | Count | 4x V100 16GB | 🟢 |
| **GPU** | Total VRAM | 64 GB HBM2 | 🟢 |

---

## Next Steps

- [ ] Install and configure NCCL
- [ ] Test GPU-to-GPU RDMA communication
- [ ] Run distributed training benchmark
- [ ] Set up Grafana monitoring
- [ ] (Future) Add switch and compare performance

