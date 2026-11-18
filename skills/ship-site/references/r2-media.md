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
