#!/bin/sh
# Runs on the router. Installs lighttpd and curl from Entware and starts Rooms on lighttpd.

set -e

PATH=/opt/sbin:/opt/bin:$PATH
NAME=$(basename "$ROOMS_HOME")
DEPLOY=$ROOMS_HOME/deploy
SERVICE=/opt/etc/init.d/S85$NAME

if ! command -v opkg >/dev/null; then
	echo "Entware isn't installed. See docs/setup-dd-wrt.md." >&2
	exit 1
fi

opkg update

# The lighttpd package adds a service that starts at boot on this same port.
# Turn that off, unless it was already here before Rooms.
new_lighttpd=yes
opkg list-installed | grep -q '^lighttpd ' && new_lighttpd=no

opkg install lighttpd lighttpd-mod-cgi lighttpd-mod-setenv curl

if [ "$new_lighttpd" = yes ] && [ -x /opt/etc/init.d/S80lighttpd ]; then
	chmod -x /opt/etc/init.d/S80lighttpd
fi

# DD-WRT trims BusyBox to fit each router, so check before anything depends on these.
for tool in awk cut date grep sed sort tr wc; do
	if ! command -v "$tool" >/dev/null; then
		echo "This router has no $tool. Install it with opkg, then run install.sh again." >&2
		exit 1
	fi
done

sh "$ROOMS_HOME/setup.sh"

fill() {
	sed -e "s|@HOME@|$ROOMS_HOME|g" -e "s|@PORT@|$ROOMS_PORT|g" "$1"
}

fill "$DEPLOY/lighttpd.conf" > "$ROOMS_HOME/lighttpd.conf"
fill "$DEPLOY/init" > "$SERVICE"
chmod 755 "$SERVICE"
"$SERVICE" restart

sleep 1
if ! curl -s -m 5 -o /dev/null "http://127.0.0.1:$ROOMS_PORT/"; then
	echo "Rooms didn't start. Port $ROOMS_PORT may be in use. See /tmp/rooms-lighttpd.log." >&2
	exit 1
fi

echo "Rooms is running on port $ROOMS_PORT."
