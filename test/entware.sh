#!/bin/sh
# Installs real Entware in a container, then runs the DD-WRT steps against fake speakers.
# This is the closest test to a DD-WRT router that doesn't need one.
#
#   docker run --rm -v "$PWD:/src:ro" alpine:3.22 sh /src/test/entware.sh

apk add --quiet --no-cache ca-certificates python3 wget

case "$(uname -m)" in
aarch64) feed=aarch64-k3.10 ;;
x86_64) feed=x64-k3.2 ;;
*) echo "No Entware feed picked for $(uname -m)" >&2; exit 1 ;;
esac

mkdir -p /opt
cd /tmp || exit 1
wget -q -O generic.sh "https://bin.entware.net/$feed/installer/generic.sh"
sh generic.sh > /tmp/entware-install.log 2>&1 || { tail -n 20 /tmp/entware-install.log; exit 1; }

export ROOMS_HOME=/opt/rooms ROOMS_PORT=8081
mkdir -p "$ROOMS_HOME"
cp -R /src/app/. "$ROOMS_HOME/"
cp -R /src/deploy/dd-wrt "$ROOMS_HOME/deploy"
sed -i 's/__VERSION__/1234/' "$ROOMS_HOME/www/index.html"
echo 1234 > "$ROOMS_HOME/version"

python3 /src/test/fake_sonos.py &
until wget -q -T 1 -O /dev/null http://127.0.1.11:1400/xml/device_description.xml; do
	sleep 1
done

printf '2\n3\n' | SUBNET=127.0.1 sh "$ROOMS_HOME/deploy/apply.sh" || exit 1

export PATH="/opt/sbin:/opt/bin:$PATH"
sleep 2

passed=0
failed=0

check() { # description actual expected
	if [ "$2" = "$3" ]; then
		passed=$((passed + 1))
		echo "ok    $1"
	else
		failed=$((failed + 1))
		echo "FAIL  $1: got [$2], wanted [$3]"
	fi
}

base=http://127.0.0.1:8081
check "curl comes from Entware" "$(command -v curl)" /opt/bin/curl
check "the system has no other curl" "$([ -e /usr/bin/curl ] && echo yes || echo no)" no
check "page is served" "$(curl -s -m 5 -o /dev/null -w '%{http_code}' "$base/")" 200
check "page is marked for offline launch" "$(curl -s -m 5 -D - -o /dev/null "$base/" | tr -d '\r' | grep -ic 'immutable')" 1
reply=$(curl -s -m 8 "$base/cgi-bin/rooms")
check "status reads the speakers" "$(echo "$reply" | sed -n 's/.*"secondName":"\([^"]*\)".*/\1/p')" "Living Room"
reply=$(curl -s -m 8 -d '' -H "Origin: $base" "$base/cgi-bin/rooms?first=44")
check "a volume change works" "$(echo "$reply" | sed -n 's/.*"firstVolume":"\([^"]*\)".*/\1/p')" 44

start=$(date +%s)
curl -sk -m 6 -o /dev/null "https://127.0.0.1:8081/"
check "https attempt fails within a second" "$([ $(($(date +%s) - start)) -le 1 ] && echo fast)" fast

check "Entware's own lighttpd service is off" "$([ -x /opt/etc/init.d/S80lighttpd ] && echo on || echo off)" off

echo "--- as if the router rebooted"
/opt/etc/init.d/rc.unslung stop > /dev/null 2>&1
sleep 1
check "stopping leaves nothing running" "$(curl -s -m 2 -o /dev/null -w '%{http_code}' "$base/")" 000
/opt/etc/init.d/rc.unslung start > /dev/null 2>&1
sleep 2
check "the startup command brings it back" "$(curl -s -m 5 -o /dev/null -w '%{http_code}' "$base/")" 200

echo "--- removal"
sh "$ROOMS_HOME/deploy/remove.sh" > /dev/null
sleep 1
check "removal stops the server" "$(curl -s -m 2 -o /dev/null -w '%{http_code}' "$base/")" 000
check "removal deletes the files" "$([ -d "$ROOMS_HOME" ] && echo there || echo gone)" gone

echo
echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
