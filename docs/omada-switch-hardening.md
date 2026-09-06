# Omada Switch Hardening

Lockdown walkthrough for the two `TP-Link Omada SG2210XMP-M2` switches, run in **standalone mode** (no
Omada controller). Design decisions and ordering live in
[`.cursor/plan/switch-hardening.md`](../.cursor/plan/switch-hardening.md); this document is the click path.

| Switch | Name | Address | Site | Notes |
|---|---|---|---|---|
| Site A | `tec-sw-a` | `192.168.1.2` | carries the LAN | **Live.** Powers `tec-pi-mgr` (Tw1/0/1) and AP 1 (Tw1/0/8) over PoE |
| Site B | `tec-sw-b` | `192.168.1.3` | the desk | Live |

Applied state, MAC, firmware and certificate dates: [`network-layout.md`](network-layout.md).
Automation account is `cursor` (Admin) with `CURSOR_SW_PWD`; SSH v2 is left on for it.

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

**SYSTEM → PoE → PoE Config** for the ports serving `tec-pi-mgr` (Tw1/0/1) and AP 1 (Tw1/0/8):

| Setting | Value |
|---|---|
| PoE Status | Enable |
| Power Limit | **Class4 (30 W)** — the Pi 5 HAT requires `at`, not `af` |
| PoE Priority | High |

A Class 3 (15.4W) negotiation boots a Pi 5 and then browns it out under SSD load, which reads as random
instability rather than a power problem. Confirm the port reports **Class 4** and Power Status **On**.

**This firmware (1.0.27) has no Perpetual PoE control** in the GUI or the CLI. The nearby page
**SYSTEM → PoE → PoE Auto Recovery** is the opposite feature: it pings a PD and *cuts power* if the
ping fails. Leave that off. A Site A reboot will drop `tec-pi-mgr` and AP 1; shut the Pi down
cleanly first rather than pulling power from a running SSD.

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
| **SECURITY → Access Security → SSH Config** | SSH **v2 only**. Left enabled for the `cursor` automation account |

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

- the certificate (`.crt` / PEM)
- the private key (`.key` / PEM)

Do **not** download PKCS#12 (`.p12` / `.pfx`). The switch page has two slots, not one bag.

OPNsense's PEM key is PKCS#8 (`BEGIN PRIVATE KEY`). The switch rejects that as **Invalid SSL key**.
Convert to traditional PKCS#1 before Load Key ([TP-Link FAQ 2813](https://www.tp-link.com/uk/support/faq/2813/)):

```bash
openssl rsa -in tec-sw-a-cert_prv.pem -traditional -out tec-sw-a-cert_prv_pkcs1.pem
openssl rsa -in tec-sw-b-cert_prv.pem -traditional -out tec-sw-b-cert_prv_pkcs1.pem
```

The first line of each converted file must be `BEGIN RSA PRIVATE KEY`. OpenSSL 3 needs `-traditional`.

### 3. Upload to the switch

Back on **SECURITY → Access Security → HTTPS Config**, scroll to the **Load Certificate** and **Load Key**
sections:

1. **Certificate File** — the exported PEM (`BEGIN CERTIFICATE`)
2. **Key File** — the **PKCS#1** converted key (`BEGIN RSA PRIVATE KEY`)
3. Load each (confirm dialog → success)

The certificate and key **must match each other** or HTTPS stops working entirely. Keep console or a second
management path available until you have confirmed the new certificate loads.

4. **Save.**
5. **Reboot.** Vendor docs say the certificate does not take effect until the switch restarts, and Save
   must happen first or the upload is lost. Firmware **1.0.27 started presenting the Internal CA cert
   immediately after Load**, before reboot. Still Save, then reboot, so the files survive the next restart.
   Firmware 1.0.27 has no Perpetual PoE: Site A reboot cuts `tec-pi-mgr` and AP 1 — shut the Pi down
   cleanly first.

**Done 2026-09-06 on both switches**, including Save, reboot, and browser trust:
`https://tec-sw-a` and `https://tec-sw-b` load secured; fingerprints unchanged after reboot.

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

**SECURITY → DoS Defend** — enable. Leave **SYN sPort less 1024** (`port-less-1024`) **off**.
That type drops NFS clients that bind source ports below 1024. It was turned on with the rest on
2026-09-06 and `mount -a` hung on tec-desktop and the laptop until it was unchecked; SMB and ping
were fine. TrueNAS exports are `secure`, so `noresvport` is not a workaround.

### 3. Storm control, then loopback detection

Order matters, and the vendor guidance is explicit: **enable storm control before loopback detection**.

1. **QoS → Bandwidth Control → Storm Control** — broadcast and multicast limits on access ports.
2. **L2 FEATURES → Switching → Port → Loopback Detection** — enable.

Do not apply storm control to the trunk or the 10G inter-site link.

**Save.**

---

## Part 5: Port-level hardening

### 1. Port Security on fixed devices — skipped 2026-09-06

Not an internet-facing control. Extra MACs on a jack are a physical-access scenario. Left documented
so it is a choice, not an unfinished checkbox. Spare jacks stay admin-up (home network, not a fortress).

**SECURITY → Port Security** would cap learned MACs (Drop, not port shutdown). Do not apply to AP ports
or trunks.

### 2. Port Isolation at Site B — skipped 2026-09-06

Site B is metres from Site A on the same VLAN. Isolating Tw1/0/5–6 from each other does not change what
they can reach on the rest of the LAN (OPNsense, NAS, docker host, Site A). Inconvenience without a WAN
win.

### 3. Spare jacks stay up; PoE only on chosen PDs

- **Do not admin-down** unused copper. A shut jack is a forgotten step the next time a laptop or
  Pi is plugged in.
