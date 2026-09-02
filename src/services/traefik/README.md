# Traefik

Replaces nginx + certbot. Routing lives as docker labels on each service; this
stack only holds the static config, the file-provider exceptions, and `acme.json`.

Access: `https://<svc>.tecronin.uk`. HTTP on :80 redirects to HTTPS.

## Routes

| Host | Backend | How |
|---|---|---|
| `nexus.tecronin.uk` | nexus:8081 | labels |
| `jenkins.tecronin.uk` | jenkins:8080 | labels |
| `grafana.tecronin.uk` | grafana:3000 | labels |
| `sonarqube.tecronin.uk` | sonarqube:9000 | labels |
| `portainer.tecronin.uk` | portainer:9000 | labels |
| `obsidian.tecronin.uk` | obsidian:8080 | labels |
| `wiki.tecronin.uk` | bookstack:80 | labels |
| `vaultwarden.tecronin.uk` | vaultwarden:8860 | labels + `lan-only@file` |
| `upsdesktop.tecronin.uk` | upsdesktop:8010 | labels |
| `upspimgr.tecronin.uk` | upspimgr:8020 | labels |
| `velxio.tecronin.uk` | velxio:80 | labels + Host override |
| `mq.tecronin.uk` | rabbitmq:15672 | labels |
| `openhab.tecronin.uk` | openhab:8881 | labels |
| `gotify.tecronin.uk` | gotify:80 | labels |
| `unifi.tecronin.uk` | unifi-os-server:443 (https) | labels + `unifi@file` + `lan-only@file` |
| `weather.tecronin.uk` | tec-weather.localdomain:8000 (WeatherWatch) | file provider |

`influxdb.tecronin.uk` is intentionally not routed (metrics stay on the LAN port).
The deprecated `unifi` stack is not routed; `unifi.tecronin.uk` is UniFi OS Server.

## File-provider exceptions

Labels cannot express these, so they live in `dynamic/`:

- **`middlewares.yml`** — `lan-only` `ipAllowList` for vaultwarden and unifi-os (`192.168.1.0/24`, `10.9.0.0/24`). Traefik v3 renamed this from v2's `ipWhiteList`.
- **`transports.yml`** — `unifi` ServersTransport with `insecureSkipVerify` and 600s restore timeouts. Referenced as `traefik.http.services.unifi-os.loadbalancer.serverstransport=unifi@file`.
- **`external.yml`** — WeatherWatch on `tec-weather.localdomain:8000`, not a container on `share-net`.
  Traefik uses OPNsense (`dns: 192.168.1.1`) so that LAN name does not loop back to this host
  (`weather.tecronin.uk` is the public name for tec-desktop).

## Add a route for a new service

On the app container (not sidecars):

```yaml
    labels:
      - traefik.enable=true
      - traefik.http.routers.<svc>.rule=Host(`<svc>.tecronin.uk`)
      - traefik.http.routers.<svc>.entrypoints=websecure
      - traefik.http.services.<svc>.loadbalancer.server.port=<container-port>
```

TLS is already on the websecure entrypoint, so no cert labels. Then:

```bash
./gradlew deploy<Svc>
# on the host, in /mnt/raid/services/<svc>
sudo docker compose up -d
```

The wildcard already covers `*.tecronin.uk`. Add a DNS A/CNAME if it is not already on the wildcard record.

## Deployment (files only)

```bash
./gradlew deployTraefik

# on the host — after deploy, so gradle put does not clobber it
# CF_DNS_API_TOKEN is the Cloudflare token used for DNS-01
echo 'CF_DNS_API_TOKEN=<token>' > /mnt/raid/services/traefik/.env
# optional, for rclone failure alerts
# optional, rclone failure alerts: GOTIFY_APP_TOKEN in host /etc/environment
```

A label change needs `docker compose up -d` on that service so Traefik sees the new labels.

Let's Encrypt renewal is Traefik's ACME resolver (Cloudflare DNS-01). `acme.json` is backed up by the offen + rclone sidecars.
