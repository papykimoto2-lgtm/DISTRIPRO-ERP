const { chromium } = require('/opt/node-tools/node_modules/playwright');const fs=require('fs');const {execSync}=require('child_process');
const ANON=fs.readFileSync('/tmp/pgr/anon.key','utf8').trim();
const sql=q=>execSync(`psql -h 127.0.0.1 -p 54330 -U postgres -d t -At -c "${q}"`).toString().trim();
let ok=0,ko=0;const chk=(n,c,x)=>{c?ok++:ko++;console.log((c?'✔':'✘')+' '+n+(c?'':'  → '+(typeof x==='string'?x:JSON.stringify(x))))};
(async()=>{const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
async function sess(u){const ctx=await b.newContext({viewport:{width:1280,height:950}});await ctx.addInitScript(k=>{window.ANGELS_CLOUD={url:'http://127.0.0.1:3011',key:k}},ANON);
 await ctx.route('https://cdn.jsdelivr.net/npm/@supabase/**',r=>r.fulfill({path:'/tmp/pgr/sbjs/package/dist/umd/supabase.js',contentType:'application/javascript'}));
 const pg=await ctx.newPage();pg.errs=[];pg.on('pageerror',e=>pg.errs.push(e.message));pg.on('dialog',d=>d.accept());
 await pg.goto('file:///home/user/DISTRIPRO-ERP/index.html');await pg.waitForSelector('#lf');await pg.fill('input[name=ident]',u);await pg.fill('input[name=pwd]','pwd'+u);await pg.click('#lf button');
 await pg.waitForFunction(()=>typeof ME!=='undefined'&&ME&&S.users.length>0,null,{timeout:8000});
 await pg.evaluate(()=>{window.__t=[];const o=window.toast;window.toast=(m,k)=>{if(k==='err')__t.push(m);return o(m,k)}});return pg}

const png=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==','base64');
const F=n=>({name:n+'.png',mimeType:'image/png',buffer:png});
const ad=await sess('admin');await ad.setViewportSize({width:1300,height:1100});await ad.evaluate(()=>{view='livreurs';render()});
const tel='07'+String(Date.now()).slice(-8),nom='Livreur Photos '+tel.slice(-4);
await ad.click('button[data-act=newLiv]');await ad.waitForSelector('[data-slot=permis]');
await ad.fill('input[name=nom]',nom);await ad.fill('input[name=tel]',tel);await ad.fill('input[name=pin]','567890');await ad.fill('input[name=ident]','lp'+tel.slice(-5));
for(const k of ['photo','piece_recto','piece_verso','permis']){await ad.setInputFiles(`[data-img=${k}]`,F(k));await ad.waitForTimeout(350)}
await ad.click('#mf .mf .btn:not(.ghost)');await ad.waitForTimeout(2500);
const id=sql(`select id from public.livreurs where tel='${tel}'`);
chk('livreur créé côté serveur',!!id,await ad.evaluate(()=>__t));
chk('4 photos enregistrées (portrait, CNI recto/verso, permis)',sql(`select string_agg(kind,',' order by kind) from public.livreur_fichiers where livreur_id='${id}'`)==='permis,photo,piece_recto,piece_verso');
chk('le portrait a une miniature',sql(`select (miniature is not null)::text from public.livreur_fichiers where livreur_id='${id}' and kind='photo'`)==='true');
// édition : retirer le permis
await ad.evaluate(()=>refresh());await ad.waitForTimeout(700);await ad.evaluate(()=>{view='livreurs';render()});
await ad.evaluate(i=>{const l=liv(i);ACT.editLiv(i)},id);await ad.waitForSelector('[data-slot=permis]');await ad.waitForTimeout(1200);
chk('édition : photos relues du serveur',await ad.locator('#mf [data-slot] img:not(.hide)').count()===4,await ad.locator('#mf [data-slot] img:not(.hide)').count());
await ad.click('#mf [data-slot=permis] button[data-act=dosDel]');await ad.click('#mf .mf .btn:not(.ghost)');await ad.waitForTimeout(2000);
chk('permis retiré côté serveur, le reste conservé',sql(`select string_agg(kind,',' order by kind) from public.livreur_fichiers where livreur_id='${id}'`)==='photo,piece_recto,piece_verso');
// remplacement
await ad.evaluate(()=>refresh());await ad.waitForTimeout(600);await ad.evaluate(()=>{view='livreurs';render()});await ad.evaluate(i=>ACT.editLiv(i),id);await ad.waitForSelector('[data-slot=permis]');await ad.waitForTimeout(900);
await ad.setInputFiles('[data-img=permis]',F('nouveau'));await ad.waitForTimeout(400);await ad.click('#mf .mf .btn:not(.ghost)');await ad.waitForTimeout(2000);
chk('permis ajouté après coup',sql(`select count(*) from public.livreur_fichiers where livreur_id='${id}' and kind='permis'`)==='1');
// droits
const aya=await sess('aya');chk('un vendeur ne lit aucune photo de livreur',await aya.evaluate(async()=>{const r=await CL.sb.from('livreur_fichiers').select('kind');return !r.error&&(r.data||[]).length===0}));
chk('aucune erreur JS',ad.errs.length===0,ad.errs);
console.log(ok+' ok / '+ko+' échecs');await b.close()})();
