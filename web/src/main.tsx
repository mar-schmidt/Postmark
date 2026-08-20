import { StrictMode } from "react";
import { createRoot, hydrateRoot } from "react-dom/client";
import { RouterProvider } from "@tanstack/react-router";

import { getRouter } from "./router";
import "./styles.css";

const rootElement = document.getElementById("root");
if (!rootElement) {
  throw new Error("Missing #root element in index.html");
}

const app = (
  <StrictMode>
    <RouterProvider router={getRouter()} />
  </StrictMode>
);

// Known routes ship prerendered markup (see scripts/prerender.mjs), so adopt it
// instead of repainting from scratch. The dev server and the 404.html fallback
// both start from an empty #root and render normally.
if (rootElement.hasChildNodes()) {
  hydrateRoot(rootElement, app);
} else {
  createRoot(rootElement).render(app);
}
