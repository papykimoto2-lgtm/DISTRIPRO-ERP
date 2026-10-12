/* Service worker : l'application s'ouvre même sans réseau (coque en cache) ; les données (Supabase) ne sont jamais mises en cache. */
const V = "angels-v2";
const COQUE = ["./", "index.html", "manifest.webmanifest", "icons/icon-192.png", "icons/icon-512.png", "icons/icon-maskable-512.png", "icons/apple-touch-icon.png"];
self.addEventListener("install", e => { e.waitUntil(caches.open(V).then(c => c.addAll(COQUE)).then(() => self.skipWaiting())); });
self.addEventListener("activate", e => { e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== V).map(k => caches.delete(k)))).then(() => self.clients.claim())); });
self.addEventListener("fetch", e => {
  const r = e.request, u = new URL(r.url);
  if (r.method === "POST" && u.origin === location.origin && u.searchParams.get("partage") === "1") {   // partage depuis WhatsApp (Web Share Target)
    e.respondWith((async () => {
      try {
        const fd = await r.formData(), c = await caches.open("angels-partage"), meta = { text: [fd.get("title"), fd.get("text"), fd.get("url")].filter(Boolean).join("\n"), files: [] };
        let i = 0;
        for (const f of fd.getAll("medias")) {
          if (typeof f === "string") continue;
          const k = "f" + (i++);
          await c.put(new URL("__partage/" + k, self.registration.scope), new Response(f, { headers: { "Content-Type": f.type || "application/octet-stream", "X-Name": encodeURIComponent(f.name || k) } }));
          meta.files.push(k);
        }
        await c.put(new URL("__partage/meta", self.registration.scope), new Response(JSON.stringify(meta), { headers: { "Content-Type": "application/json" } }));
      } catch (x) { /* on ouvre quand même l'application */ }
      return Response.redirect(new URL("./?partage=1", self.registration.scope).href, 303);
    })());
    return;
  }
  if (r.method !== "GET" || u.origin !== location.origin) return;           // API, cartes, bibliothèques externes : réseau seulement
  if (r.mode === "navigate" || u.pathname.endsWith("/index.html")) {          // page : réseau d'abord (mises à jour immédiates), cache en secours
    e.respondWith(fetch(r).then(res => { const cp = res.clone(); caches.open(V).then(c => c.put("index.html", cp)); return res; }).catch(() => caches.match("index.html")));
    return;
  }
  e.respondWith(caches.match(r).then(m => m || fetch(r).then(res => { const cp = res.clone(); caches.open(V).then(c => c.put(r, cp)); return res; })));
});
