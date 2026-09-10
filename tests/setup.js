import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { JSDOM } from "jsdom";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");

/* Minimaler Supabase-Mock: liefert überall leere/erfolgreiche Antworten,
   genau wie die Playwright-Testfahrten in diesem Projekt es bisher schon
   von Hand gemacht haben - siehe scratchpad/round*.mjs Skripte. */
function makeSupabaseMock() {
  function makeQuery() {
    let singleMode = null;
    const builder = {
      select() { return builder; },
      eq() { return builder; },
      order() { return builder; },
      match() { return builder; },
      neq() { return builder; },
      in() { return builder; },
      limit() { return builder; },
      maybeSingle() { singleMode = "maybe"; return builder; },
      single() { singleMode = "one"; return builder; },
      insert() { return Promise.resolve({ data: null, error: null }); },
      upsert() { return Promise.resolve({ data: null, error: null }); },
      update() { return { eq() { return Promise.resolve({ data: null, error: null }); } }; },
      delete() { return Promise.resolve({ data: null, error: null }); },
      then(resolve) {
        const out = singleMode ? null : [];
        return Promise.resolve(resolve({ data: out, error: null }));
      },
      catch() { return builder; },
    };
    return builder;
  }
  return {
    createClient() {
      return {
        from: makeQuery,
        auth: {
          getSession() { return Promise.resolve({ data: { session: null }, error: null }); },
          onAuthStateChange(cb) {
            setTimeout(cb, 0);
            return { data: { subscription: { unsubscribe() {} } } };
          },
        },
        channel() {
          const c = { on() { return c; }, subscribe() { return c; } };
          return c;
        },
        storage: {
          from() {
            return {
              upload() { return Promise.resolve({ data: null, error: null }); },
              getPublicUrl() { return { data: { publicUrl: "" } }; },
            };
          },
        },
        removeChannel() {},
      };
    },
  };
}

/**
 * Lädt die echte gebaute index.html in jsdom und lässt script.part einmal
 * unverändert durchlaufen - ohne die App-Logik zu refactorn, denn sie ist
 * als ein einziges IIFE geschrieben, das beim Laden die ganze Seite
 * verdrahtet (Buttons, Sektionen, …). Ein Testfixture mit nur ein paar
 * Elementen würde beim ersten `getElementById(...).onclick=` bereits
 * werfen; die echte Seite bringt alles mit, was die App erwartet.
 *
 * window.__TEST__=true (vor dem Parsen gesetzt) schaltet am Ende von
 * script.part einen Export-Haken frei: window.__TEST_EXPORTS__. Auf der
 * echten Seite bleibt er unerreichbar, es ändert sich nichts.
 */
export async function bootApp() {
  let html = fs.readFileSync(path.join(ROOT, "index.html"), "utf8");
  // Die externe Supabase-CDN-Datei nicht laden: offline/deterministisch in
  // CI, und window.supabase wird ohnehin per beforeParse gemockt, bevor
  // irgendein <script> läuft.
  html = html.replace(
    /<script src="https:\/\/cdn\.jsdelivr\.net\/npm\/@supabase\/supabase-js@2"><\/script>/,
    ""
  );

  const dom = new JSDOM(html, {
    runScripts: "dangerously",
    url: "http://localhost/",
    beforeParse(window) {
      window.__TEST__ = true;
      window.supabase = makeSupabaseMock();
    },
  });

  // Der App-Bootstrap hängt an onAuthStateChange (setTimeout) + darauf
  // aufbauenden .then()-Ketten; ein paar Ticks reichen, weil hier (anders
  // als live) alles synchron mit dem Mock auflöst.
  await new Promise((resolve) => dom.window.setTimeout(resolve, 50));

  const T = dom.window.__TEST_EXPORTS__;
  if (!T) {
    throw new Error(
      "window.__TEST_EXPORTS__ wurde nicht gesetzt - Testhaken in script.part fehlt, " +
      "oder der App-Boot ist unterwegs fehlgeschlagen (siehe dom.window Fehler)."
    );
  }
  return { dom, window: dom.window, document: dom.window.document, T };
}

let mountSeq = 0;
/** Legt frische mount/readout/editor-Container für eine isolierte Plan-Instanz an. */
export function makePlanMounts(document) {
  const n = ++mountSeq;
  const ids = { mount: `t-mount-${n}`, readout: `t-readout-${n}`, editor: `t-editor-${n}` };
  const mount = document.createElement("div"); mount.id = ids.mount;
  const readout = document.createElement("div"); readout.id = ids.readout;
  const editor = document.createElement("div"); editor.id = ids.editor;
  document.body.append(mount, readout, editor);
  return ids;
}
