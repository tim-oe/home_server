# Traefik

[Traefik v3.7](https://doc.traefik.io/traefik/v3.7/) replaces nginx + certbot. Routing lives as
docker labels on each service; this stack only holds the static config, the file-provider
exceptions, and `acme.json`.

Access: `https://<svc>.tecronin.uk`. HTTP on :80 redirects to HTTPS.

## Routes

| Host | Backend | How |
|---|---|---|
| `nexus.tecronin.uk` | nexus:8081 | labels |
| `jenkins.tecronin.uk` | jenkins:8080 | labels |
| `grafana.tecronin.uk` | grafana:3000 | labels |
| `prometheus.tecronin.uk` | prometheus:9090 | labels + `lan-only@file` |
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

`prometheus.tecronin.uk` is LAN-only. Prometheus has no authentication of its own.
The deprecated `unifi` stack is not routed; `unifi.tecronin.uk` is UniFi OS Server.

velxio's Host override is a label, not a file exception — the
[headers middleware](https://doc.traefik.io/traefik/v3.7/reference/routing-configuration/http/middlewares/headers/)
special-cases `Host` in `customRequestHeaders`, so
`traefik.http.middlewares.velxio-host.headers.customrequestheaders.Host=localhost` does what
nginx's `proxy_set_header Host localhost` used to.

## File-provider exceptions

Labels cannot express these, so they live in `dynamic/`, loaded by the
[file provider](https://doc.traefik.io/traefik/v3.7/reference/install-configuration/providers/others/file/)
with `watch: true` — edits apply without restarting Traefik. Syntax:
[file routing configuration](https://doc.traefik.io/traefik/v3.7/reference/routing-configuration/other-providers/file/).

- **`middlewares.yml`** — `lan-only` [`ipAllowList`](https://doc.traefik.io/traefik/v3.7/reference/routing-configuration/http/middlewares/ipallowlist/) for vaultwarden, unifi-os, and prometheus (`192.168.1.0/24`, `10.9.0.0/24`). Traefik v3 renamed this from v2's `ipWhiteList`.
- **`transports.yml`** — `unifi` [ServersTransport](https://doc.traefik.io/traefik/v3.7/reference/routing-configuration/http/load-balancing/serverstransport/) with `insecureSkipVerify` and 600s restore timeouts. Referenced as `traefik.http.services.unifi-os.loadbalancer.serverstransport=unifi@file`. This is the one thing that *cannot* be set from docker labels.
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

Full list of supported labels:
[docker routing configuration](https://doc.traefik.io/traefik/v3.7/reference/routing-configuration/other-providers/docker/).
What each one above does:

| Label | Reference |
|---|---|
| `traefik.enable` | required because the provider runs with `exposedByDefault: false` — see [docker provider](https://doc.traefik.io/traefik/v3.7/reference/install-configuration/providers/docker/) |
| `routers.<svc>.rule` | matchers and precedence: [rules and priority](https://doc.traefik.io/traefik/v3.7/reference/routing-configuration/http/routing/rules-and-priority/) |
| `routers.<svc>.entrypoints` | [entrypoints](https://doc.traefik.io/traefik/v3.7/reference/install-configuration/entrypoints/) — `web` and `websecure`, defined in `traefik.yml` |
| `routers.<svc>.middlewares` | [middlewares overview](https://doc.traefik.io/traefik/v3.7/reference/routing-configuration/http/middlewares/overview/); `@file` suffix references `dynamic/` |
| `services.<svc>.loadbalancer.*` | [HTTP services](https://doc.traefik.io/traefik/v3.7/reference/routing-configuration/http/load-balancing/service/) — `server.port`, `server.scheme`, `serverstransport` |

`port` is the port *inside* the container on `share-net`, not a published host port. Websocket
upgrade is automatic and there is no request body size limit, so nothing like nginx's
`proxy_set_header`/`client_max_body_size` is needed.

TLS is already on the websecure entrypoint, so no cert labels. Then:

```bash
./gradlew deploy<Svc>
# on the host, in /mnt/raid/services/<svc>
sudo docker compose up -d
```

The wildcard already covers `*.tecronin.uk`. Add a DNS A/CNAME if it is not already on the wildcard record.

## Static config (`traefik.yml`)

Everything here is startup config — changing it needs the container restarted, unlike `dynamic/`,
which is watched. Full option list:
[install configuration options](https://doc.traefik.io/traefik/v3.7/reference/install-configuration/configuration-options/).

| Setting | What it does here |
|---|---|
| [`entryPoints`](https://doc.traefik.io/traefik/v3.7/reference/install-configuration/entrypoints/) | `web` :80 redirects to `websecure` :443; `metrics` :8082 is unpublished and used for `/ping` plus Prometheus metrics |
| [`entryPoints.websecure.http.tls`](https://doc.traefik.io/traefik/v3.7/reference/routing-configuration/http/tls/tls-certificates/) | the `tecronin.uk` + `*.tecronin.uk` wildcard is set on the entrypoint, so one cert covers every route and no router carries TLS labels |
| [`certificatesResolvers.cloudflare.acme`](https://doc.traefik.io/traefik/v3.7/reference/install-configuration/tls/certificate-resolvers/acme/) | DNS-01 challenge, stored in `/letsencrypt/acme.json`. Provider credentials are [lego's Cloudflare env vars](https://go-acme.github.io/lego/dns/cloudflare/) — `CF_DNS_API_TOKEN` from `.env` |
| [`providers.docker`](https://doc.traefik.io/traefik/v3.7/reference/install-configuration/providers/docker/) | `exposedByDefault: false` so nothing is routed by accident; `network: share-net` picks the right container IP; `allowEmptyServices: true` so a Docker healthcheck that is still `starting` (unifi-os) does not delete the router and 404 |
| [`providers.file`](https://doc.traefik.io/traefik/v3.7/reference/install-configuration/providers/others/file/) | `directory: /dynamic`, `watch: true` |
| [`api.dashboard`](https://doc.traefik.io/traefik/v3.7/reference/install-configuration/api-dashboard/) | built but with `insecure: false` and no router, so it is not reachable |
| [`ping`](https://doc.traefik.io/traefik/v3.7/reference/install-configuration/observability/healthcheck/) | `/ping` on the `metrics` entrypoint (:8082), which the compose healthcheck calls |
| [`metrics.prometheus`](https://doc.traefik.io/traefik/v3.7/reference/install-configuration/observability/metrics/) | `/metrics` on the same unpublished entrypoint; Prometheus scrapes `traefik:8082` over share-net |
| [`log`](https://doc.traefik.io/traefik/v3.7/reference/install-configuration/observability/logs-and-accesslogs/) | `INFO` to stdout; access logs are off |

A bad label does not fail loudly the way `nginx -t` did — it silently drops the route. `docker logs
traefik` is the place to look.

## Deployment (files only)

```bash
./gradlew deployTraefik

# on the host — after deploy, so gradle put does not clobber it
# CF_DNS_API_TOKEN is the Cloudflare token used for DNS-01
echo 'CF_DNS_API_TOKEN=<token>' > /mnt/raid/services/traefik/.env
# optional, rclone failure alerts: GOTIFY_APP_TOKEN in host /etc/environment
```

A label change needs `docker compose up -d` on that service so Traefik sees the new labels.

Let's Encrypt renewal is Traefik's ACME resolver (Cloudflare DNS-01). `acme.json` is backed up by the offen + rclone sidecars.
