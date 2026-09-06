# Network layout

Living record of the two Omada switches. VLAN port-to-zone assignments belong here once
[`.cursor/plan/vlan-segmentation.md`](../.cursor/plan/vlan-segmentation.md) lands; until then this
file holds the management identity that
[`.cursor/plan/switch-hardening.md`](../.cursor/plan/switch-hardening.md) required.

Walkthrough: [`omada-switch-hardening.md`](omada-switch-hardening.md).

## Switches

Both stay DHCP clients. Reservations are by MAC in Dnsmasq. Automation login is user `cursor`
(Admin); the password is `CURSOR_SW_PWD` in `~/.profile`, not in this repo. SSH v2 is left on
for that account. Human `admin` passwords stay in Vaultwarden and should remain distinct per
switch.

| | Site A | Site B |
|---|---|---|
| Name | `tec-sw-a` | `tec-sw-b` |
| Address | `192.168.1.2` | `192.168.1.3` |
| MAC | `AC:A7:F1:12:41:4C` | `AC:A7:F1:12:41:04` |
| Serial | `Y261123000289` | `Y261123000217` |
| Hardware | SG2210XMP-M2 1.0 | SG2210XMP-M2 1.0 |
| Software | 1.0.27 Build 20260804 Rel.4241 | same |
| Running / next image | `image2.bin` (1.0.27) | same |
| Backup image | `image1.bin` (1.0.0 factory) | same |
| Startup config | `config1.cfg` | `config1.cfg` |
| On-switch backup | `config2.cfg` (copy of running, 2026-09-06) | same |
| Management | VLAN1 DHCP | VLAN1 DHCP |
| Web UI | `https://tec-sw-a.localdomain` (`192.168.1.2`) | `https://tec-sw-b.localdomain` (`192.168.1.3`) |
| Certificate | Internal CA, SAN `tec-sw-a.localdomain` + `tec-sw-a` | Internal CA, SAN `tec-sw-b.localdomain` + `tec-sw-b` |
| Cert notAfter | 2027-10-08 03:17:26 GMT | 2027-10-08 03:18:22 GMT |
| SHA-256 fingerprint | `B6:1F:CB:30:0D:0F:75:A1:C8:4A:66:24:82:35:0B:44:98:2B:95:4A:E8:60:DE:C2:27:43:D7:D7:C6:75:54:26` | `1F:B9:FD:08:F6:8E:67:C7:1B:12:73:16:50:AC:7E:5A:DC:F7:C9:D1:F6:97:64:25:44:21:E2:C2:46:46:82:AD` |
| Cert install | loaded GUI 2026-09-06; browser **secured**; **reboot 2026-09-06, still valid** | same |

Dnsmasq Hosts reservations were renamed 2026-09-06 to `tec-sw-a` / `tec-sw-b` so they match
the switch device names. `tec-sw-a.localdomain` → `.2`, `tec-sw-b.localdomain` → `.3`; PTRs
match. The old `tec-swtich-main` / `tec-switch-secondary` names are gone.

### Site A ports (flat LAN, 2026-09-06)

| Port | Role | State |
|---|---|---|
| Tw1/0/1 | `tec-pi-mgr` (MAC `2c:cf:67:25:88:07`) | up 1G, PoE Enable / High / Class4 — **GUI-verified 2026-09-06** |
| Tw1/0/2 | NAS IPMI `tec-truenas-ipmi` (`192.168.1.31`, MAC `90:5a:08:15:73:d7`) | **up 2026-09-06** — recabled from OPNsense; `no shutdown`, PoE off, description `nas-ipmi`; saved startup+backup. Before enable, BMC MAC was learned on Te1/0/10 (failover via NAS data path) |
| Tw1/0/3–6 | unused | admin-up, LinkDown, PoE off — plug in, get link |
| Tw1/0/7 | wired client (`00:1b:a9:82:eb:27`) | up 100M, PoE off |
| Tw1/0/8 | AP 1 (bridges client MACs) | up 2.5G, PoE Enable / High / Class4 — **GUI-verified 2026-09-06** |
| Te1/0/9 | inter-site to Site B Te1/0/10 | up 10G |
| Te1/0/10 | uplink to OPNsense `ixl1` | up 10G; DHCP Filter legal server port |

### Site B ports (flat LAN, 2026-09-06)

| Port | Role | State |
|---|---|---|
| Tw1/0/1–4 | unused | admin-up, LinkDown, PoE off — plug in, get link |
| Tw1/0/5 | desk device | up 1G, PoE off |
| Tw1/0/6 | desk device | up 100M, PoE off |
| Tw1/0/7–8 | unused | admin-up, LinkDown, PoE off — plug in, get link |
| Te1/0/9 | `tec-desktop` (plan: SFP+ 2) | up 10G |
| Te1/0/10 | inter-site from Site A Te1/0/9 | up 10G; DHCP Filter legal server port |

PoE system budget is 160W on both. Site B draws 0W.

## Hardening applied (Phases 1–2)

Applied 2026-09-06 over SSH as `cursor`. Saved with `copy running-config startup-config` and
`copy running-config backup-config` on both. **Both switches were rebooted the same day and
kept the hardened config** (Site A ~4 minutes uptime after reboot; hostname, HTTP/TLS, DHCP
Filter, DoS, and PoE Class 4/high on Tw1/0/1 and Tw1/0/8 all survived). Unused-port `shutdown` was
part of that save and was **reverted the same day**.
`tec-pi-mgr` answered ping again after the power cut.

- Hostnames `tec-sw-a` / `tec-sw-b`
- Cloud / controller enrolment already off
- HTTP disabled in config (port 80 still serves an HTTPS redirect stub on this firmware)
- HTTPS TLS 1.2 only, ciphers `ECDHE-AES128-GCM-SHA256` and `ECDHE-AES256-GCM-SHA384`
- Telnet off, SNMP off, SSH v2 on
- NTP via DHCP option 42 (OPNsense), time correct
- DoS prevent enabled, all types except **SYN sPort less 1024** (`port-less-1024`). That type was
  on with the 2026-09-06 apply and made NFS `mount -a` hang network-wide (privileged source ports;
  TrueNAS `secure` exports). Unchecked on both switches the same evening; leave it off.
- DHCP Filter global + copper access ports; legal server `192.168.1.1` on Te1/0/10
- Storm control 1024 kbps broadcast+multicast on copper; not on 10G
- Loopback detection global + copper
- Copper admin-up on every jack (2026-09-06: unused-port `shutdown` reverted). PoE only on Site A Tw1/0/1 and Tw1/0/8
- No static routing / inter-VLAN routing

Internal CA certs were issued 2026-09-06 (RSA 2048, SAN present). OPNsense PEM keys are PKCS#8;
the switch needs PKCS#1 (`openssl rsa -in … -traditional`). PKCS#12 is not a valid upload format.
GUI Load Certificate + Load Key succeeded on both. Firmware 1.0.27 presented the certs before reboot.
**Browser trust verified 2026-09-06:** `https://tec-sw-a` and `https://tec-sw-b` both load secured.
**Both switches rebooted 2026-09-06; fingerprints unchanged, HTTPS still valid.** `tec-pi-mgr` answered
ping after the Site A PoE cut.

## Still open

- Phase 3 (management VLAN, access control, ARP Inspection) waits for VLAN segmentation.
  MAC limits and Site B port isolation were **skipped** — they are not internet-facing controls.
