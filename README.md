# home_server

Home lab, cloud-like setup for development and learning.

Every service is a docker compose stack under `src/services/<svc>/`. This repo is the source of
truth for images, routing, and backup configuration. Gradle copies files to the server over SSH;
it never starts containers — that is always `docker compose up -d` on the host.

## Repo layout

| Path | Contents |
|---|---|
| `src/services/<svc>/` | one compose stack per service, plus any config it bind-mounts |
| `src/services/_common/` | shared scripts copied into every stack (`rclone-sync.sh`) |
| `src/services/traefik/` | reverse proxy: static config, `dynamic/` file provider, `acme.json` volume |
| `src/gradle/` | `services.gradle` (deploy tasks), `docker.gradle` |
| `src/bin/`, `src/bin/cron/` | host maintenance scripts, deployed to `/mnt/raid/bin` |
| `src/etc/cron.d/` | host cron entries, deployed to `/etc/cron.d` |
| `docs/` | service and host notes: setup guide, per-service config, KVM, OPNsense, NAS, PiKVM |
| `.cursor/plan/` | design and migration plans, kept as the record of why things are shaped this way |

On the server (`tec-desktop`):

| Path | Contents |
|---|---|
| `/mnt/raid/services/<svc>/` | deployed compose files — run `docker compose up -d` from here |
| `/mnt/raid/bin/` | maintenance scripts and their cron wrappers |
| `/mnt/backup/docker/<svc>/` | local backup archives on the NAS |

`share-net` is an external docker bridge that every stack joins, so containers reach each other by
name (`http://gotify`, `http://jenkins:8080`) without publishing ports.

## Deploy

```bash
./gradlew dockerNet        # once, creates share-net
./gradlew initAcl          # once, ACLs /mnt/raid/services for the ansible user
./gradlew deployScripts    # src/bin -> /mnt/raid/bin
./gradlew deployCron       # src/etc/cron.d -> /etc/cron.d

./gradlew deployVault      # one stack
./gradlew deployAll        # every stack on the deployAll list

# then, on the host
cd /mnt/raid/services/vaultwarden && sudo docker compose up -d
```

Every `deploy<Svc>` task delegates to `deployService`, which creates
`/mnt/raid/services/<svc>`, copies the stack, and copies `_common/` into it. Secrets are **not** in
this repo: each stack's `.env` is created once by hand at `/mnt/raid/services/<svc>/.env` and is
never deployed.

`deployMariadb` is deliberately outside `deployAll` — that stack is not in production yet.

## Services

