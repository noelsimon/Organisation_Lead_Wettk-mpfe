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

describe("Plan-Engine: frei vergebbare Routennummer im Zeitplan (Issue #92 Teil B)", () => {
  it("zeigt ohne gesetzte Nummer automatisch die Ziffern aus der internen Routen-ID", () => {
    const plan = makePlan({
      rows: [{ id: "T7", cls: "U9", allow: "mw", mode: "TR" }],
      groups: [{ id: "g1", cls: "U9", gender: "m", n: 2 }],
      blocks: [],
    });
    expect(plan.el.querySelector(".rnum").value).toBe("7");
  });

  it("übernimmt eine frei vergebene Nummer und zeigt sie nach dem Re-Render", () => {
    const plan = makePlan({
      rows: [{ id: "T7", cls: "U9", allow: "mw", mode: "TR" }],
      groups: [{ id: "g1", cls: "U9", gender: "m", n: 2 }],
      blocks: [],
    });
    const input = plan.el.querySelector(".rnum");
    input.value = "14";
    input.dispatchEvent(new window.Event("change"));
    expect(plan.rows[0].num).toBe(14);
    expect(plan.el.querySelector(".rnum").value).toBe("14");
  });

  it("lässt r.id als internen Schlüssel für Blöcke unangetastet, auch nach einer Nummernänderung", () => {
    const plan = makePlan({
      rows: [{ id: "T7", cls: "U9", allow: "mw", mode: "TR" }],
      groups: [{ id: "g1", cls: "U9", gender: "m", n: 2 }],
      blocks: [{ id: "b1", gid: "g1", r: "T7", s: 600 }],
    });
    const input = plan.el.querySelector(".rnum");
    input.value = "99";
    input.dispatchEvent(new window.Event("change"));
    expect(plan.blocks[0].r).toBe("T7");
    expect(plan.rows[0].id).toBe("T7");
  });

  it("fällt bei geleertem Eingabefeld wieder auf die Ziffern aus der ID zurück", () => {
    const plan = makePlan({
      rows: [{ id: "T7", cls: "U9", allow: "mw", mode: "TR", num: 14 }],
      groups: [{ id: "g1", cls: "U9", gender: "m", n: 2 }],
      blocks: [],
    });
    const input = plan.el.querySelector(".rnum");
    input.value = "";
    input.dispatchEvent(new window.Event("change"));
    expect(plan.rows[0].num).toBeNull();
    expect(plan.el.querySelector(".rnum").value).toBe("7");
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

describe("Plan-Engine: Routen-Teams (Lückenerkennung, Issue #92)", () => {
  it("braucht kein zusätzliches Team, wenn eine Route nur mit einer echten Pause dazwischen zweimal belegt ist", () => {
    const plan = makePlan({
      rows: [
        { id: "T1", cls: "U9", allow: "m", mode: "TR" },
        { id: "T2", cls: "U9", allow: "m", mode: "TR" },
        { id: "T3", cls: "U9", allow: "m", mode: "TR" },
      ],
      groups: [
        { id: "g1", cls: "U9", gender: "m", n: 2 },
        { id: "g2", cls: "U9", gender: "m", n: 2 },
        { id: "g3", cls: "U9", gender: "m", n: 2 },
        { id: "g4", cls: "U9", gender: "m", n: 2 },
      ],
      // T1: 600-612, dann eine echte Pause ohne Kletterbetrieb, dann
      // 650-662. T2 (620-632) und T3 (636-648) laufen währenddessen, aber
      // nie gleichzeitig miteinander oder mit T1 - zu jedem Zeitpunkt ist
      // höchstens eine Route aktiv, ein einziges Team reicht also aus.
      blocks: [
        { id: "b1", gid: "g1", r: "T1", s: 600 },
        { id: "b2", gid: "g2", r: "T2", s: 620 },
        { id: "b3", gid: "g3", r: "T3", s: 636 },
        { id: "b4", gid: "g4", r: "T1", s: 650 },
      ],
    });
    plan.recalc();
    expect(plan.stat.maxR).toBe(1);
    expect(T.teams(plan, plan.stat.list)).toHaveLength(1);
  });

  it("braucht weiterhin so viele Teams wie tatsächlich gleichzeitig aktive Routen (maxR)", () => {
    const plan = makePlan({
      rows: [
        { id: "T1", cls: "U9", allow: "m", mode: "TR" },
        { id: "T2", cls: "U9", allow: "m", mode: "TR" },
      ],
      groups: [
        { id: "g1", cls: "U9", gender: "m", n: 2 },
        { id: "g2", cls: "U9", gender: "m", n: 2 },
      ],
      // T1 600-612, T2 605-617 -> überlappen sich echt, brauchen 2 Teams.
      blocks: [
        { id: "b1", gid: "g1", r: "T1", s: 600 },
        { id: "b2", gid: "g2", r: "T2", s: 605 },
      ],
    });
    plan.recalc();
    expect(plan.stat.maxR).toBe(2);
    expect(T.teams(plan, plan.stat.list)).toHaveLength(2);
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
