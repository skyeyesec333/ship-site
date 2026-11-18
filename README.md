# ship-site

Publishes a website to Cloudflare Pages and then checks the live site really shows the new version.

It came out of dozens of releases of a 3D website with a contact form and large videos.

## Good for

- Saying "ship it" and getting only the finished work published
- Proving the live site serves the build you just made
- Fixing a form or secret that "doesn't work" after you set it
- Files too big for Cloudflare Pages, such as long videos

## Install

In Claude Code, run:

```
/plugin marketplace add skyeyesec333/ship-site
/plugin install ship-site@ship-site
```

Or copy the skill into your own skills folder:

```sh
git clone https://github.com/skyeyesec333/ship-site
cp -r ship-site/skills/ship-site ~/.claude/skills/
```

You can also copy it into one project's `.claude/skills/` folder instead.

## Try asking Claude

In a project that deploys to Cloudflare Pages:

- "Ship it"
- "Publish this change to the live site"
- "I just set the Resend key, why does the form still fail?"
- "This video is too big for Pages"

Or call it directly: `/ship-site`.

## You'll need

- [Claude Code](https://claude.com/claude-code)
- A Cloudflare account with a Pages project, and [wrangler](https://developers.cloudflare.com/workers/wrangler/) signed in (`wrangler login`)
- Git, Bash, Node.js 18+

## How it works

```
look → commit → push → build → wrangler pages deploy → check the live addresses
```

1. **Ships only what is ready.** It reads `git status`, stages the finished change by name, and leaves half-done work out. It checks the changes for keys.
2. **Commits and pushes** with your GitHub noreply address and a plain message about what visitors will see.
3. **Builds and checks Pages' limits** (`scripts/check-sizes.sh`):
   - files over 25 MiB;
   - too many files for your plan;
   - a `_headers` file over 100 rules;
   - binary files Cloudflare will send uncompressed.
4. **Deploys** with `wrangler pages deploy`. When a secret changed, or your folder holds unfinished work, it rebuilds **exactly one commit from a clean copy** instead (`scripts/clean-redeploy.sh`).
5. **Checks the live site** (`scripts/check-live.mjs`):
   - the status and security headers;
   - that the page names every file of the build you just made;
   - that every script and stylesheet on your own site loads (`--all-origins` checks third-party ones too).

It also guides you through secrets (`wrangler pages secret put`), reading the logs of a failing Pages Function (the site's server code), big media on R2 (Cloudflare's file storage) with a custom domain, security headers and a CSP (a rule list for what the page may load).

Add an optional `ship.config.json` at your project's root, so Claude never has to ask:

```json
{
  "project": "my-site",
  "branch": "main",
  "build": "npm run build",
  "out": "dist",
  "live": ["https://example.com", "https://my-site.pages.dev"]
}
```

The scripts also run on their own. The paths are relative to the cloned repo:

```sh
node skills/ship-site/scripts/check-live.mjs --dist dist https://example.com
skills/ship-site/scripts/clean-redeploy.sh HEAD --project my-site --branch main --dry-run
skills/ship-site/scripts/check-sizes.sh dist
```

## Licence

MIT. See [LICENSE](LICENSE).
