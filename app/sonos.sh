# Talks to Sonos speakers over their local network interface with curl and sed.
# Sourced by www/cgi-bin/rooms and setup.sh, which set ROOMS_HOME first.

PATH=/opt/sbin:/opt/bin:/usr/sbin:/usr/bin:/sbin:/bin

CONFIG=$ROOMS_HOME/config
ADDRESSES=$ROOMS_HOME/addresses
STATE=/tmp/rooms
LAST_SCAN=$STATE/last-scan
LAST_TRACK=$STATE/last-track
RESCAN_AFTER=60

mkdir -p "$STATE"
# shellcheck disable=SC1090
[ -f "$CONFIG" ] && . "$CONFIG"

request() { # url service action args
	curl -s -m 3 -H 'Content-Type: text/xml; charset="utf-8"' \
		-H "SOAPACTION: \"urn:schemas-upnp-org:service:$2:1#$3\"" \
		-d "<?xml version=\"1.0\"?><s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\"><s:Body><u:$3 xmlns:u=\"urn:schemas-upnp-org:service:$2:1\">$4</u:$3></s:Body></s:Envelope>" \
		"$1"
}

soap() { # ip service action args
	request "http://$1:1400/MediaRenderer/$2/Control" "$2" "$3" "$4"
}

uri() {
	soap "$1" AVTransport GetMediaInfo '<InstanceID>0</InstanceID>' |
		sed -n 's:.*<CurrentURI>\(.*\)</CurrentURI>.*:\1:p'
}

state() {
	soap "$1" AVTransport GetTransportInfo '<InstanceID>0</InstanceID>' |
		sed -n 's:.*<CurrentTransportState>\(.*\)</CurrentTransportState>.*:\1:p'
}

playing() {
	[ "$(state "$1")" = PLAYING ]
}

volume() { # ip
	soap "$1" RenderingControl GetVolume '<InstanceID>0</InstanceID><Channel>Master</Channel>' |
		sed -n 's:.*<CurrentVolume>\(.*\)</CurrentVolume>.*:\1:p'
}

set_volume() { # ip level
	soap "$1" RenderingControl SetVolume \
		"<InstanceID>0</InstanceID><Channel>Master</Channel><DesiredVolume>$2</DesiredVolume>" |
		grep -q SetVolumeResponse
}

set_leader() { # second-uri first-uri; sets LEADER and LIP, both empty when the rooms are separate
	LEADER=''
	LIP=''
	if [ "$1" = "x-rincon:$FIRST" ]; then
		LEADER=first
		LIP=$FIP
	elif [ "$2" = "x-rincon:$SECOND" ]; then
		LEADER=second
		LIP=$SIP
	fi
}

find_leader() {
	set_leader "$(uri "$SIP")" "$(uri "$FIP")"
}

set_player() { # picks the speaker the playback controls act on; sets PIP and PSTATE
	if [ -n "$LIP" ]; then
		PIP=$LIP
	elif [ "$FSTATE" = PLAYING ] || { [ "$FSTATE" != STOPPED ] && [ "$SSTATE" != PLAYING ]; }; then
		PIP=$FIP
	else
		PIP=$SIP
	fi
	PSTATE=$SSTATE
	[ "$PIP" = "$FIP" ] && PSTATE=$FSTATE
}

unescape() {
	sed -e 's/&lt;/</g' -e 's/&gt;/>/g' -e 's/&quot;/"/g' -e "s/&apos;/'/g" -e "s/&#39;/'/g" -e 's/&amp;/\&/g'
}

json_text() {
	sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr -d '\000-\037'
}

room_name() { # ip
	curl -s -m 2 "http://$1:1400/xml/device_description.xml" |
		sed -n 's:.*<roomName>\(.*\)</roomName>.*:\1:p' | head -n 1 | unescape | json_text
}

metadata() { # tag; reads $info
	printf '%s\n' "$info" | sed -n "s#.*<$1>\(.*\)</$1>.*#\1#p" | unescape | json_text
}

