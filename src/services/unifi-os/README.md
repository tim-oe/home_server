# UniFi OS Server

Replaces the EOL `jacobalberty/unifi` controller with [lemker/unifi-os-server](https://github.com/lemker/unifi-os-server).
The old stack in `src/services/unifi/` stays in place until cutover is verified.

Access after cutover: `https://unifi.tecronin.uk`

Do not start this stack while the old `unifi` container is running — they share 3478/udp.

`privileged: true` is required so `unifi-core` can start. Without it the service dies in `ExecStartPre` with `Result: timeout` and `:11443` accepts TCP but never completes TLS.

`unifi-core-timeout.conf` is bind-mounted into the image's systemd drop-in dir. It sets `TimeoutStartSec=15min` and replaces `ExecStartPre` with: wait for `pg_isready` on 5432, then the vendor hook. The image's `postgresql.service` is `ExecStart=/bin/true`; without the wait, `unifi-core` races `postgresql@14-main` and sticks in `start-pre` until a manual restart. The wait default is 900s (`UNIFI_CORE_PG_WAIT_TIMEOUT`) so crash recovery after an interrupted shutdown can finish. `stop_grace_period: 2m` gives systemd time to stop postgres cleanly on host reboot; Docker's 10s default SIGKILLs it and leaves a stale pid. The healthcheck is Postgres + `unifi-core` + `unifi` + `ulp-go`; `docker compose up` does not wait unless you pass `--wait --wait-timeout 900`. Do not PATH-shim `chown` — that crashed `unifi-core`.

## Deployment (files only)

```bash
# Creates /mnt/raid/services/unifi-os and /mnt/backup/docker/unifi-os, then copies compose + vhost
./gradlew deployUnifiOs

# On the server — named volumes (compose will also create these on first up)
# /mnt/raid/bin/volumes.sh   # or just the unifi-os-* lines

# Inform address for adopted devices — LAN IP of tec-desktop, not unifi.tecronin.uk
echo 'UOS_SYSTEM_IP=<lan-ip>' > /mnt/raid/services/unifi-os/.env
```

Do **not** copy `unifi-os.conf` into nginx `.conf.d` until cutover. Two `server_name unifi.tecronin.uk` blocks will fail `nginx -t`.

## Cutover

Full runbook: [`.cursor/plan/unifi-os-server-migration.md`](../../../.cursor/plan/unifi-os-server-migration.md) Phase 3.

1. Export a settings-only `.unf` from the old controller.
2. Stop the old stack: `cd /mnt/raid/services/unifi && docker compose stop` (not `down -v`).
3. Start this stack: `cd /mnt/raid/services/unifi-os && docker compose up -d`.
4. Wizard at `https://<lan-ip>:11443` — same admin username as the old controller, **Continue Without Backup**.
5. Restore the `.unf` from Settings > System > Backups.
6. Wait for APs to come online via the `8882:8080` shim, then remove that port mapping.
7. Swap the nginx vhost: remove `unifi.conf` from `.conf.d`, copy in `unifi-os.conf`, `nginx -t` and reload.

## nginx vhost notes

- Proxies to `https://unifi.localdomain` (compose network alias).
- WebSocket upgrade is required for the UniFi OS UI.
- `client_max_body_size 1G` is required for `.unf` restore uploads.

## Rollback

`docker compose down` here, restore `unifi.conf` in nginx `.conf.d`, reload nginx, `docker compose up -d` in `src/services/unifi`.
