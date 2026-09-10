import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { bootApp, makePlanMounts } from "./setup.js";

let T, window, document;
beforeAll(async () => {
  const boot = await bootApp();
  T = boot.T;
  window = boot.window;
  document = boot.document;
});
afterAll(() => window.close());

/* Jede Instanz bekommt einen eigenen localStorage-Schlüssel und eigene
   Mount-Elemente, damit Tests sich nicht gegenseitig beeinflussen und
   nichts mit der schon laufenden App-Instanz (pq/pf) kollidiert. cls muss
   eine der Standard-Wertungsklassen sein (U9/U11/U13/U15), sonst wirft
   Plan.prototype.prune() die Testdaten beim Erzeugen sofort wieder raus. */
function makePlan(opts) {
  const ids = makePlanMounts(document);
  return new T.Plan({
    mount: ids.mount,
    readout: ids.readout,
    editor: ids.editor,
    store: "vitest-plan-" + Math.random().toString(36).slice(2),
    kind: "test",
    prefix: "T",
    start: 600,
    end: 900,
    step: 30,
    axisLabel: "Test",
    ...opts,
  });
}

describe("Plan-Engine: Routenwechsel (addRoute/delRoute)", () => {
  it("addRoute hängt eine neue Route mit fortlaufender Nummer an", () => {
    const plan = makePlan({
      rows: [{ id: "T1", cls: "U9", allow: "mw", mode: "TR" }],
      groups: [{ id: "g1", cls: "U9", gender: "m", n: 2 }],
      blocks: [],
    });
    plan.addRoute("U9", "m", "TR");
    expect(plan.rows.map((r) => r.id)).toEqual(["T1", "T2"]);
    expect(plan.rows[1]).toMatchObject({ cls: "U9", allow: "m", mode: "TR" });
  });

  it("delRoute verweigert das Löschen, solange ein Balken auf der Route liegt", () => {
    const plan = makePlan({
      rows: [{ id: "T1", cls: "U9", allow: "mw", mode: "TR" }, { id: "T2", cls: "U9", allow: "mw", mode: "TR" }],
      groups: [{ id: "g1", cls: "U9", gender: "m", n: 2 }],
      blocks: [{ id: "b1", gid: "g1", r: "T1", s: 600 }],
    });
    expect(plan.delRoute("T1")).toBe(false);
    expect(plan.rows.map((r) => r.id)).toEqual(["T1", "T2"]);
  });

  it("delRoute löscht, sobald die Route frei ist - verweigert es aber für die letzte verbleibende Route", () => {
    const plan = makePlan({
      rows: [{ id: "T1", cls: "U9", allow: "mw", mode: "TR" }, { id: "T2", cls: "U9", allow: "mw", mode: "TR" }],
      groups: [{ id: "g1", cls: "U9", gender: "m", n: 2 }],
      blocks: [{ id: "b1", gid: "g1", r: "T2", s: 600 }],
    });
    expect(plan.delRoute("T1")).toBe(true);
    expect(plan.rows.map((r) => r.id)).toEqual(["T2"]);
    expect(plan.delRoute("T2")).toBe(false);
    expect(plan.rows).toHaveLength(1);
  });
});

describe("Plan-Engine: gleichzeitig belegte Routen (Doppelbelegung)", () => {
  it("markiert zwei zeitlich überlappende Blöcke auf derselben Route als clash", () => {
    const plan = makePlan({
      rows: [{ id: "T1", cls: "U9", allow: "mw", mode: "TR" }],
      groups: [{ id: "g1", cls: "U9", gender: "m", n: 2 }, { id: "g2", cls: "U9", gender: "w", n: 2 }],
      // dur je Block = n*CLIMB(6) = 12 Min: b1 600-612, b2 605-617 -> überlappen sich
      blocks: [{ id: "b1", gid: "g1", r: "T1", s: 600 }, { id: "b2", gid: "g2", r: "T1", s: 605 }],
    });
    plan.recalc();
    expect(plan.stat.clash).toBe(2);
    expect(plan.nodes.b1.classList.contains("clash")).toBe(true);
    expect(plan.nodes.b2.classList.contains("clash")).toBe(true);
  });

  it("meldet keine Doppelbelegung, wenn die Blöcke sich nicht überschneiden", () => {
    const plan = makePlan({
      rows: [{ id: "T1", cls: "U9", allow: "mw", mode: "TR" }],
      groups: [{ id: "g1", cls: "U9", gender: "m", n: 2 }, { id: "g2", cls: "U9", gender: "w", n: 2 }],
      blocks: [{ id: "b1", gid: "g1", r: "T1", s: 600 }, { id: "b2", gid: "g2", r: "T1", s: 612 }],
    });
    plan.recalc();
    expect(plan.stat.clash).toBe(0);
  });
});

