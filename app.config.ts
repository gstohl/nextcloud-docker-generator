import { defineConfig } from "@solidjs/start/config";

const isGitHubPages = process.env.GITHUB_PAGES === "true";

export default defineConfig({
  server: {
    preset: isGitHubPages ? "static" : undefined,
    prerender: isGitHubPages ? { routes: ["/"] } : undefined,
  },
  vite: {
    base: isGitHubPages ? "/nextcloud-docker-generator/" : undefined,
  },
});
