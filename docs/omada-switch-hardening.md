# Omada Switch Hardening

Lockdown walkthrough for the two `TP-Link Omada SG2210XMP-M2` switches, run in **standalone mode** (no
Omada controller). Design decisions and ordering live in
[`.cursor/plan/switch-hardening.md`](../.cursor/plan/switch-hardening.md); this document is the click path.

| Switch | Name | Site | Notes |
|---|---|---|---|
| Site A | `tec-sw-a` | carries the LAN | **Live.** Powers `tec-pi-mgr` and AP 1 over PoE |
| Site B | `tec-sw-b` | the desk | Live |

Both hold static DHCP reservations by MAC in Dnsmasq (`192.168.1.2`–`.120`), per
[`dmsaqdns.md`](dmsaqdns.md). Neither carries a switch-side static address — they stay DHCP clients so the
reservation and the DNS record stay in one place.

> **Menu paths are from the Omada smart switch web UI.** Firmware revisions shuffle pages occasionally. If
> a path below does not exist, the page is almost always one level away under the same top-level menu.
> Older JetStream firmware nests the `SECURITY` pages under `System → Access Security` instead.

## Contents

1. [Read this first: the Save Config trap](#read-this-first-the-save-config-trap)
2. [Part 1: Make configuration survive a reboot](#part-1-make-configuration-survive-a-reboot)
3. [Part 2: Accounts and management protocols](#part-2-accounts-and-management-protocols)
4. [Part 3: HTTPS hardening and a trusted certificate](#part-3-https-hardening-and-a-trusted-certificate)
5. [Part 4: Rogue DHCP and traffic defences](#part-4-rogue-dhcp-and-traffic-defences)
6. [Part 5: Port-level hardening](#part-5-port-level-hardening)
7. [Part 6: Deferred until VLANs exist](#part-6-deferred-until-vlans-exist)
8. [Verification](#verification)
9. [Troubleshooting](#troubleshooting)
10. [Deliberately not done](#deliberately-not-done)

---

## Read this first: the Save Config trap

The switch holds **two** configuration files:

- **Running config** — what the switch is doing now. **Apply** writes here. Volatile.
- **Startup config** — what the switch loads at boot. Only the **Save** button writes here.

Clicking **Apply** and walking away means the change is gone at the next reboot, with no warning and no
diff.

**This is confirmed here, not theoretical.** It was first noticed after a firmware update, but it also
reproduced on a **plain reboot after entering static IP assignments**, with no firmware involved. Treat
every setting entered on either switch before reading this as unsaved.

- **GUI:** the **Save** button on the main interface, top right. Press it after every change set.
- **CLI:** `copy running-config startup-config`

The switch also has **Dual Image and Dual Configuration**, so a firmware upgrade can leave it booting the
*backup* image. Confirm the running version before re-entering anything.

> **Site A reboots cut power to `tec-pi-mgr`.** Several steps below end in a reboot. Either confirm
> **Perpetual PoE** is enabled *and saved* first (Part 1), or shut the Pi down cleanly rather than pulling
> power from a running SSD.

---

## Part 1: Make configuration survive a reboot

Do this on both switches before entering anything else worth keeping.

### 1. Prove persistence deliberately

1. Set the device name: **SYSTEM → System Info → Device Description**. Use `tec-sw-a` / `tec-sw-b`.
   Both switches ship named `SG2210XMP-M2`, which collides in Dnsmasq because it keys the DNS record off
   the DHCP hostname — the second lease silently overwrites the first.
2. Click **Save**.
3. Reboot: **SYSTEM → System Tools → System Reboot**.
4. Log back in and confirm the name survived.

If it did not survive, stop and resolve that before continuing. Nothing else in this document is worth
doing on a switch that cannot keep a setting.

### 2. Confirm the firmware image

**SYSTEM → System Info → System Summary** for the running version, and **SYSTEM → System Tools** for the
boot file / image selection. Verify the running image is the version you installed and that the same image
is set to boot next.

This is a *second, independent* way to lose configuration, separate from the Save trap above. TP-Link's own
guidance: firmware upgrades normally preserve configuration, but **skipping many versions can lose it**, and
a new switch jumping several releases at once does exactly that. Treat post-upgrade config as suspect and
re-verify rather than assume.

### 3. Re-check PoE after any config loss

**SYSTEM → PoE → PoE Config** for the ports serving `tec-pi-mgr` and AP 1:

| Setting | Value |
|---|---|
| PoE status | Enable |
| Power limit / class | **802.3at (Class 4, 30W)** — the Pi 5 HAT requires `at`, not `af` |
| Priority | High |
| Perpetual PoE | Enable |

A Class 3 (15.4W) negotiation boots a Pi 5 and then browns it out under SSD load, which reads as random
instability rather than a power problem. Confirm the port reports **Class 4**.

Perpetual PoE is what keeps powered devices alive through a switch firmware reboot. Enable it before the
certificate reboot in Part 3.

### 4. Export a config backup

**SYSTEM → System Tools → Config Backup**. Save off-switch, one file per switch, with the firmware version
in the filename. Repeat after every change set.

This is also what makes either switch a cold spare for the other: restore Site A's export onto Site B and
only the port map and management address need changing.

---

## Part 2: Accounts and management protocols

No dependency on VLANs. Safe on the flat network as it stands.

### 1. Replace the default admin account

**SYSTEM → User Management → User Config**. The default account is `admin` / `admin` and cannot be deleted,
so change its password.

Use a **different** password on each switch, stored in Vaultwarden. Identical firmware means one credential
pattern otherwise reaches both sites, and the passwords being distinct is the only part of that which
actually buys anything.

The switch has four access levels (Admin, Operator, Power User, User). Creating anything below Admin also
requires an Enable Password under **SECURITY → AAA**, which is more machinery than a two-switch network
needs. One Admin account per switch is fine.

### 2. Never adopt into an Omada controller

This is the sharpest lockout risk on the device, and it is one accidental click in the Omada app.

- Adoption **pushes a default configuration over your standalone config**, including the VLAN interface.
  On a switch whose management address lives in a non-default VLAN, that is a lockout.
- Worse: **the GUI and CLI are inaccessible entirely while the switch is controller-managed.** Recovery
  means forgetting the device on the controller, which resets the switch.

Disable cloud access and any controller/cloud enrolment option in the UI rather than leaving it merely
unused. These switches are deliberately standalone — UniFi is already the second management plane and a
third earns nothing on two 8-port switches.

### 3. Turn off the plaintext management paths

| Page | Setting |
|---|---|
| **SECURITY → Access Security → HTTP Config** | HTTP **Disable** |
| **SECURITY → Access Security → Telnet Config** | Telnet **Disable** |
| **SECURITY → Access Security → SSH Config** | SSH **Disable** unless you will use it. If enabled: v2 only, never v1 |

HTTP is enabled on port 80 by default. Telnet is plaintext CLI on the device that controls your layer 2 —
there is no argument for leaving it on.

Do **not** disable HTTPS in the same sitting as HTTP unless you have console access; that combination
leaves no management path at all.

### 4. Confirm time is correct

**SYSTEM → System Info → System Time**. DHCP option 42 already points at OPNsense per
[`dmsaqdns.md`](dmsaqdns.md), so this should be right already. Without correct time, switch logs are not
evidence of anything.

### 5. SNMP stays off

**MAINTENANCE → SNMP → Global Config** — leave SNMP disabled.

If switch metrics are wanted in Prometheus later, that is an `snmp_exporter` job and **v3 only**
(**MAINTENANCE → SNMP → SNMP v3**). Note that this is a separate path from the `unpoller` job in
[`unifi-os-monitoring.md`](../.cursor/plan/unifi-os-monitoring.md), which covers UniFi devices and will
never see these switches.

**Save** before moving on.

---

## Part 3: HTTPS hardening and a trusted certificate

Everything on this page is **SECURITY → Access Security → HTTPS Config**.

### 1. Fix the protocol version and cipher suites first

This is the highest-value item in this document per minute spent, and it needs no certificate work at all.
**The factory defaults are bad:**

| Setting | Default | Set to |
|---|---|---|
| Protocol Version | **All** — includes SSL 3.0, TLS 1.0, TLS 1.1 | **TLS Version 1.2** |
| `RSA_WITH_RC4_128_MD5` | Enabled | **Disable** |
| `RSA_WITH_RC4_128_SHA` | Enabled | **Disable** |
| `RSA_WITH_DES_CBC_SHA` | Enabled | **Disable** |
| `RSA_WITH_3DES_EDE_CBC_SHA` | Enabled | **Disable** |
| `ECDHE_WITH_AES_128_GCM_SHA256` | Enabled | Keep |
| `ECDHE_WITH_AES_256_GCM_SHA384` | Enabled | Keep |
| Session Timeout | 10 minutes | 5–10 minutes |

The two `ECDHE_WITH_AES_*_GCM` suites work with an RSA certificate, so pruning the rest costs nothing.

**TLS 1.2 is the ceiling on this hardware** — there is no TLS 1.3 option. That is acceptable for a LAN
management interface reachable only from Management, and it is a reason not to widen who can reach it.

Optionally enable **Number Control** on the same page to cap concurrent admin sessions.

### 2. Issue a certificate from the OPNsense Internal CA

The switches are `.localdomain` names, so no public CA can issue for them. Use the Internal CA from
[`opnsense-cert-guide.md`](opnsense-cert-guide.md) — already trusted by the hosts that administer OPNsense,
which are the same hosts that administer these.

In OPNsense, **System → Trust → Certificates → + Add**, once per switch:

| Field | Value |
|---|---|
| Method | Create an internal Certificate |
| Descriptive name | `tec-sw-a WebGUI` |
| Certificate authority | your Internal CA |
| Type | **Server Certificate** |
| Key Type / Length | **RSA 2048** — not ECDSA |
| Digest | SHA256 |
| Lifetime | **825 days or less** |
| Common Name | `tec-sw-a.localdomain` |
| Alternative Names, DNS | `tec-sw-a.localdomain`, `tec-sw-a` |

The SAN field is not optional — modern browsers ignore Common Name entirely. As
[`opnsense-cert-guide.md`](opnsense-cert-guide.md) notes, OPNsense may only accept one *type* of
alternative name, so prefer DNS names and always reach the switch by name.

Then export both halves from **System → Trust → Certificates**:

- the certificate (`.crt`)
- the private key (`.key`)

Both come out PEM, which is the BASE64 encoding the switch requires.

### 3. Upload to the switch

Back on **SECURITY → Access Security → HTTPS Config**, scroll to the **Load Certificate** and **Load Key**
sections:

1. **Certificate File** — the exported `.crt`
2. **Key File** — the exported `.key`
3. Apply

The certificate and key **must match each other** or HTTPS stops working entirely. Keep console or a second
management path available until you have confirmed the new certificate loads.

4. **Save.**
5. **Reboot.** On most firmware the certificate does not take effect until the switch restarts, and Save
   must happen first or the upload goes with everything else. Site A: Perpetual PoE from Part 1 step 3.

### 4. Record the result

Write the fingerprint and the **expiry date** into `docs/network-layout.md` alongside each switch's
reserved address and config-backup location.

Renewal is manual — re-issue, re-upload, reboot — on an 825-day clock, and **nothing in this repo will
remind you.** The date being written down is the entire mitigation.

---

## Part 4: Rogue DHCP and traffic defences

None of this needs VLANs.

### 1. DHCP Filter — the one to do today

This blocks rogue and accidental DHCP servers, which is the flat network's most open door: any device that
starts handing out leases currently wins races against OPNsense.

1. **SECURITY → DHCP Filter → DHCPv4 Filter → Basic Config** — enable the filter globally, then enable
   **Status** on the access ports.
2. **SECURITY → DHCP Filter → DHCPv4 Filter → Legal DHCPv4 Servers → Create**:

   | Field | Value |
   |---|---|
   | Server IP | `192.168.1.1` (OPNsense) |
   | Client MAC | `all` |
   | Interface | the port facing OPNsense |

Get the interface right — naming the wrong port blocks legitimate DHCP for everything downstream. Test with
one client before saving and walking away.

### 2. DoS Defend

**SECURITY → DoS Defend** — enable. No downside on a network this size.

### 3. Storm control, then loopback detection

Order matters, and the vendor guidance is explicit: **enable storm control before loopback detection**.

1. **QoS → Bandwidth Control → Storm Control** — broadcast and multicast limits on access ports.
2. **L2 FEATURES → Switching → Port → Loopback Detection** — enable.

Do not apply storm control to the trunk or the 10G inter-site link.

**Save.**

---

## Part 5: Port-level hardening

### 1. Port Security on fixed devices

**SECURITY → Port Security** — cap the MAC count on ports serving devices that do not move (`tec-pi-mgr`,
AP 1, the Pi fleet). Up to 64 MACs per port are supported; the point is a low limit, not a high one.

Note the switch **will not run 802.1X and Port Security at the same time**. Since 802.1X is out of scope
here (see below), Port Security is free to use.

Do not apply it to the AP ports if the AP bridges client MACs, or to the trunk.

### 2. Port Isolation at Site B

**L2 FEATURES → Switching → Port → Port Isolation**. Site B holds a rotating cast of devices; isolate
anything with no reason to talk to its neighbours. This separates ports *within* a VLAN, so it is useful
now and still useful after segmentation.

### 3. Close the unused ports

- **Admin-down** every port not in use.
- **Disable PoE** on every port not serving a device you chose to power (**SYSTEM → PoE → PoE Config**).

A PoE port only energises after a PD negotiates, so the PoE half is hygiene rather than a hole being
closed. It belongs with the admin-down rule: an unknown device in a spare port should get neither trust nor
power.

### 4. No routing, on either switch

Both models advertise static routing and inter-VLAN routing. **Leave both off.** Traffic routed by a switch
never reaches OPNsense, so none of the firewall policy in
[`vlan-segmentation.md`](../.cursor/plan/vlan-segmentation.md) would apply to it. OPNsense is the only
router and the only enforcement point.

**Save, then export a fresh config backup.**

---

## Part 6: Deferred until VLANs exist

These three belong in [`vlan-segmentation.md`](../.cursor/plan/vlan-segmentation.md)'s phases, not here,
and the first two happen on the physical console with the `igc1` rescue port already proven.

1. **Move management onto the Management VLAN interface** (VLAN 50) via
   **SYSTEM → System Info → System IP**, and drop the VLAN 1 interface. Highest-value item, and the one
   most likely to lock you out — it severs your own session by design.
2. **Scope management access control** to Management plus the VPN range:
   **SECURITY → Access Security → Access Control**, which filters by IP, MAC, or port. This page works
   today if you restrict to specific admin host addresses, but those hosts then need DHCP reservations, and
   a typo locks you out. It is far more useful once there is a segment to name.
3. **IP-MAC binding tier, last and separately:**
   - **SECURITY → IPv4 IMPB → IP-MAC Binding** — build the table via DHCP Snooping, ARP Scanning, or
     manual entries.
   - **SECURITY → IPv4 IMPB → ARP Detection** — then enable, with the OPNsense-facing port trusted.
   - **SECURITY → IPv4 IMPB → IPv4 Source Guard** — last.

   Both ARP Detection and Source Guard **break statically addressed hosts** that have no binding entry. The
   NAS IPMI is the obvious one to check first. Not worth a mid-cutover outage, which is why they are last.

---

## Verification

```bash
# issuer must be the Internal CA, SAN must contain the FQDN,
# and notAfter must match what is recorded in docs/network-layout.md
for sw in tec-sw-a tec-sw-b; do
  echo "== $sw"
  openssl s_client -connect $sw.localdomain:443 -showcerts </dev/null 2>/dev/null \
    | openssl x509 -noout -issuer -subject -dates -ext subjectAltName
done

# TLS 1.0 and 1.1 must now fail, 1.2 must succeed
openssl s_client -connect tec-sw-a.localdomain:443 -tls1_1 </dev/null 2>&1 | tail -3
openssl s_client -connect tec-sw-a.localdomain:443 -tls1_2 </dev/null 2>&1 | grep -i "Protocol\|Cipher"

# both reservations resolve; no lease named SG2210XMP-M2 should remain in Dnsmasq
dig +short tec-sw-a.localdomain tec-sw-b.localdomain

# plaintext management must be gone
for sw in tec-sw-a tec-sw-b; do
  nc -z -w2 $sw.localdomain 80 && echo "OPEN http $sw" || echo "closed http $sw"
  nc -z -w2 $sw.localdomain 23 && echo "OPEN telnet $sw" || echo "closed telnet $sw"
done
```

- A change survives Save plus reboot, per switch.
- Running firmware matches what was installed, and the next-boot image is the same one.
- Both UIs load with **no browser warning** from a host trusting the Internal CA.
- `tec-pi-mgr`'s port reports **Class 4**, stays up under SSD load, and survives a switch reboot with
  Perpetual PoE on.
- A second DHCP server plugged into an access port hands out nothing, and legitimate clients still get
  leases from OPNsense.
- A current config export exists off-switch for both switches.
- Neither switch has static routing or inter-VLAN routing enabled.
- After Part 6: the UIs are unreachable from a Clients host and an IoT host, reachable from the admin host
  and over the VPN.

---

## Troubleshooting

**Settings vanished after a reboot.** The running config was never saved. Re-enter and press **Save**. If
they vanish even after saving, check the boot image selection under **SYSTEM → System Tools** — the switch
may be loading a different configuration alongside the backup firmware image.

**HTTPS broke after uploading the certificate.** The certificate and key do not match, or the key is not
BASE64/PEM. Re-export both from the same OPNsense certificate entry. Recover over console, or reset and
restore the config backup from Part 1 step 4.

**Browser still warns after the upload.** Either the switch has not rebooted, the CA is not in that
browser's trust store (see [`opnsense-cert-guide.md`](opnsense-cert-guide.md) Parts 4–6), or the SAN does
not contain the name you typed in the address bar. Check with the `openssl` command above.

**Clients stopped getting DHCP leases.** The DHCP Filter legal-server entry names the wrong port. Disable
the filter globally, fix the interface, re-enable.

**Locked out of the web UI.** Console cable first. Failing that, reset the switch and restore the config
backup — which is why Part 1 step 4 comes before everything else.

**`tec-pi-mgr` died during a reboot.** Perpetual PoE was not enabled, or was enabled but never saved.

---

## Deliberately not done

- **802.1X** (**SECURITY → 802.1x**) needs a RADIUS server, which does not exist here. It is also mutually
  exclusive with Port Security, which is more useful on a small static network. Ruled out rather than left
  as a permanent someday item.
- **ACLs** (**SECURITY → ACL**) can express most of the firewall policy, and should not. OPNsense is the
  single enforcement point; policy split across two devices is policy nobody can audit.
- **Syslog off-box.** Both switches log locally via **MAINTENANCE → Logs**, which means the logs are lost
  on reboot — precisely the event you want to investigate. Sending syslog to OPNsense is the obvious fix.
  **Known gap**, not solved here.
- **IPv6 Source Guard** would need the SDM template changed to EnterpriseV6 (**SYSTEM → SDM Template**),
  which is a reboot and a table-size trade-off for no benefit on an IPv4-only LAN.
