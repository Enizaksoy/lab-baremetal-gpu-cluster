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

### Key Learnings

1. **Port number matters**: Cable on port 2, so use `--ib-port=2`
2. **GID index required for RoCE**: Always add `--gid-index=2`
3. **Server must run first** for rping
4. **Cable quality matters**: Bad cable = 10G, good cable = 40G

### Server Quick Reference
| Server | Ubuntu IP | IPMI IP | RDMA IP |
|--------|-----------|---------|---------|
| gpuserver1 | 192.168.1.73 | 192.168.1.72 | 10.0.0.1 |
| gpuserver2 | 192.168.1.71 | 192.168.1.70 | 10.0.0.2 |

**Credentials**: eniz/Ubuntu123 (Ubuntu), admin/admin (IPMI)

---

## Monitoring Setup (January 21, 2026)

### Installed Components

| Component | Location | Port | Purpose |
|-----------|----------|------|---------|
| node_exporter | Both GPU servers | 9100 | System metrics (CPU, RAM, disk, network) |
| gpu_metrics.sh | Both GPU servers | - | GPU metrics via nvidia-smi |
| rdma_metrics.sh | Both GPU servers | - | RDMA/InfiniBand counters |
| Prometheus | 192.168.100.1 | 9090 | Metrics collection & storage |
| Grafana | 192.168.100.1 | 3000 | Dashboard visualization |

### Custom Metrics Scripts

**GPU Metrics** (`/usr/local/bin/gpu_metrics.sh`):
- Collects: temperature, utilization, memory, power
- Output: `/var/lib/node_exporter/gpu.prom`
- Interval: 15 seconds

**RDMA Metrics** (`/usr/local/bin/rdma_metrics.sh`):
- Collects: port_rcv_bytes, port_xmit_bytes, packets
- Source: `/sys/class/infiniband/*/ports/*/counters/`
- Output: `/var/lib/node_exporter/rdma.prom`
- Interval: 5 seconds

### Why RDMA Metrics are Special
- Standard `node_network_*` metrics **don't capture RDMA traffic**
- RDMA bypasses the Linux kernel network stack
- Must read InfiniBand counters directly from sysfs
- Device name: `rocep130s0` (RoCE device)

### Grafana Dashboard Files
- `gpu-cluster-dashboard.json` - Basic GPU monitoring
- `gpu-cluster-dashboard-v2.json` - Added network panels
- `gpu-cluster-dashboard-v3.json` - Fixed with irate()
- `gpu-cluster-dashboard-v4-rdma.json` - **Final with RDMA metrics**

### Dashboard Panels (v4)
1. GPU Temperature (with thresholds)
2. GPU Utilization %
3. GPU Memory Used (MB)
4. GPU Power Draw (Watts)
5. CPU Usage %
6. RAM Usage %
7. **RDMA Throughput (Bytes/sec)** - Shows real GPU-to-GPU traffic!
8. **RDMA Packets/sec**
9. Current GPU Status (stat panels)

### Prometheus Configuration
```yaml
# ~/prometheus/prometheus.yml
scrape_configs:
  - job_name: "gpu-cluster"
    static_configs:
      - targets:
        - '192.168.1.73:9100'  # gpuserver1
        - '192.168.1.71:9100'  # gpuserver2
```

### Systemd Services on GPU Servers
```bash
# Check status
sudo systemctl status node_exporter
sudo systemctl status gpu_metrics
sudo systemctl status rdma_metrics

# Restart if needed
sudo systemctl restart node_exporter gpu_metrics rdma_metrics
```

---

## NCCL Stress Test Results

### Multi-Node Test (4 GPUs, 2 Servers)
```bash
mpirun --allow-run-as-root -np 4 --host 192.168.1.73:2,192.168.1.71:2 \
  -x NCCL_DEBUG=INFO -x NCCL_IB_DISABLE=0 -x LD_LIBRARY_PATH \
  ./all_reduce_perf -b 1M -e 1G -f 2 -g 1 -n 100
```

**Results:**
| Size | Time | Bus Bandwidth |
|------|------|---------------|
| 1 MB | 782 µs | 2.01 GB/s |
| 128 MB | 55 ms | 3.63 GB/s |
| 1 GB | 440 ms | **3.66 GB/s** |

**Average Bus Bandwidth: 3.27 GB/s**

### Performance Analysis
- **Observed**: ~3.65 GB/s NCCL, ~6 GB/s total RDMA throughput
- **Theoretical max**: 10 GB/s (80 Gbps)
- **Efficiency**: 36-60% of theoretical
- **Bottleneck**: ConnectX-3 lacks GPUDirect RDMA (requires CPU memory copies)

### What We Learned
- RDMA traffic doesn't show in standard Linux network counters
- Must use InfiniBand sysfs counters for accurate RDMA monitoring
- `irate()` function in Prometheus/Grafana shows instantaneous throughput
- `rate()` averages over time and misses burst traffic

---

## Completed Tasks ✅
1. ✅ Configure both 40G ports with persistent IPs
2. ✅ Test RDMA on both ports
3. ✅ Compare TCP vs RDMA performance
4. ✅ Install NVIDIA drivers
5. ✅ Install CUDA toolkit 12.6
6. ✅ Install NCCL library (matching CUDA version)
7. ✅ Build nccl-tests
8. ✅ Test intra-node NCCL (2 GPUs same server)
9. ✅ Install OpenMPI on both servers
10. ✅ Set up passwordless SSH between servers
11. ✅ Rebuild nccl-tests with MPI support
12. ✅ Test multi-node NCCL (4 GPUs across 2 servers)
13. ✅ Install node_exporter on GPU servers
14. ✅ Install GPU metrics exporter (custom script)
15. ✅ Configure Prometheus to scrape GPU servers
16. ✅ Create Grafana dashboard
17. ✅ Add RDMA metrics collection

## Future Improvements
- Upgrade to ConnectX-4/5 for GPUDirect RDMA (~8-9 GB/s possible)
- Add alerting rules in Prometheus
- Set up NFS/storage for datasets
- Run actual AI training workload

---
*Last updated: January 21, 2026*
