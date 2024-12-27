# Setting up OpenVPN Instances on OPNsense

## Prerequisites
- OPNsense 22.1 or newer
- Admin access to OPNsense
- Internet connectivity

## Step 1: Create Certificate Authority and Certificates
1. Go to System > Trust > Authorities
2. Click + to create new CA:
   - Descriptor: "VPN-CA"
   - Method: Create Internal CA
   - Key Length: 2048 or 4096
   - Lifetime: 3650
   - Common Name: Your CA name

3. Go to System > Trust > Certificates
4. Create Server Certificate:
   - Descriptor: "VPN-Server-Cert"
   - Method: Create Internal Certificate
   - Certificate Authority: Select your CA
   - Type: Server Certificate
   - Key Length: 2048 or 4096
   - Common Name: Your server name

## Step 2: Create OpenVPN Instance
1. Navigate to VPN > OpenVPN > Instances
2. Click + to add new instance
3. Basic Configuration:
   - Description: "Home VPN"
   - Role: Server
   - Status: Enabled
   - Protocol: UDP
   - Port: 1194 (default)
   - Interface: WAN

4. Instance Configuration:
   - Device Mode: tun
   - Topology: subnet
   - IPv4 Tunnel Network: 10.8.0.0/24
   - IPv4 Local Network: Your LAN subnet
   - IPv4 Remote Network: Leave blank for client access
   - Concurrent Connections: Set as needed

5. Cryptographic Settings:
   - TLS Setup: Enabled
   - Certificate Authority: Select your CA
   - Server Certificate: Select your server certificate
   - Auth-Type: username/password + certificate
   - DH Parameters Length: 2048
   - Encryption Algorithm: AES-256-GCM
   - Auth Algorithm: SHA256
   - Certificate Depth: 1

6. Tunnel Settings:
   - Compression: Disabled (for security)
   - Push Register DNS: Enabled
   - DNS Servers: Your preferred DNS
   - Redirect Gateway: Enable if you want all client traffic through VPN
   - Client-to-Client: Enable if clients need to communicate

7. Save the instance configuration

## Step 3: Create Client Specific Overrides (Optional)
1. Go to VPN > OpenVPN > Client Specific Overrides
2. Click + to add new override:
   - Servers: Select your instance
   - Common Name: Match client certificate CN
   - IPv4 Address: Static IP if needed
   - Additional custom options as needed

## Step 4: Setup Firewall Rules
1. Go to Firewall > Rules > WAN
2. Add new rule:
   - Action: Pass
   - Interface: WAN
   - Protocol: UDP
   - Destination Port: 1194
   - Description: "OpenVPN Access"

3. Go to Firewall > Rules > OpenVPN
4. Add new rule:
   - Action: Pass
   - Interface: OpenVPN
   - Source: OpenVPN net
   - Destination: LAN net
   - Description: "Allow VPN to LAN"

## Step 5: Create Client Certificates
1. System > Trust > Certificates
2. Create client certificate:
   - Descriptor: "VPN-Client-1"
   - Method: Create Internal Certificate
   - Certificate Authority: Your CA
   - Type: Client Certificate
   - Key Length: 2048
   - Common Name: Unique client name

## Step 6: Export Client Configuration
1. Go to VPN > OpenVPN > Export Client
2. Select settings:
   - Instance: Your VPN instance
   - Client Certificate: Select client cert
   - Hostname: Your public IP/DNS
   - Port: 1194
3. Download configuration file

## Step 7: Setup User Authentication
1. Go to System > Access > Users
2. Create or modify user:
   - Username: VPN user
   - Password: Strong password
   - Certificates: Assign client cert
3. Enable VPN access for user

## Important Security Considerations
1. Use strong passwords
2. Implement 2FA if possible
3. Regular certificate rotation
4. Monitor VPN logs
5. Keep OPNsense updated
6. Use modern encryption standards
7. Consider implementing RADIUS

## Troubleshooting
1. Check Instance Status:
   - VPN > OpenVPN > Status
   - View active connections
   - Check service status

2. Common Issues:
   - Certificate problems: Check CA chain
   - Network connectivity: Verify firewall rules
   - Authentication issues: Check user permissions
   - Routing problems: Verify tunnel network settings
