# Why Safari hangs on some plain HTTP servers

On macOS 27 and iOS 27, Safari wouldn't open a page on a home router. There was no error, only a page that never loaded. `curl`, an embedded browser and an iOS 26.5 simulator all loaded the same page without trouble.

The page was served by uhttpd, the small web server that OpenWrt-based firmware uses. The cause turned out to be how uhttpd treats a connection that doesn't speak HTTP.

## What happens

Safari tries HTTPS first, even for an `http://` address, on the same port. So the server receives a TLS ClientHello on a port that expects plain HTTP.

Most servers see that the bytes aren't HTTP and close the connection. Safari treats that as a failed attempt and falls back to HTTP. uhttpd keeps waiting for the end of a request line that never comes, so Safari's attempt neither succeeds nor fails, and the page sits there.

## How to check a server

You don't need Safari. `curl` can make the same kind of attempt:

```bash
curl -sk -m 6 -o /dev/null -w 'exit %{exitcode} in %{time_total}s\n' https://192.168.8.1:8081/
```

Exit code 28 means the attempt timed out, so the server would hang Safari. Exit code 35 means the TLS attempt failed straight away, which is what you want.

These are the results for the servers tried:

| Server | Result |
| --- | --- |
| uhttpd, GL.iNet firmware 4.8.3 | Exit 28 after the full 6 seconds |
| nginx, GL.iNet firmware 4.8.3 | Exit 35 in 10 ms |
| lighttpd, Alpine 3.22 | Exit 35 in 1 ms |
| BusyBox `httpd`, Alpine 3.22 | Exit 35 in 2 ms |
| Python `http.server` | Exit 35 in 1 ms |

lighttpd checks for this case on purpose. Its [`h1.c`](https://github.com/lighttpd/lighttpd1.4/blob/master/src/h1.c) has the error message "unexpected TLS ClientHello on clear port".

## The fix

Put a server that refuses quickly in front of the one that doesn't. GL.iNet firmware already runs nginx, so Rooms serves the page from nginx and passes only `/cgi-bin/` to a private uhttpd on the loopback address. See [`deploy/gl-inet/nginx.conf`](../deploy/gl-inet/nginx.conf).

On DD-WRT, Rooms uses lighttpd directly.

## After the fix

The router's request log showed:

- **Safari on a Mac, using a `.local` name:** the HTTPS attempts were refused, and the page loaded over HTTP about a second later.
- **Safari on an iPhone, using an IP address:** the page loaded over HTTP, with no HTTPS attempt in the log.
- **Safari on an iPhone, using a `.local` name:** the page still showed a secure connection error and never loaded.

So use an IP address on an iPhone. The reason for the `.local` failure hasn't been found.

## What isn't known

Apple doesn't appear to document exactly when Safari tries HTTPS first, or how long it waits. The closest public description found is a [report from the iOS 18.2 beta](https://discuss.techlore.tech/t/ios-18-2-beta-adds-https-by-default-with-option-to-block-http-for-safari/10645), which says Safari prefers HTTPS and falls back when that fails. The explanation above fits what was measured here, but the rules Safari follows, and why an iPhone treated an IP address and a `.local` name differently, are inferred rather than documented.