describe("Plan-Engine: Personalbedarf (maximal gleichzeitig belegte Routen)", () => {
  it("zählt, wie viele Routen zum selben Zeitpunkt höchstens gleichzeitig besetzt sind", () => {
    const plan = makePlan({
      rows: [
        { id: "T1", cls: "U9", allow: "m", mode: "TR" },
        { id: "T2", cls: "U9", allow: "m", mode: "TR" },
        { id: "T3", cls: "U9", allow: "m", mode: "TR" },
      ],
      groups: [
        { id: "g1", cls: "U9", gender: "m", n: 1 },
        { id: "g2", cls: "U9", gender: "m", n: 1 },
        { id: "g3", cls: "U9", gender: "m", n: 1 },
      ],
      // Alle drei starten gleichzeitig auf verschiedenen Routen -> 3 Routen-Teams nötig
      blocks: [
        { id: "b1", gid: "g1", r: "T1", s: 600 },
        { id: "b2", gid: "g2", r: "T2", s: 600 },
        { id: "b3", gid: "g3", r: "T3", s: 600 },
      ],
    });
    plan.recalc();
    expect(plan.stat.maxR).toBe(3);
  });

  it("sinkt, sobald ein Block zeitlich versetzt wird", () => {
    const plan = makePlan({
      rows: [
        { id: "T1", cls: "U9", allow: "m", mode: "TR" },
        { id: "T2", cls: "U9", allow: "m", mode: "TR" },
        { id: "T3", cls: "U9", allow: "m", mode: "TR" },
      ],
      groups: [
        { id: "g1", cls: "U9", gender: "m", n: 1 },
        { id: "g2", cls: "U9", gender: "m", n: 1 },
        { id: "g3", cls: "U9", gender: "m", n: 1 },
      ],
      blocks: [
        { id: "b1", gid: "g1", r: "T1", s: 600 },
        { id: "b2", gid: "g2", r: "T2", s: 600 },
        { id: "b3", gid: "g3", r: "T3", s: 800 },
      ],
    });
    plan.recalc();
    expect(plan.stat.maxR).toBe(2);
  });
});

describe("Plan-Engine: Pausen je Startgruppe (pauseRange/pauseTxt)", () => {
  it("liefert einen einzelnen Wert, wenn beide Routen dieselbe Startreihenfolge haben", () => {
    const plan = makePlan({
      rows: [{ id: "T1", cls: "U9", allow: "m", mode: "TR" }, { id: "T2", cls: "U9", allow: "m", mode: "TR" }],
      groups: [{ id: "g1", cls: "U9", gender: "m", n: 4 }],
      blocks: [{ id: "b1", gid: "g1", r: "T1", s: 600 }, { id: "b2", gid: "g1", r: "T2", s: 700 }],
    });
    const bs = [plan.b("b1"), plan.b("b2")].sort((a, b) => a.s - b.s);
    const pr = plan.pauseRange(plan.g("g1"), bs);
    expect(pr).toEqual({ lo: 100, hi: 100, uneven: false });
  });

  it("liefert eine Spanne, wenn die zweite Route gegen die erste gedreht ist", () => {
    const plan = makePlan({
      rows: [
        { id: "T1", cls: "U9", allow: "m", mode: "TR" },
        { id: "T2", cls: "U9", allow: "m", mode: "TR", dir: "ab" },
      ],
      groups: [{ id: "g1", cls: "U9", gender: "m", n: 4 }],
      blocks: [{ id: "b1", gid: "g1", r: "T1", s: 600 }, { id: "b2", gid: "g1", r: "T2", s: 700 }],
    });
    const bs = [plan.b("b1"), plan.b("b2")].sort((a, b) => a.s - b.s);
    const pr = plan.pauseRange(plan.g("g1"), bs);
    // Basis 100 Min, n=4, CLIMB=6 -> Spanne 100 ± (4-1)*6 = 82..118
    expect(pr).toEqual({ lo: 82, hi: 118, uneven: true });

    const pt = plan.pauseTxt(plan.g("g1"), bs);
    expect(pt.txt).toBe("82–118 Min");
    expect(pt.ok).toBe(false); // 118 liegt außerhalb des 45-65-Korridors
  });
});
