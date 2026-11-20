# Big media on R2

Pages refuses any single file over **25 MiB**. A full-quality video (or a big model) belongs in an R2 bucket served from a custom domain on the same Cloudflare zone.

## Set up once

1. The user enables R2 in the dashboard (it asks for a payment method even on the free tier; storage up to 10 GB is free and R2 charges nothing for downloads).
2. `wrangler r2 bucket create <bucket>`
3. In the bucket's settings, connect a custom domain such as `media.example.com` (it must be on a zone in the same account). Do not rely on the `r2.dev` address for production: it is rate-limited.
4. Add the domain to the site's CSP (`media-src`, `img-src` or `connect-src`, whichever the files are fetched by).

## Upload

```sh
wrangler r2 object put <bucket>/<folder>/<version>/<file> --file <local> --content-type video/mp4 \
  --cache-control "public, max-age=31536000, immutable" --remote
```

- **Every new version goes under a new folder** (`reel/17/reel.mp4`, not over `reel/16/reel.mp4`), and the site's code points at the new path. Files are cached for a year as immutable; overwriting one would leave visitors with the old copy and gives no way back.
- Set the right `--content-type`; R2 serves what you give it.
- Check: `curl -sI https://media.example.com/<path>` shows 200, the type, the cache header, and `accept-ranges: bytes` (needed for video seeking).

## A pattern for video

Ship a small, silent preview with the site (well under 25 MiB) that autoplays muted, and swap the `<video>`'s `src` to the full-quality R2 file only when the visitor asks to watch with sound. Offer AV1, HEVC and H.264 sources. Do not start fetching media while the page's own loading is still in progress.

## Streaming a long or heavy video (HLS)

One fixed file at 12-15 Mbps freezes on a slow line; a ladder of qualities (HLS, played by hls.js) fixes that. How the ladder is stored decides whether it then plays smoothly:

- **One file per quality, read by byte ranges. Not hundreds of small pieces.** A ladder cut into two-second files (3 codecs x 5 qualities x 36 pieces = 540 objects) is almost never in the CDN's cache at the moment a piece is wanted, because few viewers ask for any one piece, so nearly every piece is fetched from R2 as it plays. Measured: 0.4-0.9 s before the first byte of each piece, now and then 3-9 s, on a 2 s piece. A deep buffer and retries only hide it. Cloudflare caches a whole file on the first range request for any part of it (measured: one MISS a file, then every range a HIT at 0.04-0.2 s, including a range 100 MB in, seconds later).
- **No re-encode is needed to convert.** For each quality, concatenate its init file and its pieces in order into one `.mp4`, and rewrite the playlist: `#EXT-X-MAP:URI="720.mp4",BYTERANGE="<init length>@0"`, then for each piece `#EXT-X-BYTERANGE:<length>@<offset>` above the same file name. Point the master list at the new playlists. Upload under a new folder beside the old one.
- **The bucket's CORS rule must allow the `range` request header** and expose `Content-Range`, or the ranged fetches fail from the site's origin.
- **Cloudflare keeps a separate cached copy per `Origin` header.** A file warmed with plain curl, or from localhost, is still cold for the live site. Warm with the site's own origin (and `www` if it serves too): one small range request of each file starts the copy.
- **Do not stream HEVC through hls.js.** In WebKit (Safari) the HEVC ladder locked up, buffer full, at every change of quality, in both packagings; AV1 and H.264 changed cleanly. Choose AV1 where `mediaCapabilities` says hardware decodes it smoothly, else H.264. H.264 costs about a fifth more bits for the same picture.
- **A speed check must time from the first byte**, with its own allowance for the wait before it. Timed from the request against a cold file, a 20 Mbps line read as 0.9 Mbps and the reel started at 360p.
- **A retry "at a fresh address" (`?r=1`) must be keyed per request, not per URL**, once every piece of a quality shares one URL: do it in a loader subclass from the loader's own retry count.
- **Test it cold and test every codec.** Upload and earlier test runs warm the cache, so "no freezes" measured straight after an upload proves little: play files nothing has asked for yet. A test browser picks one codec (headless Chrome and Playwright's WebKit picked AV1 here); real Safari on most devices picked another. Force each ladder in turn and force quality changes (web-perf-kit's `stream-play.mjs` does both).
