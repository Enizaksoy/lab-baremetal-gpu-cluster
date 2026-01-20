# RDMA Session Notes - January 2026

## What We Accomplished

### RDMA Test Results (Verified Working!)
- **Bandwidth**: 4555 MB/sec (36.4 Gbps)
- **Latency**: 0.88 µs (880 nanoseconds)
- **Link Speed**: 40 Gbps
- **MTU**: 9000 (Jumbo Frames)

### Network Config
- gpuserver1 (10.0.0.1/24) on ens6d1
- gpuserver2 (10.0.0.2/24) on ens6d1

### Working RDMA Commands

**Bandwidth Test:**
```bash
# Server (gpuserver2):
ib_write_bw --ib-dev=mlx4_0 --ib-port=2 --gid-index=2

# Client (gpuserver1):
ib_write_bw --ib-dev=mlx4_0 --ib-port=2 --gid-index=2 10.0.0.2
```

**Latency Test:**
```bash
# Server (gpuserver2):
ib_write_lat --ib-dev=mlx4_0 --ib-port=2 --gid-index=2

# Client (gpuserver1):
ib_write_lat --ib-dev=mlx4_0 --ib-port=2 --gid-index=2 10.0.0.2
```

**Simple RDMA Ping:**
```bash
# Server first:
rping -s -a 10.0.0.2 -v

# Then client:
rping -c -a 10.0.0.2 -v
```

### Key Learnings

1. **Port number matters**: Cable on port 2, so use `--ib-port=2`
2. **GID index required for RoCE**: Always add `--gid-index=2`
3. **Server must run first** for rping
4. **Cable quality matters**: Bad cable = 10G, good cable = 40G

### Troubleshooting
- "Port state is Down" → Wrong port number or cable issue
- "Unable to find GID" → Add --gid-index=2
- Low bandwidth → Check/replace cable

### Still TODO
1. Make RDMA IPs permanent in netplan
2. Install NVIDIA drivers
3. Set up NCCL for distributed GPU training
4. Update GPU_CLUSTER_GUIDE README (had permission issue)

### Server Quick Reference
| Server | Ubuntu IP | IPMI IP | RDMA IP |
|--------|-----------|---------|---------|
| gpuserver1 | 192.168.1.73 | 192.168.1.72 | 10.0.0.1 |
| gpuserver2 | 192.168.1.71 | 192.168.1.70 | 10.0.0.2 |

**Credentials**: eniz/Ubuntu123 (Ubuntu), admin/admin (IPMI)

---
*Session saved for continuation*
