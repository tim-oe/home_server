# Security Quick Wins

> **Implementation order: step 1 (items 1–5) and step 3 (items 6–11) of 4.**
> Status: reviewed 2026-09-05, ready to implement.
> Prerequisites: none. Items 2 and 4 must be done before
> [`lan-only-default-routing.md`](lan-only-default-routing.md) starts (they free port 8443 and remove
> the wiki host port that `APP_PROXIES` relies on). Items 6–11 resume after that plan is verified.
> Followed by: [`vlan-segmentation.md`](vlan-segmentation.md).

Short, independent hardening items that need no network redesign. Companion to
[`lan-only-default-routing.md`](lan-only-default-routing.md), which closes the internet-facing surface,
and a precursor to VLAN segmentation, which will close the LAN-facing one.

Every item here is reachable today by anything on `192.168.1.0/24` — a phone, a TV, a smart plug, a guest
laptop. That is the exposure this plan addresses, and it is larger than the internet-facing exposure the
routing plan deals with.

## Decisions

- **Ordered by blast radius, not by effort.** The NAS BMC, unauthenticated Redis, a trivially
  credentialed Postgres, and a `privileged` Jenkins come first because they are remote-code-execution-grade
  or worse, not configuration untidiness.
- **Bind, do not delete.** Host-published ports become `127.0.0.1:` bindings rather than being removed,
  preserving the host-side debugging they exist for while taking them off the LAN. Ports that another
  LAN host genuinely consumes are bound to `192.168.1.35` instead, and listed by name so the exception is
  deliberate. The list of those is reconciled against
  [`vlan-segmentation.md`](vlan-segmentation.md), which has to allow the same flows across segments
  later; the two plans must agree on what stays reachable.
- **Rotate, not just relocate.** Credentials committed to git are burned. Moving them to `.env` without
  changing the values accomplishes nothing.
- **Socket proxy only where the socket is not genuinely needed.** Portainer legitimately needs full Docker
  access. Traefik, Diun, and the backup sidecars do not.

## 1. The NAS BMC may be on the LAN

The NAS is a **TrueNAS Mini X+**, which ships with a dedicated RJ45 IPMI port alongside its two 10GBaseT
data ports. That port fronts a Baseboard Management Controller: a small computer running its own operating
system, independent of TrueNAS, powered whenever the NAS is plugged in — even when it is switched off.

It offers remote power control, a KVM console, and virtual media. Reaching it means owning the hardware
that holds every backup, and none of ZFS permissions, TrueNAS accounts, or disk encryption apply at that
layer. Supermicro BMCs have a long history of severe vulnerabilities, including unauthenticated credential
disclosure and the `cipher zero` authentication bypass, and they are patched rarely if ever. This is listed
first because unlike everything below it, a compromise here is not recoverable by reinstalling software.

Unlike the other items, this one starts with a question rather than a fix — the exposure is likely but
unconfirmed.

1. **Find out whether it is connected and what address it holds.** Check the IPMI page in the TrueNAS UI,
   or `ipmitool lan print 1` from the TrueNAS shell.
2. **Set the BMC LAN mode explicitly to dedicated.** Many Supermicro boards default to *failover*: when
   the dedicated port has no link, the BMC quietly becomes reachable through a regular data port instead.
   **Unplugging the IPMI cable therefore does not prove the BMC is off the network.** This is the part
   most people miss.
3. **Verify from another host** rather than trusting the setting, scanning both the IPMI address and the
   NAS data address — see Verification below.
4. **Change the credentials.** Older units shipped `ADMIN`/`ADMIN`; newer ones carry a unique password on
   a chassis sticker. Either way, set your own and store it in Vaultwarden.
5. **Turn off what you do not use.** If you administer via the web UI, disable IPMI-over-LAN. If you never
   use virtual media, disable it.
6. **Never forward a port to it.** It has no business being internet-reachable under any circumstances.

Until segmentation lands, the pragmatic interim is to unplug the dedicated port *after* confirming the
mode is dedicated rather than failover, so nothing silently falls back to a data port. Segmentation then
gives it a permanent home: the plan in [`vlan-segmentation.md`](vlan-segmentation.md) places it in the
Management zone, reachable only from the VPN and one designated admin host.

## 2. Unauthenticated Redis on the LAN

