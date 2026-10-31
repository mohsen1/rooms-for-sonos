#!/bin/sh
# Runs on the router. Puts Rooms behind the nginx that GL.iNet firmware already runs.
# nginx serves the page, and a private uhttpd runs the status script behind it.

set -e

NAME=$(basename "$ROOMS_HOME")
BACKEND_PORT=$((ROOMS_PORT + 1))
DEPLOY=$ROOMS_HOME/deploy
NGINX_CONF=/etc/nginx/conf.d/$NAME.conf
SERVICE=/etc/init.d/$NAME

for tool in nginx uhttpd curl; do
	if ! command -v "$tool" >/dev/null; then
		echo "This router has no $tool. These steps are for GL.iNet firmware." >&2
		exit 1
	fi
done

if [ ! -f "$NGINX_CONF" ] && netstat -ltn 2>/dev/null | grep -q ":$ROOMS_PORT "; then
	echo "Port $ROOMS_PORT is in use. Run install.sh again with another port." >&2
	exit 1
fi

sh "$ROOMS_HOME/setup.sh"

fill() {
	sed -e "s|@HOME@|$ROOMS_HOME|g" -e "s|@PORT@|$ROOMS_PORT|g" -e "s|@BACKEND_PORT@|$BACKEND_PORT|g" "$1"
}

fill "$DEPLOY/init" > "$SERVICE"
chmod 755 "$SERVICE"
"$SERVICE" enable
"$SERVICE" stop 2>/dev/null || true
"$SERVICE" start

fill "$DEPLOY/nginx.conf" > "$NGINX_CONF"
chmod 600 "$NGINX_CONF"
if ! nginx -t 2>/dev/null; then
	rm -f "$NGINX_CONF"
	echo "nginx rejected the new settings, so nothing changed." >&2
	exit 1
fi

# The service's own reload does nothing unless nginx.conf itself changed.
kill -HUP "$(cat /var/run/nginx.pid)"

# Keep Rooms through firmware upgrades that keep settings.
for kept in "$ROOMS_HOME/" "$SERVICE" "/etc/rc.d/S99$NAME" "$NGINX_CONF"; do
	grep -qxF "$kept" /etc/sysupgrade.conf || echo "$kept" >> /etc/sysupgrade.conf
done

# nginx takes a moment to swap workers after the signal.
for _ in 1 2 3 4 5 6 7 8 9 10; do
	curl -s -m 2 -o /dev/null "http://127.0.0.1:$ROOMS_PORT/cgi-bin/rooms" && break
	sleep 1
done

address=$(ip -4 -o addr show br-lan | sed -n 's/.* inet \([0-9.]*\)\/.*/\1/p' | head -n 1)
echo "Rooms is running at http://$address:$ROOMS_PORT/"
