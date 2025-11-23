# KVM Virtual Machine Optimization Guide

## Overview
This guide covers performance optimizations for KVM virtual machines using virt-install and libvirt. These optimizations can significantly improve disk I/O, network throughput, CPU performance, and overall VM responsiveness.

---

## 1. VirtIO Drivers (Highest Impact)

VirtIO is a virtualization standard for network and disk device drivers. It provides near-native performance by reducing virtualization overhead.

### Disk Optimization
```bash
--disk path=/var/lib/libvirt/images/vm.qcow2,size=32,bus=virtio,cache=none,io=native
```

**Options explained:**
- `bus=virtio` - Uses paravirtualized disk driver (much faster than IDE/SATA)
- `cache=none` - Direct I/O, bypasses host cache for better data integrity
- `io=native` - Uses native Linux AIO for better performance

### Network Optimization
```bash
--network bridge=br0,model=virtio
```

**Benefits:**
- Lower CPU overhead
- Higher throughput
- Lower latency

### Video Optimization
```bash
--video virtio
```

---

## 2. CPU Optimization

### Host CPU Passthrough (Best Performance)
```bash
--cpu host-passthrough
```

**Pros:**
- Exposes all host CPU features to guest
- Best performance
- Enables CPU-specific optimizations

**Cons:**
- Less portable (can't migrate to different CPU models)

### Host CPU Model (Good Balance)
```bash
--cpu host-model
```

**Pros:**
- Good performance
- Better migration compatibility

### vCPU Allocation
```bash
# Allocate specific number of vCPUs
--vcpus 4

# With maximum limit for hotplug
--vcpus 4,maxvcpus=8

# Pin to specific physical cores (advanced)
--cpuset=0-3
```

---

## 3. Memory Optimization

### Basic Memory Allocation
```bash
--memory 8192  # 8GB in MB
```

### Memory Ballooning
```bash
--memballoon model=virtio
```

**Benefits:**
- Dynamic memory management
- Host can reclaim unused memory

### Huge Pages (Advanced)
```bash
--memorybacking hugepages=on
```

**Prerequisites:**
```bash
# Configure on host
echo 1024 | sudo tee /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages
```

---

## 4. Disk Format & Allocation

### QCOW2 with Metadata Preallocation
```bash
--disk path=/var/lib/libvirt/images/vm.qcow2,size=32,format=qcow2,bus=virtio,cache=none,io=native,preallocation=metadata
```

**Pros:**
- Supports snapshots
- Thin provisioning
- Better performance with preallocation

### Raw Format (Maximum Performance)
```bash
--disk path=/var/lib/libvirt/images/vm.raw,size=32,format=raw,bus=virtio,cache=none,io=native
```

**Pros:**
- Best disk performance
- Lower CPU overhead

**Cons:**
- No snapshots
- Full space allocated upfront

---

## 5. Additional Device Optimizations

### QEMU Guest Agent
```bash
--channel unix,target_type=virtio,name=org.qemu.guest_agent.0
```

**Benefits:**
- Better host-guest communication
- Graceful shutdowns
- Accurate guest information
- File system quiescing for snapshots

### Random Number Generator
```bash
--rng /dev/urandom
```

**Benefits:**
- Better entropy for guest
- Faster cryptographic operations

### Memory Balloon
```bash
--memballoon model=virtio
```

---

## 6. Complete Optimized virt-install Command

### For Ubuntu Server
```bash
sudo virt-install \
  --name ubuntu-vm \
  --memory 8192 \
  --vcpus 4 \
  --cpu host-passthrough \
  --disk path=/var/lib/libvirt/images/ubuntu-vm.qcow2,size=32,bus=virtio,cache=none,io=native,preallocation=metadata \
  --network bridge=br0,model=virtio \
  --location /path/to/ubuntu.iso,kernel=casper/vmlinuz,initrd=casper/initrd \
  --extra-args 'autoinstall console=ttyS0,115200n8 serial' \
  --graphics vnc \
  --video virtio \
  --channel unix,target_type=virtio,name=org.qemu.guest_agent.0 \
  --memballoon model=virtio \
  --rng /dev/urandom \
  --os-variant ubuntu24.04
```

### For Ubuntu Desktop
```bash
sudo virt-install \
  --name ubuntu-desktop-vm \
  --memory 8192 \
  --vcpus 4 \
  --cpu host-passthrough \
  --disk path=/var/lib/libvirt/images/ubuntu-desktop-vm.qcow2,size=32,bus=virtio,cache=none,io=native \
  --network bridge=br0,model=virtio \
  --cdrom /path/to/ubuntu-desktop.iso \
  --graphics spice,listen=0.0.0.0 \
  --video qxl \
  --channel spicevmc,target_type=virtio,name=com.redhat.spice.0 \
  --channel unix,target_type=virtio,name=org.qemu.guest_agent.0 \
  --memballoon model=virtio \
  --rng /dev/urandom \
  --os-variant ubuntu24.04
```

---

## 7. Optimizing Existing VMs

### Edit VM Configuration
```bash
virsh shutdown vm-name
virsh edit vm-name
```

### Key XML Changes

#### CPU Configuration
```xml
<!-- Change from default to host-passthrough -->
<cpu mode='host-passthrough' check='none'>
  <topology sockets='1' cores='4' threads='1'/>
</cpu>
```

#### Disk Configuration
```xml
<disk type='file' device='disk'>
  <driver name='qemu' type='qcow2' cache='none' io='native'/>
  <source file='/var/lib/libvirt/images/vm.qcow2'/>
  <target dev='vda' bus='virtio'/>
  <address type='pci' domain='0x0000' bus='0x00' slot='0x04' function='0x0'/>
</disk>
```

#### Network Configuration
```xml
<interface type='bridge'>
  <source bridge='br0'/>
  <model type='virtio'/>
  <address type='pci' domain='0x0000' bus='0x00' slot='0x03' function='0x0'/>
</interface>
```

#### Add Guest Agent Channel
```xml
<channel type='unix'>
  <target type='virtio' name='org.qemu.guest_agent.0'/>
  <address type='virtio-serial' controller='0' bus='0' port='1'/>
</channel>
```

---

## 8. Guest (VM) Optimizations

### Install QEMU Guest Agent
```bash
sudo apt update
sudo apt install qemu-guest-agent
sudo systemctl enable --now qemu-guest-agent
```

### Install and Configure tuned
```bash
# Install tuned
sudo apt install tuned

# Enable and start
sudo systemctl enable --now tuned

# Set virtual-guest profile
sudo tuned-adm profile virtual-guest

# Verify
sudo tuned-adm active
```

### Disable Unnecessary Services
```bash
# Disable snapd if not needed
sudo systemctl disable snapd
sudo systemctl stop snapd

# Disable power management features (not needed in VMs)
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
```

### Install VirtIO Drivers (if not already present)
```bash
# Usually included by default in modern Linux distros
sudo apt install linux-modules-extra-$(uname -r)
```

---

## 9. Host System Optimizations

### Enable KVM Nested Virtualization (if needed)
```bash
# For Intel CPUs
echo "options kvm_intel nested=1" | sudo tee /etc/modprobe.d/kvm.conf

# For AMD CPUs
echo "options kvm_amd nested=1" | sudo tee /etc/modprobe.d/kvm.conf

# Reload modules
sudo modprobe -r kvm_intel
sudo modprobe kvm_intel
```

### Configure Huge Pages
```bash
# Add to /etc/sysctl.conf
vm.nr_hugepages = 1024

# Apply
sudo sysctl -p
```

### CPU Governor
```bash
# Set to performance mode for consistent performance
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
```

---

## 10. Performance Testing

### Test Disk I/O
```bash
# Inside VM
sudo apt install fio

# Sequential read test
fio --name=seqread --rw=read --bs=1M --size=1G --numjobs=1 --time_based --runtime=60

# Random read/write test
fio --name=randwrite --rw=randwrite --bs=4k --size=1G --numjobs=4 --time_based --runtime=60
```

### Test Network Performance
```bash
# On host
iperf3 -s

# Inside VM
sudo apt install iperf3
iperf3 -c <host_ip>
```

### Monitor VM Performance
```bash
# Real-time stats
virt-top

# Detailed info
virsh domstats vm-name
```

---

## 11. Troubleshooting

### Check VirtIO Drivers are Loaded
```bash
# Inside VM
lsmod | grep virtio

# Should show:
# virtio_net
# virtio_blk
# virtio_balloon
# virtio_console
```

### Verify Disk Cache Mode
```bash
virsh dumpxml vm-name | grep -A 5 "disk type"
```

### Check CPU Model
```bash
# Inside VM
lscpu | grep "Model name"

# Should match or be similar to host CPU if using host-passthrough
```

---

## 12. Performance Comparison

### Typical Performance Improvements

| Optimization | Expected Improvement |
|-------------|---------------------|
| VirtIO disk vs IDE | 3-5x faster I/O |
| VirtIO network vs e1000 | 2-3x throughput |
| host-passthrough vs default | 10-20% CPU performance |
| cache=none vs writethrough | Better data integrity, similar speed |
| Raw disk vs qcow2 | 5-10% faster I/O |
| Preallocated qcow2 vs thin | 15-20% faster writes |

---

## 13. Best Practices Summary

### Always Use
- VirtIO drivers for disk and network
- `cache=none,io=native` for disk
- QEMU guest agent
- Appropriate OS variant (`--os-variant`)

### Consider Using
- `host-passthrough` CPU (if not migrating VMs)
- Preallocated qcow2 or raw disks
- Memory ballooning
- More vCPUs (don't exceed physical cores)

### Avoid
- IDE/SATA disk emulation (very slow)
- e1000 network emulation (slower than virtio)
- Excessive vCPU allocation (causes contention)
- `cache=writeback` (data loss risk)

---

## 14. Quick Reference

### List Available OS Variants
```bash
osinfo-query os
```

### Check VM Resource Usage
```bash
virsh domstats vm-name --cpu-total --balloon --block --net
```

### Live VM Tuning
```bash
# Change vCPUs (if maxvcpus is set)
virsh setvcpus vm-name 4 --live

# Change memory
virsh setmem vm-name 8G --live
```

### Backup Before Optimization
```bash
virsh dumpxml vm-name > vm-name-backup.xml
cp /var/lib/libvirt/images/vm.qcow2 /backup/vm.qcow2
```

---

## Additional Resources

- [KVM Performance Tuning](https://www.linux-kvm.org/page/Tuning_KVM)
- [Red Hat Virtualization Tuning Guide](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/8/html/configuring_and_managing_virtualization/optimizing-virtual-machine-performance-in-rhel_configuring-and-managing-virtualization)
- [VirtIO Documentation](https://wiki.libvirt.org/Virtio.html)