import { defineConfig } from "vitest/config";
import { cloudflareTest } from "@cloudflare/vitest-pool-workers";

export default defineConfig({
  plugins: [cloudflareTest({
    wrangler: { configPath: "./wrangler.jsonc" },
    // Test-only binding. Production receives TYPESAFE_API_KEY only through
    // the Cloudflare secret store, never through wrangler.jsonc.
    miniflare: {
      // Match the deployed Worker compatibility date.
      compatibilityDate: "2026-09-19",
      bindings: { TYPESAFE_API_KEY: "test-key-not-a-secret" }
    }
  })]
});
