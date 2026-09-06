# Security Quick Wins

> **Implementation order: step 2 (items 1–5) and step 4 (items 6–11) of 5.**
> **This file is the source of truth.** `- [x]` done, `- [ ]` open. The command or compose edit sits
> under the item. Do remaining `[ ]` items **in order**; do not skip an open item to work a later one.
> Prerequisites: [`switch-hardening.md`](switch-hardening.md) Phases 1–2 — done. Items 2 and 5 gate
> [`lan-only-default-routing.md`](lan-only-default-routing.md) (free 8443; drop wiki `6875:80`).
> After routing is verified, resume here at item 6. Then [`vlan-segmentation.md`](vlan-segmentation.md).
> Written 2026-09-05. Checklist format 2026-09-06.

Short, independent hardening. Front/back doors, not per-device paperwork: bind or delete dangerous
listeners; a new phone still just joins WiFi. Every item here is reachable today from
`192.168.1.0/24`.

Each service change: `./gradlew deploy<Svc>` then `sudo docker compose up -d` on tec-desktop. Rotate
DB passwords **in the database** before restarting the app.

## Remaining — do in this order

**Now (before routing):**

- [x] **1** NAS BMC — find it, dedicated mode, credentials, unplug if dedicated.
- [x] **2** Redis — delete stack (preferred) or bind+password; drop `deployRedis` and `deployUnifi`. **Gates 8443.**
- [x] **3** Jenkins — remove `privileged: true`, then `user: root`.
- [x] **4** SonarQube Postgres — unpublish 5432, rotate `sonar`/`sonar`.
- [x] **5** Wiki — drop `6875:80`, rotate DB passwords. **Gates `APP_PROXIES`.**

**Then** [`lan-only-default-routing.md`](lan-only-default-routing.md) to completion.

**After routing is verified:**

- [ ] **6** Remaining host ports → `127.0.0.1` (exceptions on `192.168.1.35` below).
- [ ] **7** SSH key-only on tec-desktop; OPNsense SSH off or key-only.
- [ ] **8** MFA on OPNsense, Vaultwarden, Portainer, Grafana, UniFi, Jenkins, TrueNAS.
- [ ] **9** Force DNS through Unbound (redirect 53, block 853).
- [ ] **10** Docker socket proxy for Traefik and Diun (private network, not `share-net`).
- [ ] **11** Unattended upgrades on tec-desktop and the Pi fleet.

## Decisions

- **Ordered by blast radius, then by the routing gate.** BMC first (largest blast, LAN-only). Redis
  and wiki host-port next because they gate Traefik's public entrypoint. Jenkins `privileged` is the
  same class as open Redis and runs in this first sitting, not after MFA.
- **Bind, do not delete** (unless the stack has no consumer). `127.0.0.1:` for debug ports;
  `192.168.1.35` only when another LAN host genuinely needs it. Same exception list as
  [`vlan-segmentation.md`](vlan-segmentation.md). Does not change how a phone joins WiFi.
- **Rotate, not just relocate.** Credentials in git are burned.
- **Socket proxy only where the socket is not genuinely needed.** Portainer keeps the real socket.
  Traefik and Diun do not.
- **Home network, not a fortress.** No MAC registration. House laptop reaches UIs without VPN.

## 1. NAS BMC on the LAN

TrueNAS Mini X+ dedicated IPMI. Compromise is owning the box that holds every backup. Never
port-forward it. Permanent zone is Management in [`vlan-segmentation.md`](vlan-segmentation.md);
house Clients may still reach TrueNAS *data*. BMC itself stays off IoT/Guest.

- [x] **1.1** Find address. **Do:** TrueNAS UI IPMI page, or `ipmitool lan print 1` on the NAS.
  Confirm current NAS data IP (was `192.168.1.30` on 2026-09-05, not `.101`).
  **Did (2026-09-06):** data is `192.168.1.30` (`tec-truenas` / `truenas.tecronin.uk`, MAC
  `90:5a:08:98:1b:80`). BMC is `192.168.1.31` (`tec-truenas-ipmi`, MAC `90:5a:08:15:73:d7`).
  Old `.101` is dead (no ARP). `tec-nas` does not resolve; mounts already use `tec-truenas`.
  Dedicated cable was on OPNsense; recabled to **tec-sw-a Tw1/0/2**. Port was still
  `shutdown` from Phase 2, so no link lights; BMC stayed reachable via **failover** (MAC
  learned on Te1/0/10). **Did:** `no shutdown`, description `nas-ipmi`, PoE off, saved
  startup+backup. Link up; MAC now on Tw1/0/2; `.31` pings.
