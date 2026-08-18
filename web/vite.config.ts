import { copyFileSync, existsSync } from "node:fs";
import { resolve } from "node:path";

import tailwindcss from "@tailwindcss/vite";
import { tanstackRouter } from "@tanstack/router-plugin/vite";
import react from "@vitejs/plugin-react";
import { defineConfig, type Plugin } from "vite";
import tsConfigPaths from "vite-tsconfig-paths";

// GitHub Pages has no server-side rewrites, so a deep link like /privacy is a
// hard 404 unless we ship a fallback document. Pages serves 404.html for any
// unmatched path, so an exact copy of index.html boots the SPA there instead.
function githubPagesSpaFallback(): Plugin {
  return {
    name: "github-pages-spa-fallback",
    apply: "build",
    closeBundle() {
      const outDir = resolve(__dirname, "dist");
      const index = resolve(outDir, "index.html");
      if (existsSync(index)) {
        copyFileSync(index, resolve(outDir, "404.html"));
      }
    },
  };
}

export default defineConfig({
  // Served from the root of the postmarkmailapp.com custom domain.
  base: "/",
  plugins: [
    tsConfigPaths(),
    tanstackRouter({ target: "react", autoCodeSplitting: true }),
    react(),
    tailwindcss(),
    githubPagesSpaFallback(),
  ],
  build: {
    outDir: "dist",
    emptyOutDir: true,
  },
});
