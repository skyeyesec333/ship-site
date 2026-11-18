# ship-site

A Claude Code skill that publishes a static site or Vite app to **Cloudflare Pages** and proves it is live:

```
look → commit → push → build → wrangler pages deploy → check the live addresses
```

It came out of dozens of releases of a production three.js site with a contact-form Pages Function and its large media on R2, and it carries the lessons from them: what a push does and does not publish, why a new secret "doesn't work", the 25 MiB file limit, and how to see why a live function fails.

## What the skill does

1. **Ships only what is ready:** reads `git status`, stages the finished change by name, leaves half-done work out, and checks the diff for keys.
2. **Commits and pushes** with your GitHub noreply address and a plain message about what visitors will see.
3. **Builds and checks Pages' limits** (`scripts/check-sizes.sh`): files over 25 MiB, too many files for the plan, a `_headers` file over 100 rules, and binary files Cloudflare will send uncompressed.
4. **Deploys** with `wrangler pages deploy`, or rebuilds **exactly one commit from a clean copy** (`scripts/clean-redeploy.sh`) when a secret changed or the working tree holds unfinished work.
5. **Checks the live site** (`scripts/check-live.mjs`): status, security headers, that the page names every hashed asset of the build you just made, and that every script and stylesheet on the site's own origin loads (`--all-origins` checks third-party ones too).

It also guides secrets (`wrangler pages secret put`), tailing a failing Pages Function, big media on R2 with a custom domain, security headers and a CSP rollout.

## Install

**As a Claude Code plugin** (from inside Claude Code):

```
/plugin marketplace add skyeyesec333/ship-site
/plugin install ship-site@ship-site
```

**Or as a plain skill:**

```sh
git clone https://github.com/skyeyesec333/ship-site
cp -r ship-site/skills/ship-site ~/.claude/skills/
```

(or into a project's `.claude/skills/` to keep it to that project).

## Use

Ask in a project that deploys to Cloudflare Pages:

- "Ship it"
- "Publish this change to the live site"
- "I just set the Resend key, why does the form still fail?"
- "This video is too big for Pages"

or call it: `/ship-site`.

Optionally add a `ship.config.json` at your project's root so it never has to ask:

```json
{
  "project": "my-site",
  "branch": "main",
  "build": "npm run build",
  "out": "dist",
  "live": ["https://example.com", "https://my-site.pages.dev"]
}
```

The scripts also run on their own:

```sh
node skills/ship-site/scripts/check-live.mjs --dist dist https://example.com
skills/ship-site/scripts/clean-redeploy.sh HEAD --project my-site --branch main --dry-run
skills/ship-site/scripts/check-sizes.sh dist
```

## Requirements

- [Claude Code](https://claude.com/claude-code)
- A Cloudflare account with a Pages project, and [wrangler](https://developers.cloudflare.com/workers/wrangler/) signed in (`wrangler login`)
- Git, Bash, Node.js 18+

## Licence

MIT. See [LICENSE](LICENSE).