- [x] **1.2** Set BMC LAN mode to **dedicated** (not failover). Unplugging the cable does not prove
  it is off if failover is on.
  **Did (2026-09-06):** UI LAN Interface = dedicated. Wire check: `.31` has 80/443/623/5900; NAS
  data `.30` has TrueNAS 80/443 only (no 623/5900). Earlier Te1/0/10 MAC was while Tw1/0/2 was
  still `shutdown`.
- [x] **1.3** Verify from another host: `nmap` IPMI ports on both the BMC address and the NAS data
  address (see Verification).
  **Did (2026-09-06):** `nmap` from `tec-pi-mgr` (not tec-desktop). NAS data `.30`: 623/udp
  **closed**, 664/udp closed, 623/tcp closed, 5900/tcp closed; 80/443 are TrueNAS. BMC `.31`:
  623/udp **open** (RMCP), 5900/tcp open (KVM), 80/443 open, 664/udp closed. Dedicated holds.
- [x] **1.4** Change credentials; store in Vaultwarden. Stock was `ADMIN`/`ADMIN` or a chassis sticker.
  **Did (2026-09-06):** not factory; password stored in Vaultwarden.
- [x] **1.5** Disable IPMI-over-LAN and virtual media if unused.
  **Did (2026-09-06):** Virtual Media Port 623 **disabled** (TCP 623 / ISO; nmap closed). This ATEN
  UI has **no RMCP enable/disable** under Users or Network — only an RMCP port number (leave 623).
  UDP 623 stays open; that is accepted. KVM 5900 stays (web console).
- [x] **1.6** If dedicated is confirmed: unplug the dedicated port until VLANs exist. Record what you
  set — nothing in this repo will remind you.
  **Skipped unplug (2026-09-06):** dedicated cable is on **tec-sw-a Tw1/0/2** (future Management).
  Do not unplug. Record: dedicated LAN mode; VM port off; RMCP 623; HTTPS Internal CA.

## 2. Unauthenticated Redis (and dead `unifi` stack)

[`src/services/redis/docker-compose.yml`](../../src/services/redis/docker-compose.yml) publishes
`6379:6379` with no password. `CONFIG SET dir` + `SAVE` is a root path. `deployRedis` is in
`deployAll`; nothing in the repo consumes it.

- [x] **2.1** `docker ps` and `ss -tnp | grep 6379`. If nothing is connected: **delete the stack** and
  drop `deployRedis` from `deployAll`. That is the preferred fix.
  **Did (2026-09-06):** nothing on 6379, no redis container. `docker compose down`, removed
  `/mnt/raid/services/redis` and `src/services/redis/`. Dropped `deployRedis` from gradle.
- [ ] **2.2** Only if in use: bind `127.0.0.1:6379:6379`, `--requirepass` from `.env`, add `share-net`.
  **Skipped** — stack deleted.
- [x] **2.3** Remove `deployUnifi` from `deployAll`. Delete `src/services/unifi/` after the `unifi`
  volume is confirmed backed up. Frees host `8443:443` for Traefik `public`. **Do not skip — gates
  routing.**
  **Did (2026-09-06):** old `unifi` volume already gone; `unifi-os` healthy with backup sidecar.
  `compose down` in `/mnt/raid/services/unifi` (no resources), removed that dir and
  `src/services/unifi/`. Dropped `deployUnifi`. Host **8443 free**. `unifi-os` untouched.

## 3. Jenkins is `privileged` and runs as root

[`src/services/jenkins/docker-compose.yml`](../../src/services/jenkins/docker-compose.yml):

```yaml
    privileged: true
    user: "root"
```

`privileged: true` is host-root for any pipeline. Do this when a failed build is affordable.

- [x] **3.1** Remove `privileged: true`. Deploy, run the next scheduled job. If a pipeline needs
  Docker, use a socket-proxied `tcp://` endpoint or an agent — not `privileged` on the controller.
  **Did (2026-09-06):** `privileged: true` removed from compose.
- [x] **3.2** Drop `user: "root"`. Image default is `jenkins` (UID 1000). If the volume blocks that:
  `chown -R 1000:1000` on `jenkins-home` once.
  **Did (2026-09-06):** `user: "root"` removed.

