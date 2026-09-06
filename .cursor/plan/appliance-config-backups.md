# Appliance config backups

> **Stub, not started.** Written 2026-09-06.
> **This file is the source of truth.** `- [x]` done, `- [ ]` open. The command or GUI path sits
> under the item. Do remaining `[ ]` items **in order**; do not skip an open item to work a later one.
> Independent of the 5-step switch → quick-wins → routing → VLAN sequence. Docker volume backups
> already exist in [`container-management-overhaul.md`](container-management-overhaul.md) and the
> README; this plan is the appliances those jobs never see.
> First pull: Omada switches, OPNsense, TrueNAS config. More appliances later.

The Docker host already archives compose volumes to `/mnt/backup/docker/<svc>` and rclone's them
offsite. The firewall, the two switches, and the NAS keep their configuration **on the device**.
A dead switch or a fried OPNsense SSD currently means retyping from memory, except for one manual
GUI export of the switches on 2026-09-06.

## Remaining — do in this order

- [ ] **0** Decide runner, destination, and secret store (open decisions below).
- [ ] **1** Switches `tec-sw-a` / `tec-sw-b`.
- [ ] **2** OPNsense (`fort-apache`).
- [ ] **3** TrueNAS Mini X+ (`tec-nas` / `tec-truenas`) **config**, not the pool.
- [ ] **4** Land files on the NAS under `/mnt/backup/…`, then offsite like the docker tier.
- [ ] **5** Notify on failure via Gotify. Restore drill once per appliance.

## Decisions (open — pick these in item 0)

- **This is appliance *config*, not data.** Switch `.cfg`, OPNsense `config.xml` (and the CA),
  TrueNAS saved config. ZFS replication / pool backup is a different plan. Docker volumes stay
  with offen + rclone.
- **One collector, many devices.** The appliances have no useful onboard schedule (the switches
  have `reboot-schedule` only; OPNsense can push to GDrive itself but that splits destinations).
  A job on a LAN host pulls or is pushed-to. This Cursor VM is NAT `10.0.2.15` and cannot be the
  TFTP target.
- **Runner (pick one):** `tec-desktop` cron, a compose service on tec-desktop, or OPNsense itself.
  Prefer a host that is up when the NAS is, and that can reach `.1`, `.2`, `.3`, and the NAS.
- **Transport (pick per device, same landing zone):**
  - Switches: HTTPS GET `data/sysConfigBackup.cfg` after login (same as the GUI), or CLI
    `copy startup-config tftp ip-address <lan> filename <name>`. Pull does not need a TFTP
    daemon. See [`switch-hardening.md`](switch-hardening.md) item 1.5.
  - OPNsense: REST API / `os-api-backup`, or **System → Configuration → Backups** download.
    [`vlan-segmentation.md`](vlan-segmentation.md) Phase 0 step 1 is a one-shot before VLANs,
    not a schedule.
  - TrueNAS: **System → General → Save/Download config** (CORE vs SCALE UI name differs). API
    equivalent once the version is confirmed. **Not** a recursive snapshot of the pool.
- **Secrets stay out of git.** Switch `CURSOR_SW_PWD` is in `~/.profile`. OPNsense and TrueNAS
  API keys / users go in Vaultwarden and on the runner host env, same pattern as Gotify tokens.
- **Filenames include device, firmware/version, and date** so a restore does not grab yesterday's
  factory image. Example: `tec-sw-a-1.0.27-20260906.cfg`.
- **On-device copies do not count.** Switch `config2.cfg` dies with the switch. OPNsense history
  on the box dies with the box.

## What already exists (do not rebuild)

| What | Where | This plan |
|---|---|---|
| Docker volume tarballs + rclone offsite | README; `offen/docker-volume-backup` | out of scope |
| Host config zip `services_backup.sh` | `/mnt/backup/docker/services` | out of scope |
| Switch GUI export, once | laptop, 2026-09-06 | replace with schedule in item 1 |
| Switch on-box `config2.cfg` | both switches | not off-switch |

## Phase 0 — decide and inventory

- [ ] **1. Pick runner and landing path.** Candidate: `/mnt/backup/appliances/<device>/` on the
  NAS (already mounted on tec-desktop as `/media/docker_backup` via `//tec-nas/backup`), then
  `gdrive:/backup/appliances/…` via the existing `gdrive` stack or a new rclone dest.
- [ ] **2. Confirm TrueNAS version** (CORE vs SCALE) so the config-download API/UI is the right
  one. Hostname `tec-truenas`; repo mounts use `tec-nas`.
- [ ] **3. Confirm OPNsense backup API** with an API key that can only download config, not
  change firewall rules.
- [ ] **4. Record where the 2026-09-06 switch GUI files actually landed** (item 1.5 did not
  capture the path).

## Phase 1 — switches

Manual GUI backup is done; this is the schedule. Credentials: `cursor` / `CURSOR_SW_PWD`. SSH
needs the old algorithms listed in [`switch-hardening.md`](switch-hardening.md).

- [ ] **1. Save then export** (`copy running-config startup-config` before the copy/download, or
  the file is stale).
- [ ] **2. Pull both `tec-sw-a` and `tec-sw-b` on a cron** (daily is enough; they change rarely).
  **Do:** HTTPS `sysConfigBackup.cfg` or TFTP push to the LAN runner.
- [ ] **3. Restore test:** load Site B's file onto Site B (or a spare thought experiment: Site A
  file onto Site B needs port map + management address changed). Do not restore onto the live
  Site A uplink as a drill.

## Phase 2 — OPNsense

- [ ] **1. One-shot download now** (also satisfies vlan-segmentation Phase 0 step 1 if not done).
  **GUI:** System → Configuration → Backups.
- [ ] **2. Scheduled download** of `config.xml` plus the Internal CA material the switches and
  VPN already depend on. Encrypt the archive; it contains private keys.
- [ ] **3. Restore test** onto a known path (XML import on a spare / documented steps), not a
  live apply during the drill.

## Phase 3 — TrueNAS config

- [ ] **1. One-shot Save Config** off-box, same landing zone.
- [ ] **2. Scheduled download** of the TrueNAS config database. Pool datasets stay on ZFS;
  this file is what rebuilds shares, users, and SMB after a USB/boot-pool loss.
- [ ] **3. Restore test:** TrueNAS documents config restore as a reboot; drill on paper first,
  then a real restore only when a window exists.

## Phase 4 — land, offsite, notify

- [ ] **1. Retention** on the NAS (match docker's 7 days unless a longer keep for appliances
  is wanted — these files are tiny).
- [ ] **2. Offsite copy** through rclone / the `gdrive` stack. Do not invent a second Google
  account or OPNsense-native GDrive unless item 0 chose that on purpose.
- [ ] **3. Gotify on failure** (`GOTIFY_APP_TOKEN` already used by rclone). Silent success.
- [ ] **4. Restore drill** logged here: date, device, result.

## Later (not starters)

UniFi controller config is already inside the `unifi-os` volume sidecar. PiKVM, the Pi fleet,
and OPNsense DHCP leases are candidates once 1–3 run. ZFS replication off-NAS is its own plan.

## Risks

- **A backup that has never been restored is not a backup.** The drill is the last checkbox,
  not optional flavour.
- **OPNsense and TrueNAS configs contain secrets.** Treat the archive like Vaultwarden, not
  like a public compose file.
- **TFTP is plaintext.** If the runner uses TFTP, put it on the LAN only and prefer HTTPS/SCP
  once those paths are proven.
- **Collecting onto the NAS does not survive NAS death.** Offsite (item 4.2) is what makes
  TrueNAS config worth taking.
