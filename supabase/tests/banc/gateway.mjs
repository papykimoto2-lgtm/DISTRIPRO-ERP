// Banc d'essai : imite la façade d'un projet Supabase devant un PostgREST réel et un PostgreSQL local.
//   /rest/v1/*      -> PostgREST (vrai)
//   /auth/v1/*      -> authentification simulée (mot de passe lu dans auth.users.mdp, JWT HS256 signé comme GoTrue)
//   /functions/v1/* -> fonctions serveur simulées (la vraie tourne sous Deno)
// Variables : PORT (3011), PGREST (http://127.0.0.1:3010), JWT_SECRET, PGURL.
import http from "node:http";
import { createHmac } from "node:crypto";
import pg from "pg";

const PORT = +(process.env.PORT ?? 3011), PGREST = process.env.PGREST ?? "http://127.0.0.1:3010";
const SECRET = process.env.JWT_SECRET ?? "super-secret-jwt-token-with-at-least-32-characters-long";
const db = new pg.Pool({ connectionString: process.env.PGURL ?? "postgres://postgres@127.0.0.1:54330/t" });
const b64u = (x) => Buffer.from(x).toString("base64url");
export const jwt = (claims) => { const h = b64u(JSON.stringify({ alg: "HS256", typ: "JWT" })), p = b64u(JSON.stringify(claims)); return `${h}.${p}.${createHmac("sha256", SECRET).update(`${h}.${p}`).digest("base64url")}`; };
const verif = (t) => { try { const [h, p, s] = t.split("."); if (createHmac("sha256", SECRET).update(`${h}.${p}`).digest("base64url") !== s) return null; const c = JSON.parse(Buffer.from(p, "base64url")); return c.exp && c.exp < Date.now() / 1000 ? null : c; } catch { return null; } };
const session = (u) => { const now = Math.floor(Date.now() / 1000), exp = now + 3600;
  return { access_token: jwt({ aud: "authenticated", role: "authenticated", sub: u.id, email: u.email, exp, iat: now }), token_type: "bearer", expires_in: 3600, expires_at: exp,
    refresh_token: jwt({ sub: u.id, kind: "refresh", exp: now + 86400 }), user: { id: u.id, aud: "authenticated", role: "authenticated", email: u.email, app_metadata: {}, user_metadata: {}, created_at: new Date().toISOString() } }; };
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, apikey, content-type, prefer, x-client-info, accept-profile, content-profile, range, range-unit, x-supabase-api-version", "Access-Control-Allow-Methods": "GET,POST,PATCH,PUT,DELETE,OPTIONS", "Access-Control-Expose-Headers": "content-range, content-type" };
const send = (res, code, obj) => { res.writeHead(code, { ...cors, "Content-Type": "application/json" }); res.end(obj === undefined ? "" : JSON.stringify(obj)); };
const body = (req) => new Promise((ok) => { const c = []; req.on("data", (d) => c.push(d)); req.on("end", () => ok(Buffer.concat(c))); });
export const journal = [];   // requêtes vues, pour les tests