## 4. SonarQube Postgres `sonar` / `sonar` on the LAN

[`src/services/sonarqube/docker-compose.yml`](../../src/services/sonarqube/docker-compose.yml)
published 5432 with git-committed credentials. Collided with timescaledb.

- [x] **4.1** Drop the published 5432 port. SonarQube uses `db:5432` on `share-net`.
  **Did (2026-09-06):** `db` has no `ports:`. Host `5432` not listening. Container `postgresql`
  shows `5432/tcp` only.
- [x] **4.2** Move password to `.env` as `SONAR_DB_PASSWORD`; `SONAR_JDBC_PASSWORD` and
  `POSTGRES_PASSWORD` must match.
  **Did (2026-09-06):** compose uses `${SONAR_DB_PASSWORD:?set SONAR_DB_PASSWORD in .env}`.
  Host `/mnt/raid/services/sonarqube/.env` is `chmod 600`. Copy that value into Vaultwarden.
- [x] **4.3** Rotate the live role **before** restart:
  `docker exec postgresql psql -U sonar -c "ALTER USER sonar WITH PASSWORD '<new>';"`
  **Did (2026-09-06):** `ALTER USER sonar` then recreate. JDBC pool connects. Recreate left ES
  `metadatas` corrupt (`IndexCreator` NPE); stopped SQ, deleted `es7` in `sonarqube-data` only
  (Postgres is source of truth), restarted. `api/system/status` is `UP` 9.9.8;
  `https://sonarqube.tecronin.uk` 200. Timescaledb still publishes host 5432 if that stack is up.

## 5. Wiki credentials in git, and host port 6875

[`src/services/wiki/docker-compose.yml`](../../src/services/wiki/docker-compose.yml) had
`changeme_root` / `bookstack@123` and `"6875:80"`. No Traefik in front of 6875; that made
`APP_PROXIES: "*"` unsafe. **Gates routing.**

- [x] **5.1** Drop `"6875:80"`. `APP_URL` is the HTTPS name.
  **Did (2026-09-06):** no `ports:` on bookstack. Host 6875 not listening. Container has `80/tcp` only.
- [x] **5.2** `${BOOKSTACK_DB_PASSWORD}` and `${BOOKSTACK_DB_ROOT_PASSWORD}` in
  `/mnt/raid/services/wiki/.env`. Update the healthcheck (`-pbookstack@123`).
  **Did (2026-09-06):** compose requires those plus `BOOKSTACK_APP_KEY` from the host `.env`
  (`chmod 600`). Copied live `APP_KEY` and `SMTP_*` into `.env` so recreate did not wipe mail/key.
  Healthcheck uses container `MYSQL_PASSWORD`. Copy DB passwords into Vaultwarden.
- [x] **5.3** Rotate MariaDB users **before** restarting BookStack.
  **Did (2026-09-06):** stopped bookstack, `ALTER USER` for `bookstack@%` and all `root` hosts
  (socket root; `changeme_root` was not the live root). Then `compose up -d`. DB healthy;
  `https://wiki.tecronin.uk` 302 → `/login` 200; `Nothing to migrate.`

## 6. Remaining host-published ports off the LAN

Do this **after** routing. Item 5 already dropped wiki 6875. Loopback by default; `192.168.1.35`
only for named exceptions.

Short form: `"127.0.0.1:8860:8860"`. Long form (`mode: host`): `host_ip: 127.0.0.1` — a
`127.0.0.1:` prefix inside `published:` is invalid.

- [ ] **6.1** Loopback: grafana 3000, jenkins 8088 and 50000, nexus 8081, portainer 8050, openhab 8881,
  obsidian 8954, ups 8010/8020, velxio 3080, vaultwarden 8860, mq 5672 and 15672, unifi-os 11443,
  timescaledb 5432 (or delete the stack if `ss -tnp | grep :5432` shows no remote client — weather
  data is MariaDB per [`weather-mariadb-migration.md`](weather-mariadb-migration.md)).
- [ ] **6.2** Keep on `192.168.1.35`:
  - mariadb 3306 — tec-weather / piSolar. `host_ip: 192.168.1.35`; grants `@'192.168.1.%'` when that
    plan deploys. Binding here vs there: do it in the mariadb plan if that stack is not live yet.
  - rabbitmq **1883** — ESP32 fleet. 5672 and 15672 → loopback.
  - unifi-os **8080**, **3478/udp**, **10003/udp**. **8882** stays until `set-inform` to 8080
    ([`unifi-os-server-migration.md`](unifi-os-server-migration.md)); then loopback/remove.
  - nexus **8082** — `192.168.1.35` if LAN `docker push`; loopback if only localhost. Check
    `docker logs nexus` for remote sources. 8081 UI → loopback.
