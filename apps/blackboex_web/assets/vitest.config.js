/**
 * @file Vitest configuration for Blackboex JavaScript tests.
 */
import { defineConfig } from "vitest/config";

/**
 * Exports the module default value.
 */
export default defineConfig({
  test: {
    environment: "jsdom",
    include: ["test/**/*.test.js"],
    globals: true,
  },
});
