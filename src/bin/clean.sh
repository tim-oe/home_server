#!/bin/bash
#
# script to clean system
#
echo 'purging temp'
# purge files
find /tmp/ -maxdepth 1 -type f -mtime +1 -exec rm -vfR {} \;
# purge all other subdirs
find /tmp/* -maxdepth 1 -type d \( ! -iname ".*" \) -mtime +1 -exec rm -vfR {} \;
# purge files

echo 'purging archived logs'
# global log files
find /var/log/ -iname "*.gz" -type f -exec rm -vfR {} \;
find /var/log/ -iname "*.backup" -type f -exec rm -vfR {} \;
for i in 0 1 2 3 4 5 6 7 8 9;
        do find /var/log/ -iname *.$i -type f -exec rm -vfR {} \;;
done
journalctl --vacuum-time=1days

if command -v snap &> /dev/null
then
    echo 'truncating snap'
    sudo snap set system refresh.retain=2
    set -eu
    LANG=en_US.UTF-8 snap list --all | awk '/disabled/{print $1, $3}' |
	    while read snapname revision; do
		    snap remove "$snapname" --revision="$revision"
        done	
    sudo rm -fR /var/lib/snapd/cache/*
fi

echo 'truncating apt'
sudo apt clean
sudo apt autoremove --purge

# docker
if command -v docker &> /dev/null
then
	echo 'truncating docker'
	sudo docker system prune -af
	sudo docker image prune -af
	sudo docker container prune -f
	sudo docker volume prune -af
fi

df -H
echo 'list large folders'
du / -aBM 2>/dev/null | sort -nr | head -n 50

echo 'complete'