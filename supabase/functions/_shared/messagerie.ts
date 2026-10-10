// Logique d'envoi de messages (WhatsApp / SMS) — pure, sans dépendance, testable sous Node et Deno.
// Aucun secret n'est stocké ici : ils viennent de l'environnement de l'Edge Function.

export type Notif = {
  id: string; event: string; canal: "whatsapp" | "sms"; tel: string; message: string; vars: Record<string, string>;
};
export type Cfg = {
  provider?: "twilio" | "meta";
  canal?: "whatsapp" | "sms";
  indicatif?: string;
  // Modèles WhatsApp approuvés : { confirmee: { name, lang, vars: ["client","numero"], content_sid } }
  templates?: Record<string, { name?: string; lang?: string; vars?: string[]; content_sid?: string }>;
};
export type Env = Record<string, string | undefined>;
export type Resultat = { ok: boolean; providerId?: string; erreur?: string; definitif?: boolean };

/** Numéro au format international sans « + » (ex. 2250707000001). Null si invalide.
 *  Numéro national (≤ 10 chiffres, le 0 initial est conservé en Côte d'Ivoire) : l'indicatif est ajouté.
 *  « +… » ou « 00… » ou 11 chiffres et plus : déjà international. */
export function normaliserTel(brut: string, indicatif = "225"): string | null {
  const s = String(brut ?? "").trim();
  let d = s.replace(/\D/g, "");
  if (d.startsWith("00")) d = d.slice(2);
  else if (!s.startsWith("+") && d.length <= 10) d = indicatif + d;
  return d.length >= 9 && d.length <= 15 ? d : null;
}

/** 4xx (hors 408/429) = définitif ; 5xx, 408, 429, réseau = à retenter. */
export const estDefinitif = (status: number) => status >= 400 && status < 500 && status !== 408 && status !== 429;

export function requeteTwilio(n: Notif, cfg: Cfg, env: Env): { url: string; init: RequestInit } | { erreur: string } {
  const sid = env.TWILIO_ACCOUNT_SID, token = env.TWILIO_AUTH_TOKEN;
  const from = n.canal === "whatsapp" ? env.TWILIO_WHATSAPP_FROM : env.TWILIO_SMS_FROM;
  if (!sid || !token || !from) return { erreur: "Configuration Twilio incomplète (TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, TWILIO_WHATSAPP_FROM / TWILIO_SMS_FROM)" };
  const tel = normaliserTel(n.tel, cfg.indicatif);
  if (!tel) return { erreur: "Numéro de téléphone invalide" };
  const p = new URLSearchParams();
  p.set("To", (n.canal === "whatsapp" ? "whatsapp:+" : "+") + tel);
  p.set("From", from.startsWith("whatsapp:") || n.canal === "sms" ? from : "whatsapp:" + from);
  const t = cfg.templates?.[n.event];
  if (n.canal === "whatsapp" && t?.content_sid) {
    p.set("ContentSid", t.content_sid);
    const v: Record<string, string> = {};
    (t.vars ?? []).forEach((k, i) => (v[String(i + 1)] = String(n.vars[k] ?? "")));
    p.set("ContentVariables", JSON.stringify(v));
  } else p.set("Body", n.message);
  if (env.WEBHOOK_URL) p.set("StatusCallback", env.WEBHOOK_URL + "?p=twilio");
  return {
    url: `https://api.twilio.com/2010-04-01/Accounts/${sid}/Messages.json`,
    init: { method: "POST", headers: { Authorization: "Basic " + btoa(`${sid}:${token}`), "Content-Type": "application/x-www-form-urlencoded" }, body: p.toString() },
  };
}

