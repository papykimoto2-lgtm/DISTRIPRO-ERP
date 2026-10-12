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

const ay=await sess('aya'),ad=await sess('admin'),pr=await sess('moussa'),sv=await sess('awa');
const ISSA=sql("select id from public.livreurs where nom like 'Issa%' limit 1");
const mk=async(nom)=>{await ay.evaluate(()=>{view='mesCmd';render()});await ay.click('button:has-text("Nouvelle commande")');await ay.waitForSelector('#v_pay');
 await ay.fill('input[name=nom]',nom);await ay.fill('input[name=tel]','07'+String(Date.now()).slice(-8));await ay.fill('input[name=quartier]','Angré');await ay.fill('.vd >> nth=0','Robe');await ay.fill('.vp >> nth=0','15000');await ay.click('#mf .mf .btn:not(.ghost)');await ay.waitForTimeout(1800);
 const id=sql(`select c.id from public.commandes c join public.clients k on k.id=c.client_id where k.nom='${nom}'`);
 await ad.evaluate(i=>CL.rpc("commande_action",{p_cid:i,p_action:"confirmer"}),id);await pr.evaluate(async i=>{await CL.rpc("commande_action",{p_cid:i,p_action:"preparer"});await CL.rpc("commande_action",{p_cid:i,p_action:"prete"})},id);return id};
const o1=await mk('Off A '+Date.now().toString().slice(-5)),o2=await mk('Off B '+Date.now().toString().slice(-5));
sql(`update public.livraisons set statut='refusee' where livreur_id='${ISSA}' and statut='affectee'`);
// le livreur est connecté avant l'affectation
const is=await sess('issa');await is.setViewportSize({width:420,height:900});await is.evaluate(()=>{window.__vib=[];navigator.vibrate=p=>{window.__vib.push(p);return true}});
await is.evaluate(()=>{const lv=livreurOf(ME);localStorage.setItem('angels_offres_'+lv.id,JSON.stringify(S.livraisons.filter(l=>l.livreur_id===lv.id&&l.statut==='affectee').map(l=>l.id)))});
const t0=Date.now();
const l1=await sv.evaluate(async([id,l])=>(await CL.rpc("affecter_livraison",{p_cid:id,p_lid:l,p_motif:"",p_force:true})).livraison_id,[o1,ISSA]);
await is.waitForSelector('#offre',{timeout:16000});const dt=(Date.now()-t0)/1000;
chk('la fiche apparaît sans action du livreur (vérification automatique toutes les 6 s, ≤ 15 s sur le banc)',dt<=15,dt);
const t=await is.innerText('#offre');
chk('fiche : gain, zone, montant à encaisser',/Nouvelle course/.test(t)&&/Vous gagnez/.test(t)&&/Cocody|Angré/.test(t)&&/À encaisser/.test(t),t);
chk('sonnerie et vibration déclenchées',await is.evaluate(()=>(window.__ring||0)>=1&&window.__vib.length>=1));
await is.click('#offre_no');await is.waitForSelector('[data-m]');await is.click('#offre [data-m="Trop loin"]');await is.waitForTimeout(1800);
chk('refus enregistré côté serveur avec son motif',sql(`select statut||'/'||motif from public.livraisons where id='${l1}'`)==='refusee/Trop loin',sql(`select statut||'/'||coalesce(motif,'') from public.livraisons where id='${l1}'`));
chk('la commande redevient disponible',['prete'].includes(sql(`select statut from public.commandes where id='${o1}'`)));
// 2e course acceptée
const l2=await sv.evaluate(async([id,l])=>(await CL.rpc("affecter_livraison",{p_cid:id,p_lid:l,p_motif:"",p_force:true})).livraison_id,[o2,ISSA]);
await is.waitForSelector('#offre',{timeout:16000});await is.click('#offre_ok');await is.waitForTimeout(1800);
chk('acceptation enregistrée côté serveur',sql(`select statut from public.livraisons where id='${l2}'`)==='acceptee');
chk('la fiche ne revient pas (offre déjà présentée)',await is.locator('#offre').count()===0);
await is.waitForTimeout(12000);chk('toujours aucune fiche après un cycle de rafraîchissement',await is.locator('#offre').count()===0);
chk('aucune erreur JS',is.errs.length===0,is.errs);
console.log(ok+' ok / '+ko+' échecs');await b.close()})();
