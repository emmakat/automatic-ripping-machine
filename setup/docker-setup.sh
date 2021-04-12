#!/usr/bin/env bash

SRCDIR="/opt"
DATADIR="/srv/docker/arm"

sudo chmod -R 777 /opt
cd /opt
git clone -b jessica https://github.com/emmakat/automatic-ripping-machine.git arm
chmod +x arm/scripts/docker_build.sh
chmod +x arm/scripts/docker-entrypoint.sh
chmod +x arm/scripts/docker_arm_wrapper.sh
chmod +x arm/arm/ripper/main.py
chmod -R 777 arm/docs  
chmod +x arm/scripts/docker_build.sh

cd "$SRCDIR"
arm/scripts/docker_build.sh
sudo install -D -v setup/docker-arm.rules -t /etc/udev/rules.d
sudo udevadm control --reload
echo done.  insert a disc...
