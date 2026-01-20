# GPU Cluster Setup - Complete Step-by-Step Guide

**Author:** Eniz Aksoy (CCIE #23970)
**Date:** January 2026
**Hardware:** 2× HYVE G2GPU12, 4× Tesla V100 16GB, Mellanox ConnectX-3 Pro 40GbE

This guide documents every step of building a bare-metal AI training cluster, including commands, outputs, and key learnings.

---

## Table of Contents

1. [Step 1: Configure RDMA Network (40G Ports)](#step-1-configure-rdma-network-40g-ports)
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

## Step 1: Configure RDMA Network (40G Ports)

### Goal
Configure both 40GbE ports on the ConnectX-3 Pro with persistent IP addresses for RDMA communication.

### Server Reference

| Server | Management IP | IPMI IP | RDMA Port1 (ens6) | RDMA Port2 (ens6d1) |
|--------|--------------|---------|-------------------|---------------------|
| gpuserver1 | 192.168.1.73 | 192.168.1.72 | 10.0.1.1 | 10.0.0.1 |
| gpuserver2 | 192.168.1.71 | 192.168.1.70 | 10.0.1.2 | 10.0.0.2 |

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

## Step 2: Test RDMA Performance

### Goal
Verify RDMA is working and measure bandwidth/latency.

### Commands

**Bandwidth Test (ib_write_bw):**

```bash
# On gpuserver2 (server - start first):
ib_write_bw --ib-dev=mlx4_0 --ib-port=2 --gid-index=2

# On gpuserver1 (client):
ib_write_bw --ib-dev=mlx4_0 --ib-port=2 --gid-index=2 10.0.0.2
```

**Latency Test (ib_write_lat):**

```bash
# On gpuserver2 (server):
ib_write_lat --ib-dev=mlx4_0 --ib-port=2 --gid-index=2

# On gpuserver1 (client):
ib_write_lat --ib-dev=mlx4_0 --ib-port=2 --gid-index=2 10.0.0.2
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

### RDMA Testing
```bash
# Bandwidth
ib_write_bw --ib-dev=mlx4_0 --ib-port=2 --gid-index=2 [server_ip]

# Latency
ib_write_lat --ib-dev=mlx4_0 --ib-port=2 --gid-index=2 [server_ip]
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

---

*Guide created during hands-on cluster setup session, January 2026*
*Built with the assistance of Claude Code*
