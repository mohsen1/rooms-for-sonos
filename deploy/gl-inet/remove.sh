#!/bin/sh
# Runs on the router. Removes everything apply.sh added.

NAME=$(basename "$ROOMS_HOME")
NGINX_CONF=/etc/nginx/conf.d/$NAME.conf
SERVICE=/etc/init.d/$NAME

rm -f "$NGINX_CONF"
kill -HUP "$(cat /var/run/nginx.pid)"

if [ -x "$SERVICE" ]; then
	"$SERVICE" stop
	"$SERVICE" disable
fi
rm -f "$SERVICE"

for kept in "$ROOMS_HOME/" "$SERVICE" "/etc/rc.d/S99$NAME" "$NGINX_CONF"; do
	grep -vxF "$kept" /etc/sysupgrade.conf > /tmp/sysupgrade.conf.new
	cat /tmp/sysupgrade.conf.new > /etc/sysupgrade.conf
done
rm -f /tmp/sysupgrade.conf.new

rm -rf "$ROOMS_HOME"
echo "Rooms is removed."
