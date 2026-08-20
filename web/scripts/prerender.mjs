/**
 * Prerenders every static route to its own index.html.
 *
 * GitHub Pages serves 404.html for any path it has no file for, which means a
 * deep link like /privacy answered with an HTTP 404 status even though the SPA
 * then painted the right page. Crawlers that check status codes — Google's
 * OAuth verification review among them — can read that as a missing page. A
 * real dist/privacy/index.html makes the same URL a 200 with the policy text
 * already in the markup, no JavaScript required.
 */
import { access, mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const distDir = join(root, "dist");
const entryPath = join(root, "dist-ssr", "entry-server.js");

const escapeAttr = (value) =>
  String(value)
    .replace(/&/g, "&amp;")
    .replace(/"/g, "&quot;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");

const escapeText = (value) =>
  String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");

const renderAttrs = (attrs) =>
  Object.entries(attrs)
    .filter(([, value]) => value != null)
    .map(([key, value]) => `${key}="${escapeAttr(value)}"`)
    .join(" ");

/**
 * React 19 emits <title>/<meta>/<link> inline when they are rendered inside a
 * subtree rather than a whole document. We author the head ourselves from the
 * router's resolved tags, so drop those inline copies to avoid duplicates.
 */
function stripHoistedTags(html) {
  return html
    .replace(/<title[^>]*>[\s\S]*?<\/title>/gi, "")
    .replace(/<meta\b[^>]*\/?>/gi, "")
    .replace(/<link\b[^>]*\/?>/gi, "");
}

/** Replace a tag already present in the template, or insert it before </head>. */
function upsert(html, pattern, tag) {
  if (pattern.test(html)) {
    return html.replace(pattern, tag);
  }
  return html.replace(/([ \t]*)<\/head>/i, `    ${tag}\n$1</head>`);
}

function applyHead(html, headTags) {
  let out = html;

  for (const { tag, attrs, children } of headTags) {
    if (tag === "title") {
      out = upsert(
        out,
        /<title[^>]*>[\s\S]*?<\/title>/i,
        `<title>${escapeText(children ?? "")}</title>`,
      );
      continue;
    }

    if (tag === "meta") {
      const key = attrs.name ? "name" : attrs.property ? "property" : null;
      const rendered = `<meta ${renderAttrs(attrs)} />`;
      if (!key) {
        out = upsert(out, /$^/, rendered);
        continue;
      }
      const pattern = new RegExp(
        `<meta\\b[^>]*\\b${key}=["']${attrs[key].replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}["'][^>]*>`,
        "i",
      );
      out = upsert(out, pattern, rendered);
      continue;
    }

    if (tag === "link") {
      const rendered = `<link ${renderAttrs(attrs)} />`;
      const pattern =
        attrs.rel === "canonical"
          ? /<link\b[^>]*\brel=["']canonical["'][^>]*>/i
          : /$^/;
      out = upsert(out, pattern, rendered);
    }
  }

  return out;
}

/** Guard against the SSR bundle referencing asset names the client never emitted. */
async function verifyAssets(html, route) {
  const referenced = new Set(
    [...html.matchAll(/(?:src|href)="(\/assets\/[^"]+)"/g)].map((m) => m[1]),
  );

  for (const url of referenced) {
    try {
      await access(join(distDir, url));
    } catch {
      throw new Error(
        `${route} references ${url}, which is missing from dist/`,
      );
    }
  }
}

// 404.html is the untouched copy of the client build's index.html (the SPA
// fallback plugin writes it before this script runs), and prerendering never
// overwrites it. Reading the template from there keeps this script idempotent,
// since the home route's output replaces dist/index.html itself.
const templatePath = join(distDir, "404.html");
const template = await readFile(templatePath, "utf8");
if (!template.includes('<div id="root"></div>')) {
  throw new Error(
    `${templatePath} has no empty <div id="root"></div> to inject into`,
  );
}

const { getStaticPaths, render } = await import(pathToFileURL(entryPath).href);
const routes = getStaticPaths();

for (const route of routes) {
  const { html, head } = await render(route);
  const body = stripHoistedTags(html);

  let document = applyHead(template, head);
  document = document.replace(
    '<div id="root"></div>',
    `<div id="root">${body}</div>`,
  );

  await verifyAssets(document, route);

  const outPath =
    route === "/"
      ? join(distDir, "index.html")
      : join(distDir, route, "index.html");
  await mkdir(dirname(outPath), { recursive: true });
  await writeFile(outPath, document, "utf8");

  console.log(`prerendered ${route} -> ${outPath.replace(`${root}/`, "")}`);
}

console.log(`prerendered ${routes.length} route(s)`);
