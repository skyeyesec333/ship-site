#!/usr/bin/env node
// Check that live addresses serve the site you just built.
//
//   node check-live.mjs [--dist dist] [--strict-headers] [--all-origins] [--timeout 15] <url> [<url> ...]
//
// For each address: HTTP status, security headers present / missing, whether the page references every hashed
// asset that the local build's index.html references (proving the new build is the one served), and the status
// of every script, stylesheet, modulepreload, preload and icon the page names. Exits 1 on any failure.
// Assets are fetched without following redirects: one that redirects to another host or from https to http
// is reported. Every request times out (default 15 s).
// Needs Node 18+ (built-in fetch). Sends a neutral User-Agent and nothing else.

import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

const args = process.argv.slice(2);
let dist = null, strictHeaders = false, allOrigins = false, timeoutS = 15;
const MAX_ASSETS = 200;
const urls = [];
for (let i = 0; i < args.length; i++) {
  if (args[i] === "--dist") dist = args[++i];
  else if (args[i] === "--timeout") timeoutS = Number(args[++i]);
  else if (args[i] === "--strict-headers") strictHeaders = true;
  else if (args[i] === "--all-origins") allOrigins = true;
  else if (args[i] === "-h" || args[i] === "--help") { console.log("usage: check-live.mjs [--dist dist] [--strict-headers] [--all-origins] [--timeout 15] <url> ..."); process.exit(0); }
  else urls.push(args[i]);
}
if (!urls.length) { console.error("give at least one URL"); process.exit(2); }
if (dist === undefined) { console.error("--dist needs a folder"); process.exit(2); }
if (!(timeoutS > 0)) { console.error("--timeout needs a number of seconds"); process.exit(2); }

const UA = "ship-site-check/0.1";
const HEADERS = ["strict-transport-security", "x-content-type-options", "x-frame-options", "referrer-policy",
  "content-security-policy", "permissions-policy", "cross-origin-opener-policy"];

