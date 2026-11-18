# Hardening a Pages site

## Response headers (`public/_headers`, copied into the build)

A working starting point. It applies to static files only; a Pages Function sets its own headers.

```
/*
  Content-Security-Policy-Report-Only: default-src 'self'; script-src 'self'; img-src 'self' data: blob:; style-src 'self' 'unsafe-inline'; font-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'
  X-Content-Type-Options: nosniff
  X-Frame-Options: DENY
  Referrer-Policy: strict-origin-when-cross-origin
  Permissions-Policy: camera=(), microphone=(), geolocation=(), payment=(), usb=()
  Cross-Origin-Opener-Policy: same-origin
  Strict-Transport-Security: max-age=31536000; includeSubDomains

# Vite names these by content: a changed file gets a new name, so cache for a year.
/assets/*
  Cache-Control: public, max-age=31536000, immutable
```

- **Start the Content-Security-Policy as `-Report-Only`.** It logs what it would block and blocks nothing. Walk through the whole site on a preview deployment with the console open, add what is legitimately needed (Cloudflare Web Analytics adds `static.cloudflareinsights.com` to scripts and `cloudflareinsights.com` to connect; Turnstile needs `https://challenges.cloudflare.com` in script and frame; WebAssembly needs `'wasm-unsafe-eval'`; workers from blobs need `worker-src blob:`; media from another domain needs `media-src`), then rename the header to `Content-Security-Policy`.
- Leave `upgrade-insecure-requests` out while report-only (browsers ignore it there and warn on every load); add it when enforcing.
- **`Cross-Origin-Opener-Policy: same-origin` breaks popups that must talk back to the page:** sign in with Google/GitHub (OAuth popups), payment windows (PayPal, Stripe Checkout in a popup), some embeds. If the site opens any, use `same-origin-allow-popups` instead.
- **`includeSubDomains` in `Strict-Transport-Security` applies to every subdomain of the zone** for the whole `max-age`, including ones served elsewhere over plain http (an old blog, a device on `*.example.com`). Leave it out until every subdomain serves https; never add `preload` without being sure, as it is very slow to undo.
- **Do not add `Cross-Origin-Embedder-Policy`** if the site uses Turnstile or other third-party frames: it blocks them.
- Only `/assets/*` (content-hashed names) gets a long cache. Files in `public/` keep their names when their contents change; a year's cache would serve an old file to new code.

## A Pages Function that accepts posts (a contact form)

- **Allowlist origins** in the function (a var such as `ALLOWED_ORIGINS`): the custom domain(s) and the exact `pages.dev` address with its previews (`*.my-site.pages.dev`). If Cloudflare gave the project a **suffixed** address (`my-site-7xq.pages.dev`), that full origin must be on the list or the form is refused there. Allow localhost only behind a flag set in a local `.dev.vars`.
- An Origin header can be faked by a script, so the allowlist is not a bot defence: add Turnstile and a Cloudflare rate-limiting rule on the route before the domain is announced.
- **Fail closed:** on the live site, answer 503 if the bot-check secret is missing rather than skipping the check silently.
- Limit body size (e.g. 16 KB), refuse non-object JSON and non-string fields, strip control characters (including Unicode line and paragraph separators) from every field, and validate email addresses against the characters an address may contain (no `? & = %`).
- The dev server (Vite) does not run Pages Functions: a form posted in dev fails. Test the function with `wrangler pages dev <out>` and a stand-in for the mail provider.
- Prefer an API key of the site's own, limited to sending.

## Comments in the build

The minifier drops comments from code, but not from inside template strings, which is where shader code (GLSL) and HTML snippets live. A build-only Vite plugin can strip `/* ... */` blocks from template strings under `src/` in its `transform` hook (walk the source, track quotes and `${}` nesting, replace each comment inside a template with one space). Keep shader comments as block comments so such a plugin can find them. Check after building:

```sh
grep -o '/\*[^*]\{0,60\}' dist/assets/*.js | head
```

## History

A file deleted from the tree is still in Git history. If a secret or personal file was ever committed, removing it needs `git filter-repo --path <file> --invert-paths` and a force push, which rewrites everyone's history: the user's call, and only worth it before a repo is made public or shared.
