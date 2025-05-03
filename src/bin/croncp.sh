#!/bin/bash
#
# script to move cron files since gradle plugin not working direct commands
#
sudo mv /tmp/cron.d/* /etc/cron.d/
sudo chmod 644 /etc/cron.d/*
sudo chown root:root /etc/cron.d/*
sudo rm -fR /tmp/cron.d