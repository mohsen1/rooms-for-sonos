#!/bin/sh
# Runs Rooms on BusyBox and lighttpd against fake speakers. No hardware needed.
#
#   docker run --rm -v "$PWD:/src:ro" alpine:3.22 sh /src/test/run.sh

apk add --quiet --no-cache curl jq lighttpd python3

python3 /src/test/fake_sonos.py &
until curl -s -m 1 -o /dev/null http://127.0.1.11:1400/xml/device_description.xml; do
	sleep 1
done

ROOMS_HOME=/opt/rooms
cp -R /src/app "$ROOMS_HOME"
sed -i 's/__VERSION__/1234/' "$ROOMS_HOME/www/index.html"
echo 1234 > "$ROOMS_HOME/version"
sed -e "s|@HOME@|$ROOMS_HOME|g" -e 's|@PORT@|8081|g' /src/deploy/dd-wrt/lighttpd.conf > "$ROOMS_HOME/lighttpd.conf"

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
status() { curl -s -m 8 "$base/cgi-bin/rooms"; }
field() { status | jq -r ".$1"; }
post() { curl -s -m 15 -d '' -H "Origin: $base" "$base/cgi-bin/rooms?$1"; }
soap() { # ip service action args
	curl -s -m 3 -H "SOAPACTION: \"urn:schemas-upnp-org:service:$2:1#$3\"" -d "<u:$3>$4</u:$3>" "http://$1:1400/$5" >/dev/null
}

echo "--- setup"
list=$(printf '2\n3\n' | SUBNET=127.0.1 sh "$ROOMS_HOME/setup.sh" | tr -d '\r')
check "offers each room once, without surrounds or stereo pairs" "$(echo "$list" | grep -c ') ')" 3
check "lists rooms by name" "$(echo "$list" | grep -m 1 ') ')" "  1) Bedroom"
check "reports the choice" "$(echo "$list" | sed -n 's/.*\(Using .*\)/\1/p')" "Using Kitchen and Living Room."
check "saves the first room" "$(sed -n 1p "$ROOMS_HOME/config")" FIRST=RINCON_FIRST
check "saves the second room" "$(sed -n 2p "$ROOMS_HOME/config")" SECOND=RINCON_SECOND
check "saves the subnet" "$(sed -n 3p "$ROOMS_HOME/config")" SUBNET=127.0.1

lighttpd -f "$ROOMS_HOME/lighttpd.conf"
sleep 1

echo "--- page"
headers=$(curl -s -m 5 -D - -o /dev/null "$base/" | tr -d '\r')
check "page is served" "$(echo "$headers" | head -n 1 | cut -d' ' -f2)" 200
check "page is marked for offline launch" "$(echo "$headers" | grep -i '^cache-control' | cut -d' ' -f2-)" "public, max-age=2592000, immutable, stale-if-error=2592000"
check "page carries its version" "$(curl -s -m 5 "$base/" | grep -c 'rooms-version" content="1234"')" 1
check "manifest is served" "$(curl -s -m 5 -o /dev/null -w '%{http_code}' "$base/manifest.json")" 200
check "status is never cached" "$(curl -s -m 8 -D - -o /dev/null "$base/cgi-bin/rooms" | tr -d '\r' | grep -i '^cache-control' | cut -d' ' -f2)" no-store

echo "--- https attempts"
start=$(date +%s)
curl -sk -m 6 -o /dev/null "https://127.0.0.1:8081/"
code=$?
check "https attempt fails instead of hanging" "$([ "$code" -ne 28 ] && echo fast)" fast
check "https attempt fails within a second" "$([ $(($(date +%s) - start)) -le 1 ] && echo fast)" fast

echo "--- status"
now=$(status)
check "reads the first room's name" "$(echo "$now" | jq -r .firstName)" Kitchen
check "reads the second room's name" "$(echo "$now" | jq -r .secondName)" "Living Room"
check "reports what's playing" "$(echo "$now" | jq -r .player)" PLAYING
check "reports the page version" "$(echo "$now" | jq -r .page)" 1234
check "turns a relative art path into a full address" "$(echo "$now" | jq -r .art)" "http://127.0.1.12:1400/getaa?track=1&size=300"
soap 127.0.1.11 DeviceProperties SetZoneAttributes "<DesiredZoneName>Back Porch</DesiredZoneName>" DeviceProperties/Control
check "follows a rename made on Sonos" "$(field firstName)" "Back Porch"
soap 127.0.1.11 DeviceProperties SetZoneAttributes "<DesiredZoneName>Kitchen</DesiredZoneName>" DeviceProperties/Control

echo "--- volume"
post first=40 >/dev/null
check "first slider moves the first room" "$(field firstVolume)" 40
check "and leaves the second alone" "$(field secondVolume)" 20
post second=20 >/dev/null

echo "--- rooms"
now=$(post to=everywhere)
check "everywhere groups the rooms" "$(echo "$now" | jq -r .leader)" second
check "the group has a volume" "$(echo "$now" | jq -r .groupVolume)" 30
post groupstart=15 >/dev/null
post group=20 >/dev/null
now=$(post group=30)
check "group volume keeps the first room's level" "$(echo "$now" | jq -r .firstVolume)" 40
check "group volume keeps the second room's level" "$(echo "$now" | jq -r .secondVolume)" 20
now=$(post to=first)
check "moving to one room splits the group" "$(echo "$now" | jq -r .leader)" ""
check "the music moves with it" "$(echo "$now" | jq -r .first)" PLAYING
check "and stops in the other room" "$(echo "$now" | jq -r .second)" STOPPED

echo "--- playback"
check "shows the track" "$(field title)" "First Song"
now=$(post do=next)
check "next changes the track" "$(field title)" 'Rock & Roll "Live"'
check "names with quotes come through" "$(field artist)" "Guns N' Roses"
post do=previous >/dev/null
post do=pause >/dev/null
check "pause reports paused" "$(field player)" PAUSED_PLAYBACK
check "a paused track stays on show" "$(field title)" "First Song"
post do=play >/dev/null
check "play reports playing" "$(field player)" PLAYING

echo "--- refusals"
check "refuses a volume over 100" "$(post first=101 | jq -r .error)" choice
check "refuses text as a volume" "$(post second=abc | jq -r .error)" choice
check "refuses an unknown action" "$(post do=stop | jq -r .error)" choice
check "refuses another website" "$(curl -s -m 8 -d '' -H 'Origin: http://example.com' "$base/cgi-bin/rooms?do=pause" | jq -r .error)" origin
curl -s -m 8 "$base/cgi-bin/rooms?do=pause" >/dev/null
check "a plain GET changes nothing" "$(field player)" PLAYING

echo "--- finding speakers"
check "setup saves the addresses it found" "$(sed -n 1p "$ROOMS_HOME/addresses")" FIP=127.0.1.11
printf 'FIP=127.0.1.200\nSIP=127.0.1.201\n' > "$ROOMS_HOME/addresses"
rm -f /tmp/rooms/last-scan
check "a moved speaker gets a quick answer, not a wait" "$(field error)" speakers
sleep 3
check "finds speakers again after their addresses change" "$(field firstName)" Kitchen

echo
echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
