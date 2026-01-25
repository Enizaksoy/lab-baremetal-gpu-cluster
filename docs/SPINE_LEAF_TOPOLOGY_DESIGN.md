# Spine-Leaf Topology Design for GPU Cluster
## January 2026

---

## Hardware Inventory

### High-Speed Fabric (40G)
| Device | Model | Ports | Role |
|--------|-------|-------|------|
| Spine-1 | Cisco N9K-C9332PQ | 32x 40G | Spine Switch |
| Spine-2 | Cisco N9K-C9332PQ | 32x 40G | Spine Switch |
| Leaf-1 | Cisco N9K-C9332PQ | 32x 40G | Leaf Switch |
| Leaf-2 | Cisco N9K-C9332PQ | 32x 40G | Leaf Switch |

### Management Network (1G)
| Device | Model | Ports | Role |
|--------|-------|-------|------|
| Mgmt-SW | Cisco WS-C3750X-24P-S | 24x 1G PoE + 2x 10G (C3KX-NM-10G) | Management Switch |

### Compute - GPU Servers
| Device | 40G Ports | 1G Copper | IPMI | GPUs |
|--------|-----------|-----------|------|------|
| GPU Server 1 | 2 (CX3-Pro) | 2 | 1 | 2x V100 |
| GPU Server 2 | 2 (CX3-Pro) | 2 | 1 | 2x V100 |

### Compute - ESXi Hosts (Lenovo P920)
| Device | 40G Ports | 10G Copper | 1G Copper | Notes |
|--------|-----------|------------|-----------|-------|
| ESXi Host 1 (192.168.50.152) | 2 (CX4-Lx) | 2 | 2 | Lenovo P920 |
| ESXi Host 2 (192.168.50.32) | 2 (CX4-Lx) | 2 | 2 | Lenovo P920 |

---

## Topology Design (Dual-Homed for Redundancy)

```
                    ┌─────────────────────────────────────────────────────┐
                    │              SPINE LAYER (40G)                      │
                    │                                                     │
                    │   ┌─────────────┐         ┌─────────────┐          │
                    │   │   SPINE-1   │         │   SPINE-2   │          │
                    │   │  N9K-9332PQ │         │  N9K-9332PQ │          │
                    │   │             │         │             │          │
                    │   └──┬──┬──┬──┬─┘         └─┬──┬──┬──┬──┘          │
                    │      │  │  │  │             │  │  │  │             │
                    └──────┼──┼──┼──┼─────────────┼──┼──┼──┼─────────────┘
                           │  │  │  │             │  │  │  │
              ┌────────────┘  │  │  └──────┬──────┘  │  │  └────────────┐
              │     ┌─────────┘  └─────┐   │   ┌─────┘  └─────────┐     │
              │     │                  │   │   │                  │     │
              ▼     ▼                  ▼   ▼   ▼                  ▼     ▼
    ┌─────────────────────┐                         ┌─────────────────────┐
    │      LEAF-1         │                         │       LEAF-2        │
    │    N9K-9332PQ       │◄───── 4x 40G ECMP ────►│    N9K-9332PQ       │
    │                     │                         │                     │
    └─┬───┬───┬───┬───┬───┘                         └───┬───┬───┬───┬───┬─┘
      │   │   │   │   │                                 │   │   │   │   │
      │   │   │   │   └─────────────┐     ┌─────────────┘   │   │   │   │
      │   │   │   └─────────────┐   │     │   ┌─────────────┘   │   │   │
      │   │   └─────────────┐   │   │     │   │   ┌─────────────┘   │   │
      │   └─────────────┐   │   │   │     │   │   │   ┌─────────────┘   │
      │                 │   │   │   │     │   │   │   │                 │
      ▼                 ▼   ▼   ▼   ▼     ▼   ▼   ▼   ▼                 ▼
    ┌───────────────────────────────────────────────────────────────────────┐
    │                    DUAL-HOMED SERVERS (Redundancy)                    │
    │                                                                       │
    │  ┌─────────────────────────┐       ┌─────────────────────────┐       │
    │  │     GPU SERVER 1        │       │     GPU SERVER 2        │       │
    │  │   ┌─────┐   ┌─────┐     │       │   ┌─────┐   ┌─────┐     │       │
    │  │   │V100 │   │V100 │     │       │   │V100 │   │V100 │     │       │
    │  │   │GPU-0│   │GPU-1│     │       │   │GPU-0│   │GPU-1│     │       │
    │  │   └──┬──┘   └──┬──┘     │       │   └──┬──┘   └──┬──┘     │       │
    │  │      │         │        │       │      │         │        │       │
    │  │   Port0     Port1       │       │   Port0     Port1       │       │
    │  │   ↓ Leaf1   ↓ Leaf2     │       │   ↓ Leaf1   ↓ Leaf2     │       │
    │  │   40G       40G         │       │   40G       40G         │       │
    │  │   2x 1G + IPMI → 3750X  │       │   2x 1G + IPMI → 3750X  │       │
    │  └─────────────────────────┘       └─────────────────────────┘       │
    │                                                                       │
    │  ┌─────────────────────────┐       ┌─────────────────────────┐       │
    │  │  ESXi Host 1 (P920)     │       │  ESXi Host 2 (P920)     │       │
    │  │  192.168.50.152         │       │  192.168.50.32          │       │
    │  │                         │       │                         │       │
    │  │  vmnic3 → Leaf1 (40G)   │       │  vmnic5 → Leaf1 (40G)   │       │
    │  │  vmnic4 → Leaf2 (40G)   │       │  vmnic6 → Leaf2 (40G)   │       │
    │  │  1G Copper → 3750X      │       │  1G Copper → 3750X      │       │
    │  │  10G Copper → 3750X     │       │  10G Copper → 3750X     │       │
    │  │  [ubunturdma1-4 VMs]    │       │  [ubunturdma5-8 VMs]    │       │
    │  └─────────────────────────┘       └─────────────────────────┘       │
    └───────────────────────────────────────────────────────────────────────┘


                         MANAGEMENT LAYER (1G/10G)
    ┌────────────────────────────────────────────────────────────────────┐
    │                    CISCO 3750X-24P-S                               │
    │                    + C3KX-NM-10G Module                            │
    │  ┌────────────────────────────────────────────────────────────┐    │
    │  │ Gi1/0/1-24 (1G PoE)         │  Te1/0/1-2 (10G Module)      │    │
    │  └─────────────────────────────┴──────────────────────────────┘    │
    │                                                                     │
    │  1G Ports:                        10G Ports:                        │
    │  • GPU1 Mgmt (eth0, eth1)         • ESXi Host 1 (10G copper)       │
    │  • GPU1 IPMI                      • ESXi Host 2 (10G copper)       │
    │  • GPU2 Mgmt (eth0, eth1)                                          │
    │  • GPU2 IPMI                                                        │
    │  • ESXi Host 1 (1G copper)                                         │
    │  • ESXi Host 2 (1G copper)                                         │
    │  • Spine-1/2 OOB Mgmt                                              │
    │  • Leaf-1/2 OOB Mgmt                                               │
    └────────────────────────────────────────────────────────────────────┘
```