- **Disable PoE** on every port not serving a device you chose to power (**SYSTEM → PoE → PoE Config**).

A PoE port only energises after a PD negotiates, so the PoE half is hygiene. Link stays available.

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
the format the switch accepts. OPNsense PEM keys are PKCS#8 (`BEGIN PRIVATE KEY`) and fail Load Key as
**Invalid SSL key** until converted with `openssl rsa -in … -traditional`. PKCS#12 is not accepted.
Recover over SSH, or reset and restore the config backup from Part 1.

**Browser still warns after the upload.** On 1.0.27 the new cert can appear before reboot. Remaining causes:
the CA is not in that browser's trust store (see [`opnsense-cert-guide.md`](opnsense-cert-guide.md)
Parts 4–6), or the SAN does not contain the name you typed in the address bar. Check with the `openssl`
command above. Reach the switch by `tec-sw-a.localdomain` / `tec-sw-b.localdomain`, not only by IP.

**Clients stopped getting DHCP leases.** The DHCP Filter legal-server entry names the wrong port. Disable
the filter globally, fix the interface, re-enable.

**Locked out of the web UI.** Console cable first. Failing that, reset the switch and restore the config
backup — which is why Part 1 step 4 comes before everything else.

**`tec-pi-mgr` died during a reboot.** Perpetual PoE was not enabled, or was enabled but never saved.

**NFS `mount -a` hangs (laptop and tec-desktop) while SMB and ping to the NAS still work.**
**SECURITY → DoS Defend → SYN sPort less 1024** is on. Uncheck it on **both** switches, Apply, Save.

---

## CLI that was applied (2026-09-06)

Standalone SSH as `cursor`, then `enable`. Copper is `two-gigabitEthernet`, SFP+ is
`ten-gigabitEthernet`. Save is `copy running-config startup-config`. The checklist and the
commands that ran live in [`.cursor/plan/switch-hardening.md`](../.cursor/plan/switch-hardening.md);
this section is a copy of the 2026-09-06 replay.

DoS types must be set one at a time. Storm control needs `rate-mode kbps` *before* the numeric
limit (`storm-control broadcast kbps 1024` is a syntax error on this firmware).

### Both switches

```
configure
hostname tec-sw-a
no ip http server
ip http secure-server
ip http secure-protocol tls12
ip http secure-ciphersuite ecdhe-a128-g-s256 ecdhe-a256-g-s384
ip dos-prevent
ip dos-prevent type land
ip dos-prevent type scan-synfin
ip dos-prevent type xma-scan
ip dos-prevent type null-scan
ip dos-prevent type blat
ip dos-prevent type ping-flood
ip dos-prevent type syn-flood
ip dos-prevent type win-nuke
ip dos-prevent type ping-of-death
ip dos-prevent type smurf
ip dhcp filter
ip dhcp filter server permit-entry server-ip 192.168.1.1 client-mac all interface ten-gigabitEthernet 1/0/10
loopback-detection
interface range two-gigabitEthernet 1/0/1-8
 ip dhcp filter
 loopback-detection
 storm-control rate-mode kbps
 storm-control broadcast 1024
 storm-control multicast 1024
exit
end
copy running-config startup-config
copy running-config backup-config
```

On Site B the hostname is `tec-sw-b`. Legal DHCP server port is Te1/0/10 on both (OPNsense
uplink on Site A; inter-site toward OPNsense on Site B).

Do **not** replay `ip dos-prevent type port-less-1024` (GUI: SYN sPort less 1024). It was in the
2026-09-06 apply, then removed the same evening after it broke NFS. See Part 4 step 2.

### Site A only — PoE keep, copper stays up

```
configure
interface two-gigabitEthernet 1/0/1
 power inline supply enable
 power inline priority high
 power inline consumption class4
 description tec-pi-mgr
exit
interface two-gigabitEthernet 1/0/8
 power inline supply enable
 power inline priority high
 power inline consumption class4
 description ap-1
exit
interface range two-gigabitEthernet 1/0/2-7
 no shutdown
 power inline supply disable
exit
end
copy running-config startup-config
copy running-config backup-config
```

### Site B only — all PoE off, copper stays up

```
configure
interface range two-gigabitEthernet 1/0/1-8
 no shutdown
 power inline supply disable
exit
end
copy running-config startup-config
copy running-config backup-config
```

Tw1/0/5 and Tw1/0/6 stay up (desk devices). Telnet, SNMP and cloud were already off; SSH v2
was left on for `cursor`. Port isolation and MAC limits were **skipped** (not internet-facing).
GUI config backup was taken 2026-09-06. Internal CA certs loaded the same day; HTTPS still valid
after reboot.

Port map: [`network-layout.md`](network-layout.md).

---

## Deliberately not done

- **802.1X** (**SECURITY → 802.1x**) needs a RADIUS server, which does not exist here. It is also mutually
  exclusive with Port Security, which is more useful on a small static network. Ruled out rather than left
  as a permanent someday item.
- **DoS type `port-less-1024` / SYN sPort less 1024.** Breaks NFS (privileged source ports) on this
  LAN. Left off after the 2026-09-06 outage; do not turn it back on.
- **ACLs** (**SECURITY → ACL**) can express most of the firewall policy, and should not. OPNsense is the
  single enforcement point; policy split across two devices is policy nobody can audit.
- **Syslog off-box.** Both switches log locally via **MAINTENANCE → Logs**, which means the logs are lost
  on reboot — precisely the event you want to investigate. Sending syslog to OPNsense is the obvious fix.
  **Known gap**, not solved here.
- **IPv6 Source Guard** would need the SDM template changed to EnterpriseV6 (**SYSTEM → SDM Template**),
  which is a reboot and a table-size trade-off for no benefit on an IPv4-only LAN.
