import { defineConfig } from "tsup";

export default defineConfig([
  // CJS + ESM
  {
    entry: { "chinese-summary": "src/chinese-summary.ts" },
    format: ["esm", "cjs"],
    dts: true,
    clean: true,
    minify: false,
    sourcemap: true,
    outDir: "dist",
    outExtension({ format }) {
      return format === "esm" ? { js: ".mjs" } : { js: ".cjs" };
    },
  },
  // IIFE：浏览器 <script> 标签引入
  {
    entry: { "chinese-summary": "src/chinese-summary.ts" },
    format: ["iife"],
    globalName: "ChineseSummary",
    clean: false,
    minify: false,
    sourcemap: true,
    outDir: "dist",
    outExtension: () => ({ js: ".iife.js" }),
    footer: { js: "window.ChineseSummary = ChineseSummary;" },
  },
]);
