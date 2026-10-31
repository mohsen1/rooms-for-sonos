#!/bin/sh
# Copies Rooms to a router and starts it. Run this on your computer.
#
#   ./install.sh gl-inet root@192.168.8.1
#   ./install.sh dd-wrt root@192.168.1.1
#
# The port is optional and defaults to 8081:
#
#   ./install.sh gl-inet root@192.168.8.1 8090

set -e

usage() {
	echo "Usage: $0 gl-inet|dd-wrt root@router [port]" >&2
	exit 1
}

platform=$1
router=$2
port=${3:-8081}
home=${ROOMS_HOME:-/opt/rooms}
source=$(cd "$(dirname "$0")" && pwd)

case "$platform" in
gl-inet | dd-wrt) ;;
*) usage ;;
esac
[ -n "$router" ] || usage

staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT

version=$(date +%s)
cp -R "$source/app/." "$staging/"
cp -R "$source/deploy/$platform" "$staging/deploy"
sed "s/__VERSION__/$version/" "$source/app/www/index.html" > "$staging/www/index.html"
echo "$version" > "$staging/version"

COPYFILE_DISABLE=1 tar --format=ustar -C "$staging" -cf - . |
	ssh "$router" "mkdir -p '$home' && tar -xf - -C '$home'"

ssh -t "$router" "ROOMS_HOME='$home' ROOMS_PORT='$port' FIRST='${FIRST:-}' SECOND='${SECOND:-}' SUBNET='${SUBNET:-}' sh '$home/deploy/apply.sh'"
