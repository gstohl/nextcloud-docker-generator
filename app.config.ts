import { defineConfig } from "@solidjs/start/config";

const isGitHubPages = process.env.GITHUB_PAGES === "true";
const basePath = isGitHubPages ? "/nextcloud-docker-generator" : "";

export default defineConfig({
  server: {
    preset: isGitHubPages ? "static" : undefined,
    prerender: isGitHubPages ? { routes: ["/"] } : undefined,
    baseURL: basePath,
  },
  vite: {
    base: basePath + "/",
  },
});
