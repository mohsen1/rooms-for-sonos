#!/bin/sh
# Finds the Sonos rooms on this network and saves the two that Rooms controls.
# Runs on the router. To skip the questions, set FIRST, SECOND and SUBNET.
# SUBNET looks like 192.168.1. Set it alone if the search looks in the wrong place.

given_first=$FIRST
given_second=$SECOND
given_subnet=$SUBNET

ROOMS_HOME=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=app/sonos.sh
. "$ROOMS_HOME/sonos.sh"

TAB=$(printf '\t')

save() { # first-uuid second-uuid subnet [first-ip second-ip]
	printf 'FIRST=%s\nSECOND=%s\nSUBNET=%s\n' "$1" "$2" "$3" > "$CONFIG"
	[ -n "$4" ] && printf 'FIP=%s\nSIP=%s\n' "$4" "$5" > "$ADDRESSES"
}

column() { # line number
	printf '%s\n' "$1" | cut -f"$2"
}

subnets() {
	{ ip -4 addr 2>/dev/null; ifconfig 2>/dev/null; } |
		sed -n 's/.*inet \(addr:\)\{0,1\}\([0-9]*\.[0-9]*\.[0-9]*\)\.[0-9]*.*/\2/p' |
		grep -v '^127\.' | sort -u
}

first_speaker() { # subnet
	found=$STATE/found.$$
	rm -f "$found"
	i=1
	while [ "$i" -le 254 ] && [ ! -s "$found" ]; do
		(
			if curl -s -m 2 "http://$1.$i:1400/xml/device_description.xml" | grep -q Sonos; then
				echo "$1.$i" > "$found"
			fi
		) &
		[ $((i % 32)) -eq 0 ] && wait
		i=$((i + 1))
	done
	wait
	cat "$found" 2>/dev/null
	rm -f "$found"
}

# Surrounds and subs belong to a room and aren't listed as their own member,
# and the second speaker of a stereo pair is marked Invisible.
list_rooms() { # speaker-ip; prints name, uuid and ip, separated by tabs
	request "http://$1:1400/ZoneGroupTopology/Control" ZoneGroupTopology GetZoneGroupState '' |
		unescape | tr '<' '\n' | grep '^ZoneGroupMember ' | grep -v 'Invisible="1"' |
		sed -n "s#.* UUID=\"\([^\"]*\)\".*Location=\"http://\([0-9.]*\):.* ZoneName=\"\([^\"]*\)\".*#\3$TAB\1$TAB\2#p" | sort -u
}

if [ -n "$given_first" ] && [ -n "$given_second" ] && [ -n "$given_subnet" ]; then
	save "$given_first" "$given_second" "$given_subnet"
	exit 0
fi

if [ -f "$CONFIG" ]; then
	echo "Keeping the rooms in $CONFIG. Delete that file and run this again to choose new ones."
	exit 0
fi

echo "Looking for Sonos speakers..."
speaker=''
for subnet in ${given_subnet:-$(subnets)}; do
	speaker=$(first_speaker "$subnet")
	[ -n "$speaker" ] && break
done

if [ -z "$speaker" ]; then
	echo "No Sonos speakers found. This router must be on the same network as the speakers." >&2
	exit 1
fi

rooms=$STATE/rooms.$$
list_rooms "$speaker" > "$rooms"
count=$(wc -l < "$rooms")

if [ "$count" -lt 2 ]; then
	rm -f "$rooms"
	echo "Found $count Sonos room. Rooms needs two." >&2
	exit 1
fi

first_choice=1
second_choice=2
if [ "$count" -gt 2 ]; then
	echo "Rooms controls two rooms. Pick them by number:"
	cut -f1 "$rooms" | awk '{ printf "  %d) %s\n", NR, $0 }'
	printf 'First room: '
	read -r first_choice
	printf 'Second room: '
	read -r second_choice
fi

case "$first_choice$second_choice" in
*[!0-9]* | '')
	rm -f "$rooms"
	echo "Please enter a number from the list." >&2
	exit 1
	;;
esac

first=$(sed -n "${first_choice}p" "$rooms")
second=$(sed -n "${second_choice}p" "$rooms")
rm -f "$rooms"

if [ -z "$first" ] || [ -z "$second" ] || [ "$first" = "$second" ]; then
	echo "Please pick two different rooms from the list." >&2
	exit 1
fi

save "$(column "$first" 2)" "$(column "$second" 2)" "$subnet" "$(column "$first" 3)" "$(column "$second" 3)"
echo "Using $(column "$first" 1) and $(column "$second" 1)."
