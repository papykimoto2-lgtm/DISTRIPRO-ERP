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
const F=n=>Array.from({length:n},(_,i)=>({name:'p'+i+'.png',mimeType:'image/png',buffer:png}));
const NM='Cli Photo '+Date.now();
const ay=await sess('aya');
await ay.click('button:has-text("Nouvelle commande")');await ay.waitForSelector('#v_phf',{state:'attached'});
await ay.fill('input[name=nom]',NM);await ay.fill('input[name=tel]','07'+String(Date.now()).slice(-8));await ay.fill('input[name=quartier]','Angré');await ay.fill('.vd >> nth=0','Montre');await ay.fill('.vp >> nth=0','12000');
await ay.setInputFiles('#v_phf',F(2));await ay.waitForTimeout(600);
await ay.click('#mf .mf .btn:not(.ghost)');await ay.waitForTimeout(2500);
const oid=sql(`select c.id from public.commandes c join public.clients k on k.id=c.client_id where k.nom='${NM}'`);
chk('commande créée avec 2 photos côté serveur',!!oid&&sql(`select count(*) from public.commande_photos where commande_id='${oid}'`)==='2',await ay.evaluate(()=>__t));
await ay.evaluate(()=>refresh());await ay.waitForTimeout(500);
await ay.evaluate(id=>ACT.cmdPhotos(id),oid);await ay.waitForSelector('#ph_f',{state:'attached'});await ay.waitForTimeout(300);
chk('gestionnaire cloud : 2 photos relues du serveur',await ay.locator('#mf .wph img').count()===2&&/2\/8/.test(await ay.innerText('#mf')));
await ay.setInputFiles('#ph_f',F(1));await ay.waitForTimeout(2000);
chk('1 photo ajoutée → 3 en base',sql(`select count(*) from public.commande_photos where commande_id='${oid}'`)==='3'&&await ay.locator('#mf .wph img').count()===3);
await ay.click('#mf .wph .wthumb button >> nth=0');await ay.waitForTimeout(1500);
chk('1 photo retirée → 2 en base',sql(`select count(*) from public.commande_photos where commande_id='${oid}'`)==='2'&&await ay.locator('#mf .wph img').count()===2);
await ay.setInputFiles('#ph_f',F(9));await ay.waitForTimeout(4500);
chk('limite de 8 photos appliquée',sql(`select count(*) from public.commande_photos where commande_id='${oid}'`)==='8');
await ay.evaluate(()=>closeModal());
// concurrent : ne voit ni ne modifie
const ri=await sess('rival');
chk('un autre fournisseur n\'a pas le droit d\'ajouter',await ri.evaluate(async id=>{try{await CL.rpc("ajouter_photo_commande",{p_commande:id,p_fichier:"data:image/png;base64,AA"});return false}catch(e){return true}},oid));
chk('ni de retirer',await ri.evaluate(async id=>{try{const r=await CL.sb.from("commande_photos").select("id").eq("commande_id",id);return (r.data||[]).length===0}catch(e){return true}},oid));
// commande livrée : plus de modification
const liv=sql("select id from public.commandes where vendeur_id='00000000-0000-0000-0000-0000000000b1' and statut='livree' limit 1");
if(liv){chk('commande livrée : ajout refusé par le serveur',await ay.evaluate(async id=>{try{await CL.rpc("ajouter_photo_commande",{p_commande:id,p_fichier:"data:image/png;base64,AA"});return false}catch(e){return /terminée/.test(e.message)}},liv));
 await ay.evaluate(()=>refresh());await ay.waitForTimeout(500);await ay.evaluate(id=>photoManager(cmd(id)),liv);await ay.waitForTimeout(700);chk('commande livrée : interface en lecture seule',await ay.locator('#ph_f').count()===0)}
// admin
const ad=await sess('admin');await ad.evaluate(id=>photoManager(cmd(id)),oid);await ad.waitForTimeout(800);chk('l\'administrateur voit le gestionnaire (8/8)',/8\/8/.test(await ad.innerText('#mf')));
chk('aucune erreur JS',ay.errs.length===0&&ad.errs.length===0,[ay.errs,ad.errs]);
console.log(ok+' ok / '+ko+' échecs');await b.close()})();
