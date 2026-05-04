/**
 * @file Vitest configuration for Blackboex JavaScript tests.
 */
import { defineConfig } from "vitest/config";

/**
 * Vitest config for jsdom-based hook and library tests under `assets/test`.
 */
export default defineConfig({
  test: {
    environment: "jsdom",
    include: ["test/**/*.test.js"],
    globals: true,
  },
});
