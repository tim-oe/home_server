# Traefik

[Traefik v3.7](https://doc.traefik.io/traefik/v3.7/) replaces nginx + certbot. Routing lives as
docker labels on each service; this stack only holds the static config, the file-provider
exceptions, and `acme.json`.

Access: `https://<svc>.tecronin.uk`. HTTP on :80 redirects to HTTPS.

Two HTTPS entrypoints:

- **`websecure` `:443`** — LAN and WireGuard. Every router is here. `lan-only@file`
  (`192.168.1.0/24`, `10.9.0.0/24`) is applied at the entrypoint, so a new service that
  copies the label template is not reachable from the internet. Curl from tec-desktop
  itself against a `*.tecronin.uk` name returns **403**; that is expected (the source is
  the Docker bridge, not the LAN).
- **`public` `:8443`** — internet. OPNsense forwards WAN:443 here. Only routers that
  list `entrypoints=websecure,public` are reachable. That is currently **wiki** and
  **weather**.

JSON `accessLog` is on. Filter public traffic with
`docker logs traefik | jq -R 'fromjson? | select(.entryPointName=="public")'`.

## Routes

| Host | Backend | How | Public |
|---|---|---|---|
| `nexus.tecronin.uk` | nexus:8081 | labels | no |
| `jenkins.tecronin.uk` | jenkins:8080 | labels | no |
| `grafana.tecronin.uk` | grafana:3000 | labels | no |
| `prometheus.tecronin.uk` | prometheus:9090 | labels + `prometheus-lan` ipAllowList | no |
| `sonarqube.tecronin.uk` | sonarqube:9000 | labels | no |
| `portainer.tecronin.uk` | portainer:9000 | labels | no |
| `obsidian.tecronin.uk` | obsidian:8080 | labels | no |
| `wiki.tecronin.uk` | bookstack:80 | labels | **yes** |
| `vaultwarden.tecronin.uk` | vaultwarden:8860 | labels + `vaultwarden-lan` ipAllowList | no |
| `git.tecronin.uk` | forgejo:3000 | labels + `forgejo-lan` ipAllowList | no |
| `upsdesktop.tecronin.uk` | upsdesktop:8010 | labels | no |
| `upspimgr.tecronin.uk` | upspimgr:8020 | labels | no |
| `velxio.tecronin.uk` | velxio:80 | labels + Host override | no |
| `mq.tecronin.uk` | rabbitmq:15672 | labels | no |
| `openhab.tecronin.uk` | openhab:8881 | labels | no |
| `gotify.tecronin.uk` | gotify:80 | labels | no |
| `backrest.tecronin.uk` | backrest:9898 | labels + `backrest-lan` ipAllowList | no |
| `unifi.tecronin.uk` | unifi-os-server:443 (https) | labels + `unifi@file` + `unifi-os-lan` ipAllowList | no |
| `weather.tecronin.uk` | tec-weather.localdomain:8000 (WeatherWatch) | file provider | **yes** |

`prometheus.tecronin.uk` is LAN-only. Prometheus has no authentication of its own.
`lan-only@file` now also applies to every `websecure` router; the per-service ipAllowList
labels on prometheus, vaultwarden, unifi-os, forgejo, and backrest stay as a must-never-be-public marker.
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

- **`middlewares.yml`** — `lan-only` [`ipAllowList`](https://doc.traefik.io/traefik/v3.7/reference/routing-configuration/http/middlewares/ipallowlist/) (`192.168.1.0/24`, `10.9.0.0/24`), applied on the `websecure` entrypoint. Do not also set a docker label of `middlewares=lan-only@file`: that 404s on Traefik start until this file is parsed. Vaultwarden, prometheus, unifi-os, and forgejo keep the same CIDRs as labels on the app container. Traefik v3 renamed this from v2's `ipWhiteList`.
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

`entrypoints=websecure` is LAN-only (plus WireGuard). Publishing to the internet is a
deliberate second label: `entrypoints=websecure,public`. Only wiki and weather do that.

Before testing from the LAN, create the **Unbound host override** on OPNsense:
`<svc>.tecronin.uk` → `192.168.1.35`. Without it the LAN resolves the name to the WAN
IP, NAT reflection delivers it to the `public` entrypoint, and a new LAN-only service
404s. That is fail-closed, not a broken deploy.

LAN-only extra lock (still needed for services that must never grow a `public`
entrypoint): add the ipAllowList on **this** container (unique middleware name) and
point the router at it with no `@file`. Copying `lan-only@file` from an old stack
404s until Traefik parses `/dynamic`.

```yaml
      - traefik.http.middlewares.<svc>-lan.ipallowlist.sourcerange=192.168.1.0/24,10.9.0.0/24
      - traefik.http.routers.<svc>.middlewares=<svc>-lan
```

Full list of supported labels:
[docker routing configuration](https://doc.traefik.io/traefik/v3.7/reference/routing-configuration/other-providers/docker/).
What each one above does:

| Label | Reference |
|---|---|
| `traefik.enable` | required because the provider runs with `exposedByDefault: false` — see [docker provider](https://doc.traefik.io/traefik/v3.7/reference/install-configuration/providers/docker/) |
| `routers.<svc>.rule` | matchers and precedence: [rules and priority](https://doc.traefik.io/traefik/v3.7/reference/routing-configuration/http/routing/rules-and-priority/) |
| `routers.<svc>.entrypoints` | [entrypoints](https://doc.traefik.io/traefik/v3.7/reference/install-configuration/entrypoints/) — `websecure` is LAN-only; add `public` only to publish |
| `routers.<svc>.middlewares` | [middlewares overview](https://doc.traefik.io/traefik/v3.7/reference/routing-configuration/http/middlewares/overview/); omit `@file` when the middleware is a label on the same container |
| `services.<svc>.loadbalancer.*` | [HTTP services](https://doc.traefik.io/traefik/v3.7/reference/routing-configuration/http/load-balancing/service/) — `server.port`, `server.scheme`, `serverstransport` |

`port` is the port *inside* the container on `share-net`, not a published host port. Websocket
upgrade is automatic and there is no request body size limit, so nothing like nginx's
`proxy_set_header`/`client_max_body_size` is needed.

TLS is already on the websecure (and public) entrypoint, so no cert labels. Then:

```bash
./gradlew deploy<Svc>
# on the host, in /mnt/raid/services/<svc>
sudo docker compose up -d
```

Create the Unbound override **before** that test. Public DNS (A/CNAME, orange cloud)
is only for services that opt into `public`; wiki and weather are reconciled by
`src/bin/cloudflare-dns.sh`.

## Static config (`traefik.yml`)

Everything here is startup config — changing it needs the container restarted, unlike `dynamic/`,
which is watched. Full option list:
[install configuration options](https://doc.traefik.io/traefik/v3.7/reference/install-configuration/configuration-options/).

| Setting | What it does here |
|---|---|
| [`entryPoints`](https://doc.traefik.io/traefik/v3.7/reference/install-configuration/entrypoints/) | `web` :80 redirects to `websecure` :443; `websecure` is LAN-only with `lan-only@file`; `public` :8443 is internet (wiki/weather only); `metrics` :8082 is unpublished and used for `/ping` plus Prometheus metrics |
| [`entryPoints.websecure.http.tls`](https://doc.traefik.io/traefik/v3.7/reference/routing-configuration/http/tls/tls-certificates/) (and the same block on `public`) | the `tecronin.uk` + `*.tecronin.uk` wildcard is set on the entrypoint, so one cert covers every route and no router carries TLS labels |
| [`certificatesResolvers.cloudflare.acme`](https://doc.traefik.io/traefik/v3.7/reference/install-configuration/tls/certificate-resolvers/acme/) | DNS-01 challenge, stored in `/letsencrypt/acme.json`. Provider credentials are [lego's Cloudflare env vars](https://go-acme.github.io/lego/dns/cloudflare/) — `CF_DNS_API_TOKEN` from the host `/etc/environment` |
| [`providers.docker`](https://doc.traefik.io/traefik/v3.7/reference/install-configuration/providers/docker/) | `exposedByDefault: false` so nothing is routed by accident; `network: share-net` picks the right container IP; `allowEmptyServices: true` so a Docker healthcheck that is still `starting` (unifi-os) does not delete the router and 404 |
| [`providers.file`](https://doc.traefik.io/traefik/v3.7/reference/install-configuration/providers/others/file/) | `directory: /dynamic`, `watch: true` |
| [`api.dashboard`](https://doc.traefik.io/traefik/v3.7/reference/install-configuration/api-dashboard/) | built but with `insecure: false` and no router, so it is not reachable |
| [`ping`](https://doc.traefik.io/traefik/v3.7/reference/install-configuration/observability/healthcheck/) | `/ping` on the `metrics` entrypoint (:8082), which the compose healthcheck calls |
| [`metrics.prometheus`](https://doc.traefik.io/traefik/v3.7/reference/install-configuration/observability/metrics/) | `/metrics` on the same unpublished entrypoint; Prometheus scrapes `traefik:8082` over share-net |
| [`log`](https://doc.traefik.io/traefik/v3.7/reference/install-configuration/observability/logs-and-accesslogs/) | `INFO` to stdout; JSON `accessLog` on. Filter with `jq -R 'fromjson? | select(.entryPointName=="public")'` |

A bad label does not fail loudly the way `nginx -t` did — it silently drops the route. `docker logs
traefik` is the place to look.

## Deployment (files only)

```bash
./gradlew deployTraefik

# on the host — CF_DNS_API_TOKEN in /etc/environment is the Cloudflare token used for DNS-01
# optional, rclone failure alerts: GOTIFY_APP_TOKEN in the same file
```

A label change needs `docker compose up -d` on that service so Traefik sees the new labels.

Let's Encrypt renewal is Traefik's ACME resolver (Cloudflare DNS-01). `acme.json` is backed up by the offen + rclone sidecars.
