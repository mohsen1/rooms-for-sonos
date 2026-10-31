# How to install Rooms on a GL.iNet router

Rooms runs beside the GL.iNet admin panel and leaves it alone. The installer adds one nginx site, one small background service, and a folder at `/opt/rooms`.

This guide was tested on a GL-AXT1800 with firmware 4.8.3, in access point mode, with real Sonos speakers. Other models on 4.x firmware should behave the same way, and the installer stops with a message if the router lacks nginx, uhttpd or curl. A router reboot and a firmware upgrade with this install haven't been tested yet.

## Before you start

You need:

- A router on the same network as your speakers. Speakers on a guest network or a separate VLAN can't be reached.
- The router's admin password. SSH uses the same password, with the user name `root`.
- A computer with `ssh` and `git`.
- At least two Sonos rooms.

The examples use `192.168.8.1`, the default address of a GL.iNet router. If the router is in access point mode, its address comes from your main router, which lists it among its connected devices. Use that address everywhere below.

## 1. Check that you can log in

```bash
ssh root@192.168.8.1
```

Enter the admin password, then type `exit`. If `ssh` reports `no matching host key type found`, follow GL.iNet's [SSH guide](https://docs.gl-inet.com/router/en/4/tutorials/ssh_log_in_to_the_router/).

## 2. Install Rooms

Run these on your computer:

```bash
git clone https://github.com/mohsen1/rooms-for-sonos.git
cd rooms-for-sonos
./install.sh gl-inet root@192.168.8.1
```

You'll be asked for the router's password twice, once to copy the files and once to set them up.

The installer then looks for speakers. If it finds exactly two rooms, it uses them. If it finds more, it lists them and asks you to pick two by number. Surrounds, subs and the second speaker of a stereo pair aren't listed as rooms.

It finishes by printing the page's address:

```text
Rooms is running at http://192.168.8.1:8081/
```

## 3. Try it

Start some music in one of the two rooms, for example from Spotify. Then open that address on your phone and tap the other room. The music should move there within a few seconds.

## 4. Add it to your iPhone's Home Screen

Open the address in Safari, tap Share, then Add to Home Screen. You may need to tap View More first.

- Use the IP address, not a `.local` name. A `.local` address never loaded on the iPhone used for testing.
- If the router is in access point mode, reserve its address in your main router. The icon keeps pointing at the same address, so it stops working if the address changes.

## Other tasks

### Use a different port

Add the port to the end of the command. Rooms uses that port and the one after it.

```bash
./install.sh gl-inet root@192.168.8.1 8090
```

### Choose different rooms

Delete the saved choice and install again:

```bash
ssh root@192.168.8.1 rm /opt/rooms/config
./install.sh gl-inet root@192.168.8.1
```

### Search a specific network

The installer searches every network the router is attached to. To search one network, set `SUBNET` to the first three parts of its addresses:

```bash
SUBNET=192.168.1 ./install.sh gl-inet root@192.168.8.1
```

### Update Rooms

Run `git pull`, then run the same install command. Your rooms are kept. A page that's already open reloads itself once it sees the new version.

### Keep Rooms through a firmware upgrade

Turn on [Keep Settings](https://docs.gl-inet.com/router/en/4/tutorials/how_to_upgrade_downgrade_router/) when you upgrade. Rooms lists its files in `/etc/sysupgrade.conf`, which the firmware uses to decide what to keep. This hasn't been tested through a real upgrade, so if Rooms is gone afterwards, install it again.

### Remove Rooms

```bash
./uninstall.sh root@192.168.8.1
```

This removes everything the installer added, including its lines in `/etc/sysupgrade.conf`.

## Troubleshooting

| What you see | What to do |
| --- | --- |
| `Port 8081 is in use` | Install on [another port](#use-a-different-port). |
| `No Sonos speakers found` | Check that the speakers and router share a network, or [search a specific network](#search-a-specific-network). |
| `Found 1 Sonos room` | Rooms needs two. A stereo pair or home theatre set counts as one room. |
| "Not connected to home Wi-Fi" while you're at home | The page can't reach the router or one of the two rooms. Check that both rooms are switched on. If a speaker's address changed, Rooms finds it again after about 15 seconds. |
| The Home Screen icon opens an old version | Delete the icon and add it again. iOS keeps a separate copy of the page for each icon. |
