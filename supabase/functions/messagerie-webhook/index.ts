// Edge Function « messagerie-webhook » : reçoit les accusés du prestataire (livré / lu / échec).
// Déployer SANS vérification JWT (le prestataire n'a pas de compte) : l'authenticité repose sur la signature.
//   supabase functions deploy messagerie-webhook --no-verify-jwt
import { createClient } from "npm:@supabase/supabase-js@2";
import { statutMeta, statutTwilio, verifierMeta, verifierTwilio } from "../_shared/messagerie.ts";

const ok = () => new Response("ok");
const refus = (m: string, s = 403) => new Response(m, { status: s });

Deno.serve(async (req) => {
  const u = new URL(req.url);
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

  // --- Meta : vérification de l'abonnement (GET) ---
  if (req.method === "GET") {
    const token = Deno.env.get("META_VERIFY_TOKEN");
    if (u.searchParams.get("hub.mode") === "subscribe" && token && u.searchParams.get("hub.verify_token") === token)
      return new Response(u.searchParams.get("hub.challenge") ?? "");
    return refus("Refusé");
  }
  if (req.method !== "POST") return refus("Méthode non autorisée", 405);

  // --- Twilio (formulaire) ---
  if (u.searchParams.get("p") === "twilio") {
    const token = Deno.env.get("TWILIO_AUTH_TOKEN");
    if (!token) return refus("Non configuré", 500);
    const params: Record<string, string> = {};
    (await req.formData()).forEach((v, k) => (params[k] = String(v)));
    // Twilio signe l'URL publique exacte. WEBHOOK_URL = adresse publique de cette fonction, SANS paramètre (« ?p=twilio » est ajouté ici et à l'envoi).
    const pub = (Deno.env.get("WEBHOOK_URL") ?? u.origin + u.pathname) + "?p=twilio";
    if (!(await verifierTwilio(pub, params, req.headers.get("X-Twilio-Signature") ?? "", token))) return refus("Signature invalide");
    const st = statutTwilio(params.MessageStatus);
    if (st && params.MessageSid) await admin.rpc("maj_statut_provider", { p_provider_id: params.MessageSid, p_statut: st, p_erreur: params.ErrorMessage ?? params.ErrorCode ?? null });
    return ok();
  }

  // --- Meta WhatsApp Cloud (JSON signé) ---
  const secret = Deno.env.get("META_APP_SECRET");
  if (!secret) return refus("Non configuré", 500);
  const brut = await req.text();
  if (!(await verifierMeta(brut, req.headers.get("X-Hub-Signature-256") ?? "", secret))) return refus("Signature invalide");
  let j: any; try { j = JSON.parse(brut); } catch { return refus("JSON invalide", 400); }
  for (const e of j.entry ?? []) for (const c of e.changes ?? []) for (const s of c.value?.statuses ?? []) {
    const st = statutMeta(s.status);
    if (st && s.id) await admin.rpc("maj_statut_provider", { p_provider_id: s.id, p_statut: st, p_erreur: s.errors?.[0]?.title ?? null });
  }
  return ok();
});