[`src/services/redis/docker-compose.yml`](../../src/services/redis/docker-compose.yml) publishes 6379 to
every host on the LAN and sets no password:

```yaml
    ports:
      - "6379:6379"
    command: redis-server --appendonly yes
```

An open Redis is not merely a data leak. `CONFIG SET dir` plus `SAVE` lets an unauthenticated client write
arbitrary files as the Redis user, which is the standard path to dropping an SSH key or a cron entry. Treat
this as the most urgent item.

- Confirm whether this stack is actually running. `deployRedis` **is** in `deployAll`
  (`src/gradle/services.gradle`), so its files are on the host, but it has no `share-net`, nothing else
  in the repo references `redis` or `6379`, and the root README lists it only as a "LAN-only datastore"
  with no consumer. The only way anything could use it is over the host port. `docker ps` and
  `ss -tnp | grep 6379` settle it. **If nothing is connected, delete the stack and drop `deployRedis`
  from `deployAll`** — that is the best fix.
- If it is in use: bind to `127.0.0.1:6379:6379`, add `--requirepass` from `.env`, and give it
  `share-net` so its consumers reach it by container name rather than host port.
- While in `deployAll`: also remove `deployUnifi`. The deprecated `unifi` stack is not routed by Traefik,
  cannot run alongside `unifi-os` (both publish 8882), and publishes host `8443:443`, which the routing
  plan needs for Traefik's `public` entrypoint. Delete the stack directory once its `unifi` volume has been
  confirmed backed up; that removes the risk of it being brought up by accident and stealing the port.

## 3. SonarQube Postgres reachable with `sonar` / `sonar`

[`src/services/sonarqube/docker-compose.yml`](../../src/services/sonarqube/docker-compose.yml) publishes
the database to the LAN with guessable credentials committed to git:

```yaml
      POSTGRES_USER: "sonar"
      POSTGRES_PASSWORD: "sonar"
    ports:
      - target: 5432
        published: 5432
```

- Drop the published port entirely. SonarQube reaches `db:5432` over `share-net`; nothing needs it on the
  host, and 5432 also collides with the standalone timescaledb stack.
- Move the password to `.env` as `SONAR_DB_PASSWORD` and rotate it. It appears twice, as
  `SONAR_JDBC_PASSWORD` and `POSTGRES_PASSWORD`, and both must match.
- Rotating means the existing volume's role password must change too:
  `docker exec postgresql psql -U sonar -c "ALTER USER sonar WITH PASSWORD '<new>';"` before restarting
  SonarQube, otherwise it will fail to connect.

## 4. Wiki database credentials committed in git

[`src/services/wiki/docker-compose.yml`](../../src/services/wiki/docker-compose.yml) still carries its
template values, including the literal placeholder:

```yaml
      MYSQL_ROOT_PASSWORD: changeme_root       # <-- change this
      MYSQL_PASSWORD: bookstack@123            # <-- change this
      DB_PASSWORD: bookstack@123               # <-- must match MYSQL_PASSWORD above
```

Less severe than the two above, because this MariaDB publishes no host port and is only reachable on
`share-net`. But the values are in git history, the wiki is one of only two internet-facing services, and
the pattern is inconsistent with every other stack here, which already sources secrets from `.env`.

- Move to `${BOOKSTACK_DB_PASSWORD}` and `${BOOKSTACK_DB_ROOT_PASSWORD}` in
  `/mnt/raid/services/wiki/.env`, matching the existing `${BOOKSTACK_APP_KEY}` convention in the same file.
- Rotate both. Change the MariaDB users before restarting BookStack, and remember the healthcheck also
  hardcodes the password (`-pbookstack@123`) and must be updated in step.
- The same file publishes BookStack itself on the host: `"6875:80"`. That is the application the routing
  plan is about to put on the internet, reachable on the LAN over plain HTTP with no Traefik in front.
  Drop the port; the comment beside it (`http://your-host:6875`) is template residue, `APP_URL` is the
  HTTPS name, and nothing else uses it. It also has to go for `APP_PROXIES: "*"` in the routing plan to
  be safe, since that setting trusts forwarded headers from any direct client.

## 5. Host-published ports come off the LAN

Beyond the two above, these bypass Traefik entirely and ignore `lan-only@file`:

