#!/usr/bin/env node
// Zieht den reinen JS-Inhalt aus src/script.part (das die eigenen
// <script>-Tags im Dateiinhalt trägt, siehe src/build.py) und schreibt ihn
// als echte .js-Datei, damit ESLint sie parsen kann - ohne script.part
// selbst anzufassen.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");

const src = fs.readFileSync(path.join(ROOT, "src/script.part"), "utf8");
const m = /^<script>\n([\s\S]*)\n<\/script>\n?$/.exec(src);
if (!m) {
  console.error("extract-js.mjs: konnte <script>…</script> in src/script.part nicht finden");
  process.exit(1);
}

const outDir = path.join(ROOT, ".eslint-tmp");
fs.mkdirSync(outDir, { recursive: true });
fs.writeFileSync(path.join(outDir, "script.part.js"), m[1]);
