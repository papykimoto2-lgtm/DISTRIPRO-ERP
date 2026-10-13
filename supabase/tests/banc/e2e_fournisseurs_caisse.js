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

const AYA='00000000-0000-0000-0000-0000000000b1';
const yao=await sess('yao');await yao.setViewportSize({width:1300,height:1000});
const due=await yao.evaluate(async id=>{const r=await CL.rpc("vendeur_dues",{p_vid:id});return r&&r[0]?+r[0].restant:0},AYA);
chk('un fournisseur a un reste à régler (données du banc)',due>0,due);
// 1. aucune caisse ouverte : refus serveur
sql("update public.caisse_sessions set statut='cloturee', fond_cloture_theorique=fond_ouverture, fond_cloture_reel=fond_ouverture, ecart=0, ecart_regularise=true, cloturee_le=now() where statut='ouverte'");
sql("insert into public.caisses(org_id,nom,compte) select id,'Caisse Fournisseurs '||floor(random()*1000)::text,'571' from public.organisations limit 1 on conflict do nothing");
await yao.evaluate(()=>refresh());
const r1=await yao.evaluate(async id=>{try{await CL.rpc("regler_vendeur",{p_vid:id,p_montant:1000,p_mode:"Espèces",p_note:""});return "ok"}catch(e){return e.message}},AYA);
chk('serveur : espèces refusées tant qu\'aucune caisse n\'est ouverte',/Aucune caisse ouverte/.test(r1),r1);
// 2. caisse ouverte avec un fond
const cid=sql("select id from public.caisses where actif order by compte, cree_le limit 1");
sql(`insert into public.caisse_sessions(org_id,caisse_id,fond_ouverture,ouverte_par_nom) select org_id,id,100000,'Test' from public.caisses where id='${cid}'`);
await yao.evaluate(()=>refresh());await yao.waitForTimeout(500);await yao.evaluate(()=>{view='caisse';render()});
chk('la liste « Fournisseurs à régler » s\'affiche (cloud)',await yao.locator('h2:has-text("Fournisseurs à régler")').count()===1&&/Aya/.test(await yao.innerText('main')));
const solde0=+sql(`select app.caisse_solde_session(id) from public.caisse_sessions where caisse_id='${cid}' and statut='ouverte'`)||100000;
await yao.locator('tr:has-text("Aya") [data-act=vReg]').click();await yao.waitForSelector('input[name=m]');await yao.fill('input[name=m]','5000');await yao.click('#mf .mf .btn:not(.ghost)');await yao.waitForTimeout(2500);
chk('règlement espèces enregistré côté serveur',sql(`select count(*) from public.reglements_vendeurs where vendeur_id='${AYA}' and montant=5000 and mode ~* '^esp'`)>='1');
const mv=sql(`select type||'/'||statut||'/'||categorie||'/'||montant from public.caisse_mouvements where source='reglement_vendeur' and caisse_id='${cid}' order by cree_le desc limit 1`);
chk('sortie automatique dans la caisse (validée, « Règlement vendeur », 5 000 F)',mv==='sortie/valide/Règlement vendeur/5000',mv);
chk('le solde de la caisse baisse de 5 000 F',+sql(`select app.caisse_solde_session(id) from public.caisse_sessions where caisse_id='${cid}' and statut='ouverte'`)===100000-5000);
// 3. au-delà du solde : refusé ; Mobile Money : accepté sans caisse
sql(`insert into public.caisse_mouvements(org_id,caisse_id,session_id,numero,type,montant,motif,statut,source,cree_par_nom) select org_id,caisse_id,id,'T-'||floor(random()*100000)::text,'sortie',94000,'Retrait test','valide','manuel','Test' from public.caisse_sessions where caisse_id='${cid}' and statut='ouverte'`);
const r3=await yao.evaluate(async id=>{try{await CL.rpc("regler_vendeur",{p_vid:id,p_montant:3000,p_mode:"Espèces",p_note:""});return "ok"}catch(e){return e.message}},AYA);
chk('serveur : espèces refusées au-delà du solde de la caisse',/Solde de caisse insuffisant/.test(r3),r3);
const n0=sql("select count(*) from public.caisse_mouvements where source='reglement_vendeur'");
const r4=await yao.evaluate(async id=>{try{await CL.rpc("regler_vendeur",{p_vid:id,p_montant:3000,p_mode:"Wave",p_note:"WV-TEST"});return "ok"}catch(e){return e.message}},AYA);
chk('Mobile Money accepté et sans écriture de caisse',r4==='ok'&&sql("select count(*) from public.caisse_mouvements where source='reglement_vendeur'")===n0,r4);
const aya=await sess('aya');chk('le fournisseur ne peut pas régler (et ne voit pas la caisse)',await aya.evaluate(async id=>{try{await CL.rpc("regler_vendeur",{p_vid:id,p_montant:100,p_mode:"Espèces",p_note:""});return false}catch(e){return true}},AYA));
chk('aucune erreur JS',yao.errs.length===0,yao.errs);
console.log(ok+' ok / '+ko+' échecs');await b.close()})();
