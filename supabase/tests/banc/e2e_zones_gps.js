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

const ay=await sess('aya');
chk('zones du serveur : 22 dont Songon et Dabou',await ay.evaluate(()=>S.config.zones.length>=22&&['Songon','Dabou','Grand-Bassam'].every(n=>S.config.zones.some(z=>z.nom===n))),await ay.evaluate(()=>S.config.zones.length));
chk('zones existantes de la base complétées',sql("select count(*) from public.zones where org_id=(select org_id from public.vendeurs where id='00000000-0000-0000-0000-0000000000b1') and nom in ('Songon','Dabou','Grand-Bassam','Bingerville')")==='4');
await ay.setViewportSize({width:1280,height:950});
await ay.evaluate(()=>{view='mesCmd';render()});await ay.evaluate(()=>vAdrForm());await ay.waitForSelector('#va_gps');
await ay.selectOption('select[name=z]','Songon');await ay.fill('input[name=q]','Songon-Agban');
await ay.fill('input[name=geo]','https://maps.google.com/?q=5.3290,-4.2570');await ay.click('#mf .mf .btn:not(.ghost)');await ay.waitForTimeout(1500);
chk('adresse + position GPS enregistrées côté serveur',sql("select (adresse_collecte->>'zone')||'/'||(adresse_collecte->>'quartier')||'/'||(adresse_collecte->>'lat')||'/'||(adresse_collecte->>'lng') from public.vendeurs where id='00000000-0000-0000-0000-0000000000b1'")==='Songon/Songon-Agban/5.329000/-4.257000',await ay.evaluate(()=>__t));
const ad=await sess('admin');
await ad.evaluate(()=>CL.rpc("maj_adresse_collecte",{p:{zone:"Songon",quartier:"Songon-Kassemblé"},p_vendeur:"00000000-0000-0000-0000-0000000000b1"}));
chk('modification par l\'équipe sans position : la position est conservée',sql("select (adresse_collecte->>'quartier')||'/'||(adresse_collecte->>'lat') from public.vendeurs where id='00000000-0000-0000-0000-0000000000b1'")==='Songon-Kassemblé/5.329000');
await ay.evaluate(()=>refresh());await ay.waitForTimeout(600);
chk('la fiche chargée contient la position',await ay.evaluate(()=>{const v=vend();return v&&v.adresse_collecte&&v.adresse_collecte.lat==5.329}),await ay.evaluate(()=>vend()&&vend().adresse_collecte));
// page publique : zones du serveur
await ay.evaluate(()=>view='mesCmd');await ay.evaluate(()=>render());await ay.click('button:has-text("Lien de commande client")');await ay.waitForSelector('#mf input[readonly]');
const link=await ay.inputValue('#mf input[readonly]');
const ctx=await b.newContext({viewport:{width:420,height:900}});await ctx.addInitScript(k=>{window.ANGELS_CLOUD={url:'http://127.0.0.1:3011',key:k}},ANON);
await ctx.route('https://cdn.jsdelivr.net/npm/@supabase/**',r=>r.fulfill({path:'/tmp/pgr/sbjs/package/dist/umd/supabase.js',contentType:'application/javascript'}));
const P=await ctx.newPage();await P.goto(link);await P.waitForSelector('#o_send');
const z=await P.$$eval('#o_zone option',o=>o.map(x=>x.textContent));chk('page publique cloud : zones élargies',z.includes('Songon')&&z.includes('Dabou')&&z.length>=22,z.length);
await P.selectOption('#o_zone','Songon');await P.focus('#o_q');chk('page publique : quartiers proposés pour Songon',await P.getAttribute('#o_q','list')==='dl_q_songon');
await P.fill('.ol .o_d','Table');await P.fill('#o_nom','Client Songon');await P.fill('#o_tel','0707404040');await P.fill('#o_q','Songon-Agban');await P.click('#o_send');await P.waitForTimeout(1500);
chk('commande publique reçue chez le bon fournisseur (Aya) uniquement',sql("select vendeur_id from public.demandes_commande where nom='Client Songon'")==='00000000-0000-0000-0000-0000000000b1');
chk('aucune erreur JS fournisseur',ay.errs.length===0,ay.errs);
console.log(ok+' ok / '+ko+' échecs');await b.close()})();
