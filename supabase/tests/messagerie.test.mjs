// Tests de la logique d'envoi : node --experimental-strip-types supabase/tests/messagerie.test.mjs
import assert from "node:assert/strict";
import { createHmac } from "node:crypto";
import * as M from "../functions/_shared/messagerie.ts";

let n = 0; const t = async (nom, f) => { try { await f(); n++; console.log("PASS ", nom); } catch (e) { console.log("FAIL ", nom, "\n     ", e.message); process.exitCode = 1; } };
const notif = (o = {}) => ({ id: "n1", event: "en_cours", canal: "whatsapp", tel: "07 07 00 00 01", message: "Bonjour Awa", vars: { client: "Awa", numero: "CMD-1", code: "4821" }, ...o });
const env = { TWILIO_ACCOUNT_SID: "AC123", TWILIO_AUTH_TOKEN: "tok", TWILIO_WHATSAPP_FROM: "+14155238886", TWILIO_SMS_FROM: "+15005550006", WEBHOOK_URL: "https://x.supabase.co/functions/v1/messagerie-webhook", META_WA_TOKEN: "T", META_WA_PHONE_ID: "999" };
const rep = (status, body) => async () => new Response(typeof body === "string" ? body : JSON.stringify(body), { status });

await t("numéros : national, +, 00, avec indicatif, invalides", () => {
  assert.equal(M.normaliserTel("07 07 00 00 01"), "2250707000001");
  assert.equal(M.normaliserTel("+225 07 07 00 00 01"), "2250707000001");
  assert.equal(M.normaliserTel("00225 0707000001"), "2250707000001");
  assert.equal(M.normaliserTel("225 0707000001"), "2250707000001");
  assert.equal(M.normaliserTel("+33 6 12 34 56 78"), "33612345678");
  assert.equal(M.normaliserTel("123"), null);
  assert.equal(M.normaliserTel(""), null);
  assert.equal(M.normaliserTel("abc"), null);
});
await t("classification des erreurs HTTP", () => {
  assert.equal(M.estDefinitif(400), true); assert.equal(M.estDefinitif(401), true); assert.equal(M.estDefinitif(404), true);
  assert.equal(M.estDefinitif(429), false); assert.equal(M.estDefinitif(408), false); assert.equal(M.estDefinitif(500), false); assert.equal(M.estDefinitif(503), false);
});
await t("Twilio WhatsApp : corps libre, numéro préfixé, rappel de statut", () => {
  const r = M.requeteTwilio(notif(), {}, env);
  const p = new URLSearchParams(r.init.body);
  assert.equal(r.url, "https://api.twilio.com/2010-04-01/Accounts/AC123/Messages.json");
  assert.equal(p.get("To"), "whatsapp:+2250707000001"); assert.equal(p.get("From"), "whatsapp:+14155238886");
  assert.equal(p.get("Body"), "Bonjour Awa"); assert.equal(p.get("StatusCallback"), env.WEBHOOK_URL + "?p=twilio");
  assert.equal(r.init.headers.Authorization, "Basic " + Buffer.from("AC123:tok").toString("base64"));
});
await t("Twilio WhatsApp : modèle approuvé (ContentSid + variables ordonnées)", () => {
  const cfg = { templates: { en_cours: { content_sid: "HX1", vars: ["client", "code", "numero"] } } };
  const p = new URLSearchParams(M.requeteTwilio(notif(), cfg, env).init.body);
  assert.equal(p.get("ContentSid"), "HX1"); assert.equal(p.get("Body"), null);
  assert.deepEqual(JSON.parse(p.get("ContentVariables")), { 1: "Awa", 2: "4821", 3: "CMD-1" });
});
await t("Twilio SMS : expéditeur SMS, pas de préfixe whatsapp", () => {
  const p = new URLSearchParams(M.requeteTwilio(notif({ canal: "sms" }), {}, env).init.body);
  assert.equal(p.get("To"), "+2250707000001"); assert.equal(p.get("From"), "+15005550006");
});
await t("Twilio : configuration ou numéro manquant = erreur claire", () => {
  assert.match(M.requeteTwilio(notif(), {}, {}).erreur, /Twilio incomplète/);
  assert.match(M.requeteTwilio(notif({ tel: "12" }), {}, env).erreur, /invalide/);
});
await t("Meta : modèle avec paramètres ordonnés ; texte libre sinon ; pas de SMS", () => {
  const cfg = { provider: "meta", templates: { en_cours: { name: "depart_livreur", lang: "fr", vars: ["client", "numero"] } } };
  const b = JSON.parse(M.requeteMeta(notif(), cfg, env).init.body);
  assert.equal(b.to, "2250707000001"); assert.equal(b.type, "template"); assert.equal(b.template.name, "depart_livreur");
  assert.deepEqual(b.template.components[0].parameters, [{ type: "text", text: "Awa" }, { type: "text", text: "CMD-1" }]);
  const b2 = JSON.parse(M.requeteMeta(notif(), { provider: "meta" }, env).init.body);
  assert.equal(b2.type, "text"); assert.equal(b2.text.body, "Bonjour Awa");
  assert.match(M.requeteMeta(notif({ canal: "sms" }), cfg, env).erreur, /Twilio pour les SMS/);
});
await t("envoyerUne Twilio : succès -> identifiant du message", async () => {
  const r = await M.envoyerUne(notif(), {}, env, rep(201, { sid: "SM777" })); assert.deepEqual(r, { ok: true, providerId: "SM777" });
});
await t("envoyerUne : 400 = définitif ; 500 et 429 = à retenter ; réseau = à retenter", async () => {
  const a = await M.envoyerUne(notif(), {}, env, rep(400, { message: "numéro non WhatsApp" })); assert.equal(a.ok, false); assert.equal(a.definitif, true); assert.match(a.erreur, /400.*non WhatsApp/);
  assert.equal((await M.envoyerUne(notif(), {}, env, rep(500, "oops"))).definitif, false);
  assert.equal((await M.envoyerUne(notif(), {}, env, rep(429, {}))).definitif, false);
  const r = await M.envoyerUne(notif(), {}, env, async () => { throw new Error("ECONNRESET"); }); assert.equal(r.definitif, false); assert.match(r.erreur, /ECONNRESET/);
});
await t("envoyerUne Meta : succès, et erreur 131047 (hors fenêtre 24 h) = définitif", async () => {
  const cfg = { provider: "meta" };
  assert.deepEqual(await M.envoyerUne(notif(), cfg, env, rep(200, { messages: [{ id: "wamid.A" }] })), { ok: true, providerId: "wamid.A" });
  const e = await M.envoyerUne(notif(), cfg, env, rep(400, { error: { message: "Re-engagement message", code: 131047 } })); assert.equal(e.definitif, true); assert.match(e.erreur, /Re-engagement/);
});
await t("réponse 200 sans identifiant : pas considérée comme envoyée", async () => {
  const r = await M.envoyerUne(notif(), {}, env, rep(200, {})); assert.equal(r.ok, false);
});
await t("signature Twilio : valide, falsifiée, paramètre modifié", async () => {
  const url = env.WEBHOOK_URL + "?p=twilio", params = { MessageSid: "SM1", MessageStatus: "delivered", To: "whatsapp:+225" };
  const sig = createHmac("sha1", "tok").update(url + "MessageSidSM1MessageStatusdeliveredTowhatsapp:+225").digest("base64");
  assert.equal(await M.verifierTwilio(url, params, sig, "tok"), true);
  assert.equal(await M.verifierTwilio(url, params, sig, "autre-token"), false);
  assert.equal(await M.verifierTwilio(url, { ...params, MessageStatus: "read" }, sig, "tok"), false);
  assert.equal(await M.verifierTwilio(url, params, "", "tok"), false);
});
await t("signature Meta : valide, falsifiée, corps modifié", async () => {
  const body = JSON.stringify({ entry: [{ changes: [] }] }), sig = "sha256=" + createHmac("sha256", "secret").update(body).digest("hex");
  assert.equal(await M.verifierMeta(body, sig, "secret"), true);
  assert.equal(await M.verifierMeta(body + " ", sig, "secret"), false);
  assert.equal(await M.verifierMeta(body, sig, "x"), false);
  assert.equal(await M.verifierMeta(body, "", "secret"), false);
});
await t("traduction des statuts du prestataire", () => {
  assert.equal(M.statutTwilio("delivered"), "livre"); assert.equal(M.statutTwilio("read"), "lu"); assert.equal(M.statutTwilio("undelivered"), "echec");
  assert.equal(M.statutTwilio("queued"), null); assert.equal(M.statutMeta("sent"), null); assert.equal(M.statutMeta("failed"), "echec");
});
console.log(`\n${n} vérifications réussies`);
