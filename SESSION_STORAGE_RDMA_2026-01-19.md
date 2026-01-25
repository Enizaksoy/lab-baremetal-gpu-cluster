# Session Summary: Storage RDMA Architecture Planning
**Date:** January 19, 2026
**Status:** Paused - Ready to Continue

---

## Session Overview

Discussed and planned the complete AI cluster architecture with **separated compute and storage RDMA fabrics**, matching production AI datacenter designs.

---

## Key Decisions Made

### 1. Architecture: Separate Compute & Storage Networks ✅

| Network | Speed | NICs | Purpose |
|---------|-------|------|---------|
| **Compute Fabric** | 4x 40G | ConnectX-3 Pro (GPU servers) | NCCL GPU-to-GPU RDMA |
| **Storage Fabric** | 40G → 10G | ConnectX-4 Lx (GPU) → 25G@10G (P920) | NVMe-oF over RDMA |

### 2. Hardware Allocation

**GPU Servers (Bare Metal):**
- ConnectX-3 Pro (2x 40G) → **COMPUTE** (NCCL)
- ConnectX-4 Lx (moved from P920) → **STORAGE CLIENT** (NVMe-oF initiator)

**P920 ESXi Hosts (Storage Tier):**
- 25G NICs @ 10G (breakout cables) → **STORAGE TARGETS** (NVMe-oF)
- Keep existing NVMe drives for storage pool

### 3. Storage Discovered on P920s

| Datastore | Capacity | Free | Speed | Host |
|-----------|----------|------|-------|------|
| 4TB_NVME_7500 | 3.73 TB | 1.77 TB | 7,500 MB/s | Host 1 |
| 2TB_NVME_2_7300MB/s | 1.86 TB | 0.51 TB | 7,300 MB/s | Host 2 |
| 2TB_NVME_1_3500MB/s | 1.91 TB | 1.06 TB | 3,500 MB/s | Host 2 |
| 2TB_NVME_1_3000MB/s | 1.91 TB | 1.41 TB | 3,000 MB/s | Host 1 |
| 1TB_SSD | 0.93 TB | 0.82 TB | SATA | Host 1 |

**Total: ~10.8 TB storage available**

---

## Diagram Created

**File:** `AI_Cluster_Full_Architecture.drawio`
**Location:** `/01-RDMA-RoCEv2-AI-Cluster/images/`

Shows:
- Compute Tier (GPU Servers with V100s)
- Storage Tier (P920 ESXi with NVMe)
- ESXi VM Cluster (8x Ubuntu RDMA VMs)
- Network switch ports and VLAN assignments
- Both compute and storage RDMA paths

---

## Network Design

### VLANs
| VLAN | Subnet | Purpose |
|------|--------|---------|
| 100 | 10.0.1.0/24 | GPU Compute RDMA |
| 200 | 10.0.2.0/24 | Storage RDMA |

### Switch Port Allocation (Nexus 9332PQ)
| Ports | Speed | Purpose |
|-------|-------|---------|
| Eth1/1/1-2 | 40G | ESXi Host 2 SR-IOV |
| Eth1/2/1-2 | 40G | ESXi Host 1 SR-IOV |
| Eth1/3/1-4 | 40G | GPU Compute (CX-3 Pro) |
| Eth1/4/1-2 | 40G | GPU Storage (CX-4 Lx) |
| Eth1/5/1-4 | 10G | P920 Storage (25G@10G breakout) |

---

## Why 10G Storage is OK

- 10G network (~1.1 GB/s) is the bottleneck, not NVMe (7.5 GB/s)
- Still excellent for learning NVMe-oF concepts
- Latency remains low (RDMA benefit)
- Matches many real-world storage deployments
- Future upgrade: just swap breakout cables for 40G DAC

---

## Hardware Already Owned

- [x] Dual M.2 PCIe Adapter (purchased) - for adding NVMe
- [x] ConnectX-4 Lx NICs in P920s (will move to GPU servers)
- [x] ConnectX-3 Pro NICs in GPU servers
- [x] 10+ TB NVMe storage across P920s
- [x] 25G NICs in P920s (will use @ 10G for storage)

---

## Next Steps (When Resuming)

1. **Physical Hardware Migration**
   - Move ConnectX-4 Lx from P920s to GPU servers
   - Install dual M.2 adapter if adding more NVMe

2. **Network Configuration**
   - Configure VLAN 100 (compute) and VLAN 200 (storage)
   - Set up PFC/ECN on new ports

3. **NVMe-oF Setup**
   - Create Storage VM on P920 (Ubuntu 22.04)
   - Configure nvmet (NVMe target)
   - Configure nvme-cli (initiator) on GPU servers

4. **Testing**
   - NVMe-oF connectivity test
   - fio benchmarks over RDMA
   - Integration with GPU training workloads

---

## Connection Details (Reference)

| System | IP | Credentials |
|--------|-----|-------------|
| vCenter | vcenter.mylab.com | Administrator@mylab.com / Elma12743?? |
| ESXi Host 1 | 192.168.50.152 | root / Versa@123!! |
| ESXi Host 2 | 192.168.50.32 | root / Versa@123!! |
| Grafana | 192.168.100.1:3000 | admin / Versa@123!! |

---

## Files Created This Session

1. `AI_Cluster_Full_Architecture.drawio` - Complete architecture diagram
2. `SESSION_STORAGE_RDMA_2026-01-19.md` - This summary file

---

## Key Insight

**This architecture mirrors production AI clusters:**
- NVIDIA DGX systems use separate compute and storage NICs
- Storage is disaggregated from GPU compute
- NVMe-oF over RDMA is standard for AI training data
- Even at 10G, storage RDMA provides learning value

---

*Resume this session by reading this file and the draw.io diagram*
