#!/bin/sh
# Removes Rooms from a router. Run this on your computer.
#
#   ./uninstall.sh root@192.168.8.1

set -e

router=$1
home=${ROOMS_HOME:-/opt/rooms}

if [ -z "$router" ]; then
	echo "Usage: $0 root@router" >&2
	exit 1
fi

ssh "$router" "ROOMS_HOME='$home' sh '$home/deploy/remove.sh'"
