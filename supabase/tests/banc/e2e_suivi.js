const { chromium } = require('/opt/node-tools/node_modules/playwright');
const fs=require('fs');const {execSync}=require('child_process');
const ANON=fs.readFileSync('/tmp/pgr/anon.key','utf8').trim();
const sql=q=>execSync(`psql -h 127.0.0.1 -p 54330 -U postgres -d t -At -c "${q}"`).toString().trim();
let ok=0,ko=0;const chk=(n,c,x)=>{c?ok++:ko++;console.log((c?'✔':'✘')+' '+n+(c?'':'  → '+(x||'')))};
(async()=>{const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
async function ctxN(){const ctx=await b.newContext({viewport:{width:1100,height:850}});await ctx.addInitScript(k=>{window.ANGELS_CLOUD={url:'http://127.0.0.1:3011',key:k}},ANON);
 await ctx.route('https://cdn.jsdelivr.net/npm/@supabase/**',r=>r.fulfill({path:'/tmp/pgr/sbjs/package/dist/umd/supabase.js',contentType:'application/javascript'}));return ctx}
async function sess(u){const ctx=await ctxN();const pg=await ctx.newPage();pg.errs=[];pg.on('pageerror',e=>pg.errs.push(e.message));
 await pg.goto('file:///home/user/DISTRIPRO-ERP/index.html');await pg.waitForSelector('#lf');await pg.fill('input[name=ident]',u);await pg.fill('input[name=pwd]','pwd'+u);await pg.click('#lf button');
 await pg.waitForFunction(()=>typeof ME!=='undefined'&&ME&&S.users.length>0,null,{timeout:8000});pg.ctx=ctx;return pg}
const ad=await sess('admin');
const cid=sql("select id from public.commandes where statut='livree' and vendeur_id is null order by numero limit 1");
const tok=await ad.evaluate(async id=>{await ACT.suiviLien(id);return document.querySelector('#modal input[readonly]').value},cid);
chk('lien cloud avec jeton 64 hex',/#suivi=[a-f0-9]{64}$/.test(tok),tok.slice(-70));
const ctx=await ctxN();const cp=await ctx.newPage();const er=[];cp.on('pageerror',e=>er.push(e.message));
await cp.goto('file:///home/user/DISTRIPRO-ERP/index.html#suivi='+tok.split('#suivi=')[1]);await cp.waitForTimeout(2500);
let t=await cp.innerText('body');chk('client (sans compte) : « Livrée »',/Livrée/.test(t)&&/Suivi de commande/.test(t),t.slice(0,120));
chk('invitation à noter',await cp.isVisible('#sv_st'));
await cp.click('#sv_st button >> nth=4');await cp.fill('#sv_cm','Parfait');await cp.click('#sv_ok');await cp.waitForTimeout(2500);
t=await cp.innerText('body');chk('merci pour votre avis',/Merci pour votre avis/.test(t)&&/★★★★★/.test(t),t.slice(0,160));
chk('avis en base',sql("select note||':'||commentaire from public.avis_livraison")==='5:Parfait');
await ad.evaluate(()=>refresh());chk('admin voit la satisfaction',await ad.evaluate(()=>S.avis.length===1&&S.avis[0].note===5));
await ad.evaluate(()=>{view='livreurs';render()});chk('colonne avis clients',/★ 5\.0/.test(await ad.innerText('body')));
const ko_=await sess('koffi');chk('commercial ne lit pas les avis',await ko_.evaluate(()=>S.avis.length===0));
// lien invalide
await cp.goto('about:blank');await cp.goto('file:///home/user/DISTRIPRO-ERP/index.html#suivi='+'0'.repeat(64));await cp.waitForTimeout(2000);chk('lien invalide',/expiré ou invalide/i.test(await cp.innerText('body')));
// page ne contient pas le code
console.log('erreurs JS',er,ad.errs);console.log(ok+' ok / '+ko+' échecs');await b.close()})().catch(e=>{console.error('CRASH',e.message.slice(0,300));process.exit(1)});
