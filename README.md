# home_server
home lab cloud like setup for development and learning 

## services
- build
    - [jenkins](https://www.jenkins.io/)
    - [nexus](https://www.sonatype.com/products/nexus-repository)
    - [sonarqube](https://www.sonarqube.org/)
- monitoring
    - [grafana](https://grafana.com/)
    - [influxdb](https://www.influxdata.com/)
    - [telgraf](https://www.influxdata.com/time-series-platform/telegraf/)
- [unifi OS Server](https://github.com/lemker/unifi-os-server)
    - [self-hosting UniFi](https://help.ui.com/hc/en-us/articles/34210126298775-Self-Hosting-UniFi)
- reverse proxy
    - [traefik](https://traefik.io/) (labels on each service)
    - [ssl via Let's Encrypt DNS-01](https://doc.traefik.io/traefik/https/acme/) (Cloudflare)
- [volume backup](https://github.com/offen/docker-volume-backup/)
- [home automation openhab (wip)](https://www.openhab.org/)
- [vaultwarden](https://github.com/dani-garcia/vaultwarden)
- [portainer](https://www.howtogeek.com/devops/)
- [obsidian-remote](https://github.com/sytone/obsidian-remote)
- [gotify](https://gotify.net/)
- [DIUN](https://crazymax.dev/diun/) (notify-only image watch)

## two level backup
- local backup to nas via docker-volume-backup
- cloud backup via [rclone](https://rclone.org/) sidecars (offen `prune-post`, plus `gdrive-sync` for orphan paths)
    - config file at /root/.config/rclone/rclone.conf
    - rclone failures post to Gotify when `GOTIFY_APP_TOKEN` is set in `/etc/environment`

## image updates (notify-only)
DIUN checks registries daily at 06:00 and posts to Gotify. Nothing pulls or restarts on its own. Git is the source of truth for tags.

1. Open the Gotify message and note the new tag.
2. Bump `image:` in that service's `docker-compose.yml` and commit.
3. `./gradlew deploy<Svc>` then on the host `docker compose up -d`.

`obsidian-remote` and `velxio` only publish a moving tag (`latest` / `master`); those are watched by digest. Sidecar copies of `offen` and `rclone` are ignored so you get one alert per image, from `vaultwarden-backup` and `gdrive-sync`.

After first Gotify boot, create two applications in the UI and add the tokens to **host** `/etc/environment` (not per-stack `.env`). Compose `env_file` injects that file into rclone sidecars and DIUN:

```
GOTIFY_DEFAULTUSER_PASS=<admin-password>
GOTIFY_APP_TOKEN=<rclone-app-token>
DIUN_NOTIF_GOTIFY_TOKEN=<diun-app-token>
```

Then `sudo docker compose up -d` on those stacks so the containers pick it up. Stack `.env` next to `docker-compose.yml` is also loaded for Gotify (overrides `/etc/environment`). `/etc/environment` is world-readable; that is the tradeoff for one file. The admin password is only applied on first boot of an empty `gotify-data` volume.

## kvm
- [setup bridged network nm](https://gist.github.com/plembo/f7abd2d9b6f76e7afdece02dae7e5097)
- [kvm bridge network](https://gist.github.com/plembo/a7b69f92953a76ab2d06533754b5e2bb)

## nas
- [letsencrypt certs](https://www.truenas.com/docs/scale/scaletutorials/credentials/certificates/settingupletsencryptcertificates/)


## TODO
- container monitoring dashboard
    -grafana/telegraf?
- custom container from nexus    
-[backup restore](https://offen.github.io/docker-volume-backup/how-tos/restore-volumes-from-backup.html)
    - verified manual restor from backup of vault
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
- shell into container
    - ```docker exec -it <container name> /bin/bash```
- container shell to copy volume data (WIP)
    - ```docker run -it --rm -v <src volume>:/src:ro -v <dest volume>:/dest bash:latest```    
- create compose compatible volume
    - ```docker volume create --name "vol_name" --label "com.docker.compose.project=container_name" --label "com.docker.compose.version=$(docker compose version)" --label "com.docker.compose.volume=vol_name"```
- connect to container
    - ```docker exec -it container_name  /bin/bash```