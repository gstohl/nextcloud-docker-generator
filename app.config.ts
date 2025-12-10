import { defineConfig } from "@solidjs/start/config";

export default defineConfig({
  // Static preset for GitHub Pages - only set during build
  ...(process.argv.includes("build") && {
    server: {
      preset: "static",
      prerender: {
        routes: ["/"],
      },
    },
    vite: {
      base: "/nextcloud-docker-generator/",
    },
  }),
});
