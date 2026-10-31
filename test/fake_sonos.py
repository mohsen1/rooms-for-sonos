#!/usr/bin/env python3
"""Pretends to be a small Sonos household, so Rooms can be tested without speakers.

Each speaker listens on port 1400 of its own loopback address, as real ones do on
their own IP addresses. It answers only the calls Rooms makes, and copies the Sonos
habits Rooms depends on, such as reporting no track details while Spotify is paused.
"""

import html
import http.server
import re
import socketserver
import threading
from xml.sax.saxutils import escape

TRACKS = [
    ("First Song", "Test Artist"),
    ('Rock & Roll "Live"', "Guns N' Roses"),
]


class Speaker:
    def __init__(self, ip, uuid, room, volume, playing=False):
        self.ip = ip
        self.uuid = uuid
        self.room = room
        self.volume = volume
        self.uri = f"x-sonos-vli:{uuid}:2,spotify:session" if playing else ""
        self.transport = "PLAYING" if playing else "STOPPED"
        self.track = 0
        self.snapshot = {}


KITCHEN = Speaker("127.0.1.11", "RINCON_FIRST", "Kitchen", 30)
LIVING = Speaker("127.0.1.12", "RINCON_SECOND", "Living Room", 20, playing=True)
SURROUND = Speaker("127.0.1.13", "RINCON_SURROUND", "Living Room", 20)
BEDROOM = Speaker("127.0.1.14", "RINCON_THIRD", "Bedroom", 15)
STEREO_RIGHT = Speaker("127.0.1.15", "RINCON_THIRD_RIGHT", "Bedroom", 15)

ROOMS = [KITCHEN, LIVING, BEDROOM]
EVERYONE = ROOMS + [SURROUND, STEREO_RIGHT]
LOCK = threading.Lock()


def by_uuid(uuid):
    return next(speaker for speaker in EVERYONE if speaker.uuid == uuid)


def leader_of(speaker):
    if speaker.uri.startswith("x-rincon:"):
        return by_uuid(speaker.uri.removeprefix("x-rincon:"))
    return speaker


def members(leader):
    return [s for s in ROOMS if leader_of(s) is leader]


def group_level(volumes):
    return int(sum(volumes) / len(volumes) + 0.5)


def argument(body, name):
    found = re.search(f"<{name}>(.*?)</{name}>", body, re.S)
    return html.unescape(found.group(1)) if found else ""


def track_metadata(speaker):
    title, artist = TRACKS[speaker.track]
    didl = (
        "<DIDL-Lite><item>"
        "<upnp:albumArtURI>/getaa?track=1&amp;size=300</upnp:albumArtURI>"
        f"<dc:title>{escape(title)}</dc:title>"
        f"<dc:creator>{escape(artist)}</dc:creator>"
        "</item></DIDL-Lite>"
    )
    return escape(didl)


def zone_group_state():
    def member(speaker, attributes=""):
        return (
            f'<ZoneGroupMember UUID="{speaker.uuid}" '
            f'Location="http://{speaker.ip}:1400/xml/device_description.xml" '
            f'ZoneName="{escape(speaker.room)}"{attributes}>'
        )

    state = (
        "<ZoneGroupState><ZoneGroups>"
        f'<ZoneGroup Coordinator="{KITCHEN.uuid}">{member(KITCHEN)}</ZoneGroupMember></ZoneGroup>'
        f'<ZoneGroup Coordinator="{LIVING.uuid}">{member(LIVING)}'
        f'<Satellite UUID="{SURROUND.uuid}" ZoneName="{escape(SURROUND.room)}"/>'
        "</ZoneGroupMember></ZoneGroup>"
        f'<ZoneGroup Coordinator="{BEDROOM.uuid}">{member(BEDROOM)}</ZoneGroupMember>'
        f'{member(STEREO_RIGHT, " Invisible=" + chr(34) + "1" + chr(34))}</ZoneGroupMember></ZoneGroup>'
        "</ZoneGroups></ZoneGroupState>"
    )
    return f"<ZoneGroupState>{escape(state)}</ZoneGroupState>"


