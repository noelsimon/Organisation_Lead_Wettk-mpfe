#!/usr/bin/env node
// Zieht den reinen JS-Inhalt aus dem gebauten index.html (letztes
// <script>…</script>, siehe src/build.py) und schreibt ihn als echte
// .js-Datei, damit ESLint sie parsen kann. Die App-Logik liegt seit Issue #4
// in mehreren script-*.part-Modulen (src/build.py fügt sie zu einem
// gemeinsamen <script> zusammen) - hier gegen das fertige index.html zu
// linten statt gegen die einzelnen Module ist unabhängig davon, wie viele
// Module es gerade sind.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");

const html = fs.readFileSync(path.join(ROOT, "index.html"), "utf8");
const start = html.lastIndexOf("<script>");
const end = html.indexOf("</script>", start);
if (start === -1 || end === -1) {
  console.error("extract-js.mjs: konnte das App-<script> in index.html nicht finden (erst 'npm run build'?)");
  process.exit(1);
}
const js = html.slice(start + "<script>".length, end);

const outDir = path.join(ROOT, ".eslint-tmp");
fs.mkdirSync(outDir, { recursive: true });
fs.writeFileSync(path.join(outDir, "script.part.js"), js);
