# OPNsense Unbound DNS Setup Guide

Complete guide for configuring Unbound DNS on OPNsense, including common issues and troubleshooting steps.

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Initial Configuration](#initial-configuration)
3. [DNS Query Forwarding Setup](#dns-query-forwarding-setup)
4. [DHCP Configuration](#dhcp-configuration)
5. [Testing DNS Resolution](#testing-dns-resolution)
6. [Common Issues and Troubleshooting](#common-issues-and-troubleshooting)
7. [Advanced Configuration](#advanced-configuration)

---

## Prerequisites

### Network Setup
- OPNsense installed with LAN interface configured (e.g., 192.168.10.1/24)
- WAN interface connected to upstream network or internet
- Basic firewall rules allowing LAN traffic

### Access Requirements
- Console or SSH access to OPNsense
- Web GUI access (https://[LAN_IP])
- Default credentials after factory reset: `root` / `opnsense`

---

## Initial Configuration

### 1. Verify Interface Configuration

**GUI: Interfaces → [LAN]**
- Enable interface: ✓ Checked
- IPv4 Configuration Type: Static IPv4
- IPv4 address: `192.168.10.1` / `24` (or your chosen subnet)
- Save and Apply Changes

**Console verification:**
```bash
# Check interface status
ifconfig igc1  # Replace igc1 with your LAN interface name

# Should show:
# - inet 192.168.10.1
# - status: active
# - media: 1000baseT <full-duplex>
```

### 2. Check for Conflicting DHCP/DNS Services

**CRITICAL:** Only ONE DHCP/DNS service can run at a time.

**GUI: Services → Dnsmasq DNS**
- If enabled, **disable it**
- Dnsmasq conflicts with both Unbound and ISC DHCPv4

**GUI: Services → Dnsmasq DHCP**
- If enabled, **disable it**

**Reboot after disabling Dnsmasq:**
```bash
# From console
reboot
```

### 3. Configure System DNS Servers

**GUI: System → Settings → General**

Add public DNS servers (these will be used by Unbound for forwarding):

1. DNS Server 1: `1.1.1.1` (Cloudflare)
2. DNS Server 2: `1.0.0.1` (Cloudflare secondary)
3. DNS Server 3: `8.8.8.8` (Google - optional)
4. DNS Server 4: `8.8.4.4` (Google secondary - optional)

**Important settings:**
- Gateway: Leave as "none" or default
- **Uncheck** "Allow DNS server list to be overridden by DHCP/PPP on WAN"
  - This ensures your manual DNS servers are always used

**Save**

---

## DNS Query Forwarding Setup

### Option 1: Use System Nameservers (Recommended)

This is the most reliable method and easiest to maintain.

**GUI: Services → Unbound DNS → General**
- Enable: ✓ **Checked**
- Network Interfaces: **All** (or select LAN specifically)
- DNSSEC: ✓ Checked (optional but recommended)
- Save

**GUI: Services → Unbound DNS → Query Forwarding**
- Use System Nameservers: ✓ **Checked**
- Save and Apply

**Restart Unbound:**
- Click the **Restart** button at the top of the page

**Verify configuration:**
```bash
# Check forward-zone exists
cat /var/unbound/unbound.conf | grep -A 10 "forward-zone"

# Should show:
# forward-zone:
#   name: "."
#   forward-addr: 1.1.1.1
#   forward-addr: 1.0.0.1
#   forward-addr: 8.8.8.8
#   (etc.)

# Test DNS resolution from OPNsense
host google.com
nslookup google.com

# Should return IP addresses
```

### Option 2: Manual Forwarders (Alternative)

**Note:** This method can be problematic. Use Option 1 unless you have specific requirements.

**GUI: Services → Unbound DNS → Query Forwarding**
- Use System Nameservers: ❌ **Unchecked**
- Click **+** to add forwarders manually:
  - Server IP: `1.1.1.1`, Port: `53`, Enable: ✓
  - Server IP: `1.0.0.1`, Port: `53`, Enable: ✓
  - Server IP: `8.8.8.8`, Port: `53`, Enable: ✓
  - Server IP: `8.8.4.4`, Port: `53`, Enable: ✓
- Save and Apply

**Verify as above**

### Option 3: Recursive Mode (Privacy-Focused)

For maximum privacy, configure Unbound to query root DNS servers directly.

**GUI: Services → Unbound DNS → Query Forwarding**
- Use System Nameservers: ❌ **Unchecked**
- Remove all manual forwarders
- Save and Apply

**GUI: Services → Unbound DNS → General**
- Enable: ✓ Checked
- DNSSEC: ✓ Checked (strongly recommended for recursive mode)
- Save

**Pros:**
- Maximum privacy (no third party sees your queries)
- Direct authoritative answers
- No dependency on external DNS providers

**Cons:**
- Slower initial queries (50-200ms vs 10-30ms)
- Higher router CPU usage

---

## DHCP Configuration

### Enable ISC DHCPv4 on LAN

**GUI: Services → ISC DHCPv4 → [LAN]**

If [LAN] tab doesn't appear:
1. Verify LAN interface is enabled (Interfaces → [LAN])
2. Refresh browser or restart web GUI: `service nginx restart`

**Configuration:**
- Enable DHCP server on LAN interface: ✓ **Checked**
- Range:
  - From: `192.168.10.100`
  - To: `192.168.10.250`
- DNS servers: **Leave blank** (auto-uses OPNsense IP)
- Gateway: **Leave default** (auto-uses OPNsense IP)
- Domain name: `localdomain` (or your preference)
- Save

### Verify DHCP is Working

**Check from client:**
```bash
# Release and renew DHCP
sudo dhclient -r  # release
sudo dhclient     # renew

# Or restart network connection
sudo nmcli connection down "Connection Name"
sudo nmcli connection up "Connection Name"

# Verify IP assignment
ip addr show

# Should show IP in range 192.168.10.100-250
```

---

## Testing DNS Resolution

### From OPNsense Console

```bash
# Test DNS resolution
host google.com
nslookup google.com
drill google.com

# Should return IP addresses without errors

# Check Unbound is listening
sockstat -4 -l | grep :53

# Should show:
# unbound  unbound  [PID]  tcp4  *:53  *:*
# unbound  unbound  [PID]  udp4  *:53  *:*

# Test query to specific interface
drill google.com @192.168.10.1

# Should return successful response
```

### From Client Computer

```bash
# Check DNS configuration
cat /etc/resolv.conf
# Should show: nameserver 192.168.10.1

# Or for systemd-resolved systems
resolvectl status
# Should show DNS Server: 192.168.10.1

# Test resolution
nslookup google.com
ping google.com
nslookup google.com 192.168.10.1

# All should resolve successfully
```

---

## Common Issues and Troubleshooting

### Issue 1: SERVFAIL Errors

**Symptom:**
```bash
nslookup google.com 192.168.10.1
;; Got SERVFAIL reply from 192.168.10.1
```

**Diagnosis:**
```bash
# Check if forward-zone exists
cat /var/unbound/unbound.conf | grep -A 10 "forward-zone"
```

**Solution:**
- No forward-zone present = Query Forwarding not configured
- Enable "Use System Nameservers" in Query Forwarding
- Verify DNS servers in System → Settings → General
- Restart Unbound service

### Issue 2: Client Can't Resolve, But OPNsense Can

**Symptom:**
- `host google.com` works on OPNsense console
- Client gets SERVFAIL or timeouts

**Diagnosis:**
```bash
# Check if Unbound is listening on LAN IP
sockstat -4 -l | grep :53

# Monitor queries (run on OPNsense, query from client)
tcpdump -i igc1 -n port 53
```

**Solutions:**

**A. Access Control Issue**

GUI: Services → Unbound DNS → Access Lists
- Add entry for LAN subnet:
  - Network: `192.168.10.0/24`
  - Action: **Allow**
  - Save

**B. Firewall Blocking DNS**

GUI: Firewall → Rules → LAN
- Verify rule exists allowing LAN to ANY
- If missing, add:
  - Action: Pass
  - Interface: LAN
  - Protocol: Any
  - Source: LAN net
  - Destination: Any

**C. Interface Binding Issue**

GUI: Services → Unbound DNS → General
- Network Interfaces: Change from "LAN" to **"All"**
- Save and restart service

### Issue 3: systemd-resolved Interference (Linux Clients)

**Symptom:**
```bash
cat /etc/resolv.conf
nameserver 127.0.0.53  # Still showing local stub resolver
```

**Solution A: Configure systemd-resolved**
```bash
sudo nano /etc/systemd/resolved.conf
```

Add:
```
[Resolve]
DNS=192.168.10.1
Domains=localdomain
```

Restart:
```bash
sudo systemctl restart systemd-resolved
```

**Solution B: Bypass systemd-resolved**
```bash
# Stop and disable systemd-resolved
sudo systemctl stop systemd-resolved
sudo systemctl disable systemd-resolved

# Remove stub resolver symlink
sudo rm /etc/resolv.conf

# Create direct resolv.conf
sudo nano /etc/resolv.conf
```

Add:
```
nameserver 192.168.10.1
search localdomain
```

Make immutable:
```bash
sudo chattr +i /etc/resolv.conf
```

**Solution C: Use resolvectl**
```bash
# Set DNS directly for interface
sudo resolvectl dns [interface-name] 192.168.10.1

# Verify
resolvectl status
```

### Issue 4: Routing Conflict (Multiple IPs on Same Subnet)

**Symptom:**
```bash
netstat -rn | grep 192.168.10
# Shows route pointing to wrong interface (e.g., ix10 instead of igc1)
```

**Diagnosis:**
```bash
# Check all interfaces for conflicting IPs
ifconfig -a | grep -A 5 "192.168.10"
```

**Solution:**
```bash
# Remove IP from conflicting interface
ifconfig ix10 inet 192.168.10.x delete
ifconfig ix10 down

# Verify route now points to correct interface
netstat -rn | grep 192.168.10
# Should show igc1 (or your LAN interface)
```

**Permanent fix in GUI:**
- Interfaces → Assignments
- Find conflicting interface
- Either unassign it or change its IP to different subnet

### Issue 5: Dnsmasq Still Running

**Symptom:**
```bash
sockstat -4 -l | grep :53
# Shows dnsmasq instead of unbound
```

**Solution:**
- Services → Dnsmasq DNS → Disable
- Services → Dnsmasq DHCP → Disable
- Reboot: `reboot`
- Verify only Unbound is running

### Issue 6: WAN Interface Can't Reach Upstream DNS

**Symptom:**
- OPNsense console can't resolve: `host google.com` fails
- But client queries reach OPNsense (visible in tcpdump)

**Diagnosis:**
```bash
# Can OPNsense reach upstream network?
ping 192.168.1.1  # Your upstream router
ping 8.8.8.8      # Internet

# Check WAN interface status
ifconfig [wan-interface]
```

**Solution:**
- Verify WAN interface has IP and gateway
- Interfaces → [WAN] → Check configuration
- Test connectivity to upstream DNS servers
- Check firewall rules on WAN (should allow outbound DNS)

### Issue 7: DNS Works But Websites Don't Load

**Symptom:**
- `nslookup google.com` works
- `ping google.com` works
- Browser shows "can't connect"

**Diagnosis:**
```bash
# Check if HTTP/HTTPS traffic is blocked
curl -I https://google.com
telnet google.com 443
```

**Solution:**
- Firewall → Rules → LAN
- Verify rule allows ALL protocols (not just DNS)
- Check NAT rules: Firewall → NAT → Outbound
- Should have automatic outbound NAT or manual rules for LAN

---

## Advanced Configuration

### Access Lists for Specific Networks

**GUI: Services → Unbound DNS → Access Lists**

Example configurations:

**Allow LAN:**
- Access List name: `LAN Network`
- Networks: `192.168.10.0/24`
- Action: Allow

**Deny specific subnet:**
- Access List name: `Guest Network Block`
- Networks: `192.168.20.0/24`
- Action: Deny

**Allow specific IPs only:**
- Access List name: `Admin Only`
- Networks: `192.168.10.5/32`, `192.168.10.10/32`
- Action: Allow
- (Then add a deny-all rule for `192.168.10.0/24`)

### Custom DNS Overrides

**GUI: Services → Unbound DNS → Overrides → Host Overrides**

Use for local hostname resolution:

- Host: `server`
- Domain: `localdomain`
- IP: `192.168.10.50`

Now `server.localdomain` resolves to 192.168.10.50

### DNSSEC Configuration

**GUI: Services → Unbound DNS → Advanced**

- Harden DNSSEC data: ✓ Checked
- DNSSEC: ✓ Checked

**Test DNSSEC:**
```bash
# From OPNsense
drill sigfail.verteiltesysteme.net  # Should FAIL (invalid DNSSEC)
drill sigok.verteiltesysteme.net    # Should SUCCEED (valid DNSSEC)
```

### Performance Tuning

**GUI: Services → Unbound DNS → Advanced**

For high-traffic networks:

- Number of threads: `4` (or number of CPU cores)
- Unwanted Reply Threshold: `10000000`
- Message Cache Size: `50m`
- RRset Cache Size: `100m`
- Outgoing Range: `4096`
- Number of Queries Per Thread: `2048`
- Jostle Timeout: `200`

### Logging and Monitoring

**Enable query logging:**

GUI: Services → Unbound DNS → Advanced
- Log Level: `1` (operational info) or `2` (detailed queries)

**View logs:**
```bash
# Real-time monitoring
tail -f /var/log/resolver.log

# Search for specific domain
grep "google.com" /var/log/resolver.log

# Count queries per client
grep "query:" /var/log/resolver.log | awk '{print $6}' | sort | uniq -c | sort -rn
```

---

## Configuration Checklist

Use this checklist when setting up or troubleshooting:

### Initial Setup
- [ ] LAN interface configured with static IP
- [ ] Dnsmasq disabled (both DNS and DHCP)
- [ ] System DNS servers configured (System → Settings → General)
- [ ] Unbound enabled (Services → Unbound DNS → General)
- [ ] Query Forwarding configured ("Use System Nameservers" checked)
- [ ] Unbound service restarted

### DHCP Setup
- [ ] ISC DHCPv4 enabled on LAN
- [ ] DHCP range configured
- [ ] DNS and gateway left blank (auto-configured)

### Testing
- [ ] `host google.com` works from OPNsense console
- [ ] `sockstat -4 -l | grep :53` shows unbound listening
- [ ] `cat /var/unbound/unbound.conf | grep forward-zone` shows forwarders
- [ ] Client receives DHCP address in correct range
- [ ] Client's resolv.conf shows 192.168.10.1 as DNS
- [ ] `nslookup google.com` works from client
- [ ] Websites load in browser

### Firewall Rules
- [ ] LAN → Any rule exists (allows all outbound)
- [ ] NAT configured for internet access

---

## Quick Reference Commands

### OPNsense Console

```bash
# Check interfaces
ifconfig
ifconfig igc1

# Test DNS
host google.com
nslookup google.com
drill google.com @192.168.10.1

# Check Unbound
sockstat -4 -l | grep :53
service unbound status
service unbound restart

# View configuration
cat /var/unbound/unbound.conf | grep -A 10 "forward-zone"
cat /var/unbound/unbound.conf | grep "interface:"
cat /var/unbound/unbound.conf | grep -A 5 "access-control"

# Monitor DNS queries
tail -f /var/log/resolver.log
tcpdump -i igc1 -n port 53

# Check routing
netstat -rn
route -n get 192.168.10.200

# Restart services
service unbound restart
service dhcpd restart
```

### Client (Linux)

```bash
# Network configuration
ip addr show
ip route show
nmcli connection show

# DNS configuration
cat /etc/resolv.conf
resolvectl status

# Test DNS
nslookup google.com
nslookup google.com 192.168.10.1
dig google.com
host google.com

# DHCP
sudo dhclient -r  # release
sudo dhclient     # renew

# Network restart
sudo nmcli connection down "Connection-Name"
sudo nmcli connection up "Connection-Name"
```

---

## Migration from Main Router to OPNsense

When replacing your main router with this OPNsense setup:

### Pre-Migration
- [ ] DNS already pointing to public servers (1.1.1.1, 8.8.8.8)
- [ ] All LAN configuration tested and working
- [ ] DHCP range doesn't conflict with existing network
- [ ] Document current ISP connection settings (DHCP/PPPoE/Static)

### During Migration
1. **Configure WAN**: Interfaces → [WAN] → Set for ISP type
2. **Physical swap**: Disconnect old router WAN, connect OPNsense WAN to modem
3. **Test connectivity**: Verify internet works from OPNsense console
4. **Client testing**: Clients should get DHCP and have internet

### Post-Migration
- [ ] DNS resolution working from clients
- [ ] Internet access working
- [ ] All expected devices received DHCP leases
- [ ] Check Services → ISC DHCPv4 → Leases to verify

### Rollback Plan
- Keep old router powered off but connected
- If issues occur, swap cables back
- Old router should work immediately

---

## Additional Resources

- OPNsense Documentation: https://docs.opnsense.org
- Unbound DNS Documentation: https://nlnetlabs.nl/documentation/unbound/
- OPNsense Forum: https://forum.opnsense.org
- RFC 1918 Private Networks: 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16

---

## Summary

A properly configured Unbound DNS setup requires:

1. **Single DHCP/DNS service** (disable Dnsmasq)
2. **System DNS servers** configured (for forwarding)
3. **Query Forwarding enabled** ("Use System Nameservers")
4. **Access control** allowing LAN subnet
5. **Client DHCP** properly configured to use OPNsense as gateway and DNS

The most reliable configuration is:
- Use System Nameservers: ✓ Enabled
- Public DNS servers (1.1.1.1, 8.8.8.8) in System Settings
- ISC DHCPv4 for client configuration
- Standard LAN firewall rules allowing all outbound traffic

This provides a stable, maintainable DNS infrastructure for your network.