export function requeteMeta(n: Notif, cfg: Cfg, env: Env): { url: string; init: RequestInit } | { erreur: string } {
  const token = env.META_WA_TOKEN, phone = env.META_WA_PHONE_ID;
  if (!token || !phone) return { erreur: "Configuration WhatsApp Cloud incomplète (META_WA_TOKEN, META_WA_PHONE_ID)" };
  if (n.canal !== "whatsapp") return { erreur: "Le fournisseur Meta n'envoie que du WhatsApp (utilisez Twilio pour les SMS)" };
  const tel = normaliserTel(n.tel, cfg.indicatif);
  if (!tel) return { erreur: "Numéro de téléphone invalide" };
  const t = cfg.templates?.[n.event];
  const body = t?.name
    ? { messaging_product: "whatsapp", to: tel, type: "template", template: { name: t.name, language: { code: t.lang ?? "fr" },
        components: [{ type: "body", parameters: (t.vars ?? []).map((k) => ({ type: "text", text: String(n.vars[k] ?? "") })) }] } }
    : { messaging_product: "whatsapp", to: tel, type: "text", text: { body: n.message } };   // texte libre : accepté seulement dans les 24 h après un message du client
  return {
    url: `https://graph.facebook.com/${env.META_GRAPH_VERSION ?? "v21.0"}/${phone}/messages`,
    init: { method: "POST", headers: { Authorization: "Bearer " + token, "Content-Type": "application/json" }, body: JSON.stringify(body) },
  };
}

export async function envoyerUne(n: Notif, cfg: Cfg, env: Env, f: typeof fetch = fetch): Promise<Resultat> {
  const provider = cfg.provider ?? "twilio";
  const r = provider === "meta" ? requeteMeta(n, cfg, env) : requeteTwilio(n, cfg, env);
  if ("erreur" in r) return { ok: false, erreur: r.erreur, definitif: true };
  try {
    const res = await f(r.url, r.init);
    const txt = await res.text();
    let j: any = {}; try { j = JSON.parse(txt); } catch { /* corps non JSON */ }
    if (res.ok) {
      const id = provider === "meta" ? j?.messages?.[0]?.id : j?.sid;
      return id ? { ok: true, providerId: String(id) } : { ok: false, erreur: "Réponse sans identifiant de message", definitif: false };
    }
    const msg = (provider === "meta" ? j?.error?.message : j?.message) ?? txt.slice(0, 200);
    return { ok: false, erreur: `HTTP ${res.status} — ${msg}`, definitif: estDefinitif(res.status) };
  } catch (e) {
    return { ok: false, erreur: "Réseau : " + (e instanceof Error ? e.message : String(e)), definitif: false };
  }
}

// ---- Webhooks : vérification des signatures et traduction des statuts ----
const enc = new TextEncoder();
async function hmac(algo: "SHA-1" | "SHA-256", key: string, data: string): Promise<Uint8Array> {
  const k = await crypto.subtle.importKey("raw", enc.encode(key), { name: "HMAC", hash: algo }, false, ["sign"]);
  return new Uint8Array(await crypto.subtle.sign("HMAC", k, enc.encode(data)));
}
const b64 = (u: Uint8Array) => btoa(String.fromCharCode(...u));
const hex = (u: Uint8Array) => [...u].map((x) => x.toString(16).padStart(2, "0")).join("");
function egal(a: string, b: string) { if (a.length !== b.length) return false; let r = 0; for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i); return r === 0; }

/** Twilio : base64(HMAC-SHA1(authToken, url + paramètres triés « clé+valeur »)). */
export async function verifierTwilio(url: string, params: Record<string, string>, signature: string, authToken: string) {
  const data = url + Object.keys(params).sort().map((k) => k + params[k]).join("");
  return egal(b64(await hmac("SHA-1", authToken, data)), signature ?? "");
}
/** Meta : « sha256=<hex(HMAC-SHA256(appSecret, corps brut))> ». */
export async function verifierMeta(corpsBrut: string, signature: string, appSecret: string) {
  return egal("sha256=" + hex(await hmac("SHA-256", appSecret, corpsBrut)), signature ?? "");
}
export function statutTwilio(s: string): "livre" | "lu" | "echec" | null {
  return ({ delivered: "livre", read: "lu", failed: "echec", undelivered: "echec" } as Record<string, "livre" | "lu" | "echec">)[s] ?? null;
}
export function statutMeta(s: string): "livre" | "lu" | "echec" | null {
  return ({ delivered: "livre", read: "lu", failed: "echec" } as Record<string, "livre" | "lu" | "echec">)[s] ?? null;
}
