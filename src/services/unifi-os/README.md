# UniFi OS Server

Replaces the EOL `jacobalberty/unifi` controller with [lemker/unifi-os-server](https://github.com/lemker/unifi-os-server).
The old `src/services/unifi/` stack was removed 2026-09-06.

Access after cutover: `https://unifi.tecronin.uk`

Do not start a second controller on 3478/udp.

`privileged: true` is required so `unifi-core` can start. Without it the service dies in `ExecStartPre` with `Result: timeout` and `:11443` accepts TCP but never completes TLS.

That same privileged systemd will spawn gettys on the host's TTYs and take over the local console — the login prompt becomes `uos-server` instead of `tec-desktop` ([upstream #58](https://github.com/lemker/unifi-os-server/issues/58)). The compose file masks those units by bind-mounting `/dev/null` over them. After deploying, recreate the container and reboot the host once; stopping the container alone does not give the console back. SSH is unaffected. If the host hostname itself was rewritten, restore it with `hostnamectl set-hostname tec-desktop`.

`unifi-core-timeout.conf` is bind-mounted into the image's systemd drop-in dir. It sets `TimeoutStartSec=15min` and replaces `ExecStartPre` with: wait for `pg_isready` on 5432, then the vendor hook. The image's `postgresql.service` is `ExecStart=/bin/true`; without the wait, `unifi-core` races `postgresql@14-main` and sticks in `start-pre` until a manual restart. The wait default is 900s (`UNIFI_CORE_PG_WAIT_TIMEOUT`) so crash recovery after an interrupted shutdown can finish. `stop_grace_period: 2m` gives systemd time to stop postgres cleanly on host reboot; Docker's 10s default SIGKILLs it and leaves a stale pid. The healthcheck is Postgres + `unifi-core` + `unifi` + `ulp-go`; `docker compose up` does not wait unless you pass `--wait --wait-timeout 900`. Do not PATH-shim `chown` — that crashed `unifi-core`.

## Deployment (files only)

```bash
# Creates /mnt/raid/services/unifi-os and /mnt/backup/docker/unifi-os, then copies compose
./gradlew deployUnifiOs

# On the server — named volumes (compose will also create these on first up)
# /mnt/raid/bin/volumes.sh   # or just the unifi-os-* lines

# Inform address for adopted devices — LAN IP of tec-desktop, not unifi.tecronin.uk
echo 'UOS_SYSTEM_IP=<lan-ip>' > /mnt/raid/services/unifi-os/.env
```

Routing is Traefik labels on `unifi-os-server` (`unifi.tecronin.uk`, `lan-only@file`, `unifi@file` transport).

After a restart the container is `health: starting` until Postgres, `unifi-core`, `unifi`, and `ulp-go` are all active (up to 15 minutes, longer if `ubnt-dpkg-restore` is unpacking a pending Network app upgrade). Traefik keeps the router during that window (`allowEmptyServices`); the UI 404s only if the labels never landed. Direct check while Core is still down: `https://<lan-ip>:11443`.

## Cutover

Done 2026-09. Old jacobalberty stack removed. Runbook kept in
[`.cursor/plan/unifi-os-server-migration.md`](../../../.cursor/plan/unifi-os-server-migration.md) Phase 3.

## Rollback

`docker compose down` here, then restore the `unifi-os-*` volumes from `/mnt/backup/docker/unifi-os`.
The jacobalberty stack is gone.
