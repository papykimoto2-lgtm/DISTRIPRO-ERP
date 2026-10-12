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
const dues0=await ay.evaluate(()=>CL.vd&&Object.values(CL.vd)[0]?Object.values(CL.vd)[0].acquis:0);
await ay.click('button:has-text("Nouvelle commande")');await ay.waitForSelector('#v_pay');
await ay.fill('input[name=nom]','Cli Cloud');await ay.fill('input[name=tel]','0707555111');await ay.fill('input[name=quartier]','Angré');await ay.fill('.vd >> nth=0','Robe');await ay.fill('.vq >> nth=0','2');await ay.fill('.vp >> nth=0','15000');
await ay.selectOption('#v_pay','partiel');await ay.fill('#v_pv','12000');await ay.click('#mf .mf .btn:not(.ghost)');await ay.waitForTimeout(1800);
const oid=sql("select id from public.commandes where vendeur_id='00000000-0000-0000-0000-0000000000b1' order by numero desc limit 1");
chk('paiement partagé enregistré côté serveur',sql(`select paye_vendeur||'/'||paiement from public.commandes where id='${oid}'`)==='12000/partiel'&&sql(`select count(*) from public.fonds where commande_id='${oid}' and mode='Payé au vendeur' and montant=12000`)==='1',await ay.evaluate(()=>__t));
// refus d'un montant supérieur
await ay.click('button:has-text("Nouvelle commande")');await ay.waitForSelector('#v_pay');await ay.fill('input[name=nom]','X');await ay.fill('input[name=tel]','0707');await ay.fill('input[name=quartier]','A');await ay.fill('.vd >> nth=0','R');await ay.fill('.vp >> nth=0','1000');await ay.selectOption('#v_pay','partiel');await ay.fill('#v_pv','5000');await ay.click('#mf .mf .btn:not(.ghost)');await ay.waitForTimeout(1200);
chk('montant trop élevé refusé par le serveur',(await ay.evaluate(()=>__t)).some(m=>/compris entre/.test(m)));await ay.evaluate(()=>closeModal());
// cycle de livraison
const ad=await sess('admin');await ad.evaluate(id=>CL.rpc("commande_action",{p_cid:id,p_action:"confirmer"}),oid);
const pr=await sess('moussa');await pr.evaluate(async id=>{await CL.rpc("commande_action",{p_cid:id,p_action:"preparer"});await CL.rpc("commande_action",{p_cid:id,p_action:"prete"})},oid);
const sv=await sess('awa');const lid=await sv.evaluate(async id=>(await CL.rpc("affecter_livraison",{p_cid:id,p_lid:S.livreurs.find(l=>l.nom.startsWith("Issa")).id,p_motif:"",p_force:true})).livraison_id,oid);
const att=+sql(`select montant_attendu from public.livraisons where id='${lid}'`),tot=+sql(`select total from public.commandes where id='${oid}'`);
chk('le livreur ne doit encaisser que le reste',att===tot-12000,att+' vs '+tot);
const is=await sess('issa');const code=sql(`select code from public.livraison_codes where livraison_id='${lid}'`);
const res=await is.evaluate(async([lid,code,att])=>{await CL.rpc("livreur_consentement");await CL.rpc("livraison_action",{p_lid:lid,p_action:"accepter",p:{}});await CL.rpc("livraison_action",{p_lid:lid,p_action:"prise_en_charge",p:{nb_colis:1}});await CL.rpc("livraison_action",{p_lid:lid,p_action:"demarrer",p:{}});return await CL.rpc("livraison_action",{p_lid:lid,p_action:"confirmer",p:{code,montant:att,mode:"Espèces",recu_par:"Cli"}})},[lid,code,att]);
chk('livraison confirmée sans écart',sql(`select statut||'/'||ecart from public.livraisons where id='${lid}'`)==='livree/0',JSON.stringify(res));
// dû au vendeur
await ay.evaluate(async()=>{await refresh();render()});
const net=await ay.evaluate(id=>{const e=Object.values(CL.vd)[0].elig.find(x=>x.commande_id===id);return e&&e.net},oid);
chk('dû au vendeur = (30 000 − 12 000) × (1 − commission)',net===Math.round(18000*(1-(+sql("select commission_pct from public.vendeurs where id='00000000-0000-0000-0000-0000000000b1'"))/100)),net);
console.log('erreurs JS',ay.errs,ad.errs,is.errs);console.log(ok+' ok / '+ko+' échecs');await b.close()})().catch(e=>{console.error('CRASH',e.message.slice(0,400));process.exit(1)});