### Key Design Principle: Dual-Homing

Every server connects to BOTH leaf switches:
- **GPU Server Port 0** → Leaf-1 | **GPU Server Port 1** → Leaf-2
- **ESXi vmnic3/5** → Leaf-1 | **ESXi vmnic4/6** → Leaf-2

**Benefits:**
- If Leaf-1 fails → traffic continues via Leaf-2
- If Leaf-2 fails → traffic continues via Leaf-1
- Active-Active: both paths used simultaneously (LACP or ECMP)

---

## Cabling Plan

### Spine-to-Leaf Uplinks (40G QSFP+)

| Source | Port | Destination | Port | Cable | Purpose |
|--------|------|-------------|------|-------|---------|
| Spine-1 | Eth1/1 | Leaf-1 | Eth1/31 | QSFP+ 40G | Uplink 1 |
| Spine-1 | Eth1/2 | Leaf-1 | Eth1/32 | QSFP+ 40G | Uplink 2 |
| Spine-1 | Eth1/3 | Leaf-2 | Eth1/31 | QSFP+ 40G | Uplink 1 |
| Spine-1 | Eth1/4 | Leaf-2 | Eth1/32 | QSFP+ 40G | Uplink 2 |
| Spine-2 | Eth1/1 | Leaf-1 | Eth1/29 | QSFP+ 40G | Uplink 3 |
| Spine-2 | Eth1/2 | Leaf-1 | Eth1/30 | QSFP+ 40G | Uplink 4 |
| Spine-2 | Eth1/3 | Leaf-2 | Eth1/29 | QSFP+ 40G | Uplink 3 |
| Spine-2 | Eth1/4 | Leaf-2 | Eth1/30 | QSFP+ 40G | Uplink 4 |

**Bandwidth per Leaf:** 4x 40G = 160 Gbps to spine layer

### GPU Servers - Dual-Homed (40G QSFP+)

