# Complete WireGuard VPN Setup Guide for OPNsense

This guide provides a complete walkthrough for setting up WireGuard VPN on OPNsense, including all the necessary configuration steps that are often missed in basic tutorials.

## Prerequisites

- OPNsense firewall (tested on 25.7.6)
- WireGuard plugin installed (`os-wireguard`)
- Local network access to OPNsense for initial configuration
- Client device with WireGuard installed

## Part 1: Install WireGuard Plugin

1. Navigate to **System → Firmware → Plugins**
2. Search for "wireguard"
3. Install **os-wireguard** plugin
4. Wait for installation to complete

## Part 2: Configure WireGuard Server Instance

### Create Server Instance

1. Go to **VPN → WireGuard → Instances**
2. Click **+** to add a new instance
3. Configure the instance:
   - **Name:** wg0 (or your preferred name)
   - **Public Key:** (auto-generated, note this for client config)
   - **Private Key:** (auto-generated)
   - **Listen Port:** 51820
   - **Tunnel Address:** 10.9.0.1/24 (adjust subnet as needed)
   - **Peers:** (leave empty, will configure next)
4. Click **Save**

### Enable WireGuard Service

**CRITICAL STEP:** At the bottom of the Instances page, there is a checkbox to **"Enable WireGuard"**. This master switch must be enabled for the service to start.

1. Scroll to the bottom of **VPN → WireGuard → Instances**
2. Check the **"Enable WireGuard"** checkbox
3. Click **Save**
4. The WireGuard service should now appear in **System → Diagnostics → Services**

## Part 3: Configure Client Peer

### Add Client Peer in OPNsense