- [ ] **6.3** NUT 3493 is host `upsd`, not this list.

## 7. Admin SSH (tec-desktop and OPNsense)

- [ ] **7.1** tec-desktop: `PasswordAuthentication no`, `PermitRootLogin no`. Optional `AllowUsers`
  scoped to LAN and `10.9.0.0/24` once routing makes VPN the remote path.
- [ ] **7.2** OPNsense: SSH off or key-only; GUI HTTPS with the Internal CA cert
  ([`docs/opnsense-cert-guide.md`](../../docs/opnsense-cert-guide.md)). After VLANs: reachable from
  Clients and VPN, not IoT/Guest — not a one-host ACL.

Switch UIs are done: [`switch-hardening.md`](switch-hardening.md).

## 8. MFA on the accounts that matter

No SSO. Built-in TOTP until Authentik exists.

- [ ] **8.1** OPNsense web UI.
- [ ] **8.2** Vaultwarden.
- [ ] **8.3** Portainer.
- [ ] **8.4** Grafana, UniFi, Jenkins.
- [ ] **8.5** TrueNAS (separate from BMC item 1).

## 9. Force DNS through Unbound

Routing makes split-horizon load-bearing. Do this **after** routing.

- [ ] **9.1** OPNsense LAN: redirect outbound TCP/UDP 53 to the firewall.
- [ ] **9.2** Block outbound 853 (DoT).
- [ ] Browser DoH over 443 is a known gap (canary domain / blocklist later). Not solved here.

## 10. Docker socket proxy for Traefik and Diun

`:ro` on a unix socket does not restrict the API. Traefik is the most exposed container.

- [ ] **10.1** Add [`tecnativa/docker-socket-proxy`](https://github.com/Tecnativa/docker-socket-proxy)
  with `CONTAINERS=1` (Diun also `IMAGES=1`). Point Traefik `providers.docker.endpoint` at
  `tcp://docker-socket-proxy:2375`.
- [ ] **10.2** Proxy network is `internal: true` in the traefik stack — **not** `share-net`.
  `GET /containers/{id}/json` returns `Config.Env` (Cloudflare token, DB passwords). Traefik and
  Diun join that private net plus whatever they already need.
- [ ] Offen backup sidecars: residual risk, no proxy in this item. Portainer keeps the real socket
  (item 6 took 8050 off the LAN). `unifi-os` stays `privileged` (image requires it).

## 11. Unattended upgrades

Pinned images are correct; unpatched kernel under them is not.

- [ ] **11.1** `unattended-upgrades` (or equivalent) on tec-desktop.
- [ ] **11.2** Same on the Pi fleet.

## Verification

```bash
# from another LAN host, not tec-desktop — all should refuse or time out
for p in 6379 5432 8860 8050 3000 8088 50000 6875 8081 5672 15672; do
  nc -z -w2 192.168.1.35 $p && echo "OPEN $p" || echo "closed $p"
done
# 8443 is only allowed to be Traefik's public entrypoint, never the old unifi container
docker ps --filter publish=8443 --format '{{.Names}}'   # on tec-desktop: "traefik" or nothing
# deliberate exceptions
for p in 3306 1883 8080; do
  nc -z -w2 192.168.1.35 $p && echo "ok $p" || echo "BROKEN $p"
done
nc -zu -w2 192.168.1.35 3478 && echo "ok 3478/udp"

# on tec-desktop: nothing privileged except unifi-os-server
docker ps -q | xargs docker inspect -f '{{.Name}} {{.HostConfig.Privileged}}' | grep true

# BMC must not answer on the NAS data address
sudo nmap -sU -p623,664 192.168.1.30
nmap -p80,443,5900,5901 192.168.1.30
```

- [ ] Every service still loads through `https://<svc>.tecronin.uk`.
- [ ] `docker logs` clean after SonarQube and BookStack rotation.
- [ ] From a LAN client with DNS `1.1.1.1`, Unbound still returns `192.168.1.35` for a service name
      (item 9).
- [ ] NAS SMB/NFS still work after BMC changes.