- grafana 3000, jenkins 8088 and 50000, nexus 8081 and 8082, portainer 8050, openhab 8881,
  obsidian 8954, ups 8010 and 8020, velxio 3080, vaultwarden 8860, wiki 6875, mq 5672/15672/1883,
  unifi-os 11443/8080/8882
- standalone mariadb 3306, timescaledb 5432

Vaultwarden is the sharpest example: the routing plan puts `lan-only@file` in front of
`vaultwarden.tecronin.uk`, and then `8860:8860` serves the same application to the same network with no
filter at all.

Two forms of port syntax are in use, and the fix differs:

```yaml
# short form — grafana, vaultwarden, portainer, nexus, openhab, obsidian, velxio, upsmon, rabbitmq, wiki
    ports:
      - "127.0.0.1:8860:8860"

# long form with mode: host — jenkins, sonarqube, mariadb, timescaledb
    ports:
      - target: 8080
        published: 8088
        host_ip: 127.0.0.1
        protocol: tcp
        mode: host
```

A `127.0.0.1:` prefix inside `published:` is not valid in the long form; `host_ip:` is the field.
Everything keeps working through Traefik, host-side `curl` debugging still works, and the port
disappears from the LAN.

**Exceptions — these stay reachable from the LAN, bound to `192.168.1.35` rather than left on every
interface.** Each is a flow another host depends on, and each reappears in the VLAN plan's cross-segment
rules, so the two lists are kept identical on purpose:

- **mariadb 3306.** Not a debugging port: `tec-weather` and the piSolar Pi write to it over the network,
  per [`weather-mariadb-migration.md`](weather-mariadb-migration.md). Binding it to loopback breaks the
  weather station the day the migration lands. `host_ip: 192.168.1.35`, and narrow the grants from
  `@'%'` to `@'192.168.1.%'` as that plan already suggests.
- **rabbitmq 1883.** The ESP32 fleet publishes MQTT to `192.168.1.35:1883`; this is a fact, not a
  possibility to check. Stays. 5672 (AMQP) and 15672 (management UI) have no known LAN client — 15672 is
  what `mq.tecronin.uk` fronts — so those two go to loopback.
- **unifi-os 8080, 3478/udp, 10003/udp.** Inform, STUN, and discovery from the APs. Stay. **8882** stays
  until the `set-inform` migration to 8080 is done and the compose comment about it is removed; then it
  goes.
- **nexus 8082.** Docker registry connector; [`docs/nexus-docker-repo,md`](../../docs/nexus-docker-repo,md)
  documents LAN clients doing `docker push <host>:8082`. If any Pi or workstation still pulls from it,
  stays on `192.168.1.35`; if only tec-desktop pushes via `localhost:8082`, loopback. Check
  `docker logs nexus` for remote source addresses before deciding. 8081 (the UI) goes to loopback either
  way, Traefik fronts it.
- **jenkins 50000.** Inbound JNLP agent port. Loopback unless an agent exists off-host; today the compose
  file shows none, so loopback, and note the exception if one is ever added.
- **timescaledb 5432.** No consumer anywhere in the repo, and it cannot even be running at the same time
  as SonarQube's Postgres, which publishes the same port in the same `mode: host`. Before binding to
  loopback, `ss -tnp | grep :5432` on tec-desktop for any remote source address; if there is none, the
  better question is whether the stack should exist at all now that
  [`weather-mariadb-migration.md`](weather-mariadb-migration.md) puts the weather data in MariaDB.
- **NUT 3493** is served by the host's `upsd`, not a container, so it is out of this list; the `upsmon`
  containers reach it by hostname and are unaffected.

## 6. Docker socket exposure

Eleven containers mount `/var/run/docker.sock`. Two mount it read-write (`portainer`, `diun`); the rest
use `:ro`, which is worth being clear about: **`:ro` on a unix socket prevents nothing.** It applies to the
file node, not to the API calls you can make through it. Any container in this list, if compromised, can
create a privileged container and own the host.

