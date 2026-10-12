const { chromium } = require('/opt/node-tools/node_modules/playwright');const fs=require('fs');const {execSync}=require('child_process');
const ANON=fs.readFileSync('/tmp/pgr/anon.key','utf8').trim();
const sql=q=>execSync(`psql -h 127.0.0.1 -p 54330 -U postgres -d t -At -c "${q}"`).toString().trim();
let ok=0,ko=0;const chk=(n,c,x)=>{c?ok++:ko++;console.log((c?'✔':'✘')+' '+n+(c?'':'  → '+(x||'')))};
(async()=>{const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
async function sess(u){const ctx=await b.newContext({viewport:{width:1280,height:900},acceptDownloads:true});await ctx.addInitScript(k=>{window.ANGELS_CLOUD={url:'http://127.0.0.1:3011',key:k}},ANON);
 await ctx.route('https://cdn.jsdelivr.net/npm/@supabase/**',r=>r.fulfill({path:'/tmp/pgr/sbjs/package/dist/umd/supabase.js',contentType:'application/javascript'}));
 const pg=await ctx.newPage();pg.errs=[];pg.on('pageerror',e=>pg.errs.push(e.message));pg.on('dialog',d=>d.accept());
 await pg.goto('file:///home/user/DISTRIPRO-ERP/index.html');await pg.waitForSelector('#lf');await pg.fill('input[name=ident]',u);await pg.fill('input[name=pwd]','pwd'+u);await pg.click('#lf button');
 await pg.waitForFunction(()=>typeof ME!=='undefined'&&ME&&S.users.length>0,null,{timeout:8000});
 await pg.evaluate(()=>{window.__t=[];const o=window.toast;window.toast=(m,k)=>{if(k==='err')__t.push(m);return o(m,k)}});return pg}
const ad=await sess('admin');
await ad.evaluate(()=>{view='journal';render()});await ad.waitForTimeout(1500);
let t=await ad.innerText('body');chk('journal chargé depuis le serveur',/Journal des mouvements de stock/.test(t)&&/Mouvements/.test(t)&&!/Chargement du journal/.test(t),t.slice(0,150));
const n0=+sql("select count(*) from public.stock_mouvements");
// entrée de stock
await ad.click('button:has-text("Entrée de stock")');await ad.selectOption('select[name=p]',{index:0});await ad.fill('input[name=q]','40');await ad.fill('input[name=r]','BL-CLOUD-1');await ad.fill('input[name=c]','9000');await ad.click('#mf .mf .btn:not(.ghost)');await ad.waitForTimeout(1500);
chk('entrée de stock côté serveur',+sql("select count(*) from public.stock_mouvements")===n0+1&&sql("select count(*) from public.stock_mouvements where type='entree' and ref='BL-CLOUD-1'")==='1',await ad.evaluate(()=>__t));
chk('journal rafraîchi avec la nouvelle entrée',/BL-CLOUD-1/.test(await ad.innerText('body')));
// inventaire
await ad.evaluate(()=>{view='inventaire';render()});await ad.waitForTimeout(500);
await ad.click('button:has-text("Ouvrir un inventaire")');await ad.fill('input[name=n]','Test cloud');await ad.click('#mf .mf .btn:not(.ghost)');await ad.waitForTimeout(1500);
chk('inventaire ouvert en base',sql("select statut from public.inventaires order by numero desc limit 1")==='ouvert'&&/En cours/.test(await ad.innerText('body')),await ad.evaluate(()=>__t));
const L=await ad.evaluate(()=>invOuvert().lignes.map(l=>({id:l.produit_id,th:l.theorique})));
const order=await ad.$$eval('input[data-inv]',els=>els.map(e=>e.dataset.inv));
for(let i=0;i<order.length;i++){const th=L.find(x=>x.id===order[i]).th;await ad.fill(`input[data-inv]>>nth=${i}`,String(i===0?Math.max(0,th-2):th));await ad.press(`input[data-inv]>>nth=${i}`,'Tab');await ad.waitForTimeout(250)}
await ad.waitForTimeout(800);
chk('comptages enregistrés côté serveur',+sql("select count(*) from public.inventaire_lignes where compte is not null and inventaire_id=(select id from public.inventaires order by numero desc limit 1)")===order.length);
const first=order[0];const s0=+sql(`select stock from public.produits where id='${first}'`);
await ad.click('button:has-text("Valider")');await ad.waitForSelector('button:has-text("Valider définitivement")');await ad.click('button:has-text("Valider définitivement")');await ad.waitForTimeout(2000);
const s1=+sql(`select stock from public.produits where id='${first}'`);
chk('inventaire validé : stock corrigé de -2',s1===Math.max(0,L.find(x=>x.id===first).th-2)||s1===s0-2,s0+' → '+s1+' '+JSON.stringify(await ad.evaluate(()=>__t)));
chk('mouvement « inventaire » au journal',+sql("select count(*) from public.stock_mouvements where type='inventaire'")>=1);
// états
await ad.evaluate(()=>{view='etats';render()});await ad.waitForTimeout(1800);t=await ad.innerText('body');
chk('états périodiques depuis le serveur',/1\. État des stocks/.test(t)&&/Total/.test(t),t.slice(0,120));
const coh=await ad.evaluate(()=>{const r=DC[Object.keys(DC).find(k=>k.startsWith("e|"))];return r&&r.rows&&r.rows.every(x=>x.ouverture+x.entrees+x.sorties+x.retours+x.ajustements+x.inventaires===x.cloture)});chk('ouverture + mouvements = clôture (serveur)',coh);
// droits
const pr=await sess('moussa');await pr.evaluate(()=>{view='inventaire';render()});await pr.waitForTimeout(800);
chk('préparateur : pas de bouton Valider',!(await pr.isVisible('button:has-text("Valider")')));
const ya=await sess('yao');await ya.evaluate(()=>{view='etats';render()});await ya.waitForTimeout(1500);chk('caissier : état des stocks lisible',/1\. État des stocks/.test(await ya.innerText('body')));
console.log('erreurs JS',ad.errs,pr.errs,ya.errs);console.log(ok+' ok / '+ko+' échecs');await b.close()})().catch(e=>{console.error('CRASH',e.message.slice(0,300));process.exit(1)});
