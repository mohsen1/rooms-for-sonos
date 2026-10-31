# How to install Rooms on a DD-WRT router

DD-WRT's firmware doesn't include everything Rooms needs, so this install uses [Entware](https://github.com/Entware/Entware), a package system that lives on a USB drive. Rooms and its packages go on that drive.

> [!IMPORTANT]
> This guide hasn't been run on a physical DD-WRT router yet. The install has been tested in a container with real Entware packages and fake speakers ([`test/entware.sh`](../test/entware.sh)), but that container can't check DD-WRT's own menus or its trimmed-down system tools. The menu steps are based on DD-WRT's documentation and may differ between builds. If you try this, please [open an issue](https://github.com/mohsen1/rooms-for-sonos/issues) with your router model and build number, whether or not it worked.

The `dd-wrt` install depends only on Entware being available at `/opt`, so it may also work on FreshTomato or Asuswrt-Merlin. Neither has been tried.

## Before you start

You need:

- A DD-WRT router with a USB port, on the same network as your speakers.
- A USB drive. A small one is enough. Formatting it erases it.
- A computer with `ssh` and `git`.
- At least two Sonos rooms.

The examples use `192.168.1.1`, DD-WRT's default address. If your router uses another address, use it everywhere below.

## 1. Turn on SSH

1. In the router's web interface, open **Services > Services**.
2. Under **Secure Shell**, enable **SSHd**, then click **Apply Settings**.
3. Check that you can log in as `root` with the router's password:

```bash
ssh root@192.168.1.1
```

## 2. Set up the USB drive

1. On a computer, format the drive as ext4. FAT won't work, because Entware needs symbolic links.
2. Plug the drive into the router.
3. Open **Services > USB** and enable **Core USB Support**, **USB Storage Support** and **Automatic Drive Mount**.
4. Set the drive to mount on `/opt`, then click **Apply Settings**.
5. Check the mount over SSH. This should print a line for your drive:

```sh
mount | grep /opt
```

## 3. Install Entware

Find the router's processor type over SSH:

```sh
uname -m
```

Use the result to pick a feed:

| `uname -m` | Feed |
| --- | --- |
| `armv7l` | `armv7sf-k3.2` |
| `aarch64` | `aarch64-k3.10` |
| `mips`, little-endian (usually Broadcom or MediaTek) | `mipselsf-k3.4` |
| `mips`, big-endian (usually Atheros) | `mipssf-k3.4` |

For anything else, see the [full list of feeds](https://bin.entware.net/).

Then download and run the installer for your feed. This example uses `armv7sf-k3.2`:

```sh
cd /opt
wget https://bin.entware.net/armv7sf-k3.2/installer/generic.sh
sh generic.sh
```

If the router's `wget` can't do HTTPS, use `http://` instead. That download isn't protected in transit, and [ddwrt-secure-entware](https://github.com/Lanchon/ddwrt-secure-entware) describes the risk and a way around it.

If `bin.entware.net` doesn't resolve, add a public DNS server and try again:

```sh
echo nameserver 1.1.1.1 >> /etc/resolv.conf
```

## 4. Start Entware when the router boots

1. Open **Administration > Commands**.
2. Paste these lines and click **Save Startup**. The wait gives the drive time to mount.

```sh
sleep 10
/opt/etc/init.d/rc.unslung start
```

3. Clear the box, paste this line and click **Save Shutdown**.

```sh
/opt/etc/init.d/rc.unslung stop
```

## 5. Install Rooms

Run these on your computer:

```bash
git clone https://github.com/mohsen1/rooms-for-sonos.git
cd rooms-for-sonos
./install.sh dd-wrt root@192.168.1.1
```

You'll be asked for the router's password twice, once to copy the files and once to set them up.

The installer adds `lighttpd` and `curl` from Entware, then looks for speakers. If it finds exactly two rooms, it uses them. If it finds more, it lists them and asks you to pick two by number. It finishes with:

```text
Rooms is running on port 8081.
```

If it reports that a tool is missing, install that tool with `opkg install`, then run the same command again. DD-WRT leaves out different tools on different routers.

## 6. Try it

Start some music in one of the two rooms, for example from Spotify. Then open `http://192.168.1.1:8081/` on your phone and tap the other room. The music should move there within a few seconds.

## 7. Add it to your iPhone's Home Screen

Open the address in Safari, tap Share, then Add to Home Screen. You may need to tap View More first. Use the IP address, not a `.local` name.

## Other tasks

### Use a different port

Add the port to the end of the command:

```bash
./install.sh dd-wrt root@192.168.1.1 8090
```

### Choose different rooms

Delete the saved choice and install again:

```bash
ssh root@192.168.1.1 rm /opt/rooms/config
./install.sh dd-wrt root@192.168.1.1
```

### Search a specific network

The installer searches every network the router is attached to. To search one network, set `SUBNET` to the first three parts of its addresses:

```bash
SUBNET=192.168.1 ./install.sh dd-wrt root@192.168.1.1
```

### Update Rooms

Run `git pull`, then run the same install command. Your rooms are kept.

### Upgrade DD-WRT

[DD-WRT's Entware guide](https://dd-wrt.com/wiki/index.php/Installing_Entware) advises removing the drive, or at least disabling USB support, before you upgrade the firmware.

### Remove Rooms

```bash
./uninstall.sh root@192.168.1.1
```

This removes Rooms and its service. Entware and its packages stay on the drive. To remove lighttpd too, run `opkg remove lighttpd` on the router.

## Troubleshooting

| What you see | What to do |
| --- | --- |
| `Entware isn't installed` | Finish steps 2 and 3, and check that `/opt` is mounted. |
| `Rooms didn't start` | Another program may be using the port. Install on [another port](#use-a-different-port), or read `/tmp/rooms-lighttpd.log` on the router. |
| `No Sonos speakers found` | Check that the speakers and router share a network, or [search a specific network](#search-a-specific-network). |
| The page is gone after a reboot | Check the startup commands from step 4, and that the drive mounted on `/opt`. |
| "Not connected to home Wi-Fi" while you're at home | The page can't reach the router or one of the two rooms. Check that both rooms are switched on. |
