# Prometheus

Pull-based monitoring for the estate: Prometheus scrapes node_exporter on every
host, cAdvisor on this host, and Traefik's unpublished metrics entrypoint.
Grafana is the query UI, dashboard host, and alerter; Gotify is the sink.

Access: `https://prometheus.tecronin.uk` (LAN-only via `lan-only@file`).
Grafana stays at `https://grafana.tecronin.uk`.

The Prometheus TSDB is **not** backed up. It is large and regenerable from
live scrapes. `grafana-data` is backed up by the grafana stack's offen sidecar.

## Scrapes

| Job | Target | What |
|---|---|---|
| `node` | `tec-desktop.localdomain:9100` | this host, compose `node-exporter` with host networking |
| `node` | `tec-kvm.localdomain:9100` | PiKVM, `pacman -S prometheus-node-exporter` |
| `node` | `tec-weather.localdomain:9100` | weather host, native node_exporter via piImage |
| `node` | `tec-pi-mgr.localdomain:9100` | mgr Pi |
| `node` | `tec-time.localdomain:9100` | time Pi, native node_exporter via piImage |
| `node` | `fort-apache.localdomain:9100` | OPNsense `os-node_exporter` plugin |
| `cadvisor` | `cadvisor:8080` | containers on tec-desktop, unpublished, share-net only |
| `traefik` | `traefik:8082` | Traefik Prometheus metrics + `/ping`, unpublished |

Interval is 30s. Retention is 90 days / 15 GB.

Prometheus uses OPNsense DNS (`192.168.1.1`) so `.localdomain` names resolve.
cAdvisor and Traefik are docker names on `share-net`.

node_exporter listens on host port 9100 on every machine and should be firewalled
to the LAN. cAdvisor has no Traefik router.

## Agents on the other hosts

Native `prometheus-node-exporter` is the [piImage](https://github.com/tim-oe/piImage)
role `common/node_exporter`, on the `pi` group (`tec-pi-mgr`, `tec-time`,
`tec-weather`, …). Apply from tec-pi-mgr:

```bash
cd ~/src/piImage
inv ansible.role --name common.node_exporter --host tec-pi-mgr
inv ansible.role --name common.node_exporter --host tec-time
inv ansible.role --name common.node_exporter --host tec-weather
```

tec-desktop already has the compose `node-exporter`; do not apply that role
there. Allow TCP 9100 from the LAN if a host filters inbound.

### tec-kvm (PiKVM)

Arch overlay, not the apt role. SSH as root:

```bash
rw
pacman -S prometheus-node-exporter
systemctl enable --now prometheus-node-exporter
ro
```

### OPNsense (fort-apache)

1. System > Firmware > Plugins > install `os-node_exporter`.
2. Services > Node Exporter: enable, listen `0.0.0.0:9100`.
3. Firewall > Rules > LAN: allow TCP 9100 from `192.168.1.0/24`.
4. Confirm `https://prometheus.tecronin.uk/targets` shows `fort-apache` up.

### Optional

- **UPS:** `ghcr.io/druggeri/nut_exporter` against the two `upsd` instances at
  `tec-desktop.localdomain:3493` and `tec-pi-mgr.localdomain:3493` that
  `src/services/upsmon` already talks to. Not deployed.
- **UniFi:** `ghcr.io/unpoller/unpoller` for AP, switch, and client metrics. Not
  deployed.

## Grafana alerts

Provisioned under `src/services/grafana/provisioning/`. Contact point is a
webhook to `http://gotify/message`. Create a **second** Gotify application
(not DIUN's) so image-update and alert notifications mute independently:

```bash
# on the host, after deployGrafana has copied the stack
# GRAFANA_USERNAME / GRAFANA_PASSWORD / GRAFANA_DOMAIN already live here
echo 'GOTIFY_TOKEN=<grafana-gotify-app-token>' >> /mnt/raid/services/grafana/.env
```

`GOTIFY_TOKEN` is required; compose will refuse to start grafana without it.

## Deployment (files only)

```bash
./gradlew deployPrometheus
./gradlew deployGrafana
./gradlew deployTraefik   # Traefik metrics entrypoint is in the static config

# on the host
cd /mnt/raid/services/prometheus && sudo docker compose up -d
cd /mnt/raid/services/grafana && sudo docker compose up -d
# Traefik static config change needs a recreate
cd /mnt/raid/services/traefik && sudo docker compose up -d
```

Bring Prometheus up before Grafana so the datasource has something to talk to.
InfluxDB was in the grafana stack and is gone; `docker compose up` will drop
that container. Its empty volumes (`influxdb-data`, `influxdb-data2`,
`influxdb-conf`, `grafana-provisioning`) can be removed by hand after cutover.

`prometheus.tecronin.uk` is already on the `*.tecronin.uk` wildcard. No extra
DNS record.
