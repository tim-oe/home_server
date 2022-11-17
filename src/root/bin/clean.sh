#!/bin/bash
#
# script to clean cruft from system
#
echo 'truncate syslog'
sudo truncate -s 0 syslog

echo 'purging temp'
# purge files
find /tmp/ -maxdepth 1 -type f -mtime 1 -exec rm -vfR {} \;
# purge all other subdirs
find /tmp/* -maxdepth 1 -type d \( ! -iname ".*" \) -mtime 1 -exec rm -vfR {} \;
# purge files

echo 'purging archived logs'
# global log files
find /var/log/ -iname "*.gz" -type f -exec rm -vfR {} \;
find /var/log/ -iname "*.backup" -type f -exec rm -vfR {} \;
for i in 0 1 2 3 4 5 6 7 8 9;
        do find /var/log/ -iname *.$i -type f -exec rm -vfR {} \;;
done

echo 'truncating journals'
#flush journal logs
journalctl --vacuum-time=1days

sudo rm -fR /var/lib/snapd/cache/*
sudo apt clean
sudo apt autoremove --purge

# docker
sudo docker system prune -f
sudo docker image prune -f
sudo docker container prune -f
sudo docker volume prune -f

df -H
echo 'list large folders'
du / -aBM 2>/dev/null | sort -nr | head -n 50

echo 'complete'