1. Go to **VPN → WireGuard → Peers**
2. Click **+** to add a new peer
3. Configure the peer:
   - **Name:** client1 (or device name)
   - **Public Key:** (paste client's public key)
   - **Allowed IPs:** 10.9.0.2/32 (client's VPN IP)
   - **Instance:** Select your instance (wg0)
4. Click **Save**

### Generate Client Configuration

Create a client configuration file (e.g., `wg-client.conf`):

```ini
[Interface]
Address = 10.9.0.2/24
PrivateKey = <client-private-key>
DNS = 1.1.1.1, 1.0.0.1

[Peer]
PublicKey = <server-public-key-from-instance>
Endpoint = <your-public-ip>:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 30
```

**DNS Options:**

- Use `1.1.1.1, 1.0.0.1` (Cloudflare) for fast public DNS
- Use `8.8.8.8, 8.8.4.4` (Google) as alternative
- Use `10.9.0.1` to route DNS through OPNsense (slower but more private)

**AllowedIPs Options:**

- `0.0.0.0/0` - Full tunnel (all traffic through VPN)
- `10.9.0.0/24, 192.168.1.0/24` - Split tunnel (only home networks through VPN)

## Part 4: Verify WireGuard is Running

1. Go to **System → Diagnostics → Services**
2. Verify **wireguard** service is listed and running (green status)
3. Go to **VPN → WireGuard → Status**
4. Verify interface is up and peer is listed

If the service is not running:

- Check the master "Enable WireGuard" checkbox at bottom of Instances page
- Try restarting the service from System → Diagnostics → Services
- Check **VPN → WireGuard → Logfile** for errors

## Part 5: Assign WireGuard Interface

**IMPORTANT:** The interface must be assigned before firewall rules can be created.

1. Go to **Interfaces → Assignments**
2. In the "New interface" dropdown, select **wg0** (or your instance name)
3. Click **+** to add it
4. Click on the newly added interface (e.g., OPT1)
5. Configure the interface:
   - **Enable interface:** Check
   - **Description:** WireGuard (or preferred name)
   - **IPv4 Configuration Type:** None (already configured in VPN settings)
6. Click **Save**
7. Click **Apply Changes**

## Part 6: Configure Firewall Rules

### Allow WireGuard Traffic on WAN

This allows incoming VPN connections:

1. Go to **Firewall → Rules → WAN**
2. Click **+** to add a rule
3. Configure:
   - **Action:** Pass
   - **Interface:** WAN
   - **Protocol:** UDP
   - **Destination:** This Firewall
   - **Destination port:** 51820
   - **Description:** Allow WireGuard
4. Click **Save**
5. Click **Apply Changes**

### Allow Traffic from WireGuard Clients

This allows VPN clients to access network resources:

1. Go to **Firewall → Rules → WireGuard** (tab should now be visible)
2. Click **+** to add a rule
3. Configure:
   - **Action:** Pass
   - **Interface:** WireGuard
   - **Direction:** in
   - **TCP/IP Version:** IPv4
   - **Protocol:** any
   - **Source:** any (or specify 10.9.0.0/24 for WireGuard network only)
   - **Destination:** any
   - **Description:** Allow WireGuard client traffic
4. Click **Save**
5. Click **Apply Changes**

## Part 7: Configure Outbound NAT

**CRITICAL STEP:** Without this, VPN clients can only reach local networks, not the internet.

1. Go to **Firewall → NAT → Outbound**
2. Check current mode at the top
3. If set to "Automatic outbound NAT rule generation":
   - Change to **"Hybrid outbound NAT rule generation"**
   - Click **Save** and **Apply Changes**
4. Click **+** to add a manual outbound NAT rule
5. Configure:
   - **Interface:** WAN (your internet interface)
   - **TCP/IP Version:** IPv4
   - **Protocol:** any
   - **Source:** Network, enter `10.9.0.0/24` (your WireGuard subnet)
   - **Source Port:** any
   - **Destination:** any
   - **Destination Port:** any
   - **Translation / target:** Interface address
   - **Description:** WireGuard NAT
6. Click **Save**
7. Click **Apply Changes**

## Part 8: Enable IP Forwarding (Verify)

IP forwarding should already be enabled on OPNsense, but verify:

1. Go to **System → Settings → Tunables**
2. Look for `net.inet.ip.forwarding`
3. Verify it's set to **1**
4. If not present or set to 0, add/edit it:
   - **Tunable:** `net.inet.ip.forwarding`
   - **Value:** `1`
   - **Description:** Enable IP forwarding

## Part 9: Optional DNS Configuration

If using OPNsense as DNS server for VPN clients:

### Allow DNS Queries from WireGuard

1. Go to **Firewall → Rules → WireGuard**
2. Add a specific DNS rule (optional, covered by "any" rule above):
   - **Action:** Pass
   - **Protocol:** TCP/UDP
   - **Source:** WireGuard net
   - **Destination:** This Firewall
   - **Destination port:** 53
   - **Description:** Allow DNS queries

### Configure Unbound for WireGuard

1. Go to **Services → Unbound DNS → Access Lists**
2. Add WireGuard network (10.9.0.0/24) to allowed networks
3. Or go to **Services → Unbound DNS → General**
4. Enable **DNS Query Forwarding**
5. Add upstream DNS servers (1.1.1.1, 8.8.8.8, etc.)

## Part 10: Testing and Verification

### Connect from Client

Import your client configuration and connect. Then test:

```bash
# Check WireGuard status
sudo wg show

# Should see transfer data in both directions
# received: should show data (not 0 B)
# sent: should show data

# Test VPN gateway
ping 10.9.0.1

# Test local network (if applicable)
ping 192.168.1.1

# Test internet connectivity
ping 8.8.8.8

# Test DNS resolution
ping google.com
nslookup google.com
```

### Check OPNsense Status

1. Go to **VPN → WireGuard → Status**
2. Verify:
   - Interface is up
   - Peer is connected
   - Transfer statistics show data in both directions

### Troubleshooting

**Connection established but can't ping gateway:**

- Verify WireGuard service is running (System → Diagnostics → Services)
- Check firewall rules on WireGuard interface
- Verify interface is assigned

**Can ping gateway but not internet:**

- Check Outbound NAT configuration
- Verify NAT rule for WireGuard subnet exists

**Slow DNS resolution:**

- Use public DNS servers in client config (1.1.1.1, 8.8.8.8)
- Or optimize Unbound DNS with fast upstream servers

**No data received (0 B):**

- Check firewall rules allow traffic
- Verify Outbound NAT is configured
- Check WireGuard logfile for errors

## Security Considerations

1. **Change default subnet:** Consider using a non-standard subnet instead of 10.9.0.0/24
2. **Limit access:** Configure specific firewall rules instead of "any" to limit what VPN clients can access
3. **Monitor connections:** Regularly check VPN → WireGuard → Status for unexpected peers
4. **Rotate keys:** Periodically regenerate keys for enhanced security
5. **Use strong endpoints:** Consider using a domain name with Dynamic DNS instead of raw IP

## Network Topology

```
Internet
    ↓
WAN Interface (97.235.59.83:51820)
    ↓
OPNsense Firewall
    ↓
WireGuard Instance (10.9.0.1/24)
    ↓
VPN Clients (10.9.0.2, 10.9.0.3, etc.)
    ↓
Local Network (192.168.1.0/24) ← Optional access
```

## Common Configuration Scenarios

### Scenario 1: Full Tunnel VPN (All Traffic Through VPN)

```ini
AllowedIPs = 0.0.0.0/0
DNS = 1.1.1.1, 1.0.0.1
```

### Scenario 2: Split Tunnel (Only Home Network Through VPN)

```ini
AllowedIPs = 10.9.0.0/24, 192.168.1.0/24
# Don't set DNS, use local DNS
```

### Scenario 3: Privacy-Focused (All DNS Through VPN)

```ini
AllowedIPs = 0.0.0.0/0
DNS = 10.9.0.1
```

## Summary Checklist

- [ ] WireGuard plugin installed
- [ ] Instance created with tunnel address and port
- [ ] **Master "Enable WireGuard" checkbox enabled**
- [ ] Client peer configured with allowed IPs
- [ ] WireGuard service running
- [ ] Interface assigned in OPNsense
- [ ] WAN firewall rule allows UDP 51820
- [ ] WireGuard interface firewall rules allow traffic
- [ ] **Outbound NAT configured for WireGuard subnet**
- [ ] IP forwarding enabled
- [ ] DNS configured (public or OPNsense)
- [ ] Client configuration created with proper DNS
- [ ] Connection tested (ping gateway, internet, DNS)

## Additional Resources

- OPNsense WireGuard Documentation: <https://docs.opnsense.org/manual/how-tos/wireguard-client.html>
- WireGuard Official Site: <https://www.wireguard.com/>
- OPNsense Forums: <https://forum.opnsense.org/>

---

*Last Updated: October 2025*
*Tested on: OPNsense 25.7.6-amd64, FreeBSD 14.3-RELEASE-p4*
