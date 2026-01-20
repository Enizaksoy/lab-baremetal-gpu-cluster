# Quick Start Guide

Get your GPU cluster up and running in 30 minutes.

## Prerequisites

- 2x GPU servers with IPMI access
- Ubuntu 22.04 LTS installed
- Network connectivity (DHCP)

## Step 1: Install ipmitool (on your workstation)

```bash
# Ubuntu/Debian
sudo apt install -y ipmitool

# macOS
brew install ipmitool

# Windows (via WSL)
wsl -e sudo apt install -y ipmitool
```

## Step 2: Verify IPMI Connectivity

```bash
ipmitool -I lanplus -H <IPMI_IP> -U admin -P admin chassis status
```

You should see:
```
System Power         : on
Power Overload       : false
...
```

## Step 3: Enable Serial Console

SSH into your server and run:

```bash
# Enable serial getty
sudo systemctl enable --now serial-getty@ttyS1.service

# Configure GRUB
sudo sed -i 's/GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="console=tty0 console=ttyS1,9600n8"/' /etc/default/grub
echo 'GRUB_TERMINAL="console serial"' | sudo tee -a /etc/default/grub
echo 'GRUB_SERIAL_COMMAND="serial --speed=9600 --unit=1 --word=8 --parity=no --stop=1"' | sudo tee -a /etc/default/grub
sudo update-grub
```

## Step 4: Set IPMI Baud Rate

```bash
ipmitool -I lanplus -H <IPMI_IP> -U admin -P admin sol set volatile-bit-rate 9.6 1
ipmitool -I lanplus -H <IPMI_IP> -U admin -P admin sol set non-volatile-bit-rate 9.6 1
```

## Step 5: Test SOL Connection

```bash
ipmitool -I lanplus -H <IPMI_IP> -U admin -P admin sol activate
```

Press Enter to see login prompt. Exit with `~.`

## Step 6: Configure Persistent Network

```bash
sudo tee /etc/netplan/01-network.yaml << 'EOF'
network:
  version: 2
  ethernets:
    enp5s0:
      dhcp4: true
EOF

echo "network: {config: disabled}" | sudo tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
sudo rm -f /etc/netplan/50-cloud-init.yaml
sudo netplan apply
```

## Done!

Your server now has:
- ✅ IPMI remote management
- ✅ SOL console access
- ✅ Persistent network configuration

## Next Steps

- [Install NVIDIA Drivers](docs/nvidia-drivers.md)
- [Configure RDMA](docs/rdma-setup.md)
- [Set up Distributed Training](docs/distributed-training.md)

## Common Commands

```bash
# SSH to server
ssh user@<SERVER_IP>

# SOL console
ipmitool -I lanplus -H <IPMI_IP> -U admin -P admin sol activate

# Power control
ipmitool -I lanplus -H <IPMI_IP> -U admin -P admin chassis power on
ipmitool -I lanplus -H <IPMI_IP> -U admin -P admin chassis power off
ipmitool -I lanplus -H <IPMI_IP> -U admin -P admin chassis power reset

# Check sensors
ipmitool -I lanplus -H <IPMI_IP> -U admin -P admin sdr type temperature
```
