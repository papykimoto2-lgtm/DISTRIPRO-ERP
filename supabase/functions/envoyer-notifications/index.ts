// Edge Function « envoyer-notifications » : envoie les messages clients en attente (WhatsApp / SMS).
// Appelée toutes les minutes par pg_cron (en-tête x-cron-secret) ou à la demande par un administrateur connecté.
import { createClient } from "npm:@supabase/supabase-js@2";
import { envoyerUne, type Cfg, type Notif } from "../_shared/messagerie.ts";

const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ erreur: "Méthode non autorisée" }, 405);
  const url = Deno.env.get("SUPABASE_URL")!;
  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

  // Autorisation : secret du planificateur, ou administrateur connecté.
  const secret = Deno.env.get("CRON_SECRET");
  const okCron = !!secret && req.headers.get("x-cron-secret") === secret;
  if (!okCron) {
    const caller = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } });
    const { data: u } = await caller.auth.getUser();
    if (!u?.user) return json({ erreur: "Non autorisé" }, 401);
    const { data: me } = await caller.from("membres").select("role, actif").eq("user_id", u.user.id).single();
    if (!me?.actif || me.role !== "admin") return json({ erreur: "Réservé aux administrateurs" }, 403);
  }

  const env = Deno.env.toObject();
  const { data: lot, error } = await admin.rpc("reserver_notifications", { p_limit: 20 });
  if (error) return json({ erreur: error.message }, 500);

  const cfgs = new Map<string, Cfg>();
  const bilan = { reserves: lot?.length ?? 0, envoyes: 0, a_retenter: 0, echecs: 0 };
  for (const n of lot ?? []) {
    if (!cfgs.has(n.org_id)) {
      const { data: o } = await admin.from("organisations").select("config").eq("id", n.org_id).single();
      cfgs.set(n.org_id, (o?.config?.messagerie ?? {}) as Cfg);
    }
    const cfg = cfgs.get(n.org_id)!;
    const r = await envoyerUne(n as Notif, cfg, env);
    await admin.rpc("marquer_notification", {
      p_id: n.id, p_ok: r.ok, p_provider: cfg.provider ?? "twilio", p_provider_id: r.providerId ?? null,
      p_erreur: r.erreur ?? null, p_definitif: r.definitif ?? false,
    });
    if (r.ok) bilan.envoyes++; else if (r.definitif || n.tentatives + 1 >= 3) bilan.echecs++; else bilan.a_retenter++;
  }
  return json(bilan);
});
