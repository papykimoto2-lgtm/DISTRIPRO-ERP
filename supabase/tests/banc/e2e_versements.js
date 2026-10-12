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
const ad=await sess('admin');
const oid=await ad.evaluate(async()=>{const cl=S.clients.find(c=>c.adresses.length&&!c.vendeur_id),p=S.produits.find(x=>x.stock>5);return (await CL.rpc("creer_commande",{p:{client_id:cl.id,adresse_id:cl.adresses[0].id,frais:1500,remise:0,paiement:"livraison",mode:"Espèces",confirmer:true,lignes:[{produit_id:p.id,qte:1}]}})).id});
const pr=await sess('moussa');await pr.evaluate(async id=>{await CL.rpc("commande_action",{p_cid:id,p_action:"preparer"});await CL.rpc("commande_action",{p_cid:id,p_action:"prete"})},oid);
const sv=await sess('awa');const lid=await sv.evaluate(async id=>(await CL.rpc("affecter_livraison",{p_cid:id,p_lid:S.livreurs.find(l=>l.nom.startsWith("Issa")).id,p_motif:"",p_force:true})).livraison_id,oid);
const code=sql(`select code from public.livraison_codes where livraison_id='${lid}'`),att=+sql(`select montant_attendu from public.livraisons where id='${lid}'`);
const is=await sess('issa');await is.evaluate(async lid=>{await CL.rpc("livreur_consentement");for(const a of ["accepter"])await CL.rpc("livraison_action",{p_lid:lid,p_action:a,p:{}});await CL.rpc("livraison_action",{p_lid:lid,p_action:"prise_en_charge",p:{nb_colis:1}});await CL.rpc("livraison_action",{p_lid:lid,p_action:"demarrer",p:{}})},lid);
await is.evaluate(async()=>{await refresh();render()});
await is.evaluate(id=>ACT.lConf(id),lid);await is.waitForSelector('input[name=code]');await is.fill('input[name=code]',code);await is.selectOption('select[name=mode]','Wave');
await is.click('#mf .mf .btn:not(.ghost)');await is.waitForTimeout(1300);
chk('Wave sans référence refusé par l\'application',/Référence de la transaction/.test((await is.evaluate(()=>__t)).join(' ')||await is.innerText('body'))&&sql(`select statut from public.livraisons where id='${lid}'`)==='en_cours');
const ref='WV'+Date.now().toString().slice(-6);await is.fill('input[name=ref]',ref);await is.click('#mf .mf .btn:not(.ghost)');await is.waitForTimeout(1800);
chk('livraison confirmée en Wave, référence enregistrée',sql(`select statut from public.livraisons where id='${lid}'`)==='livree'&&sql(`select ref||'/'||mode||'/'||direct::text from public.fonds where livraison_id='${lid}'`)===ref+'/Wave/false',await is.evaluate(()=>__t));
// panneau + déclaration
await is.evaluate(async()=>{await refresh();render()});chk('le livreur voit son argent à reverser et les comptes',/Mon argent à reverser/.test(await is.innerText('body')));
await is.click('button:has-text("J\'ai envoyé par Mobile Money")');await is.waitForSelector('input[name=ref]');const ref2='MP'+Date.now().toString().slice(-6);await is.fill('input[name=m]','4000');await is.fill('input[name=ref]',ref2);await is.click('#mf .mf .btn:not(.ghost)');await is.waitForTimeout(1800);
chk('versement déclaré côté serveur',sql(`select statut||'/'||montant from public.versements_declares where ref='${ref2}'`)==='declare/4000',await is.evaluate(()=>__t));
// caissier
const ya=await sess('yao');await ya.evaluate(()=>{view='finance';render()});await ya.waitForTimeout(600);
chk('le caissier voit le versement à valider',new RegExp(ref2).test(await ya.innerText('body')));
await ya.click(`tr:has-text("${ref2}") button:has-text("Reçu — valider")`);await ya.waitForTimeout(1800);
chk('validation : reversement créé avec la référence',sql(`select count(*) from public.fonds where type='reversement' and ref='${ref2}' and montant=4000`)==='1'&&sql(`select statut from public.versements_declares where ref='${ref2}'`)==='valide',await ya.evaluate(()=>__t));
// direct
const lid2=null;
const koi=await sess('koffi');chk('le commercial ne voit pas les versements',await koi.evaluate(()=>(S.versements||[]).length===0));
console.log('erreurs JS',ad.errs,is.errs,ya.errs);console.log(ok+' ok / '+ko+' échecs');await b.close()})().catch(e=>{console.error('CRASH',e.message.slice(0,400));process.exit(1)});