http.createServer(async (req, res) => {
  const url = new URL(req.url, "http://x"), raw = await body(req);
  if (req.method === "OPTIONS") { res.writeHead(204, cors); return res.end(); }
  journal.push(`${req.method} ${url.pathname}`);
  try {
    if (url.pathname === "/auth/v1/token") {
      const j = JSON.parse(raw.toString() || "{}");
      if (url.searchParams.get("grant_type") === "refresh_token") { const c = verif(j.refresh_token ?? ""); if (!c) return send(res, 400, { error: "invalid_grant", error_description: "Invalid Refresh Token" });
        const r = await db.query("select id, email from auth.users where id = $1", [c.sub]); return send(res, 200, session(r.rows[0])); }
      const r = await db.query("select id, email from auth.users where lower(email) = lower($1) and mdp = $2", [j.email, j.password]);
      return r.rows[0] ? send(res, 200, session(r.rows[0])) : send(res, 400, { error: "invalid_grant", error_description: "Invalid login credentials", code: 400, msg: "Invalid login credentials" });
    }
    if (url.pathname === "/auth/v1/user") { const c = verif((req.headers.authorization ?? "").slice(7)); return c ? send(res, 200, { id: c.sub, email: c.email, aud: "authenticated", role: "authenticated" }) : send(res, 401, { msg: "invalid JWT" }); }
    if (url.pathname === "/auth/v1/logout") return send(res, 204);
    if (url.pathname.startsWith("/functions/v1/")) {
      const c = verif((req.headers.authorization ?? "").slice(7)); if (!c) return send(res, 401, { erreur: "Non connecté" });
      const m = (await db.query("select * from public.membres where user_id = $1 and actif", [c.sub])).rows[0];
      if (!m || m.role !== "admin") return send(res, 403, { erreur: "Réservé aux administrateurs" });
      const b = JSON.parse(raw.toString() || "{}"), nom = url.pathname.split("/").pop();
      if (nom !== "creer-utilisateur") return send(res, 404, { erreur: "Fonction inconnue" });
      if (b.action === "reset") { await db.query("update auth.users set mdp = $2 where id = $1", [b.user_id, b.mot_de_passe]); return send(res, 200, { ok: true }); }
      if (!b.nom || !b.role || !b.identifiant || String(b.mot_de_passe ?? "").length < 6) return send(res, 400, { erreur: "nom, role, identifiant et mot de passe (6 min.) requis" });
      const email = b.identifiant.includes("@") ? b.identifiant.toLowerCase() : `${b.identifiant.toLowerCase().replace(/[^a-z0-9._-]/g, "")}@users.angels-erp.app`;
      const u = (await db.query("insert into auth.users(email, mdp) values ($1, $2) returning id", [email, b.mot_de_passe])).rows[0];
      let lid = null, vid = null;
      if (b.role === "livreur") lid = (await db.query("insert into public.livreurs(org_id, nom, tel, zone, moto_id, remu, type, commission_pct) values ($1,$2,$3,$4,$5,$6,$7,$8) returning id", [m.org_id, b.nom, b.tel ?? null, b.zone ?? null, b.moto_id ?? null, b.remu ? JSON.stringify(b.remu) : null, b.type === "externe" ? "externe" : "interne", Math.min(100, Math.max(0, Number(b.commission_pct) || 0))])).rows[0].id;
      if (b.role === "vendeur") vid = (await db.query("insert into public.vendeurs(org_id, nom, tel, commission_pct) values ($1,$2,$3,$4) returning id", [m.org_id, b.nom, b.tel ?? null, b.commission_pct ?? 0])).rows[0].id;
      await db.query("insert into public.membres(user_id, org_id, role, nom, livreur_id, vendeur_id) values ($1,$2,$3,$4,$5,$6)", [u.id, m.org_id, b.role, b.nom, lid, vid]);
      return send(res, 200, { ok: true, user_id: u.id, email });
    }
    if (url.pathname.startsWith("/rest/v1/")) {
      const h = { ...req.headers }; delete h.host; delete h.connection; delete h["content-length"]; delete h.apikey;
      const r = await fetch(PGREST + url.pathname.slice(8) + url.search, { method: req.method, headers: h, body: ["GET", "HEAD"].includes(req.method) ? undefined : raw });
      const out = Buffer.from(await r.arrayBuffer()), rh = {}; r.headers.forEach((v, k) => { if (!["content-encoding", "transfer-encoding", "connection"].includes(k) && !k.startsWith("access-control-")) rh[k] = v; });
      res.writeHead(r.status, { ...rh, ...cors }); return res.end(out);
    }
    send(res, 404, { erreur: "Introuvable" });
  } catch (e) { send(res, 500, { erreur: String(e.message ?? e) }); }
}).listen(PORT, "127.0.0.1", () => console.log("banc d'essai prêt sur", PORT));
