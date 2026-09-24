import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { bootApp } from "./setup.js";

let T, window;
beforeAll(async () => {
  const boot = await bootApp();
  T = boot.T;
  window = boot.window;
});
afterAll(() => window.close());

describe("fmt (Minuten seit Mitternacht -> HH:MM)", () => {
  it("formatiert und füllt mit führenden Nullen auf", () => {
    expect(T.fmt(0)).toBe("00:00");
    expect(T.fmt(90)).toBe("01:30");
    expect(T.fmt(600)).toBe("10:00");
    expect(T.fmt(630)).toBe("10:30");
  });
  it("rundet Bruchteile von Minuten", () => {
    expect(T.fmt(90.6)).toBe("01:31");
  });
});

describe("parseTime (HH:MM -> Minuten seit Mitternacht)", () => {
  it("parst gültige Uhrzeiten", () => {
    expect(T.parseTime("10:30")).toBe(630);
    expect(T.parseTime("00:00")).toBe(0);
    expect(T.parseTime("23:59")).toBe(1439);
  });
  it("gibt null für ungültige Eingaben zurück", () => {
    expect(T.parseTime("")).toBeNull();
    expect(T.parseTime("nope")).toBeNull();
    expect(T.parseTime("10")).toBeNull();
  });
});

describe("routeNum (Issue #92 Teil B: frei vergebbare Routennummer)", () => {
  it("fällt ohne num auf die Ziffern aus r.id zurück (Bestandsdaten unverändert)", () => {
    expect(T.routeNum({ id: "Q7" })).toBe("7");
    expect(T.routeNum({ id: "F12" })).toBe("12");
  });
  it("nutzt num, sobald gesetzt - auch 0 und nicht-fortlaufende Werte", () => {
    expect(T.routeNum({ id: "Q7", num: 14 })).toBe(14);
    expect(T.routeNum({ id: "Q1", num: 0 })).toBe(0);
  });
  it("ignoriert num, wenn es explizit gelöscht wurde (null/leer), und fällt zurück", () => {
    expect(T.routeNum({ id: "Q3", num: null })).toBe("3");
    expect(T.routeNum({ id: "Q3", num: "" })).toBe("3");
  });
});

describe("quota (Finalquote je Wertungsgruppe)", () => {
  it("0 Gemeldete -> 0 Plätze", () => {
    expect(T.quota(0)).toBe(0);
    expect(T.quota(-3)).toBe(0);
  });
  it("unter 20 Gemeldeten: höchstens 6 Plätze, nie mehr als gemeldet", () => {
    expect(T.quota(5)).toBe(5);
    expect(T.quota(6)).toBe(6);
    expect(T.quota(19)).toBe(6);
  });
  it("ab 20 Gemeldeten: höchstens 10 Plätze", () => {
    expect(T.quota(20)).toBe(10);
    expect(T.quota(50)).toBe(10);
  });
});
