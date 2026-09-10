// Edge Function: benachrichtigt eine Person per Resend, wenn ihr eine
// Aufgabe zugewiesen wird. Wird durch einen Supabase Database Webhook
// (Tabelle "task_assignees", Event INSERT) aufgerufen — siehe README.
// Nach dem Vorbild von notify-signup, mit einem Unterschied: der Webhook
// liefert bei task_assignees nur task_id + profile_id (keine Titel/
// Namen/E-Mail), daher lädt diese Function Aufgabe, zugewiesene Person und
// Wettkampf selbst nach - mit dem Service-Role-Key, der jeder Edge
// Function automatisch zur Verfügung steht (kein RLS-Umweg nötig, aber
// auch kein zusätzliches Secret zu setzen).
//
// Secrets vor dem Deploy setzen (dieselben wie bei notify-signup, werden
// gemeinsam genutzt):
//   supabase secrets set RESEND_API_KEY=re_xxxxxxxx
//   supabase secrets set NOTIFY_FROM="Regieplan <onboarding@resend.dev>"   (optional, Default siehe unten)
//
// Deploy:
//   supabase functions deploy notify-task-assigned

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const PRIO_LABEL: Record<string, string> = {
  niedrig: "niedrig",
  mittel: "mittel",
  hoch: "hoch",
};

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 });
  }

  let payload: any;
  try {
    payload = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "invalid json" }), { status: 400 });
  }

  // Database-Webhook-Form: {type:"INSERT", table:"task_assignees", record:{task_id, profile_id}}
  const record = payload.record ?? payload;
  const taskId = record?.task_id;
  const profileId = record?.profile_id;
  if (!taskId || !profileId) {
    return new Response(JSON.stringify({ error: "task_id oder profile_id fehlt im Webhook-Payload" }), { status: 400 });
  }

  const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");
  const FROM = Deno.env.get("NOTIFY_FROM") || "Regieplan <onboarding@resend.dev>";
  // SUPABASE_URL/SUPABASE_SERVICE_ROLE_KEY sind für jede Edge Function
  // automatisch gesetzt, kein manuelles "secrets set" nötig.
  const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
  const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!RESEND_API_KEY) {
    return new Response(JSON.stringify({ error: "RESEND_API_KEY fehlt (supabase secrets set ...)" }), { status: 500 });
  }
  if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
    return new Response(JSON.stringify({ error: "SUPABASE_URL/SUPABASE_SERVICE_ROLE_KEY nicht verfügbar" }), { status: 500 });
  }

  const db = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  const [{ data: task, error: taskErr }, { data: assignee, error: profErr }] = await Promise.all([
    db.from("tasks").select("title, description, priority, competition_id").eq("id", taskId).maybeSingle(),
    db.from("profiles").select("email, full_name").eq("id", profileId).maybeSingle(),
  ]);
  if (taskErr || !task) {
    return new Response(JSON.stringify({ error: "Aufgabe nicht gefunden", detail: taskErr?.message }), { status: 404 });
  }
  if (profErr || !assignee?.email) {
    return new Response(JSON.stringify({ error: "Zugewiesene Person nicht gefunden oder ohne E-Mail", detail: profErr?.message }), { status: 404 });
  }

  const { data: comp } = await db.from("competitions").select("name").eq("id", task.competition_id).maybeSingle();
  const prio = PRIO_LABEL[task.priority as string] || task.priority || "";

  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${RESEND_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: FROM,
      to: [assignee.email],
      subject: `Neue Aufgabe: ${task.title}`,
      html:
        `<p>Hallo ${escapeHtml(assignee.full_name || "")},</p>` +
        `<p>dir wurde im Regieplan${comp?.name ? ` für <strong>${escapeHtml(comp.name)}</strong>` : ""} eine Aufgabe zugewiesen:</p>` +
        `<p><strong>${escapeHtml(task.title)}</strong>${prio ? ` (Priorität: ${escapeHtml(prio)})` : ""}</p>` +
        (task.description ? `<p>${escapeHtml(task.description)}</p>` : "") +
        `<p>Details und Kommentare unter „Aufgaben" auf der Seite.</p>`,
    }),
  });

  if (!res.ok) {
    const detail = await res.text();
    return new Response(JSON.stringify({ error: "resend request failed", detail }), { status: 502 });
  }

  return new Response(JSON.stringify({ ok: true }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});

function escapeHtml(s: string): string {
  return String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c] as string));
}
