import { renderToString } from "react-dom/server";
import { RouterProvider, createMemoryHistory } from "@tanstack/react-router";

import { getRouter } from "./router";

export interface HeadTag {
  tag: string;
  attrs: Record<string, string>;
  children?: string;
}

export interface RenderResult {
  html: string;
  head: HeadTag[];
}

/**
 * Collect the <head> tags the matched routes declared through their `head()`
 * option. We emit these into the document ourselves rather than trusting
 * whatever <HeadContent /> serialises into the body, so each prerendered page
 * ends up with exactly one <title> and one canonical link.
 */
function collectHead(matches: readonly unknown[]): HeadTag[] {
  const tags: HeadTag[] = [];

  for (const match of matches as Array<{
    meta?: Array<Record<string, string> | undefined>;
    links?: Array<Record<string, string> | undefined>;
  }>) {
    for (const meta of match.meta ?? []) {
      if (!meta) continue;
      const { title, ...attrs } = meta;
      if (typeof title === "string") {
        tags.push({ tag: "title", attrs: {}, children: title });
        continue;
      }
      if (Object.keys(attrs).length > 0) {
        tags.push({ tag: "meta", attrs: attrs as Record<string, string> });
      }
    }
    for (const link of match.links ?? []) {
      if (!link) continue;
      tags.push({ tag: "link", attrs: link as Record<string, string> });
    }
  }

  return tags;
}

export async function render(url: string): Promise<RenderResult> {
  const router = getRouter(createMemoryHistory({ initialEntries: [url] }));

  await router.load();

  const html = renderToString(<RouterProvider router={router} />);

  return { html, head: collectHead(router.state.matches) };
}

/** Every static (non-parameterised) path in the route tree. */
export function getStaticPaths(): string[] {
  const router = getRouter(createMemoryHistory({ initialEntries: ["/"] }));

  return Object.keys(router.routesByPath)
    .filter((path) => !path.includes("$") && !path.includes("*"))
    .sort();
}
