# Opening a Home Screen web app with no network and no HTTPS

Rooms is a page on a home router, reached at an address like `http://192.168.8.1:8081/`. When you tap its icon away from home, the router can't be reached, and the page should still open and say so.

The usual tool for this is a service worker, but service workers need a [secure context](https://developer.mozilla.org/en-US/docs/Web/Security/Secure_Contexts), and plain HTTP on a private address isn't one. A certificate that an iPhone trusts is more than a home router page should ask of anyone. So the page has to survive on the HTTP cache alone.

This note describes what worked in testing, what broke it, and what's still unknown.

## What worked

The server sends the page with this header:

```http
Cache-Control: public, max-age=2592000, immutable, stale-if-error=2592000
```

With it, the Home Screen app opened from a cold start with the server unreachable. All of the page's styles and scripts are inline, so that one cached response is the whole app.

The page then asks the router for its state once a second, with a two-second limit. After two failures in a row, it shows "Not connected to home Wi-Fi". It keeps asking, so it recovers by itself when you get home.

The [nginx](../deploy/gl-inet/nginx.conf) and [lighttpd](../deploy/dd-wrt/lighttpd.conf) configurations both set this header on the page only. The status reply is never cached.

## What broke it

An earlier version refreshed its own copy in the background:

```js
fetch(location.href, { cache: 'reload' });
```

That looks harmless, and the fetch succeeded, but the Home Screen app stopped opening offline afterwards. It seems the fetch replaced the cached page with a copy iOS won't use without a network. A full `location.reload()` doesn't have this problem.

## Updating a page marked immutable

`immutable` tells the browser not to check for a new version, so the server can no longer replace the page by itself. Rooms works around this with a version number:

1. The installer stamps a version into a `<meta>` tag in the page and into a file on the router.
2. Each status reply includes the router's version.
3. If the two differ, and the speakers answered, the page calls `location.reload()`.
4. A `sessionStorage` entry limits this to one reload for each version, so a stubborn cache can't cause a reload loop.

Put this in place before anyone installs the page. A copy cached without the check has no way to learn about a new version, and the only fix is to delete the icon and add it again. That happened during development, when a bug fixed on the server stayed on one iPhone until the icon was re-added.

## Testing it

Two things made results misleading during this work.

**Each Home Screen icon has its own cache.** Clearing Safari's data doesn't touch it. On a simulator it's in `Library/WebClips/<id>.webclip/Storage/NetworkCache` under the device's data folder. Missing this meant one test ran against an old page and gave a false result.

**A page still in memory proves nothing.** Close the app fully and make the server unreachable before you open it, so the test is a cold launch.

## What isn't known

- **Which directive does the work.** The header has three parts, and they weren't tested one at a time. A test with `max-age` alone did fail, but that test page also made the `fetch` call above, so it proves nothing. The header may be longer than it needs to be.
- **Whether a real iPhone behaves the same.** These results come from an iOS 26.5 simulator, running against a real router through an SSH tunnel that could be switched off. The offline launch hasn't been confirmed on a physical iPhone or on iOS 27.
- **Whether Apple intends this.** None of this is documented behaviour for Home Screen apps, so an iOS update could change it.

If you can confirm or disprove any of these, please [open an issue](https://github.com/mohsen1/rooms-for-sonos/issues).

## References

- [Cache-Control](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Cache-Control) on MDN
- [RFC 8246](https://www.rfc-editor.org/rfc/rfc8246), which defines `immutable`
- [RFC 5861](https://www.rfc-editor.org/rfc/rfc5861), which defines `stale-if-error`
