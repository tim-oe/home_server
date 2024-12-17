# home_server
put desktop system to a purpose for local development.

## build services
- [jenkins](https://www.jenkins.io/)
- [nexus](https://www.sonatype.com/products/nexus-repository)
- [sonarqube](https://www.sonarqube.org/)
- [nginx](https://nginx.org/en/)

## management services
- [openhab](https://www.openhab.org/)
- [Unifi Controller](https://community.ui.com/releases/UniFi-Network-Application-7-2-95/7adebab5-8c41-4989-835d-ab60dba55255)

## docker 
- [docker-compose](https://docs.docker.com/compose/compose-file/#compose-file-structure-and-examples)
- get volumes mapped to a given container
    - ```docker inspect --type container -f '{{range $i, $v := .Mounts }}{{printf "%v\n" $v}}{{end}}' <container_id>```
- shell into container
    - ```docker exec -it <container name> /bin/bash```

## systemd (not used as docker handles container lifecycle)
- [general](https://www.freedesktop.org/software/systemd/man/systemd.unit.html)
- [unit](https://manpages.ubuntu.com/manpages/xenial/en/man5/systemd.unit.5.html)
- [service](https://manpages.ubuntu.com/manpages/xenial/en/man5/systemd.service.5.html)
- [install](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/8/html/configuring_basic_system_settings/assembly_working-with-systemd-unit-files_configuring-basic-system-settings)