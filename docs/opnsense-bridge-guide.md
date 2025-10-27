# Bridging Additional Network Ports to LAN in OPNsense

This guide explains how to bridge multiple network ports together in OPNsense to create a unified LAN with multiple physical connections.

## Overview

By creating a bridge interface, you can combine multiple network ports so they all function as part of the same LAN network. This is useful when you want to use all available ports on your OPNsense device as LAN ports.

## Prerequisites

- Administrative access to OPNsense web interface
- Multiple available network ports on your device
- Basic understanding of your current network configuration

## Step-by-Step Instructions

### Step 1: Assign Optional Ports

1. Navigate to **Interfaces → Assignments**
2. Locate your additional physical ports in the interface list
3. Assign each additional port as an optional interface (OPT1, OPT2, etc.)
4. Click on each newly assigned optional interface
5. Enable the interface (check the "Enable interface" box)
6. **Do not configure IP addresses** - leave them unconfigured
7. Save changes for each interface

### Step 2: Create the Bridge Interface

1. Navigate to **Interfaces → Other Types → Bridge**
2. Click the **+** (plus) button to add a new bridge
3. In the "Member interfaces" dropdown, select all the **optional ports** you want to bridge together (OPT1, OPT2, etc.)
4. **Important:** Do NOT add the LAN port to the bridge at this stage
5. Optionally, give the bridge a description (e.g., "LAN Bridge")
6. Click **Save**
7. Click **Apply changes**

### Step 3: Assign Bridge to LAN Interface

1. Navigate to **Interfaces → Assignments**
2. Find the **LAN** interface in the assignments list
3. Click the dropdown next to LAN and change it from the physical port to the **bridge** interface you just created
4. Click **Save**
5. Click **Apply changes**

### Step 4: Move Your Physical Connection

⚠️ **Critical Step - You Will Lose Connectivity Temporarily**

At this point, if you are connected via the original physical LAN port, you will lose network connectivity because that port is no longer assigned to the LAN interface.

**To restore connectivity:**

1. Unplug your network cable from the physical LAN port
2. Plug it into one of the **optional ports** that you added to the bridge (OPT1, OPT2, etc.)
3. Wait a few seconds for the connection to establish
4. Your IP address and network settings should remain the same

### Step 5: Verify Connectivity

Before proceeding, verify that everything is working correctly:

1. **Test network connectivity:**
   - Open a command prompt or terminal
   - Ping your OPNsense router's IP address (e.g., `ping 192.168.1.1`)
   - Verify you receive replies

2. **Access the web GUI:**
   - Open your web browser
   - Navigate to the OPNsense web interface
   - Confirm you can log in and access the configuration

### Step 6: Add Physical LAN Port to Bridge

Now that you have working connectivity through a bridged port, you can add the original physical LAN port to the bridge:

1. Navigate to **Interfaces → Assignments**
2. Assign the original physical LAN port as a new optional interface (it will likely be the next available OPT number, e.g., OPT3)
3. Click **Save**

4. Navigate to **Interfaces → Other Types → Bridge**
5. Click the **edit** icon (pencil) next to your bridge
6. In the "Member interfaces" dropdown, add the newly assigned optional interface (the old physical LAN port)
7. Click **Save**
8. Click **Apply changes**

## Verification

All your network ports should now be functioning as a unified LAN:

1. Test connectivity on each port by plugging devices into different ports
2. Verify all devices receive IP addresses from your DHCP server
3. Confirm devices can communicate with each other and access the internet

## Troubleshooting

### Lost Connectivity After Step 3

This is expected. Make sure you move your connection to one of the optional ports that are part of the bridge.

### Cannot Access Web GUI

- Verify you're connected to a port that's part of the bridge
- Check that your device has obtained an IP address in the correct subnet
- Try clearing your browser cache or using a different browser

### Device Performance Issues

Some network adapters don't handle bridging well:

- Check CPU usage in **System → Activity**
- Consider using hardware that better supports bridging
- Ensure your NICs support promiscuous mode

## Additional Notes

- All bridged ports will share the same IP subnet
- Firewall rules applied to the LAN interface will affect all bridged ports
- DHCP server on LAN will serve all bridged ports
- This creates a true Layer 2 bridge - all ports are in the same broadcast domain

## Rollback Instructions

If you need to revert these changes:

1. Navigate to **Interfaces → Assignments**
2. Change LAN back to the original physical port
3. Remove optional interface assignments
4. Delete the bridge interface in **Interfaces → Other Types → Bridge**

---

**Last Updated:** October 2025  
**OPNsense Version:** Compatible with OPNsense 23.x and later