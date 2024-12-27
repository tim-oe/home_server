# Setting up OpenVPN on OPNsense

## Prerequisites
- OPNsense installed and configured with internet access
- Admin access to OPNsense web interface
- Basic understanding of networking concepts

## Step 1: Create Certificate Authority (CA)
1. Navigate to System > Trust > Authorities
2. Click the + button to add a new CA
3. Fill in the following:
   - Descriptor: "OpenVPN-CA" (or your preferred name)
   - Method: Create Internal CA
   - Key Length: 2048 bits (or 4096 for higher security)
   - Lifetime: 3650 (10 years)
   - Common Name: Your desired CA name
4. Save the CA

## Step 2: Create Server Certificate
1. Go to System > Trust > Certificates
2. Click + to create a new certificate
3. Configure the following:
   - Method: Create Internal Certificate
   - Descriptor: "OpenVPN-Server-Cert"
   - Certificate Authority: Select the CA created in Step 1
   - Type: Server Certificate
   - Key Length: 2048 bits
   - Lifetime: 3650
   - Common Name: Your server name
4. Save the certificate

## Step 3: Configure OpenVPN Server
1. Navigate to VPN > OpenVPN > Servers
2. Click + to add a new server
3. Configure these essential settings:
   - Description: "Home VPN Server"
   - Server Mode: Remote Access (SSL/TLS + User Auth)
   - Protocol: UDP
   - Device Mode: tun
   - Interface: WAN
   - Local Port: 1194 (default)
   - TLS Authentication: Enable
   - Peer Certificate Authority: Select your CA
   - Server Certificate: Select your server certificate
   - Encryption algorithm: AES-256-GCM
   - IPv4 Tunnel Network: 10.0.8.0/24 (or your preferred subnet)
   - IPv4 Local Network: Your LAN subnet (e.g., 192.168.1.0/24)
   - Concurrent Connections: Set as needed
4. Save the server configuration

## Step 4: Create Client Certificate
1. Return to System > Trust > Certificates
2. Create a new certificate:
   - Method: Create Internal Certificate
   - Descriptor: "OpenVPN-Client-Cert"
   - Certificate Authority: Your CA
   - Type: Client Certificate
   - Key Length: 2048 bits
   - Common Name: Client name

## Step 5: Configure Firewall Rules
1. Go to Firewall > Rules > WAN
2. Add a new rule:
   - Action: Pass
   - Interface: WAN
   - Protocol: UDP
   - Destination Port: 1194 (or your chosen port)
   - Description: "Allow OpenVPN"
3. Add rules in the OpenVPN tab to allow traffic from VPN to LAN

## Step 6: Export Client Configuration
1. Go to VPN > OpenVPN > Client Export
2. Select your client configuration options:
   - Remote Access Server: Your VPN server
   - Hostname: Your public IP or dynamic DNS
   - Port: 1194 (or your chosen port)
3. Download the client configuration file (.ovpn)

## Step 7: Setup Client
1. Install OpenVPN client on your device
2. Import the .ovpn file
3. Connect to your VPN

## Troubleshooting Tips
- Check firewall logs for blocked connections
- Verify port forwarding on your router if needed
- Ensure correct subnet configuration
- Check OpenVPN server logs for connection issues
- Verify certificates are properly created and signed

## Security Recommendations
1. Use strong encryption (AES-256-GCM)
2. Enable TLS Authentication
3. Use certificate authentication + user authentication
4. Regularly update OPNsense
5. Use strong passwords for user authentication
6. Consider implementing 2FA
7. Regularly audit VPN access logs