read_track() { # ip; sets TITLE, ARTIST and ART
	info=$(soap "$1" AVTransport GetPositionInfo '<InstanceID>0</InstanceID>' | unescape)
	TITLE=$(metadata dc:title)
	ARTIST=$(metadata dc:creator)
	ART=$(metadata upnp:albumArtURI)
	case "$ART" in
	/*) ART="http://$1:1400$ART" ;;
	http://* | https://*) ;;
	*) ART='' ;;
	esac
}

# Sonos reports nothing about a paused Spotify track, so keep the last one on show.
remember_track() {
	if [ -n "$TITLE" ]; then
		printf '%s\n%s\n%s\n' "$TITLE" "$ARTIST" "$ART" > "$LAST_TRACK"
	elif { [ "$PSTATE" = PAUSED_PLAYBACK ] || [ "$PSTATE" = TRANSITIONING ]; } && [ -f "$LAST_TRACK" ]; then
		TITLE=$(sed -n 1p "$LAST_TRACK")
		ARTIST=$(sed -n 2p "$LAST_TRACK")
		ART=$(sed -n 3p "$LAST_TRACK")
	fi
}

transport() { # action [arguments]
	soap "$PIP" AVTransport "$1" "<InstanceID>0</InstanceID>$2" | grep -q "$1Response"
}

# Asks the speakers everything at once, so the page gets its answer sooner.
read_rooms() { # sets LEADER, LIP, FNAME, SNAME, FSTATE, SSTATE, FVOLUME, SVOLUME, GVOLUME, PIP, PSTATE, TITLE, ARTIST and ART
	answers=$STATE/answers.$$
	mkdir -p "$answers"
	room_name "$FIP" > "$answers/first-name" &
	room_name "$SIP" > "$answers/second-name" &
	uri "$SIP" > "$answers/second-uri" &
	uri "$FIP" > "$answers/first-uri" &
	state "$FIP" > "$answers/first-state" &
	state "$SIP" > "$answers/second-state" &
	volume "$FIP" > "$answers/first-volume" &
	volume "$SIP" > "$answers/second-volume" &
	wait
	set_leader "$(cat "$answers/second-uri")" "$(cat "$answers/first-uri")"
	FNAME=$(cat "$answers/first-name")
	SNAME=$(cat "$answers/second-name")
	FSTATE=$(cat "$answers/first-state")
	SSTATE=$(cat "$answers/second-state")
	FVOLUME=$(cat "$answers/first-volume")
	SVOLUME=$(cat "$answers/second-volume")
	rm -rf "$answers"
	GVOLUME=''
	[ -n "$LIP" ] && GVOLUME=$(group_volume "$LIP")
	set_player
	read_track "$PIP"
	remember_track
}

group_volume() { # leader-ip
	soap "$1" GroupRenderingControl GetGroupVolume '<InstanceID>0</InstanceID>' |
		sed -n 's:.*<CurrentVolume>\(.*\)</CurrentVolume>.*:\1:p'
}

# Sonos scales each room from this snapshot, which is what keeps their ratio.
snapshot_group() { # leader-ip
	soap "$1" GroupRenderingControl SnapshotGroupVolume '<InstanceID>0</InstanceID>' |
		grep -q SnapshotGroupVolumeResponse
}

set_group_volume() { # leader-ip level
	soap "$1" GroupRenderingControl SetGroupVolume \
		"<InstanceID>0</InstanceID><DesiredVolume>$2</DesiredVolume>" |
		grep -q SetGroupVolumeResponse
}

alive() { # ip uuid
	[ -n "$1" ] && curl -s -m 2 "http://$1:1400/xml/device_description.xml" | grep -q "uuid:$2"
}

scan() {
	found=$STATE/scan.$$
	mkdir -p "$found"
	i=1
	while [ "$i" -le 254 ]; do
		(
			page=$(curl -s -m 1 "http://$SUBNET.$i:1400/xml/device_description.xml")
			case "$page" in
			*"uuid:$FIRST"*) echo "$SUBNET.$i" > "$found/first" ;;
			*"uuid:$SECOND"*) echo "$SUBNET.$i" > "$found/second" ;;
			esac
		) &
		[ $((i % 32)) -eq 0 ] && wait
		i=$((i + 1))
	done
	wait
	FIP=$(cat "$found/first" 2>/dev/null)
	SIP=$(cat "$found/second" 2>/dev/null)
	rm -rf "$found"
	[ -n "$FIP" ] && [ -n "$SIP" ] && printf 'FIP=%s\nSIP=%s\n' "$FIP" "$SIP" > "$ADDRESSES"
}

locate() {
	# shellcheck disable=SC1090
	[ -f "$ADDRESSES" ] && . "$ADDRESSES"
	alive "$FIP" "$FIRST" &
	first_check=$!
	alive "$SIP" "$SECOND" &
	second_check=$!
	wait "$first_check" && wait "$second_check" && return 0

	# A speaker may just be off, so don't scan the network on every page refresh.
	now=$(date +%s)
	last=$(cat "$LAST_SCAN" 2>/dev/null || echo 0)
	[ $((now - last)) -lt "$RESCAN_AFTER" ] && return 1
	echo "$now" > "$LAST_SCAN"

	# A scan outlasts the page's patience, so it runs on its own and a later update finds the result.
	scan < /dev/null > /dev/null 2>&1 &
	return 1
}

wait_for() { # ip uri
	for _ in 1 2 3 4 5; do
		[ "$(uri "$1")" = "$2" ] && return 0
		sleep 1
	done
	return 1
}

join() { # ip leader-uuid
	soap "$1" AVTransport SetAVTransportURI \
		"<InstanceID>0</InstanceID><CurrentURI>x-rincon:$2</CurrentURI><CurrentURIMetaData></CurrentURIMetaData>" >/dev/null
	wait_for "$1" "x-rincon:$2"
}

standalone() { # ip
	soap "$1" AVTransport BecomeCoordinatorOfStandaloneGroup '<InstanceID>0</InstanceID>' >/dev/null
}

hand_over() { # leader-ip new-leader-uuid
	soap "$1" AVTransport DelegateGroupCoordinationTo \
		"<InstanceID>0</InstanceID><NewCoordinator>$2</NewCoordinator><RejoinGroup>1</RejoinGroup>" >/dev/null
	wait_for "$1" "x-rincon:$2"
}

pause() { # ip
	soap "$1" AVTransport Pause '<InstanceID>0</InstanceID><Speed>1</Speed>' >/dev/null
}

only() { # target-ip target-uuid other-ip other-uuid
	if [ "$(uri "$1")" = "x-rincon:$4" ]; then
		hand_over "$3" "$2" || return 1
	elif [ "$(uri "$3")" != "x-rincon:$2" ]; then
		playing "$3" || return 0
		if playing "$1"; then
			pause "$3"
			return 0
		fi
		join "$1" "$4" && hand_over "$3" "$2" || return 1
	fi
	standalone "$3"
}

together() {
	[ "$(uri "$SIP")" = "x-rincon:$FIRST" ] && return 0
	[ "$(uri "$FIP")" = "x-rincon:$SECOND" ] && return 0
	if playing "$SIP" && ! playing "$FIP"; then
		join "$FIP" "$SECOND"
	else
		join "$SIP" "$FIRST"
	fi
}
