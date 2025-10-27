# OPNsense Certificate Authority and Certificate Setup Guide

Complete guide for creating and trusting self-signed certificates for OPNsense web GUI access.

## Table of Contents
- [Prerequisites](#prerequisites)
- [Part 1: Create Certificate Authority in OPNsense](#part-1-create-certificate-authority-in-opnsense)
- [Part 2: Create Web GUI Certificate](#part-2-create-web-gui-certificate)
- [Part 3: Apply Certificate to Web GUI](#part-3-apply-certificate-to-web-gui)
- [Part 4: Install CA on Linux](#part-4-install-ca-on-linux)
- [Part 5: Install CA in Firefox](#part-5-install-ca-in-firefox)
- [Part 6: Install CA in Chrome](#part-6-install-ca-in-chrome)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

- Administrative access to OPNsense
- Root/sudo access on Linux client computers
- Decide how you'll access OPNsense (IP address and/or hostname)

---

## Part 1: Create Certificate Authority in OPNsense

The Certificate Authority (CA) is what signs your certificates and needs to be trusted by client computers.

1. Log into OPNsense web GUI
2. Navigate to **System → Trust → Authorities**
3. Click the **+** (Add) button
4. Fill in the following fields:

   | Field | Value | Notes |
   |-------|-------|-------|
   | **Descriptive name** | `Internal CA` | Or any name you prefer |
   | **Method** | Create an internal Certificate Authority | |
   | **Key Type** | RSA | |
   | **Key Length** | 2048 or 4096 bits | 4096 is more secure |
   | **Digest Algorithm** | SHA256 or SHA512 | |
   | **Lifetime** | 3650 days (10 years) | Long lifetime for CAs |
   | **Country Code** | US | Your 2-letter country code |
   | **State/Province** | Your state | |
   | **City** | Your city | |
   | **Organization** | `Home Network` | Or your organization name |
   | **Organizational Unit** | Optional | Can leave blank |
   | **Email Address** | Your email | |
   | **Common Name** | `Internal CA` | Must be unique |

5. Click **Save**

### Export the CA Certificate

1. Stay on **System → Trust → Authorities**
2. Find your newly created CA
3. Click the **download** icon (📥)
4. Save the file (it will download as a `.pem` file)
5. Rename it to something memorable like `internal-ca.crt` or `internal-ca.pem`

---

## Part 2: Create Web GUI Certificate

Now create a certificate for the OPNsense web interface, signed by your CA.

1. Navigate to **System → Trust → Certificates**
2. Click the **+** (Add) button
3. Fill in the following fields:

   | Field | Value | Notes |
   |-------|-------|-------|
   | **Method** | Create an internal Certificate | |
   | **Descriptive name** | `OPNsense WebGUI` | Or any descriptive name |
   | **Certificate authority** | Select your CA | The one you just created |
   | **Type** | Server Certificate | |
   | **Key Type** | RSA | |
   | **Key Length** | 2048 bits | Sufficient for most use cases |
   | **Digest Algorithm** | SHA256 | |
   | **Lifetime** | 825 days or less | Browsers enforce maximum lifetimes |
   | **Country Code** | US | Match your CA or use your own |
   | **State/Province** | Your state | |
   | **City** | Your city | |
   | **Organization** | `Home Network` | |
   | **Organizational Unit** | Optional | Can use "Web GUI" or leave blank |
   | **Email Address** | Your email | |
   | **Common Name** | `opnsense` or hostname | Your router's hostname |

4. **CRITICAL: Alternative Names Section**
   
   Modern browsers **require** the Subject Alternative Name (SAN) field. Add **all** ways you access OPNsense:
   
   **Important Note:** OPNsense may only allow you to use **one type** of alternative name (either DNS names OR IP addresses, not both). If you need both, choose DNS names and always access via hostname.
   
   - **For hostname access:** In the "DNS domain names" field, add:
     ```
     opnsense.localdomain,opnsense,opnsense.local
     ```
     (Adjust to match your actual hostnames - comma-separated or as the UI requires)
   
   - **For IP access only:** In the "IP address" field, add:
     ```
     192.168.1.1
     ```
     (Use your actual OPNsense IP)
   
   - **URIs:** Leave empty (not needed for web GUI)

5. Click **Save**

### Verify Certificate Details

```bash
# From a Linux machine, check what certificate OPNsense is serving
openssl s_client -connect 192.168.1.1:443 -showcerts < /dev/null 2>/dev/null | openssl x509 -noout -text | grep -A 5 "Subject Alternative Name"
```

---

## Part 3: Apply Certificate to Web GUI

1. Navigate to **System → Settings → Administration**
2. Under **SSL Certificate**, select your new certificate from the dropdown
3. Click **Save**
4. Your browser will disconnect - this is normal
5. Reconnect to the OPNsense GUI using the same URL

---

## Part 4: Install CA on Linux

The CA certificate must be installed in the system certificate store.

### Ubuntu/Debian/Mint

```bash
# Copy the CA certificate to the system store
sudo cp internal-ca.crt /usr/local/share/ca-certificates/

# Ensure it has .crt extension (required)
sudo mv /usr/local/share/ca-certificates/internal-ca.pem /usr/local/share/ca-certificates/internal-ca.crt

# Update the certificate store
sudo update-ca-certificates

# Verify it was added (should show "1 added")
# Check it's in the system bundle
ls -la /etc/ssl/certs/ | grep internal-ca
```

### Fedora/RHEL/CentOS

```bash
# Copy to system trust store
sudo cp internal-ca.crt /etc/pki/ca-trust/source/anchors/

# Update certificates
sudo update-ca-trust

# Verify
ls -la /etc/pki/ca-trust/source/anchors/
```

### Arch Linux

```bash
# Copy to system trust store
sudo cp internal-ca.crt /etc/ca-certificates/trust-source/anchors/

# Update certificates
sudo trust extract-compat

# Verify
ls -la /etc/ca-certificates/trust-source/anchors/
```

### Verify System Installation

```bash
# Check the certificate is valid
openssl x509 -in /usr/local/share/ca-certificates/internal-ca.crt -text -noout | grep -A 3 "Basic Constraints"

# Should show: CA:TRUE
```

---

## Part 5: Install CA in Firefox

Firefox uses its own certificate store and **does not** use system certificates.

### Import CA into Firefox

1. Open Firefox
2. Navigate to **Settings** (or type `about:preferences` in the address bar)
3. Search for **"certificates"** in the settings search box
4. Click **View Certificates**
5. Go to the **Authorities** tab
6. Click **Import**
7. Browse to your CA certificate file (`.pem` or `.crt`)
8. **Check the box:** "Trust this CA to identify websites"
9. Click **OK**
10. **Restart Firefox** completely (close all windows)

### Verify in Firefox

1. Visit your OPNsense URL (e.g., `https://opnsense.localdomain/`)
2. Click the padlock icon
3. Click **"Connection secure"** → **"More information"**
4. Click **"View Certificate"**
5. Verify your CA appears in the certificate chain

---

## Part 6: Install CA in Chrome

Chrome on Linux uses the NSS certificate database, which is separate from the system store.

### Install NSS Tools

```bash
# Ubuntu/Debian
sudo apt install libnss3-tools

# Fedora/RHEL
sudo dnf install nss-tools

# Arch
sudo pacman -S nss
```

### Import CA into Chrome's NSS Database

```bash
# Create NSS database if it doesn't exist
mkdir -p ~/.pki/nssdb
certutil -d sql:$HOME/.pki/nssdb -N  # Only if database doesn't exist

# Import the CA certificate
certutil -d sql:$HOME/.pki/nssdb -A -t "CT,C,C" -n "Internal-CA-OPNsense" -i /usr/local/share/ca-certificates/internal-ca.crt

# Verify it was added
certutil -d sql:$HOME/.pki/nssdb -L
```

**Trust flags explained:**
- `C` = Trusted for SSL/TLS
- `T` = Trusted for email
- `C` = Trusted for object signing

### Restart Chrome

```bash
# Kill all Chrome processes
pkill -9 chrome

# Clear cache (optional but recommended)
rm -rf ~/.cache/google-chrome/Default/Cache/*

# Start Chrome
google-chrome
```

### Verify in Chrome

1. Visit your OPNsense URL
2. Click the padlock icon → **"Connection is secure"**
3. Click the certificate icon
4. Verify the certificate is valid and shows your CA in the chain

---

## Troubleshooting

### Chrome: ERR_CERT_AUTHORITY_INVALID

**Problem:** Chrome doesn't trust the certificate even after system installation.

**Solutions:**

1. **Check if CA is in NSS database:**
   ```bash
   certutil -d sql:$HOME/.pki/nssdb -L
   ```
   If your CA isn't listed, import it using the Chrome installation steps above.

2. **Check for nickname conflicts:**
   ```bash
   certutil -d sql:$HOME/.pki/nssdb -L | grep -i internal
   ```
   If you have multiple CAs with similar names, they might conflict. Delete old ones:
   ```bash
   certutil -d sql:$HOME/.pki/nssdb -D -n "old-ca-nickname"
   ```

3. **Verify the correct certificate is being served:**
   ```bash
   openssl s_client -connect 192.168.1.1:443 -showcerts < /dev/null 2>/dev/null | openssl x509 -noout -text | grep "Serial Number" -A 2
   ```
   Compare the serial number with what you see in OPNsense under System → Trust → Certificates.

4. **Clear Chrome's HSTS cache:**
   - Go to `chrome://net-internals/#hsts`
   - Under "Delete domain security policies", enter your domain/IP
   - Click **Delete**
   - Restart Chrome

5. **Completely restart Chrome:**
   ```bash
   pkill -9 chrome
   rm -rf ~/.cache/google-chrome/Default/Cache/*
   google-chrome
   ```

### Firefox: Certificate Not Trusted

**Problem:** Firefox shows certificate error even after importing CA.

**Solutions:**

1. **Verify CA was imported correctly:**
   - Settings → Privacy & Security → Certificates → View Certificates
   - Authorities tab → Look for your CA
   - Make sure "This certificate can identify websites" is checked

2. **Re-import the CA:**
   - Delete the existing CA from Firefox's authorities list
   - Re-import and ensure you check "Trust this CA to identify websites"
   - Restart Firefox completely

3. **Check the certificate chain:**
   - Visit the OPNsense URL
   - Click the padlock → Connection not secure → More information → View Certificate
   - Verify the issuer matches your CA

### Subject Alternative Name (SAN) Mismatch

**Problem:** Certificate error when accessing by IP or different hostname.

**Symptoms:**
- Works with `https://opnsense.localdomain/`
- Fails with `https://192.168.1.1/` or `https://opnsense/`

**Solution:**

The certificate's Subject Alternative Name must include all access methods. Recreate the certificate with all required SANs:

```bash
# Check what SANs are currently in the certificate
openssl s_client -connect 192.168.1.1:443 -showcerts < /dev/null 2>/dev/null | openssl x509 -noout -text | grep -A 5 "Subject Alternative Name"
```

If missing, recreate the certificate in OPNsense with all required DNS names and IPs in the Alternative Names section.

**Note:** Due to OPNsense UI limitations, you may only be able to add DNS names OR IP addresses, not both. In this case:
- Use DNS names in the certificate
- Always access OPNsense via hostname
- Configure DNS/hosts file if needed

### System Certificate Store Not Working

**Problem:** Certificate added to system store but browsers still don't trust it.

**Solutions:**

1. **Verify certificate has correct permissions:**
   ```bash
   ls -l /usr/local/share/ca-certificates/
   # Should be readable by all users
   sudo chmod 644 /usr/local/share/ca-certificates/internal-ca.crt
   ```

2. **Verify certificate is valid:**
   ```bash
   openssl x509 -in /usr/local/share/ca-certificates/internal-ca.crt -text -noout | grep "CA:TRUE"
   ```
   Must show `CA:TRUE` in Basic Constraints.

3. **Re-run update command:**
   ```bash
   sudo update-ca-certificates --fresh --verbose
   ```

4. **Check symlink was created:**
   ```bash
   ls -la /etc/ssl/certs/ | grep internal-ca
   ```
   Should show a symlink pointing to your certificate.

### Certificate Shows Wrong Issuer

**Problem:** Browser shows certificate is issued by unknown authority.

**Solutions:**

1. **Verify certificate chain on server:**
   ```bash
   openssl s_client -connect 192.168.1.1:443 -showcerts < /dev/null
   ```
   Should show TWO certificates:
   - Server certificate (fort-apache or similar)
   - CA certificate (Internal CA)

2. **Check certificate applied in OPNsense:**
   - System → Settings → Administration
   - Verify correct certificate is selected
   - Save and reconnect

3. **Verify CA signed the certificate:**
   ```bash
   # In OPNsense, System → Trust → Certificates
   # Check the certificate details - Issuer should match your CA's Common Name
   ```

### OPNsense Alternative Names Not Persisting

**Problem:** Adding DNS names causes IP address to disappear, or vice versa.

**This is a known OPNsense limitation.** The UI may only allow one type of alternative name.

**Workaround:**
1. Choose DNS names over IP addresses (more flexible)
2. Add all hostname variations you use
3. Always access OPNsense via hostname
4. If needed, add local DNS or hosts file entries

**Linux hosts file:**
```bash
sudo nano /etc/hosts

# Add line:
192.168.1.1  opnsense.localdomain opnsense
```

### Testing Certificate Trust

**Verify system trusts the CA:**
```bash
openssl verify -CAfile /etc/ssl/certs/ca-certificates.crt /path/to/server-cert.pem
```

**Check certificate from command line:**
```bash
curl -v https://192.168.1.1/
# Should NOT show certificate errors if properly trusted
```

**View full certificate details:**
```bash
openssl s_client -connect 192.168.1.1:443 -showcerts < /dev/null 2>/dev/null | openssl x509 -noout -text
```

### Multiple Devices

For each additional computer/phone/tablet:
1. Copy the CA certificate file to the device
2. Follow the appropriate installation steps for that device's OS
3. Firefox on any device requires manual import (doesn't use system store)

---

## Summary

1. **Create CA** in OPNsense (System → Trust → Authorities)
2. **Create certificate** signed by CA (System → Trust → Certificates)
   - **Must include** Subject Alternative Names (SAN)
3. **Apply certificate** to web GUI (System → Settings → Administration)
4. **Install CA** on Linux system certificate store
5. **Install CA** in Firefox (manual import required)
6. **Install CA** in Chrome's NSS database (Linux-specific)

## Key Points

- Modern browsers **require** Subject Alternative Names (SAN) - Common Name alone is not enough
- Firefox always needs manual CA import (doesn't use system certificates)
- Chrome on Linux needs CA in NSS database (doesn't automatically use system certificates)
- Always restart browsers completely after importing certificates
- Certificate must include all hostnames/IPs you'll use to access OPNsense
- CA certificates should have long lifetimes (10 years); server certificates should be shorter (2 years or less)

---

*Last updated: October 2025*