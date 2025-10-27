#!/bin/bash

# Simple single partition creator
# Usage: ./script.sh /dev/sdX

DEVICE="$1"

# Check if device is a block device
if [ ! -b "$DEVICE" ]; then
    echo "Error: $DEVICE is not a block device"
    exit 1
fi

# Check if device has existing partitions
if fdisk -l "$DEVICE" 2>/dev/null | grep -q "^$DEVICE[0-9]"; then
    echo "Warning: $DEVICE has existing partitions that will be destroyed"
    read -p "Continue? (Y/n): " answer
    if [[ "$answer" == "n" || "$answer" == "N" ]]; then
        echo "Aborted"
        exit 0
    fi
fi

# Create MBR partition table with single primary partition
# fdisk commands:
#   o - create a new empty DOS partition table
#   n - add a new partition
#   p - primary partition
#   1 - partition number (1-4)
#   <empty> - first sector (default: start of disk)
#   <empty> - last sector (default: end of disk)
#   w - write table to disk and exit
fdisk "$DEVICE" << EOF
o
n
p
1


w
EOF

echo "Partition created on $DEVICE"