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
- [unifi WAP controller](https://github.com/jacobalberty/unifi-docker)
    - [unifi wap](https://community.ui.com/releases/UniFi-Network-Application-8-6-9/e4bd3f71-a2c4-4c98-b12a-a8b0b1c2178e)
- reverse proxy
    - [nginx](https://nginx.org/en/)
    - [ssl via certbot](https://certbot-dns-cloudflare.readthedocs.io/en/stable/)
- [volume backup](https://github.com/offen/docker-volume-backup/)
- [home automation openhab (wip)](https://www.openhab.org/)
- [vaultwarden](https://github.com/dani-garcia/vaultwarden)
- [portainer](https://www.howtogeek.com/devops/)

## two level backup
- local backup to nas via docker-volume-backup
- cloud backup via [rclone](https://rclone.org/)
    - config file at /root/.config/rclone/rclone.conf

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
- [watchtower](https://containrrr.dev/watchtower/introduction/)
    - [DIUN](https://crazymax.dev/diun/)
how-to-get-started-with-portainer-a-web-ui-for-docker/#install-portainer)
    - [komodo](https://komo.do/docs/intro)
- [nginx proxy mgr](https://nginxproxymanager.com/)
    - [npmplus](https://github.com/ZoeyVid/NPMplus)
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