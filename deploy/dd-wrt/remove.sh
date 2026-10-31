#!/bin/sh
# Runs on the router. Removes everything apply.sh added, apart from the Entware packages.

NAME=$(basename "$ROOMS_HOME")
SERVICE=/opt/etc/init.d/S85$NAME

if [ -x "$SERVICE" ]; then
	"$SERVICE" stop
fi
rm -f "$SERVICE"

rm -rf "$ROOMS_HOME"
echo "Rooms is removed. To remove lighttpd too, run: opkg remove lighttpd"
