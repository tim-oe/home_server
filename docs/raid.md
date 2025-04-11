## create DAID array

- wipe drive
    - for each drive to go in array, replace sdX with drive device name
    - ```sudo wipefs -a /dev/sdX*```
- partition and format drives
    - trying to use the drive without a primary partition would fail on reboot
    - not sure if formatting is needed but better safe than sorry...
    - ```sudo parted /dev/sdX mklabel gpt; sudo parted /dev/sdX mkpart primary 0% 100%; sudo mkfs.ext4 /dev/sdX1```
- create raid array
    - ```sudo mdadm --create --verbose /dev/md0 --level=5 --raid-devices=4 /dev/sdb1 /dev/sdc1 /dev/sdd1 /dev/sde1```
- format raid array
    - ```sudo mkfs.ext4 /dev/md0```
- once array completes
    - ```sudo dpkg-reconfigure mdadm```
- init for drives to be present at start
    - ```sudo update-initramfs -u```

# reinit array if it goes awol
```mdadm --assemble /dev/md0 /dev/sdb1 /dev/sdc1 /dev/sdd1 /dev/sde1```