# UniFi OS Server

Replaces the EOL `jacobalberty/unifi` controller with [lemker/unifi-os-server](https://github.com/lemker/unifi-os-server).
The old stack in `src/services/unifi/` stays in place until cutover is verified.

Access after cutover: `https://unifi.tecronin.uk`

Do not start this stack while the old `unifi` container is running — they share 3478/udp.

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

## Cutover

Full runbook: [`.cursor/plan/unifi-os-server-migration.md`](../../../.cursor/plan/unifi-os-server-migration.md) Phase 3.

1. Export a settings-only `.unf` from the old controller.
2. Stop the old stack: `cd /mnt/raid/services/unifi && docker compose stop` (not `down -v`).
3. Start this stack: `cd /mnt/raid/services/unifi-os && docker compose up -d`.
4. Wizard at `https://<lan-ip>:11443` — same admin username as the old controller, **Continue Without Backup**.
5. Restore the `.unf` from Settings > System > Backups.
6. Wait for APs to come online via the `8882:8080` shim, then remove that port mapping.

UI is `https://unifi.tecronin.uk` via Traefik (self-signed backend, WebSocket, no body-size cap for `.unf` restores).

## Rollback

`docker compose down` here, then `docker compose up -d` in `src/services/unifi`. The old controller volume is untouched.
