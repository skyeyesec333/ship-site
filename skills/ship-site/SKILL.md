---
name: ship-site
description: Publish a static site or Vite/React app to Cloudflare Pages and prove it is live. Use when the user says ship, publish, deploy, push live, release, or "put it on the site"; when a Pages secret was set or changed and must take effect; when a file is too big for Pages; or when a Pages Function (a contact form, an API route) fails on the live site.
---

# Ship a site to Cloudflare Pages

A release flow refined over dozens of releases of a production site: a large three.js app with a Pages Function behind its contact form and its big media on R2.

```
1. look      git status; decide what ships and what does not
2. commit    plain message saying what visitors will see; noreply author; push
3. build     the project's build command into the output folder; size check
4. deploy    wrangler pages deploy <out> --project-name <p> --branch <b>
5. check     scripts/check-live.mjs against every live address
```

Do every step every time, and report what the live check printed. "Deployed" without step 5 is not shipped.

## Config

Read `ship.config.json` at the project root if it exists; otherwise ask once and offer to write it:

```json
{
  "project": "my-site",
  "branch": "main",
  "build": "npm run build",
  "out": "dist",
  "live": ["https://example.com", "https://www.example.com", "https://my-site.pages.dev"]
}
```

`project` is the Cloudflare Pages project name, `branch` the one Pages treats as production. A `wrangler.toml` with `pages_build_output_dir` gives `out` too.

## 1. Look before shipping

- `git status --short` and `git diff --stat`. A dirty tree is normal: other work may be half done. **Ship only the change that is ready.** Stage those paths by name (never `git add -A` on a tree with unrelated edits), and say what you left out.
- `wrangler pages deploy` uploads the built folder, **not** a commit. If unrelated edits are in the working tree, the build contains them. When they must not go out, build from a clean copy of the commit: `scripts/clean-redeploy.sh <commit>` (step 4b).
- Never commit secrets: `.env`, `.dev.vars`, `.wrangler/` belong in `.gitignore`. Grep the staged diff for keys (`sk_`, `re_`, `-----BEGIN`, `api_key`) before committing.

## 2. Commit and push

- Author email: the user's **GitHub noreply address** (`<id>+<login>@users.noreply.github.com`, shown in GitHub's email settings), never a personal one. Check `git config user.email` before the first commit in a repo.
- The message says what changed for a visitor in a plain sentence ("The contact form now says why a send failed"), not the code ("fix handler").
- Push to the production branch. **A Pages project that was created with `wrangler pages project create` is not connected to Git: the push publishes nothing.** Check in the dashboard (Settings → Builds) or `wrangler pages project list` if unsure. If it *is* Git-connected, the push is the deploy; skip step 4 and wait for that build instead.

## 3. Build

Run the build command. Then:

```sh
scripts/check-sizes.sh dist        # any file over 25 MiB? Pages refuses them
```

- **Pages refuses any single file over 25 MiB.** Big media (video, large models) go on **R2 behind a custom domain** (see [references/r2-media.md](references/r2-media.md)).
- **Cloudflare does not compress `application/octet-stream`.** Binary formats it does not know (`.vrm`, `.bin`, custom extensions) are served at full size. Gzip them at build time and inflate in the browser with `DecompressionStream`, keeping the plain file beside it as a fallback.
- Comments in shipped JS/CSS: the minifier removes them, but **text inside template strings (GLSL shaders, HTML snippets) is left alone**. If source comments hold notes not meant for visitors, strip block comments from template strings in a build-only plugin and check the output with `grep -c '/\*' dist/assets/*.js`. See [references/hardening.md](references/hardening.md).

## 4. Deploy

```sh
wrangler pages deploy <out> --project-name <project> --branch <branch>
```

Use the global `wrangler` the user is signed in with (`wrangler whoami`). Keep the deployment URL it prints (`https://<hash>.<project>.pages.dev`); step 5 checks it too.

### 4b. A clean redeploy of an exact commit

For a redeploy where nothing in the code should change (a secret was added, a rollback, a dirty tree):

```sh
scripts/clean-redeploy.sh <commit> --project <project> --branch <branch> [--build "npm run build"] [--out dist] [--dry-run]
```

It `git archive`s that commit into a scratch folder, links the project's `node_modules`, builds there and deploys that build. Only what is in the commit can ship. `--dry-run` stops before the deploy.

## 5. Check it live

```sh
node scripts/check-live.mjs --dist <out> <url> [<url> ...]
```

For each address it reports the status, the security headers present and missing, whether the page references the **asset names of the build you just made** (so you know the new version is the one being served and not a cache), and the status of every script, stylesheet and preload the page names (any 4xx/5xx fails). Exit code 1 on any failure. Report its output.

If it shows the old assets: wait a few seconds and run it again (the custom domain can lag the `pages.dev` address briefly); if it persists, check that the deploy went to the production branch, not a preview.

## Secrets

- `wrangler pages secret put NAME --project-name <project>`: the word after `put` is the **name** of the secret. The value is typed at the prompt that follows. **Never put the value on the command line**: it would become a secret's name (readable in the dashboard) and sit in shell history. If that happens, delete that entry and have the user rotate the key.
- **A secret takes effect only on the next deployment.** After setting or changing one, redeploy (4b with the commit that is already live, so nothing unfinished goes out with it).
- Secrets are the user's to handle: let them type the value. Never write keys into the repo, a config file, or a chat.

## When a Pages Function fails live

Tail it while sending one request:

```sh
wrangler pages deployment tail <deployment-url> --project-name <project> --format json
```

It needs the deployment's address (from step 4 or `wrangler pages deployment list --project-name <project>`). Read the status code and the function's own log lines. Common causes: a secret not set or set before the last deploy, the origin not on the function's allowlist (add every `pages.dev` address Cloudflare gave the project, including any with a suffix, e.g. `my-site-abc.pages.dev`), a bot check (Turnstile) whose widget does not list that hostname.

More hard-won rules (headers, CSP, origins, caching): [references/hardening.md](references/hardening.md).