| Server | NIC Port | Leaf | Port | IP (RDMA) | Purpose |
|--------|----------|------|------|-----------|---------|
| GPU Server 1 | CX3-Pro Port 0 | **Leaf-1** | Eth1/1 | 10.0.0.1 | GPU-0 → Leaf-1 |
| GPU Server 1 | CX3-Pro Port 1 | **Leaf-2** | Eth1/1 | 10.0.1.1 | GPU-1 → Leaf-2 |
| GPU Server 2 | CX3-Pro Port 0 | **Leaf-1** | Eth1/2 | 10.0.0.2 | GPU-0 → Leaf-1 |
| GPU Server 2 | CX3-Pro Port 1 | **Leaf-2** | Eth1/2 | 10.0.1.2 | GPU-1 → Leaf-2 |

**Redundancy:** If Leaf-1 fails, GPU-1 ports on Leaf-2 maintain connectivity.

### ESXi Hosts - Dual-Homed (40G QSFP+)

| Host | vmnic | Leaf | Port | Purpose |
|------|-------|------|------|---------|
| ESXi Host 1 (192.168.50.152) | vmnic3 | **Leaf-1** | Eth1/3 | RDMA → Leaf-1 |
| ESXi Host 1 (192.168.50.152) | vmnic4 | **Leaf-2** | Eth1/3 | RDMA → Leaf-2 |
| ESXi Host 2 (192.168.50.32) | vmnic5 | **Leaf-1** | Eth1/4 | RDMA → Leaf-1 |
| ESXi Host 2 (192.168.50.32) | vmnic6 | **Leaf-2** | Eth1/4 | RDMA → Leaf-2 |

**Redundancy:** If Leaf-1 fails, vmnic4/6 on Leaf-2 maintain VM connectivity.

### Management - 3750X 1G Ports (Gi1/0/x)

| Device | Interface | 3750X Port | IP | Purpose |
|--------|-----------|------------|-----|---------|
| GPU Server 1 | eth0 (1G) | Gi1/0/1 | 192.168.1.73 | Management |
| GPU Server 1 | eth1 (1G) | Gi1/0/2 | - | Backup |
| GPU Server 1 | IPMI | Gi1/0/3 | 192.168.1.72 | IPMI/BMC |
| GPU Server 2 | eth0 (1G) | Gi1/0/4 | 192.168.1.71 | Management |
| GPU Server 2 | eth1 (1G) | Gi1/0/5 | - | Backup |
| GPU Server 2 | IPMI | Gi1/0/6 | 192.168.1.70 | IPMI/BMC |
| ESXi Host 1 | 1G Copper | Gi1/0/7 | 192.168.50.152 | ESXi Mgmt |
| ESXi Host 1 | 1G Copper-2 | Gi1/0/8 | - | Backup |
| ESXi Host 2 | 1G Copper | Gi1/0/9 | 192.168.50.32 | ESXi Mgmt |
| ESXi Host 2 | 1G Copper-2 | Gi1/0/10 | - | Backup |
| Spine-1 | Mgmt0 | Gi1/0/11 | 192.168.1.x | OOB Mgmt |
| Spine-2 | Mgmt0 | Gi1/0/12 | 192.168.1.x | OOB Mgmt |
| Leaf-1 | Mgmt0 | Gi1/0/13 | 192.168.1.x | OOB Mgmt |
| Leaf-2 | Mgmt0 | Gi1/0/14 | 192.168.1.x | OOB Mgmt |

### Management - 3750X 10G Ports (Te1/0/x - C3KX-NM-10G Module)

| Device | Interface | 3750X Port | IP | Purpose |
|--------|-----------|------------|-----|---------|
| ESXi Host 1 (P920) | 10G Copper | Te1/0/1 | 192.168.100.x | vMotion / Storage |
| ESXi Host 2 (P920) | 10G Copper | Te1/0/2 | 192.168.100.x | vMotion / Storage |

---

## IP Addressing Scheme

### RDMA/Data Networks (40G Fabric)

| VLAN | Subnet | Purpose |
|------|--------|---------|
| 10 | 10.0.0.0/24 | RDMA Rail 0 (GPU Port 0) |
| 11 | 10.0.1.0/24 | RDMA Rail 1 (GPU Port 1) |
| 250 | 192.168.250.0/24 | Legacy RDMA (VMs) |
| 251 | 192.168.251.0/24 | Legacy RDMA Rail 2 |

### Management Networks (1G)

| VLAN | Subnet | Purpose |
|------|--------|---------|
| 1 | 192.168.1.0/24 | Server Management |
| 50 | 192.168.50.0/24 | ESXi Management |
| 100 | 192.168.100.0/24 | Network Management |