| Stack | Route | Notes |
|---|---|---|
| [traefik](https://traefik.io/) | — | reverse proxy and TLS, see [its README](src/services/traefik/README.md) |
| [jenkins](https://www.jenkins.io/) | `jenkins.tecronin.uk` | host `:8088`, container `8080` |
| [nexus](https://www.sonatype.com/products/nexus-repository) | `nexus.tecronin.uk` | `8081`, docker registry on `8082` |
| [sonarqube](https://www.sonarqube.org/) | `sonarqube.tecronin.uk` | with its own postgres |
| [grafana](https://grafana.com/) + [influxdb](https://www.influxdata.com/) | `grafana.tecronin.uk` | one stack; influxdb is intentionally not routed |
| [unifi OS Server](https://github.com/lemker/unifi-os-server) | `unifi.tecronin.uk` | [self-hosting UniFi](https://help.ui.com/hc/en-us/articles/34210126298775-Self-Hosting-UniFi), see [its README](src/services/unifi-os/README.md) |
| [vaultwarden](https://github.com/dani-garcia/vaultwarden) | `vaultwarden.tecronin.uk` | LAN-only |
| [wiki](https://www.bookstackapp.com/) | `wiki.tecronin.uk` | BookStack plus its own MariaDB |
| [gotify](https://gotify.net/) | `gotify.tecronin.uk` | notification target for backup failures and image alerts |
| [DIUN](https://crazymax.dev/diun/) | — | notify-only image watch |
| [portainer](https://www.portainer.io/) | `portainer.tecronin.uk` | |
| [obsidian-remote](https://github.com/sytone/obsidian-remote) | `obsidian.tecronin.uk` | |
| [openhab](https://www.openhab.org/) | `openhab.tecronin.uk` | home automation (wip) |
| [velxio](https://github.com/davidmonterocrespo24/velxio) | `velxio.tecronin.uk` | esp32 dev, needs a `Host` override |
| [nut_webgui](https://github.com/superioone/nut_webgui) | `upsdesktop.tecronin.uk`, `upspimgr.tecronin.uk` | UPS monitoring, one container per UPS |
| [rabbitmq](https://www.rabbitmq.com/) | `mq.tecronin.uk` | management UI; AMQP and MQTT published on the LAN |
| redis, timescaledb, mariadb | — | LAN-only datastores |
| gdrive | — | offsite sync for backup paths with no owning stack |
| restorer | — | throwaway ubuntu shell for poking at volumes |
| unifi | — | deprecated `jacobalberty/unifi`, kept until the OS Server migration is retired |

`weather.tecronin.uk` is routed too, but its backend is WeatherWatch on `tec-weather`, not a
container here.

## Reverse proxy and TLS

[Traefik](https://doc.traefik.io/traefik/v3.7/) replaced nginx + certbot. Routing is
`traefik.*` labels on each service's container, so proxy config travels with the service it belongs
to and deploys through the same gradle task. TLS is a single `*.tecronin.uk` wildcard from Let's
Encrypt via the Cloudflare DNS-01 challenge, set on the `websecure` entrypoint, so routers need no
cert labels at all.

Full route inventory, the three file-provider exceptions, and how to add a route:
[`src/services/traefik/README.md`](src/services/traefik/README.md).

A label change only takes effect once the container is recreated, so redeploy the stack and
`docker compose up -d` it.

## Backups

Three tiers, in the order data moves: named volume → NAS → Google Drive.

### Volume archives to the NAS

Stacks holding data that cannot be rebuilt run an [offen/docker-volume-backup](https://github.com/offen/docker-volume-backup/)
sidecar: **vaultwarden, unifi-os, wiki, gotify, traefik** (plus mariadb, deferred, and the
deprecated unifi stack). Each sidecar has its own cron, writes a timestamped `.tar.gz` into
`/mnt/backup/docker/<svc>`, and prunes it to `BACKUP_RETENTION_DAYS: 7` by matching
`BACKUP_PRUNING_PREFIX`.

Two conventions matter:

- **`docker-volume-backup.stop-during-backup=true`** on every container in the stack, so volumes are
  copied cold. No hot copies, no per-container judgement about which volume holds a datastore.
- **`EXEC_LABEL`** on every sidecar, matched by `docker-volume-backup.exec-label` on the containers
  it may exec into. Without it, offen runs lifecycle hooks on *every* labelled container on the
  host, and hooks cross-fire between stacks.

| Stack | Volume archived | Runs at |
|---|---|---|
| vaultwarden | `vaultwarden-storage` | 01:05 |
| unifi-os | six `unifi-os-*` volumes (`var-log` excluded) | 01:15 |
| mariadb | `mariadb-dumps` | 01:25 |
| gotify | `gotify-data` | 01:45 |
| traefik | `traefik-acme` | 01:50 |
| wiki | `mariadb_data`, `bookstack_config` | 02:00 |

MariaDB is the one exception to stopping. It is the only stack close to needing 24/7 availability,
so instead of a cold copy it takes a logical dump: `dump.sh` runs as an `archive-pre` hook
(`mariadb-dump --all-databases --single-transaction --routines --events --hex-blob`) and offen
archives the resulting `mariadb-dumps` volume rather than `mariadb-data`.

### Offsite to Google Drive

Each of those stacks also runs an idle [rclone](https://rclone.org/) sidecar — `tail -f /dev/null`
until offen execs it:

```yaml
    labels:
      - docker-volume-backup.exec-label=vaultwarden
      - docker-volume-backup.prune-post=/bin/sh /rclone-sync.sh
```

`prune-post` (not `archive-post`) is the hook that matters: it fires after the archive is written
*and* after retention has been applied, so `rclone sync` mirrors deletions instead of fighting them.
The shared `_common/rclone-sync.sh` reads `RCLONE_SRC`/`RCLONE_DEST`, runs `rclone sync`, and posts
to Gotify on a non-zero exit.

| Source | Destination |
|---|---|
| `/mnt/backup/docker/vaultwarden` | `gdrive:/backup/services/vault` |
| `/mnt/backup/docker/unifi-os` | `gdrive:/backup/services/unifi-os` |
| `/mnt/backup/docker/gotify` | `gdrive:/backup/services/gotify` |
| `/mnt/backup/docker/traefik` | `gdrive:/backup/services/traefik` |
| `/mnt/backup/docker/wiki` | `gdrive:/backup/docker/wiki` |
| `/mnt/backup/docker/services` | `gdrive:/backup/docker/services` |
| `/mnt/backup/weather/db` | `gdrive:/backup/weather/db` |

The remote is configured once on the host at `/root/.config/rclone/rclone.conf` and mounted
read-only into each sidecar.

### Config zip, and the paths nobody owns

`services_backup.sh` runs from `/etc/cron.d/service_backup_cron` at 08:00 and zips
`/mnt/raid/services` plus `/etc/environment` to `/mnt/backup/docker/services/svc-<date>.zip`,
keeping 15 days. That zip is the recovery path for every stack without a volume sidecar: jenkins,
nexus, grafana/influxdb, sonarqube, openhab, portainer, obsidian, velxio, redis, rabbitmq, and
timescaledb keep state in named volumes that are deliberately **not** archived, on the basis that
they can be rebuilt from compose plus that config.

The last two rows of the table above have no offen instance to hang a `prune-post` on, so
`src/services/gdrive/` covers them with a busybox `crond` at 08:15. It replaced the old host rclone
cron and the `/opt/rclone` install.

### Restore

- [restore volumes from backup](https://offen.github.io/docker-volume-backup/how-tos/restore-volumes-from-backup.html) — verified by hand for vaultwarden
- the `restorer` stack mounts a scratch volume plus a backup volume read-only, for unpacking an
  archive into a fresh volume before pointing a service at it

## Notifications

[Gotify](https://gotify.net/) is the single notification target: rclone failures and DIUN image
alerts. Tokens live in the **host's** `/etc/environment`, which compose injects into the rclone
sidecars and DIUN via `env_file`. After Gotify's first boot, create two applications in its UI and
add:

```
GOTIFY_DEFAULTUSER_PASS=<admin-password>
GOTIFY_APP_TOKEN=<rclone-app-token>
DIUN_NOTIF_GOTIFY_TOKEN=<diun-app-token>
```

Then `sudo docker compose up -d` those stacks so the containers pick it up. A stack `.env` next to
`docker-compose.yml` is also loaded for Gotify and overrides `/etc/environment`. `/etc/environment`
is world-readable; that is the tradeoff for keeping this to one file. The admin password is only
applied on the first boot of an empty `gotify-data` volume.

## Image updates (notify-only)

DIUN checks registries daily at 06:00 and posts to Gotify. Nothing pulls or restarts on its own —
git stays the source of truth for tags.

1. Open the Gotify message and note the new tag.
2. Bump `image:` in that service's `docker-compose.yml` and commit.
3. `./gradlew deploy<Svc>`, then `docker compose up -d` on the host.

`obsidian-remote` and `velxio` only publish a moving tag (`latest` / `master`), so they are watched
by digest with `diun.watch_repo=false`. Jenkins and SonarQube use `diun.include_tags` to filter
noisy upstream tags. Sidecar copies of `offen` and `rclone` carry `diun.enable=false`, so each image
alerts once — from `vaultwarden-backup` and `gdrive-sync` respectively.

## kvm
- [setup bridged network nm](https://gist.github.com/plembo/f7abd2d9b6f76e7afdece02dae7e5097)
- [kvm bridge network](https://gist.github.com/plembo/a7b69f92953a76ab2d06533754b5e2bb)

## nas
- [letsencrypt certs](https://www.truenas.com/docs/scale/scaletutorials/credentials/certificates/settingupletsencryptcertificates/)

## TODO
- container monitoring dashboard — see [`.cursor/plan/prometheus-monitoring-stack.md`](.cursor/plan/prometheus-monitoring-stack.md)
- move the weather database into `src/services/mariadb` — see [`.cursor/plan/weather-mariadb-migration.md`](.cursor/plan/weather-mariadb-migration.md)
- custom container from nexus
- [multi volume backup](https://offen.github.io/docker-volume-backup/recipes/#running-multiple-instances-in-the-same-setup)
- [backup alternative for multi-volume](https://github.com/blacklabelops/volumerize)
    - [komodo](https://komo.do/docs/intro)
- [pihole](https://pi-hole.net/)
- [smtp relay](https://github.com/wader/postfix-relay)
- [authentik](https://docs.goauthentik.io/docs/install-config/install/docker-compose)
- [uptime-kuma](https://github.com/louislam/uptime-kuma)
- [netbox](https://github.com/netbox-community/netbox)
- [rustdesk](https://rustdesk.com/docs/en/self-host/rustdesk-server-oss/docker/)
- [speedtest-tracker](https://github.com/alexjustesen/speedtest-tracker)
- [cockpit](https://hub.docker.com/r/markdegroot/cockpit-ubuntu)

## FAQ
- [docker-compose syntax](https://docs.docker.com/compose/compose-file/#compose-file-structure-and-examples)
- get volumes mapped to a given container
    - ```docker inspect --type container -f '{{range $i, $v := .Mounts }}{{printf "%v\n" $v}}{{end}}' <container_id>```
- map every volume to the containers using it
    - ```/mnt/raid/bin/convol.sh```
- shell into container
    - ```docker exec -it <container name> /bin/bash```
- container shell to copy volume data (WIP)
    - ```docker run -it --rm -v <src volume>:/src:ro -v <dest volume>:/dest bash:latest```
- create compose compatible volume
    - ```docker volume create --name "vol_name" --label "com.docker.compose.project=container_name" --label "com.docker.compose.version=$(docker compose version)" --label "com.docker.compose.volume=vol_name"```
    - `/mnt/raid/bin/volumes.sh` does this for the existing named volumes
- why did a route stop working
    - a label change needs the container recreated: `docker compose up -d` on that stack
    - a bad label silently drops the route rather than failing loudly; check `docker logs traefik`
