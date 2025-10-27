# OPSense 10G Bridge Connectivity Issue - Resolution Guide

## Problem Summary

10 Gigabit Ethernet ports configured as bridge members in OPSense were not allowing direct device connections to communicate with other LAN clients, despite the physical link being active and established.

## Symptoms

- **Physical Layer**: Link active on both router and connected device (10Gbase-SR negotiated successfully)
- **Router Connectivity**: OPSense router could ping and access the connected device
- **Client Connectivity**: Other LAN devices could NOT ping or access the device
- **Workaround**: Connecting through an intermediate switch worked correctly
- **Interface Status**: Interface showed as `UP`, `RUNNING`, and member of LAN bridge

### Example Interface Configuration

```
ixl1: flags=1008943<UP,BROADCAST,RUNNING,PROMISC,SIMPLEX,MULTICAST,LOWER_UP>
        description: 10xgig1 (opt4)
        ether 64:62:66:25:29:b2
        media: Ethernet autoselect (10Gbase-SR <full-duplex>)
        status: active
```

### Bridge Configuration

```
bridge0: flags=1008843<UP,BROADCAST,RUNNING,SIMPLEX,MULTICAST,LOWER_UP>
        inet 192.168.1.1 netmask 0xffffff00 broadcast 192.168.1.255
        member: ixl1 flags=143<LEARNING,DISCOVER,AUTOEDGE,AUTOPTP>
```

## Root Cause

The issue was caused by **packet filtering on bridge member interfaces** (`net.link.bridge.pfil_member=1`).

In FreeBSD-based systems (including OPSense), when `pfil_member` is enabled (set to 1), the firewall processes packets at **both** the member interface level AND the bridge interface level. This causes asymmetric routing issues where:

1. **Incoming packets** (client → device): Successfully traverse the firewall rules
2. **Outgoing replies** (device → client): Get dropped or blocked at the member interface level before reaching the bridge

This results in one-way communication where the router can reach the device, but other clients cannot.

## Diagnostic Process

### Packet Capture Analysis

Running `tcpdump -i bridge0 -n host 192.168.1.101` revealed:

```
IP 192.168.1.60.42192 > 192.168.1.101.445: Flags [S], seq 3613010160
IP 192.168.1.81.60646 > 192.168.1.101.445: Flags [S], seq 3778230221
ARP, Reply 192.168.1.101 is-at 90:5a:08:98:1b:80
```

**Key Observation**: SYN packets from clients were arriving, ARP was working, but **NO SYN-ACK replies** were being returned.

### Checking System Settings

```bash
sysctl net.link.bridge.pfil_member  # Was set to 1 (default)
sysctl net.link.bridge.pfil_bridge  # Was set to 0
```

## Resolution

### Immediate Fix (Temporary)

Disable packet filtering on bridge member interfaces via shell:

```bash
sysctl net.link.bridge.pfil_member=0
```

This change takes effect immediately without requiring a reboot.

### Permanent Fix (GUI Method)

Make the change persistent across reboots:

1. Navigate to **System → Settings → Tunables**
2. Click **Add** (+ button)
3. Configure the tunable:
   - **Tunable**: `net.link.bridge.pfil_member`
   - **Value**: `0`
   - **Description**: `Disable firewall filtering on bridge members`
4. Click **Save**
5. Reboot for the tunable to take effect (or use the shell command for immediate effect)

### Alternative: Shell Configuration File Method

Add to `/boot/loader.conf.local`:

```
net.link.bridge.pfil_member=0
```

## Technical Explanation

### What pfil_member Controls

- **pfil_member=1** (default): Firewall processes packets on each individual bridge member interface (igc1, ixl0, ixl1, etc.)
- **pfil_member=0**: Firewall only processes packets at the bridge interface level (bridge0)

### Why This Matters for Bridges

When bridge members have firewall filtering enabled:
- Each physical interface applies firewall rules independently
- State tracking and rule evaluation happens multiple times
- Return traffic may not match the same path as outgoing traffic
- This creates asymmetric routing scenarios that break connectivity

With `pfil_member=0`:
- Firewall rules are applied once at the bridge level
- All bridge members act purely as Layer 2 forwarding ports
- Traffic flows correctly in both directions

### Related Settings

- **net.link.bridge.pfil_bridge**: Controls filtering on the bridge interface itself (should typically remain at default value 0)
- **net.link.bridge.pfil_onlyip**: When enabled, only filters IP traffic through pfil hooks

## Verification

After applying the fix, verify connectivity:

```bash
# From OPSense shell
ping [device-ip]

# From other LAN clients
ping [device-ip]
ssh [device-ip]
# Access web GUI, file shares, etc.
```

All tests should now succeed.

## When This Issue Occurs

This problem typically manifests when:
- Using 10 Gigabit Ethernet interfaces in bridge configurations
- Multiple interfaces are bridged together for LAN connectivity
- Devices are directly connected to high-speed bridge member ports
- Default FreeBSD/OPSense firewall filtering is enabled on bridge members

## Additional Notes

- This is a known behavior in FreeBSD-based systems, not a bug
- The default setting (`pfil_member=1`) is designed for security but can cause issues in bridged configurations
- Intermediate switches work around this because they handle Layer 2 forwarding independently
- The fix does not compromise security when firewall rules are properly configured on the bridge interface itself

## References

- FreeBSD Bridge Manual: `man 4 if_bridge`
- OPSense Documentation: https://docs.opnsense.org/
- System Tunables: System → Settings → Tunables

---

**Document Version**: 1.0  
**Date**: October 26, 2025  
**Issue**: 10G bridge member connectivity failure  
**Resolution**: Disable pfil_member filtering on bridge member interfaces