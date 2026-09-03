// Edge Function: benachrichtigt die Admin-Adresse per Resend, wenn sich
// jemand neu registriert. Wird durch einen Supabase Database Webhook
// (Tabelle "profiles", Event INSERT) aufgerufen — siehe README.
//
// Secrets vor dem Deploy setzen:
//   supabase secrets set RESEND_API_KEY=re_xxxxxxxx
//   supabase secrets set ADMIN_EMAIL=deine@mail.de
//   supabase secrets set NOTIFY_FROM="Regieplan <onboarding@resend.dev>"   (optional, Default siehe unten)
//
// Deploy:
//   supabase functions deploy notify-signup

const CAT_LABEL: Record<string, string> = {
  orga: "Orga-Team",
  sicherung: "Sicherung",
  ergebnisdienst: "Ergebnisdienst",
  routenbau: "Routenbau",
  buffet: "Buffet",
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

  // Database-Webhook-Form: {type:"INSERT", table:"profiles", record:{...}}
  const record = payload.record ?? payload;
  const fullName = record?.full_name ?? "unbekannt";
  const email = record?.email ?? "unbekannt";
  const category = record?.category ?? "";

  const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");
  const ADMIN_EMAIL = Deno.env.get("ADMIN_EMAIL");
  const FROM = Deno.env.get("NOTIFY_FROM") || "Regieplan <onboarding@resend.dev>";

  if (!RESEND_API_KEY || !ADMIN_EMAIL) {
    return new Response(JSON.stringify({ error: "RESEND_API_KEY oder ADMIN_EMAIL fehlt (supabase secrets set ...)" }), { status: 500 });
  }

  const label = CAT_LABEL[category] || category;

  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${RESEND_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: FROM,
      to: [ADMIN_EMAIL],
      subject: `Neue Anmeldung: ${fullName} (${label})`,
      html:
        `<p><strong>${escapeHtml(fullName)}</strong> (${escapeHtml(email)}) hat sich als ` +
        `<strong>${escapeHtml(label)}</strong> für den Regieplan angemeldet und wartet auf Freigabe.</p>` +
        `<p>Freigeben im Admin-Dashboard der Seite.</p>`,
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