def av_transport(speaker, action, body):
    leader = leader_of(speaker)
    if action == "GetMediaInfo":
        return f"<CurrentURI>{escape(speaker.uri)}</CurrentURI>"
    if action == "GetTransportInfo":
        return f"<CurrentTransportState>{leader.transport}</CurrentTransportState>"
    if action == "GetPositionInfo":
        metadata = track_metadata(leader) if leader.transport == "PLAYING" else "NOT_IMPLEMENTED"
        return f"<TrackMetaData>{metadata}</TrackMetaData>"
    if action == "Play":
        speaker.transport = "PLAYING"
    elif action == "Pause":
        speaker.transport = "PAUSED_PLAYBACK"
    elif action == "Next":
        speaker.track = (speaker.track + 1) % len(TRACKS)
    elif action == "Previous":
        speaker.track = (speaker.track - 1) % len(TRACKS)
    elif action == "SetAVTransportURI":
        speaker.uri = argument(body, "CurrentURI")
    elif action == "BecomeCoordinatorOfStandaloneGroup":
        speaker.uri = ""
        speaker.transport = "STOPPED"
    elif action == "DelegateGroupCoordinationTo":
        new_leader = by_uuid(argument(body, "NewCoordinator"))
        new_leader.uri = speaker.uri.replace(speaker.uuid, new_leader.uuid)
        new_leader.transport = speaker.transport
        new_leader.track = speaker.track
        speaker.uri = f"x-rincon:{new_leader.uuid}"
    return ""


def rendering_control(speaker, action, body):
    if action == "GetVolume":
        return f"<CurrentVolume>{speaker.volume}</CurrentVolume>"
    if action == "SetVolume":
        speaker.volume = int(argument(body, "DesiredVolume"))
    return ""


def group_rendering_control(speaker, action, body):
    if action == "GetGroupVolume":
        level = group_level([member.volume for member in members(speaker)])
        return f"<CurrentVolume>{level}</CurrentVolume>"
    if action == "SnapshotGroupVolume":
        speaker.snapshot = {member.uuid: member.volume for member in members(speaker)}
    elif action == "SetGroupVolume":
        desired = int(argument(body, "DesiredVolume"))
        base = group_level(list(speaker.snapshot.values()))
        for member in members(speaker):
            member.volume = min(100, int(speaker.snapshot[member.uuid] * desired / base + 0.5))
    return ""


def device_properties(speaker, action, body):
    if action == "SetZoneAttributes":
        speaker.room = argument(body, "DesiredZoneName")
    return ""


def topology(_speaker, action, _body):
    return zone_group_state() if action == "GetZoneGroupState" else ""


SERVICES = {
    "/MediaRenderer/AVTransport/Control": av_transport,
    "/MediaRenderer/RenderingControl/Control": rendering_control,
    "/MediaRenderer/GroupRenderingControl/Control": group_rendering_control,
    "/DeviceProperties/Control": device_properties,
    "/ZoneGroupTopology/Control": topology,
}


def handler_for(speaker):
    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *_args):
            pass

        def send(self, body, status=200):
            data = body.encode()
            self.send_response(status)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            if self.path == "/xml/device_description.xml":
                self.send(
                    "<root><device><manufacturer>Sonos, Inc.</manufacturer>"
                    f"<UDN>uuid:{speaker.uuid}</UDN>"
                    f"<roomName>{escape(speaker.room)}</roomName>"
                    "</device></root>"
                )
            else:
                self.send("", 404)

        def do_POST(self):
            service = SERVICES.get(self.path)
            body = self.rfile.read(int(self.headers.get("Content-Length", 0))).decode()
            if service is None:
                self.send("", 404)
                return
            action = self.headers.get("SOAPACTION", "").strip('"').split("#")[-1]
            with LOCK:
                answer = service(speaker, action, body)
            self.send(f"<s:Envelope><s:Body><u:{action}Response>{answer}</u:{action}Response></s:Body></s:Envelope>")

    return Handler


class Server(http.server.ThreadingHTTPServer):
    daemon_threads = True

    def server_bind(self):
        # HTTPServer's own version looks the address up in DNS, which can take many seconds.
        socketserver.TCPServer.server_bind(self)
        self.server_name, self.server_port = self.server_address


servers = [Server((speaker.ip, 1400), handler_for(speaker)) for speaker in EVERYONE]
for server in servers:
    threading.Thread(target=server.serve_forever, daemon=True).start()
threading.Event().wait()
