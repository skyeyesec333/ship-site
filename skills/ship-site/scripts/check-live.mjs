#!/usr/bin/env node
// Check that live addresses serve the site you just built.
//
//   node check-live.mjs [--dist dist] [--strict-headers] [--all-origins] <url> [<url> ...]
//
// For each address: HTTP status, security headers present / missing, whether the page references the asset
// file names in the local build folder (proving the new build is the one served), and the status of every
// script, stylesheet, modulepreload, preload and icon the page names. Exits 1 on any failure.
// Needs Node 18+ (built-in fetch). Sends a neutral User-Agent and nothing else.

import { readdirSync, statSync, existsSync } from "node:fs";
import { join, relative } from "node:path";

const args = process.argv.slice(2);
let dist = null, strictHeaders = false, allOrigins = false;
const MAX_ASSETS = 200;
const urls = [];
for (let i = 0; i < args.length; i++) {
  if (args[i] === "--dist") dist = args[++i];
  else if (args[i] === "--strict-headers") strictHeaders = true;
  else if (args[i] === "--all-origins") allOrigins = true;
  else if (args[i] === "-h" || args[i] === "--help") { console.log("usage: check-live.mjs [--dist dist] [--strict-headers] [--all-origins] <url> ..."); process.exit(0); }
  else urls.push(args[i]);
}
if (!urls.length) { console.error("give at least one URL"); process.exit(2); }

const UA = "ship-site-check/0.1";
const HEADERS = ["strict-transport-security", "x-content-type-options", "x-frame-options", "referrer-policy",
  "content-security-policy", "permissions-policy", "cross-origin-opener-policy"];

// Asset names from the local build: hashed files the page should reference (e.g. assets/index-a1b2c3.js).
function builtAssets(dir) {
  if (!dir) return null;
  if (!existsSync(dir)) { console.error(`build folder not found: ${dir}`); process.exit(2); }
  const out = [];
  const walk = (d) => { for (const f of readdirSync(d)) { const p = join(d, f); statSync(p).isDirectory() ? walk(p) : out.push(relative(dir, p)); } };
  walk(dir);
  return out.filter((p) => /\.(js|css)$/.test(p) && /[-.][A-Za-z0-9_-]{8,}\.(js|css)$/.test(p));
}

async function get(url, method = "GET") {
  try {
    const r = await fetch(url, { method, redirect: "follow", headers: { "user-agent": UA, "cache-control": "no-cache" } });
    return r;
  } catch (e) { return { status: 0, error: e.message, headers: new Headers(), text: async () => "" }; }
}

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
  if (r.status !== 200) { fail(`status ${r.status}${r.error ? ` (${r.error})` : ""}`); continue; }
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
  if (assets) {
    const seen = assets.filter((a) => html.includes(a.split("/").pop()));
    if (!seen.length) fail(`the page names none of this build's ${assets.length} hashed assets: an old build (or a cache) is being served`);
    else console.log(`  ok   serves this build (${seen.length} of its hashed files named in the page, e.g. ${seen[0]})`);
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
    let a = await get(ref, "HEAD");
    if (a.status === 405 || a.status === 0) a = await get(ref);
    if (a.status >= 400 || a.status === 0) { bad++; fail(`${a.status} ${ref}`); }
  }));
  if (!bad) console.log(`  ok   ${refs.length} referenced assets all load`);
}

console.log(failed ? "\nFAILED" : "\nALL OK");
process.exit(failed ? 1 : 0);