// The hashed assets the local build's index.html references (e.g. /assets/index-a1b2c3d4.js). All of them
// must appear in the live page: a chunk whose content did not change keeps its hash, so "any one" would let
// an old deployment pass.
function builtAssets(dir) {
  if (!dir) return null;
  if (!existsSync(dir)) { console.error(`build folder not found: ${dir}`); process.exit(2); }
  const index = join(dir, "index.html");
  if (!existsSync(index)) { console.error(`no index.html in ${dir}: cannot tell which build is live`); process.exit(2); }
  const html = readFileSync(index, "utf8");
  const names = new Set();
  for (const m of html.matchAll(/\b(?:src|href)=["']([^"']+)["']/gi)) {
    const file = m[1].split(/[?#]/)[0].split("/").pop();
    if (/[-.][A-Za-z0-9_-]{8,}\.(js|mjs|css)$/.test(file)) names.add(file);
  }
  if (!names.size) console.log(`warn ${index} names no hashed .js/.css files; the build check is skipped`);
  return [...names];
}

async function get(url, method = "GET", redirect = "follow") {
  try {
    return await fetch(url, { method, redirect, signal: AbortSignal.timeout(timeoutS * 1000),
      headers: { "user-agent": UA, "cache-control": "no-cache" } });
  } catch (e) {
    const error = e.name === "TimeoutError" ? `no answer in ${timeoutS} s` : e.message;
    return { status: 0, error, headers: new Headers(), text: async () => "", body: null };
  }
}
const drop = (r) => { try { r.body?.cancel(); } catch {} };  // free the socket of a body we do not read

function refsIn(html, base) {
  const refs = new Set();
  const re = /<(script|link)\b[^>]*>/gi;
  let m;
  while ((m = re.exec(html))) {
    const tag = m[0];
    const rel = (tag.match(/\brel=["']?([^"' >]+)/i) || [])[1] || "";
    const src = (tag.match(/\b(?:src|href)=["']([^"']+)["']/i) || [])[1];
    if (!src || src.startsWith("data:")) continue;
    if (m[1].toLowerCase() === "link" && !/^(stylesheet|modulepreload|preload|icon|manifest|apple-touch-icon)$/i.test(rel)) continue;
    try { refs.add(new URL(src, base).href); } catch {}
  }
  return [...refs];
}

const assets = builtAssets(dist);
let failed = false;
const fail = (msg) => { failed = true; console.log(`  FAIL ${msg}`); };

for (const url of urls) {
  console.log(`\n${url}`);
  const r = await get(url);
  if (r.status !== 200) { drop(r); fail(`status ${r.status}${r.error ? ` (${r.error})` : ""}`); continue; }
  console.log(`  ok   status 200${r.url && r.url !== url ? ` (after redirect to ${r.url})` : ""}`);

  const present = [], missing = [];
  for (const h of HEADERS) {
    if (r.headers.get(h)) present.push(h);
    else if (h === "content-security-policy" && r.headers.get("content-security-policy-report-only")) present.push("csp(report-only)");
    else missing.push(h);
  }
  console.log(`  ${missing.length ? (strictHeaders ? "FAIL" : "warn") : "ok  "} headers: ${present.join(", ") || "none"}${missing.length ? ` | missing: ${missing.join(", ")}` : ""}`);
  if (missing.length && strictHeaders) failed = true;
  if (r.headers.get("cross-origin-embedder-policy")) console.log("  warn cross-origin-embedder-policy is set: it blocks third-party frames such as Turnstile");

  const html = await r.text();
  if (assets && assets.length) {
    const missingA = assets.filter((a) => !html.includes(a));
    if (missingA.length) fail(`the page lacks ${missingA.length} of the ${assets.length} hashed files this build's index.html names (e.g. ${missingA[0]}): an old build (or a cache) is being served`);
    else console.log(`  ok   serves this build (all ${assets.length} hashed files its index.html names)`);
  }

  // Only fetch what the page references on its own origin (http/https), unless --all-origins: the page's
  // HTML decides what gets requested, so a third-party or tampered page must not steer this script elsewhere.
  const origin = new URL(r.url || url).origin;
  const all = refsIn(html, r.url || url).filter((u) => /^https?:$/.test(new URL(u).protocol));
  const others = all.filter((u) => new URL(u).origin !== origin);
  let refs = allOrigins ? all : all.filter((u) => new URL(u).origin === origin);
  if (!allOrigins && others.length) console.log(`  info ${others.length} asset(s) on other origins not fetched (pass --all-origins to check them)`);
  if (refs.length > MAX_ASSETS) { console.log(`  warn ${refs.length} assets referenced; checking the first ${MAX_ASSETS}`); refs = refs.slice(0, MAX_ASSETS); }
  let bad = 0;
  await Promise.all(refs.map(async (ref) => {
    let a = await get(ref, "HEAD", "manual");
    if (a.status === 405 || a.status === 0) { drop(a); a = await get(ref, "GET", "manual"); }
    drop(a);
    if (a.status >= 300 && a.status < 400) {
      // Not followed: say where it goes, and fail if it leaves the site or drops to http.
      const loc = a.headers.get("location");
      let to = null; try { to = new URL(loc, ref); } catch {}
      if (!to) { bad++; fail(`${a.status} ${ref} redirects with no usable Location`); return; }
      const from = new URL(ref);
      if (from.protocol === "https:" && to.protocol !== "https:") { bad++; fail(`${a.status} ${ref} redirects from https to ${to.protocol} (${to.href})`); return; }
      if (to.host !== from.host) { console.log(`  warn ${ref} redirects to another host: ${to.href} (not followed)`); return; }
      console.log(`  info ${ref} redirects within the site to ${to.pathname} (not followed)`);
      return;
    }
    if (a.status >= 400 || a.status === 0) { bad++; fail(`${a.status}${a.error ? ` (${a.error})` : ""} ${ref}`); }
  }));
  if (!bad) console.log(`  ok   ${refs.length} referenced assets all load`);
}

console.log(failed ? "\nFAILED" : "\nALL OK");
process.exit(failed ? 1 : 0);