- `traefik` only needs to watch container labels. Put
  [`tecnativa/docker-socket-proxy`](https://github.com/Tecnativa/docker-socket-proxy) in front of it with
  `CONTAINERS=1` and everything else off, and point `providers.docker.endpoint` at
  `tcp://docker-socket-proxy:2375`. This is the highest-value one: Traefik is the most exposed container
  you run.

  **The proxy must not join `share-net`.** `GET /containers/{id}/json` returns `Config.Env`, which is
  every secret of every container on the host — Cloudflare token, database passwords, `ADMIN_TOKEN`. On
  `share-net` that endpoint would be readable, unauthenticated, by every container. Create a dedicated
  `internal: true` network in the traefik stack, put the proxy on only that network, and give Traefik
  both networks. Diun joins the same private network. The proxy container itself still holds the real
  socket and is root-equivalent, but it publishes nothing, runs no user code, and its attack surface is
  one HTTP allowlist.
- `diun` needs container and image reads only, and currently has read-write. Same proxy, `CONTAINERS=1`,
  `IMAGES=1`.
- The eight `offen/docker-volume-backup` sidecars need `containers stop/start` and `exec`, which is close
  to full access. Lower priority; note the residual risk rather than contorting them.
- `portainer` genuinely needs the real socket. Leave it, and rely on item 7 plus taking 8050 off the LAN.
- **`unifi-os` is `privileged: true` with `/sys/fs/cgroup:rw`**, which the image requires to run systemd.
  No socket, but it is host-root-equivalent all the same, and it publishes five ports. Nothing to change
  — the image does not work otherwise — but it belongs on this residual-risk list next to Portainer, and
  it is one more reason the routing plan keeps `unifi.tecronin.uk` on `lan-only`.

## 7. MFA on the accounts that matter

No SSO layer exists, and the README's Authentik idea remains a TODO. Pending that, enable the built-in
second factor on the accounts whose compromise is unrecoverable:

- **OPNsense** web UI (TOTP). Most important: it is the firewall, the DNS resolver, the DHCP server, and
  the VPN concentrator. Everything else depends on it.
- **Vaultwarden** — the password vault.
- **Portainer** — holds the Docker socket, so it is root on tec-desktop.
- **Grafana**, **UniFi**, **Jenkins**.
- **TrueNAS** itself, separately from the BMC in item 1.

## 8. Force DNS through Unbound

The routing plan's split-horizon overrides are load-bearing: they are what makes LAN and VPN access work
once services are LAN-only. A device using an external resolver gets the public answer and fails.

On OPNsense, add a LAN rule redirecting outbound TCP/UDP 53 to the firewall itself, and a rule blocking
outbound 853 (DoT). This keeps devices on Unbound whether or not they cooperate, and is a prerequisite for
meaningful egress filtering later. Browser DoH over 443 cannot be blocked by port and needs either
Cloudflare's canary domain or a blocklist; note it as a known gap rather than solving it here.

## 9. Jenkins is `privileged` and runs as root

[`src/services/jenkins/docker-compose.yml`](../../src/services/jenkins/docker-compose.yml) sets both:

```yaml
    privileged: true
    user: "root"
```

`user: root` is the lesser of the two. `privileged: true` disables every container isolation mechanism
Docker has — all capabilities, no seccomp, no AppArmor, and full access to `/dev`, which means the host's
block devices. Jenkins executes arbitrary build code by design, so any pipeline, any `Jenkinsfile` in any
repo it builds, and any compromised plugin is **root on tec-desktop**, not merely root in a container. It
also publishes 8088 and 50000 to the LAN. This is the same class of exposure as the open Redis and belongs
near the top of the order, not the bottom.

- Remove `privileged: true` first and find out what breaks. Neither `jenkins-home` nor the compose file
  shows what needed it — there is no Docker socket mount and no device mapping — so it may be residue. If
  a pipeline needs Docker, the answer is a socket-proxied `tcp://` endpoint or a dedicated agent, not
  `privileged` on the controller.
- Then drop `user: "root"`. The image runs as `jenkins` (UID 1000); the usual reason for forcing root is a
  volume owned by the wrong UID, fixed once with `chown -R 1000:1000` on `jenkins-home`.

## 10. Admin surfaces the plans above do not touch

Three things are larger holes than anything in items 5 through 9 and are absent from every plan because
they live outside the repo. Listing them so they are at least decided rather than forgotten:

- **SSH on tec-desktop.** Key-only (`PasswordAuthentication no`), `PermitRootLogin no`, and since the
  routing plan makes the tunnel the only remote path, consider `AllowUsers` scoped to the LAN and
  `10.9.0.0/24`. This is the host that holds every Docker socket.
- **OPNsense management.** The web UI and SSH listen on the LAN interface by default. Confirm SSH is
  either off or key-only, that the GUI is HTTPS-only with the self-signed default replaced by the cert
  [`docs/opnsense-cert-guide.md`](../../docs/opnsense-cert-guide.md) describes, and — once
  [`vlan-segmentation.md`](vlan-segmentation.md) lands — that both are reachable only from Management,
  Clients, and the VPN.
- **Unattended security updates** on tec-desktop and the Pi fleet. Every Docker image here is pinned,
  which is right for the services, but the kernel and Docker daemon under them need `unattended-upgrades`
  or an equivalent. A pinned image on an unpatched kernel is the wrong way round.

## Order and risk

Items are independent of each other, but two of them are prerequisites for the routing plan, so the
sequence is split around it.

**Before `lan-only-default-routing.md`:**

1. NAS BMC — establish where it is, set dedicated mode, change credentials.
2. Redis (delete the stack, or bind and add a password); drop `deployRedis` and `deployUnifi` from
   `deployAll`, delete the deprecated `unifi` stack. **Gates the routing plan**: frees 8443.
3. Jenkins — remove `privileged`, then `user: root`.
4. SonarQube Postgres — unpublish and rotate.
5. Wiki — drop `6875:80`, rotate credentials. **Gates the routing plan**: `APP_PROXIES: "*"` is only safe
   once the host port is gone.

**Then run `lan-only-default-routing.md` to completion.**

**After it is verified:**

6. Bindings across the remaining stacks: loopback by default, `192.168.1.35` for the named exceptions in
   item 5.
7. SSH key-only on tec-desktop; OPNsense SSH off or key-only.
8. MFA.
9. DNS redirect rules. Sequenced here deliberately: the routing plan makes the split-horizon overrides
   load-bearing, so this is when forcing devices onto Unbound starts to matter.
10. Socket proxy for Traefik and Diun, on its own internal network.
11. Unattended upgrades.

**Then `vlan-segmentation.md`.**

Each service change is `./gradlew deploy<Svc>` then `sudo docker compose up -d` on the host. The
credential rotations are the only ones that can break a running service, and each needs the database-side
password changed before the application restarts. The Jenkins `privileged` removal can break builds, not
Jenkins itself, so do it when a failed build is affordable and check the next scheduled run.

The BMC item is the only one that touches hardware rather than software, and the only one where the fix
can be verified but not deployed from this repo — record what you set, because there is no config file
here that will remind you.

## Verification

```bash
# from another LAN host, not tec-desktop — all should now refuse or time out
for p in 6379 5432 8860 8050 3000 8088 50000 6875 8081 5672 15672; do
  nc -z -w2 192.168.1.35 $p && echo "OPEN $p" || echo "closed $p"
done
# 8443 is only allowed to be Traefik's public entrypoint, never the old unifi container
docker ps --filter publish=8443 --format '{{.Names}}'   # on tec-desktop: "traefik" or nothing
# and these must still answer, they are the deliberate exceptions
for p in 3306 1883 8080; do
  nc -z -w2 192.168.1.35 $p && echo "ok $p" || echo "BROKEN $p"
done
nc -zu -w2 192.168.1.35 3478 && echo "ok 3478/udp"

# on tec-desktop: nothing may still be privileged except unifi-os-server
docker ps -q | xargs docker inspect -f '{{.Name}} {{.HostConfig.Privileged}}' | grep true

# the BMC must not answer on the NAS data address, whatever the cable says
sudo nmap -sU -p623,664 192.168.1.101
nmap -p80,443,5900,5901 192.168.1.101
```

- Every service still loads through `https://<svc>.tecronin.uk`.
- `docker logs` clean on each restarted stack, particularly SonarQube and BookStack after rotation.
- From a LAN client with DNS manually set to `1.1.1.1`, confirm the redirect rule still returns the
  internal `192.168.1.35` for a service name.
- The NAS still serves SMB and NFS normally after the BMC changes — the BMC is independent of the data
  path, so a mistake there should not affect shares, and confirming that tells you the two really are
  separate.
