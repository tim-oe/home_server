#!/bin/bash
#

docker volume create --name "influxdb-data" --label "com.docker.compose.project=influxdb" --label "com.docker.compose.version=2.34.0" --label "com.docker.compose.volume=influxdb-data"
docker volume create --name "influxdb-data2" --label "com.docker.compose.project=influxdb" --label "com.docker.compose.version=2.34.0" --label "com.docker.compose.volume=influxdb-data2"
docker volume create --name "influxdb-conf" --label "com.docker.compose.project=influxdb" --label "com.docker.compose.version=2.34.0" --label "com.docker.compose.volume=influxdb-conf"

docker volume create --name "grafana-data" --label "com.docker.compose.project=grafana" --label "com.docker.compose.version=2.34.0" --label "com.docker.compose.volume=grafana-data"
docker volume create --name "grafana-provisioning" --label "com.docker.compose.project=grafana" --label "com.docker.compose.version=2.34.0" --label "com.docker.compose.volume=grafana-provisioning"

docker volume create --name "jenkins-home" --label "com.docker.compose.project=jenkins" --label "com.docker.compose.version=2.34.0" --label "com.docker.compose.volume=jenkins-home"

docker volume create --name "nexus-data" --label "com.docker.compose.project=nexus" --label "com.docker.compose.version=2.34.0" --label "com.docker.compose.volume=nexus-data"

docker volume create --name "certbot_etc" --label "com.docker.compose.project=certbot" --label "com.docker.compose.version=2.34.0" --label "com.docker.compose.volume=certbot_etc"
docker volume create --name "certbot_lib" --label "com.docker.compose.project=certbot" --label "com.docker.compose.version=2.34.0" --label "com.docker.compose.volume=certbot_lib"

docker volume create --name "openhab-addons" --label "com.docker.compose.project=openhab" --label "com.docker.compose.version=2.34.0" --label "com.docker.compose.volume=openhab-addons"
docker volume create --name "openhab-conf" --label "com.docker.compose.project=openhab" --label "com.docker.compose.version=2.34.0" --label "com.docker.compose.volume=openhab-conf"
docker volume create --name "openhab-userdata" --label "com.docker.compose.project=openhab" --label "com.docker.compose.version=2.34.0" --label "com.docker.compose.volume=openhab-userdata"

docker volume create --name "sonarqube-data" --label "com.docker.compose.project=sonarqube" --label "com.docker.compose.version=2.34.0" --label "com.docker.compose.volume=sonarqube-data"
docker volume create --name "sonarqube-extensions" --label "com.docker.compose.project=sonarqube" --label "com.docker.compose.version=2.34.0" --label "com.docker.compose.volume=sonarqube-extensions"

docker volume create --name "postgresql" --label "com.docker.compose.project=postgresql" --label "com.docker.compose.version=2.34.0" --label "com.docker.compose.volume=postgresql"
docker volume create --name "postgresql-data" --label "com.docker.compose.project=postgresql" --label "com.docker.compose.version=2.34.0" --label "com.docker.compose.volume=postgresql-data"

docker volume create --name "unifi" --label "com.docker.compose.project=unifi" --label "com.docker.compose.version=2.34.0" --label "com.docker.compose.volume=unifi"
docker volume create --name "unifi-run" --label "com.docker.compose.project=unifi" --label "com.docker.compose.version=2.34.0" --label "com.docker.compose.volume=unifi-run"

docker volume create --name "vaultwarden-storage" --label "com.docker.compose.project=vaultwarden" --label "com.docker.compose.version=2.34.0" --label "com.docker.compose.volume=vaultwarden-storage"