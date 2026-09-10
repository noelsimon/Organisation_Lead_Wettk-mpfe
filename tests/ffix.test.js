import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { bootApp } from "./setup.js";

let T, window;
beforeAll(async () => {
  const boot = await bootApp();
  T = boot.T;
  window = boot.window;
});
afterAll(() => window.close());

describe("ffix (fixe Besichtigung/ISO-Blöcke vor dem Finale)", () => {
  it("erzeugt Besichtigung direkt am Fensterbeginn, ISO danach, je Route", () => {
    T.CFG.win.bes = 25;
    T.CFG.win.iso = 20;
    const plan = { o: { start: 810 }, rows: [{ id: "F1", cls: "U9" }, { id: "F2", cls: "U11" }] };
    const out = T.ffix(plan);
    expect(out).toHaveLength(4);
    expect(out[0]).toMatchObject({ r: "F1", cls: "U9", dur: 25, s: 810, lab: "Besichtigung" });
    expect(out[1]).toMatchObject({ r: "F1", cls: "U9", dur: 20, s: 835, lab: "ISO" });
    expect(out[2]).toMatchObject({ r: "F2", cls: "U11", dur: 25, s: 810, lab: "Besichtigung" });
  });
  it("lässt eine Phase komplett weg, wenn ihre Dauer 0 ist", () => {
    T.CFG.win.bes = 0;
    T.CFG.win.iso = 20;
    const plan = { o: { start: 810 }, rows: [{ id: "F1", cls: "U9" }] };
    const out = T.ffix(plan);
    expect(out).toHaveLength(1);
    expect(out[0]).toMatchObject({ lab: "ISO", s: 810, dur: 20 });
  });
  it("liefert eine leere Liste ohne Routen", () => {
    T.CFG.win.bes = 25;
    T.CFG.win.iso = 20;
    expect(T.ffix({ o: { start: 810 }, rows: [] })).toEqual([]);
  });
});
