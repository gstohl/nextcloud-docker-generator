import { MetaProvider, Title } from "@solidjs/meta";
import { Router } from "@solidjs/router";
import { FileRoutes } from "@solidjs/start/router";
import { Suspense } from "solid-js";
import "./app.css";

// Get base path from Vite config (set during build)
const base = import.meta.env.BASE_URL || "/";

export default function App() {
  return (
    <Router
      base={base.endsWith("/") ? base.slice(0, -1) : base}
      root={(props) => (
        <MetaProvider>
          <Title>Nextcloud Docker Generator</Title>
          <Suspense>{props.children}</Suspense>
        </MetaProvider>
      )}
    >
      <FileRoutes />
    </Router>
  );
}