---

## Traffic Flow Examples

### Same-Leaf (Intra-Leaf) Traffic
```
GPU Server 1 GPU-0 ←──→ GPU Server 1 GPU-1
         ↓                    ↓
    Leaf-1 Eth1/1 ←────→ Leaf-1 Eth1/2

    Path: Server → Leaf → Server (no spine needed)
    Latency: ~1-2 µs (single switch hop)
```

### Cross-Leaf Traffic (Through Spines)
```
GPU Server 1 (on Leaf-1) ←──→ GPU Server 2 (on Leaf-2)

Path 1: GPU1 → Leaf-1 → Spine-1 → Leaf-2 → GPU2
Path 2: GPU1 → Leaf-1 → Spine-2 → Leaf-2 → GPU2

Bandwidth: 4x 40G = 160 Gbps (ECMP across 4 uplinks)
Latency: ~3-5 µs (3 switch hops)
```

### ECMP Load Balancing
With 4 uplinks per leaf to spine layer:
- Flows are hashed across multiple paths
- Packet reordering is minimal (per-flow hashing)
- Full bisection bandwidth between any two leafs

---

## QoS Configuration (RoCEv2/RDMA)

### On All Switches (Spine + Leaf)

```
! Enable PFC on priority 3
class-map type qos match-all class-rdma
  match cos 3

policy-map type qos policy-rdma
  class class-rdma
    set qos-group 3

policy-map type queuing policy-rdma-queuing
  class type queuing c-out-q3
    priority level 1

! Apply to all fabric ports
interface Ethernet1/1-32
  service-policy type qos input policy-rdma
  priority-flow-control mode auto
  mtu 9216
```

### ECN Configuration
```
! Enable ECN marking
hardware qos ns-only
policy-map type queuing policy-rdma-queuing
  class type queuing c-out-q3
    random-detect minimum-threshold 100 kbytes maximum-threshold 200 kbytes
    random-detect ecn
```

---

## Deployment Checklist

### Phase 1: Initial Rack & Cable (Week 1)
- [ ] Rack all 4 Nexus switches
- [ ] Connect spine-to-leaf uplinks (8 cables)
- [ ] Power on and verify basic boot
- [ ] Console access to all switches

### Phase 2: Basic Switch Config
- [ ] Configure hostnames (spine-1, spine-2, leaf-1, leaf-2)
- [ ] Configure management IPs
- [ ] Configure NTP
- [ ] Enable feature lldp
- [ ] Configure VLANs

### Phase 3: Fabric Configuration
- [ ] Configure spine-leaf interfaces
- [ ] Enable PFC/ECN/QoS
- [ ] Configure ECMP (4-way)
- [ ] Verify connectivity

### Phase 4: Server Migration
- [ ] Move GPU Server 1 to Leaf-1
- [ ] Move GPU Server 2 to Leaf-1 or Leaf-2
- [ ] Move ESXi hosts to Leaf-2
- [ ] Update RDMA IPs if needed

### Phase 5: 3750X Integration (When arrives)
- [ ] Rack 3750X
- [ ] Configure management VLAN
- [ ] Connect all 1G management ports
- [ ] Connect all IPMI ports
- [ ] Test out-of-band access

### Phase 6: Validation
- [ ] RDMA bandwidth test (ib_write_bw)
- [ ] RDMA latency test (ib_write_lat)
- [ ] Multi-node NCCL test
- [ ] PFC counter verification
- [ ] ECN marking verification

---

## Expected Performance

| Metric | Current (Single Switch) | New (Spine-Leaf) |
|--------|------------------------|------------------|
| Same-Leaf Latency | ~0.88 µs | ~1-2 µs |
| Cross-Leaf Latency | N/A | ~3-5 µs |
| Max Bisection BW | 40 Gbps | 160 Gbps |
| Redundancy | None | Full (2 spines) |
| Failure Domain | Entire fabric | Per leaf |

---

## Notes

1. **Why Spine-Leaf for GPU Cluster?**
   - Equal bandwidth between any two endpoints
   - Predictable latency (max 3 hops)
   - Easy to scale (add more leafs)
   - Better failure isolation

2. **Multi-Rail Benefits:**
   - Each GPU gets dedicated 40G path
   - No oversubscription at the NIC level
   - NCCL can use both rails simultaneously

3. **3750X Role:**
   - Out-of-band management (1G)
   - IPMI/BMC access (critical for remote troubleshooting)
   - 10G module for future use (monitoring, storage)

---

*Created: January 23, 2026*
