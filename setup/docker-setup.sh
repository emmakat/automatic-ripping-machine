#!/usr/bin/env bash

#SRCDIR="/opt/arm"
DATADIR="/srv/docker/arm"

sudo mkdir -p "$DATADIR"

#cd "$SRCDIR"
#docker build -t arm ${APT_PROXY:+--build-target ${APT_PROXY}} .

install setup/docker-arm.rules /etc/udev/rules.d/docker-arm.rules
udevadm control --reload
echo done.  insert a disc...
