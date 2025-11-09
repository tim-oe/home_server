# OPNsense Certificate for PiKVM Setup Guide

This guide walks through creating a proper SSL/TLS certificate in OPNsense and deploying it to PiKVM.

## Prerequisites

- OPNsense firewall with a Certificate Authority (CA) already created
- CA certificate imported and trusted in your browser
- SSH access to your PiKVM
- Hostname or IP address you'll use to access PiKVM

## Part 1: Create Certificate in OPNsense

### Step 1: Navigate to Certificate Management

1. Log into OPNsense web interface
2. Go to **System > Trust > Certificates**
3. Click the **+** button to add a new certificate

### Step 2: Configure Certificate Settings

Fill in the following fields:

**Method:** `Create an internal Certificate`

**Descriptive name:** `PiKVM-tec-kvm` (or whatever you prefer)

**Certificate authority:** Select your internal CA (e.g., "internal CA")

**Type:** `Server Certificate`

**Common Name (CN):** `tec-kvm` (use your PiKVM's hostname)

**Country Code:** Your country (e.g., `US`)

**State or Province:** Your state (e.g., `IL`)

**City:** Your city (e.g., `ALTON`)

**Organization:** Your organization (e.g., `network`)

**Organizational Unit:** Purpose/description (e.g., `desktop.kvm`)

**Email Address:** Your email

### Step 3: Configure Subject Alternative Names (CRITICAL)

This is the most important part. Click **+ Add** under Alternative Names and add:

1. **Type:** `DNS`, **Value:** `tec-kvm` (your hostname)
2. **Type:** `DNS`, **Value:** `tec-kvm.localdomain` (FQDN variant)
3. **Type:** `DNS`, **Value:** `tec-kvm.local` (if using .local)
4. **Type:** `IP`, **Value:** `192.168.x.x` (if accessing by IP)

> **Note:** Add every possible way you might access the PiKVM. Modern browsers require matching SAN entries.

### Step 4: Additional Settings

**Lifetime:** `730` days (2 years, or your preference)

**Digest Algorithm:** `SHA256` (recommended)

**Key length:** `2048` bits minimum (or `4096` for better security)

**Key Type:** `RSA`

### Step 5: Create the Certificate

Click **Save** to generate the certificate.

## Part 2: Export Certificate and Key

### Step 1: Export Server Certificate

1. In **System > Trust > Certificates**, find your newly created certificate
2. Click the download icon next to the certificate
3. Save as `server.crt`

### Step 2: Export Private Key

1. Click the key icon next to the certificate to export the private key
2. Save as `server.key`
3. **Keep this file secure** - never share it

## Part 3: Deploy to PiKVM

### Step 1: Transfer Files to PiKVM

Use SCP, SFTP, or copy/paste to get the files to your PiKVM. Example using SCP:

```bash
scp server.crt server.key root@tec-kvm:/root/
```

### Step 2: Install Certificate on PiKVM

SSH into your PiKVM and run:

```bash
# Make filesystem writable
rw

# Backup existing certificates
cp /etc/kvmd/nginx/ssl/server.crt /etc/kvmd/nginx/ssl/server.crt.backup
cp /etc/kvmd/nginx/ssl/server.key /etc/kvmd/nginx/ssl/server.key.backup

# Move new certificate files into place
mv /root/server.crt /etc/kvmd/nginx/ssl/server.crt
mv /root/server.key /etc/kvmd/nginx/ssl/server.key

# Set correct ownership
chown root:root /etc/kvmd/nginx/ssl/server.crt
chown root:root /etc/kvmd/nginx/ssl/server.key

# Set correct permissions
chmod 644 /etc/kvmd/nginx/ssl/server.crt
chmod 600 /etc/kvmd/nginx/ssl/server.key
```

### Step 3: Verify Certificate

Check that the certificate was installed correctly:

```bash
# View certificate details
openssl x509 -in /etc/kvmd/nginx/ssl/server.crt -text -noout | head -20

# Verify Subject Alternative Names
openssl x509 -in /etc/kvmd/nginx/ssl/server.crt -text -noout | grep -A2 "Subject Alternative Name"

# Test private key
openssl rsa -in /etc/kvmd/nginx/ssl/server.key -check
```

You should see your SANs listed (DNS:tec-kvm, DNS:tec-kvm.localdomain, etc.)

### Step 4: Restart Services

```bash
# Restart nginx to load new certificate
systemctl restart kvmd-nginx

# Check service status
systemctl status kvmd-nginx

# Make filesystem read-only again
ro
```

## Part 4: Verify in Browser

### Step 1: Ensure CA is Trusted

1. Open Chrome/Edge: **Settings > Privacy and security > Security > Manage certificates**
2. Go to **Authorities** tab
3. Verify your "internal CA" is listed and trusted for websites
4. If not, import your CA certificate and check "Trust this certificate for identifying websites"

### Step 2: Access PiKVM

Navigate to `https://tec-kvm` (or whatever hostname you used)

You should see:
- Green padlock in address bar
- No certificate warnings
- Certificate shows as issued by your internal CA

### Step 3: View Certificate Details

Click the padlock > Certificate > Details to verify:
- Common Name matches your hostname
- Subject Alternative Names are present
- Issued by your internal CA
- Valid dates are correct

## Troubleshooting

### Error: ERR_CERT_COMMON_NAME_INVALID

**Cause:** Hostname in browser doesn't match CN or SAN entries

**Solution:** Access PiKVM using exact name in certificate, or regenerate cert with correct SAN

### Error: "Scrambled Credentials"

**Cause:** Corrupted certificate file or missing certificate chain

**Solution:** 
- Re-export and re-upload certificate from OPNsense
- Ensure certificate file isn't corrupted during transfer
- May need to append CA certificate to server certificate

### Error: Certificate Not Trusted

**Cause:** CA certificate not installed in browser

**Solution:**
- Export CA from **System > Trust > Authorities** in OPNsense
- Import to browser's trusted authorities
- Restart browser

### Service Won't Start

Check nginx logs:
```bash
journalctl -u kvmd-nginx -n 50
```

Common issues:
- Incorrect file permissions
- Mismatched certificate and private key
- Syntax errors in nginx config

## Certificate Renewal

Certificates typically expire in 1-2 years. To renew:

1. In OPNsense, create a new certificate (or renew existing)
2. Export new certificate and key
3. Repeat Part 3 (Deploy to PiKVM)
4. No browser changes needed if using same CA

## Security Notes

- Never share your private key file (server.key)
- Use 2048-bit or higher key length
- Keep certificate validity period reasonable (1-2 years)
- Store CA private key securely in OPNsense
- Regularly backup your CA and certificates
- Use `ro` command on PiKVM when not making changes to protect SD card

## Additional Resources

- PiKVM Documentation: https://docs.pikvm.org
- OPNsense Documentation: https://docs.opnsense.org
- OpenSSL Certificate Verification: `man openssl-verify`