# OPNsense Dnsmasq + Unbound Configuration (Option A)

## Architecture Overview

Unbound runs on port 53 as the primary recursive resolver for all clients. Dnsmasq runs on port 53053 handling DHCP and local DNS only. Clients point at Unbound for DNS. When a query matches the local domain, Unbound forwards it to Dnsmasq and returns the answer transparently.

```
Client → Unbound :53 → Internet DNS (public queries)
                    → Dnsmasq :53053 (local domain + PTR queries)
Client → Dnsmasq :53053 (DHCP requests)
```

---

## Step 1 — Dnsmasq General Settings

**Services → Dnsmasq DNS & DHCP → General**

| Setting | Value |
|---|---|
| Enable | checked |
| Interface | LAN (your LAN interface) |
| Listen Port | `53053` |
| DHCP Authoritative | checked |
| DHCP fqdn | checked |
| DHCP default domain | `home.lan` (your chosen local domain) |
| Do not forward to system defined DNS | checked |
| Do not forward private reverse lookup | checked |

> **Do not forward to system defined DNS** prevents Dnsmasq from re-forwarding unknown local queries upstream, which would cause a loop. Set this when Unbound is forwarding local zones to Dnsmasq.

---

## Step 2 — DHCP Range

**Services → Dnsmasq DNS & DHCP → DHCP Ranges**

| Field | Value |
|---|---|
| Interface | LAN |
| Range start | `192.168.1.10` (adjust to your subnet) |
| Range end | `192.168.1.254` |
| Lease time | `86400` (24 hours) |

> Unlike ISC/Kea, Dnsmasq reservations must fall **inside** the range. Reserved IPs are fully locked out of the dynamic pool automatically — they will not be offered to other clients. Size your range to include all addresses you intend to reserve.

---

## Step 3 — DHCP Options

**Services → Dnsmasq DNS & DHCP → DHCP Options**

Add one row per option. All rows use the same interface.

| Interface | Type | Option | Value | Force |
|---|---|---|---|---|
| LAN | Set | `3` | `192.168.1.1` | unchecked |
| LAN | Set | `6` | `192.168.1.1` | checked |
| LAN | Set | `15` | `home.lan` | unchecked |

- Option `3` — default gateway
- Option `6` — DNS server (points clients at Unbound, not Dnsmasq directly). Force checked to override any client-supplied DNS.
- Option `15` — domain name suffix

Leave **Option6**, **Tag**, and **Description** fields blank for a standard home setup.

---

## Step 4 — Unbound Query Forwarding

**Services → Unbound DNS → Query Forwarding**

Add two entries per subnet — one for forward lookups, one for reverse (PTR) lookups.

| Domain | Server IP | Server Port |
|---|---|---|
| `home.lan` | `127.0.0.1` | `53053` |
| `1.168.192.in-addr.arpa` | `127.0.0.1` | `53053` |

Adjust the in-addr.arpa entry to match your subnet:

- `/24` subnet `192.168.1.x` → `1.168.192.in-addr.arpa`
- `/24` subnet `192.168.10.x` → `10.168.192.in-addr.arpa`
- All of `192.168.x.x` → `168.192.in-addr.arpa` (covers entire /16)

---

## Step 5 — Static Reservations (DHCP + DNS)

**Services → Dnsmasq DNS & DHCP → Hosts**

Host entries serve dual purpose: DHCP reservation when a MAC and IP are provided, and DNS record regardless. There is no separate DNS configuration needed for reserved hosts — Dnsmasq registers them automatically.

### DHCP reservation (device with fixed IP)

| Field | Value |
|---|---|
| IP address | `192.168.1.20` |
| MAC address | `aa:bb:cc:dd:ee:ff` |
| Hostname | `nas` |
| Domain | `home.lan` |

### DNS-only record (no DHCP, e.g. a CNAME for a service)

| Field | Value |
|---|---|
| IP address | *(leave blank)* |
| MAC address | *(leave blank)* |
| Hostname | `files` |
| Domain | `home.lan` |
| CNAME | `nas.home.lan` |

> Leave IP and MAC blank for pure DNS entries. Dnsmasq will not attempt DHCP for these records.

---

## Step 6 — CNAME Records for Reverse Proxy / Containers

For a server running multiple containers behind an nginx reverse proxy, use CNAMEs rather than aliases. One host entry holds the server's IP reservation; each service gets its own DNS-only entry pointing to it.

**Primary host entry** (with DHCP reservation):

| Field | Value |
|---|---|
| IP address | `192.168.1.10` |
| MAC address | `aa:bb:cc:dd:ee:ff` |
| Hostname | `server` |
| Domain | `home.lan` |

**Per-service CNAME entries** (DNS only, no IP or MAC):

| Hostname | Domain | CNAME |
|---|---|---|
| `portainer` | `home.lan` | `server.home.lan` |
| `grafana` | `home.lan` | `server.home.lan` |
| `heimdall` | `home.lan` | `server.home.lan` |

If the server IP changes, update only the primary host entry — all CNAMEs resolve through it automatically.

**Alias vs CNAME:**

| | Alias | CNAME |
|---|---|---|
| DNS record type | A record (stores IP directly) | CNAME record (stores target name) |
| IP change requires | Update every alias | Update primary host only |
| Best for | Simple alternate names | Services behind a reverse proxy |

---

## Step 7 — Disable ISC DHCP

1. **Services → ISC DHCPv4 → [Interface]** — uncheck Enable, save. Repeat for each interface and for ISC DHCPv6 if used.
2. **Services → Unbound DNS → Overrides → Host Overrides** — remove any entries that duplicated ISC reservations. Dnsmasq handles these now.
3. **Services → Unbound DNS → General** — disable the ISC DHCP lease registration script (`unbound_watcher`) if it was enabled.
4. **System → Diagnostics → Services** — confirm only Dnsmasq DNS/DHCP is active for DHCP. ISC should not be running.
5. *(Optional)* **System → Firmware → Plugins** — uninstall `os-isc-dhcp` to remove the end-of-life package entirely.

---

## Reference — How Queries Resolve

| Query type | Path |
|---|---|
| `google.com` | Client → Unbound → Internet DNS |
| `nas.home.lan` | Client → Unbound → Dnsmasq (returns A record) |
| `192.168.1.20` PTR | Client → Unbound → Dnsmasq (returns hostname) |
| `files.home.lan` CNAME | Client → Unbound → Dnsmasq (returns CNAME → A record) |
| DHCP lease request | Client → Dnsmasq :67 directly |

---

## Notes

- Clients always point at Unbound (`192.168.1.1:53`) for DNS — never directly at Dnsmasq. The forwarding rules in Unbound handle routing local queries transparently.
- Dynamic leases are automatically registered in Dnsmasq DNS as long as the client sends a hostname in its DHCP request. No restart or sync required.
- Dnsmasq does not need to be restarted when adding new host entries — changes apply on save.
- ISC DHCP required reservations outside the pool. Dnsmasq requires them inside. Account for this when setting range bounds.