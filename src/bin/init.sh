#!/bin/bash
#
# create network
docker network create --driver bridge share-net
# copy service scripts
sudo rm -f /usr/lib/systemd/system/jenkins.service 
sudo cp /mnt/raid/jenkins/jenkins.service /usr/lib/systemd/system
sudo rm -f /usr/lib/systemd/system/nexus.service 
sudo cp /mnt/raid/nexus/nexus.service /usr/lib/systemd/system
sudo rm -f /usr/lib/systemd/system/nginx.service 
sudo cp /mnt/raid/nginx/nginx.service /usr/lib/systemd/system
sudo rm -f /usr/lib/systemd/system/openhab.service 
sudo cp /mnt/raid/openhab/openhab.service /usr/lib/systemd/system
sudo rm -f /usr/lib/systemd/system/sonarqube.service 
sudo cp /mnt/raid/sonarqube/sonarqube.service /usr/lib/systemd/system
sudo rm -f /usr/lib/systemd/system/unifi.service 
sudo cp /mnt/raid/unifi/unifi.service /usr/lib/systemd/system
# disble to clear service
sudo systemctl disable jenkins.service
sudo systemctl disable unifi.service
sudo systemctl disable openhab.service
sudo systemctl disable nexus.service
sudo systemctl disable sonarqube.service
sudo systemctl disable nginx.service
# enable service
sudo systemctl enable jenkins.service
sudo systemctl enable unifi.service
sudo systemctl enable openhab.service
sudo systemctl enable nexus.service
sudo systemctl enable sonarqube.service
sudo systemctl enable nginx.service
