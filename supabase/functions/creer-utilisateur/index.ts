// Edge Function « creer-utilisateur » — réservée aux administrateurs de l'organisation.
// Crée le compte (Supabase Auth), la fiche métier (livreur / vendeur) et le profil (membres).
// L'inscription libre est désactivée : c'est la SEULE voie pour créer des comptes.
import { createClient } from "npm:@supabase/supabase-js@2";

const ROLES = ["admin", "direction", "superviseur", "commercial", "preparateur", "caissier", "livreur", "vendeur"];
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), { status, headers: { ...cors, "Content-Type": "application/json" } });

// L'identifiant de connexion (nom d'utilisateur ou téléphone) devient un e-mail technique.
const toEmail = (id: string) =>
  id.includes("@") ? id.toLowerCase() : `${id.toLowerCase().replace(/[^a-z0-9._-]/g, "")}@users.angels-erp.app`;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ erreur: "Méthode non autorisée" }, 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  const auth = req.headers.get("Authorization") ?? "";
  const caller = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: auth } } });
  const { data: u } = await caller.auth.getUser();
  if (!u?.user) return json({ erreur: "Non connecté" }, 401);

  const { data: me } = await caller.from("membres").select("role, org_id, actif").eq("user_id", u.user.id).single();
  if (!me || !me.actif || me.role !== "admin") return json({ erreur: "Réservé aux administrateurs" }, 403);

  let b: Record<string, any>;
  try { b = await req.json(); } catch { return json({ erreur: "Corps JSON invalide" }, 400); }
  const { nom, role, identifiant, mot_de_passe } = b;
  if (!nom || !ROLES.includes(role) || !identifiant) return json({ erreur: "nom, role et identifiant requis" }, 400);
  if (typeof mot_de_passe !== "string" || mot_de_passe.length < 6) return json({ erreur: "Mot de passe / PIN : 6 caractères minimum" }, 400);

  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data: created, error: e1 } = await admin.auth.admin.createUser({
    email: toEmail(String(identifiant)), password: mot_de_passe, email_confirm: true,
  });
  if (e1 || !created.user) return json({ erreur: e1?.message ?? "Création du compte impossible" }, 400);
  const uid = created.user.id;

  const undo = async (msg: string) => { await admin.auth.admin.deleteUser(uid); return json({ erreur: msg }, 400); };
  let livreur_id: string | null = null, vendeur_id: string | null = null;

  if (role === "livreur") {
    const { data, error } = await admin.from("livreurs").insert({
      org_id: me.org_id, nom, tel: b.tel ?? null, zone: b.zone ?? null, moto_id: b.moto_id ?? null,
    }).select("id").single();
    if (error) return undo(error.message);
    livreur_id = data.id;
  }
  if (role === "vendeur") {
    const { data, error } = await admin.from("vendeurs").insert({
      org_id: me.org_id, nom, tel: b.tel ?? null, commission_pct: Number(b.commission_pct ?? 0),
    }).select("id").single();
    if (error) return undo(error.message);
    vendeur_id = data.id;
  }
  const { error: e2 } = await admin.from("membres").insert({ user_id: uid, org_id: me.org_id, role, nom, livreur_id, vendeur_id });
  if (e2) {
    if (livreur_id) await admin.from("livreurs").delete().eq("id", livreur_id);
    if (vendeur_id) await admin.from("vendeurs").delete().eq("id", vendeur_id);
    return undo(e2.message);
  }
  await admin.from("audit_log").insert({
    org_id: me.org_id, user_id: u.user.id, user_nom: "Administrateur", role: "admin",
    action: "Création de compte", detail: `${nom} (${role})`,
  });
  return json({ ok: true, user_id: uid, email: toEmail(String(identifiant)) });
});
