# WireGuard VPN Setup Guide

## OPNsense Server and Linux Client Configuration

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [OPNsense Server Configuration](#opnsense-server-configuration)
3. [Linux Client Configuration](#linux-client-configuration)
4. [Testing and Verification](#testing-and-verification)
5. [Management and Troubleshooting](#management-and-troubleshooting)

---

## Prerequisites

### OPNsense Requirements

- OPNsense 21.1 or later
- Public IP address or Dynamic DNS hostname
- UDP port 51820 accessible from internet

### Linux Client Requirements

- Linux distribution with WireGuard support
- Root/sudo access
- WireGuard tools installed

### Network Planning

- Choose a VPN subnet different from your LAN (e.g., `10.9.0.0/24`)
- Plan IP assignments for each client
- Example used in this guide:
  - Server (OPNsense): `10.9.0.1/24`
  - Client: `10.9.0.2/32`

---

## OPNsense Server Configuration

### Step 1: Enable WireGuard

1. Navigate to **VPN → WireGuard → Settings**
2. Check **Enable WireGuard**
3. Click **Save**

### Step 2: Create WireGuard Instance (Server)

1. Navigate to **VPN → WireGuard → Instances**
2. Click **+** to add new instance
3. Configure the following:
   - **Name**: `wg0` (or preferred name)
   - **Public Key/Private Key**: Click the gear icon to generate keypair
   - **Listen Port**: `51820` (default)
   - **Tunnel Address**: `10.9.0.1/24`
   - **Peers**: Leave empty for now
4. Click **Save**
5. **Important**: Copy the **Public Key** - you'll need this for client configuration

### Step 3: Configure Firewall Rules

#### WAN Rule (Allow Incoming VPN Connections)

1. Navigate to **Firewall → Rules → WAN**
2. Click **+** to add rule
3. Configure:
   - **Action**: Pass
   - **Interface**: WAN
   - **Protocol**: UDP
   - **Destination**: WAN address
   - **Destination Port**: `51820`
   - **Description**: "WireGuard VPN"
4. Click **Save**
5. Click **Apply Changes**

#### WireGuard Interface Rules (Allow VPN Traffic)

1. Navigate to **Firewall → Rules → WireGuard** (group)
2. Click **+** to add rule
3. Configure:
   - **Action**: Pass
   - **Protocol**: Any
   - **Source**: WireGuard net (or `10.9.0.0/24`)
   - **Destination**: Any
   - **Description**: "Allow WireGuard clients to LAN"
4. Click **Save**
5. Click **Apply Changes**

### Step 4: Verify Outbound NAT

1. Navigate to **Firewall → NAT → Outbound**
2. If set to **Automatic**, no action needed
3. If set to **Manual/Hybrid**, add rule for WireGuard subnet `10.9.0.0/24`

---

## Linux Client Configuration

### Step 1: Install WireGuard

```bash
sudo apt update
sudo apt install wireguard resolvconf
```

### Step 2: Generate Client Keypair

```bash
# Generate private key and derive public key
wg genkey | tee privatekey | wg pubkey > publickey

# View the keys
cat privatekey  # Keep this SECRET
cat publickey   # This goes to OPNsense
```

**Important**: Keep the private key secure and never share it.

### Step 3: Add Client Peer in OPNsense

1. Navigate to **VPN → WireGuard → Peers**
2. Click **+** to add new peer
3. Configure the peer with the following fields:
4. Click **Save**
5. Click **Apply Changes**

#### Required Fields

- **Enabled**: ✓ (checked)
- **Name**: `client1` (descriptive name for your reference, e.g., "johns-laptop")
- **Public Key**: Paste the client's public key from Step 2
  - **Important**: This is the client's PUBLIC key, not the server's
  - Get this from the `publickey` file you generated on the Linux client
  - No generate wheel available here - must be generated on client first
- **Allowed IPs**: `10.9.0.2/32`
  - This is the VPN IP address assigned to this specific client
  - Must be unique for each peer
  - Use /32 for single IP assignment
- **Instance**: Select `wg0` (your WireGuard instance)

#### Optional Fields

- **Pre-shared Key**: Click generate wheel icon (recommended for additional security)
  - Provides post-quantum protection
  - **Copy this PSK** - you'll need it for client config file
  - If generated, must be added to client config
- **Endpoint Address**: Leave BLANK for road warrior (mobile) clients
  - Only use if client has static public IP
  - Only needed for site-to-site VPNs
- **Endpoint Port**: Leave BLANK for road warrior clients
  - Only use with static endpoint address
  - Only needed for site-to-site VPNs
- **Keepalive**: Leave default or blank
  - Client config handles this with PersistentKeepalive

#### Additional Settings

- **Description**: Optional text field for notes about this peer

#### Peer Configuration Summary

| Field | Road Warrior Client | Site-to-Site |
|-------|-------------------|--------------|
| Enabled | ✓ | ✓ |
| Name | Descriptive | Descriptive |
| Public Key | Client's public key | Remote site public key |
| Allowed IPs | Single IP (x.x.x.x/32) | Remote subnet |
| Endpoint Address | BLANK | Remote public IP |
| Endpoint Port | BLANK | Remote port |
| Pre-shared Key | Generate (optional) | Generate (optional) |
| Instance | Select server instance | Select server instance |

### Step 4: Create Client Configuration File

Create the config file:

```bash
sudo nano /etc/wireguard/wg-client.conf
```

Add the following configuration:

```ini
[Interface]
PrivateKey = <paste_contents_of_privatekey_file>
Address = 10.9.0.2/32
DNS = 192.168.1.1

[Peer]
PublicKey = <server_public_key_from_OPNsense_instance>
PresharedKey = <PSK_generated_in_OPNsense>
Endpoint = wg.tecronin.uk:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
```

**Configuration Notes**:

- **PrivateKey**: Your client's private key (from Step 2)
- **Address**: Client's VPN IP address
- **DNS**: Your LAN DNS server or router IP
- **PublicKey**: Server's public key from OPNsense instance (NOT peer public key)
- **PresharedKey**: Optional, remove line if not generated
- **Endpoint**: Can be hostname (with Dynamic DNS) or public IP address
- **AllowedIPs**:
  - `0.0.0.0/0` = Route all traffic through VPN
  - `192.168.1.0/24` = Only route LAN traffic (split-tunnel)
- **PersistentKeepalive**: Keeps connection alive through NAT

### Step 5: Set Proper Permissions

```bash
sudo chmod 600 /etc/wireguard/wg-client.conf
```

This ensures only root can read the private key.

---

## Testing and Verification

### Start the VPN Connection

```bash
sudo wg-quick up wg-client
```

Expected output:

```bash
[#] ip link add wg-client type wireguard
[#] wg setconf wg-client /dev/fd/63
[#] ip -4 address add 10.9.0.2/32 dev wg-client
[#] ip link set mtu 1420 up dev wg-client
[#] resolvconf -a tun.wg-client -m 0 -x
```

### Verify Connection Status

```bash
sudo wg show
```

Successful output shows:

```bash
interface: wg-client
  public key: <your_public_key>
  private key: (hidden)
  listening port: <random_port>

peer: <server_public_key>
  endpoint: 97.187.113.124:51820
  allowed ips: 0.0.0.0/0
  latest handshake: X seconds ago        ← Key indicator!
  transfer: XX KiB received, XX KiB sent
  persistent keepalive: every 25 seconds
```

**Important**: "latest handshake" with recent timestamp means the VPN is working!

### Test Connectivity

```bash
# Ping OPNsense WireGuard gateway
ping 10.9.0.1

# Ping LAN gateway
ping 192.168.1.1

# Check public IP (should show your home IP when using AllowedIPs 0.0.0.0/0)
curl ifconfig.me

# Test DNS resolution
nslookup google.com
```

### Test from External Network

**Important**: When testing from your home network, you may experience routing issues. For proper testing:

- Connect from mobile hotspot
- Connect from different location/network
- This simulates real remote access usage

---

## Management and Troubleshooting

### Managing the Connection

```bash
# Start VPN
sudo wg-quick up wg-client

# Stop VPN
sudo wg-quick down wg-client

# Restart VPN
sudo wg-quick down wg-client && sudo wg-quick up wg-client

# Check status
sudo wg show

# Check interface status
ip a show wg-client

# Check routing
ip route
```

### Enable at Boot (Optional)

Only enable if you want VPN to auto-connect at startup:

```bash
sudo systemctl enable wg-quick@wg-client
```

To disable auto-start:

```bash
sudo systemctl disable wg-quick@wg-client
```

### Common Issues and Solutions

#### No Handshake / "handshake: (never)"

**Possible causes**:

1. Client's public key not added to OPNsense peer
2. Wrong server public key in client config (used peer key instead of instance key)
3. WAN firewall rule not active
4. WireGuard instance not enabled in OPNsense
5. Port 51820 blocked by ISP or router

**Solutions**:

- Verify peer configuration in OPNsense
- Check WAN firewall rule is enabled
- Test port accessibility: `nc -vzu wg.tecronin.uk 51820`
- Check OPNsense logs: **VPN → WireGuard → Log File**

#### DNS Resolution Fails

**Error**: `resolvconf: command not found`

**Solution**:

```bash
sudo apt install resolvconf
# or
sudo apt install openresolv
```

#### No Internet Access When Connected

**If testing from home network**: This is normal - routing loop occurs when on same network as VPN server.

**If testing from remote network**:

- Check outbound NAT in OPNsense
- Verify WireGuard interface firewall rules
- Check AllowedIPs setting in client config

#### Connection Works But Can't Access LAN

**Solutions**:

- Verify WireGuard interface firewall rules in OPNsense
- Check that AllowedIPs includes LAN subnet or 0.0.0.0/0
- Verify outbound NAT configuration

### Monitoring in OPNsense

- **Connection Status**: VPN → WireGuard → Status
- **Logs**: VPN → WireGuard → Log File
- **Active Peers**: Shows connected clients and data transfer

---

## Adding Additional Clients

For each new device:

1. Generate new keypair on the device
2. Add new peer in OPNsense with unique IP:
   - First client: `10.9.0.2/32`
   - Second client: `10.9.0.3/32`
   - Third client: `10.9.0.4/32`
   - etc.
3. Create config file with device's private key and server's public key

### Mobile Devices (iOS/Android)

1. Install WireGuard app from App Store/Play Store
2. In OPNsense: Add peer as normal
3. Click the **QR code icon** next to the peer
4. Scan with WireGuard mobile app
5. Instant configuration!

---

## Configuration Reference

### Network Details Used in This Guide

| Component | Value |
|-----------|-------|
| VPN Subnet | 10.9.0.0/24 |
| Server IP | 10.9.0.1/24 |
| Client IP | 10.9.0.2/32 |
| WireGuard Port | 51820 (UDP) |
| Endpoint | wg.tecronin.uk:51820 |
| LAN Subnet | 192.168.1.0/24 |

### Key Concepts

- **Instance**: The WireGuard server configuration on OPNsense
- **Peer**: Each client connecting to the server
- **Public/Private Keys**: Cryptographic keypairs for authentication
- **Pre-shared Key**: Optional additional security layer
- **AllowedIPs**: Determines what traffic routes through VPN
- **Endpoint**: How clients find and connect to the server
- **PersistentKeepalive**: Maintains connection through NAT/firewalls

---

## Security Best Practices

1. **Never share private keys** - Each device should have its own keypair
2. **Use pre-shared keys** - Adds post-quantum security
3. **Use DNS-only Cloudflare records** - Don't proxy WireGuard through Cloudflare
4. **Set proper file permissions** - Config files should be 600 (readable only by root)
5. **Use strong firewall rules** - Only allow necessary traffic
6. **Keep software updated** - Regularly update OPNsense and WireGuard
7. **Monitor logs** - Check for unauthorized connection attempts
8. **Use unique IPs per client** - Makes tracking and management easier

---

## Comparison: WireGuard vs OpenVPN

| Feature | WireGuard | OpenVPN |
|---------|-----------|---------|
| Setup Complexity | Simple | Complex |
| Performance | Faster | Slower |
| Code Size | ~4,000 lines | ~100,000 lines |
| Configuration | Minimal settings | Many options |
| Cryptography | Modern, fixed | Configurable ciphers |
| Mobile Handoff | Excellent | Poor |
| Certificate Management | Key pairs only | PKI/certificates |
| Firewall Rules | Simple UDP | More complex |

---

## Additional Resources

- **OPNsense Documentation**: <https://docs.opnsense.org/>
- **WireGuard Official Site**: <https://www.wireguard.com/>
- **OPNsense Support**: <https://support.opnsense.org/>
- **Anthropic Prompting Guide**: <https://docs.claude.com/>

---

## Document History

- **Created**: October 4, 2025
- **Configuration**: OPNsense with WireGuard to Linux client
- **Tested**: Debian-based Linux distribution
- **Status**: Production-ready configuration

---

*This guide documents a working WireGuard VPN configuration successfully deployed and tested with road warrior access from external networks.*
