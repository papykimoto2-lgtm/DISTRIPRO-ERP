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

async function pub(link){const ctx=await b.newContext({viewport:{width:420,height:900},geolocation:{latitude:5.3571,longitude:-3.981,accuracy:25},permissions:['geolocation']});await ctx.addInitScript(k=>{window.ANGELS_CLOUD={url:'http://127.0.0.1:3011',key:k}},ANON);
 await ctx.route('https://cdn.jsdelivr.net/npm/@supabase/**',r=>r.fulfill({path:'/tmp/pgr/sbjs/package/dist/umd/supabase.js',contentType:'application/javascript'}));
 const pg=await ctx.newPage();pg.errs=[];pg.on('pageerror',e=>pg.errs.push(e.message));await pg.goto(link);await pg.waitForTimeout(1200);return pg}
const ay=await sess('aya');
await ay.click('button:has-text("Lien de commande client")');await ay.waitForSelector('#mf input[readonly]');
const link=await ay.inputValue('#mf input[readonly]');chk('lien cloud à jeton de 256 bits',/#commande=[a-f0-9]{64}$/.test(link),link);
chk('lien enregistré côté serveur',sql("select count(*) from public.commande_liens where vendeur_id='00000000-0000-0000-0000-0000000000b1'")==='1');
await ay.click('#mf .mf .btn:not(.ghost)').catch(()=>{});
const P=await pub(link);
chk('page publique sans connexion (cloud)',await P.locator('#o_send').count()===1&&/Commander chez/.test(await P.innerText('body')),(await P.innerText('body')).slice(0,200));
chk('les zones viennent du serveur',await P.locator('#o_zone option').count()>2);
const png=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==','base64');
await P.fill('.ol .o_d','Sac cloud');await P.fill('.ol .o_q','3');await P.fill('.ol .o_p','9000');
await P.setInputFiles('.ol input[type=file]',{name:'c.png',mimeType:'image/png',buffer:png});await P.waitForTimeout(500);
await P.click('button:has-text("Ajouter un article")');await P.locator('.ol .o_d').nth(1).fill('Ceinture');
await P.fill('#o_nom','Client Cloud');await P.fill('#o_tel','07 07 31 31 31');await P.selectOption('#o_zone','Cocody');
await P.click('button:has-text("Utiliser ma position")');await P.waitForTimeout(600);await P.fill('#o_note','Merci');
await P.click('#o_send');await P.waitForTimeout(1500);
chk('dépôt anonyme accepté, référence affichée',/Commande envoyée/.test(await P.innerText('body')),(await P.innerText('body')).slice(0,300));
chk('demande en base : lignes, GPS, capture, statut',sql("select statut||'/'||lat||'/'||jsonb_array_length(lignes)||'/'||jsonb_array_length(photos)||'/'||tel from public.demandes_commande where nom='Client Cloud'")==='nouvelle/5.357100/2/1/0707313131');
chk('aucune commande créée avant validation',sql("select count(*) from public.commandes c join public.clients k on k.id=c.client_id where k.nom='Client Cloud'")==='0');
chk('accès direct aux tables refusé pour l\'anonyme',await P.evaluate(async()=>{const r=await CL.sb.from('demandes_commande').select('id');return !!r.error||!(r.data||[]).length}));
chk('aucune erreur JS côté client',P.errs.length===0,P.errs);
// côté fournisseur
await ay.evaluate(()=>refresh());await ay.waitForTimeout(800);await ay.evaluate(()=>{view='mesCmd';render()});
chk('la demande apparaît chez le fournisseur',/Demandes reçues de vos clients \(1\)/.test(await ay.innerText('body'))&&/Client Cloud/.test(await ay.innerText('body')),(await ay.innerText('body')).slice(0,300));
const did=await ay.evaluate(()=>S.demandes[0].id);
await ay.evaluate(id=>ACT.demTraiter(id),did);await ay.waitForSelector('[data-wf="0:nom"]');
await ay.fill('[data-wl="0:1:pu"]','4000');await ay.click('#mf .mf .btn:not(.ghost)');await ay.waitForTimeout(2200);
const oid=sql("select c.id from public.commandes c join public.clients k on k.id=c.client_id where k.nom='Client Cloud'");
chk('commande créée côté serveur',!!oid,await ay.evaluate(()=>__t||[]));
chk('adresse géolocalisée avec la position du client',sql(`select a.lat||'/'||a.lng||'/'||a.gps_src from public.adresses a join public.commandes c on c.adresse_id=a.id where c.id='${oid}'`)==='5.357100/-3.981000/client');
chk('capture jointe à la commande',sql(`select count(*) from public.commande_photos where commande_id='${oid}'`)==='1');
chk('montant = 3×9000 + 4000 ; statut attente',sql(`select montant_produits||'/'||statut from public.commandes where id='${oid}'`)==='31000/attente');
chk('demande marquée traitée et liée',sql(`select statut||'/'||(commande_id='${oid}') from public.demandes_commande where id='${did}'`)==='traitee/true');
chk('la demande disparaît de la liste',!/Demandes reçues de vos clients/.test(await ay.innerText('body')));
// refus
const P2=await pub(link);await P2.fill('.ol .o_d','Autre');await P2.fill('#o_nom','Refusé');await P2.fill('#o_tel','0505121212');await P2.selectOption('#o_zone','Cocody');await P2.fill('#o_q','A');await P2.click('#o_send');await P2.waitForTimeout(1200);
await ay.evaluate(()=>refresh());await ay.waitForTimeout(600);const d2=await ay.evaluate(()=>S.demandes[0].id);
await ay.evaluate(id=>ACT.demRejeter(id),d2);await ay.waitForSelector('textarea[name=v]');await ay.fill('textarea[name=v]','Hors zone');await ay.click('#mf .mf .btn:not(.ghost)');await ay.waitForTimeout(1200);
chk('refus enregistré avec motif',sql(`select statut||'/'||motif from public.demandes_commande where id='${d2}'`)==='rejetee/Hors zone');
// limite de débit
let last='';for(let i=0;i<6;i++){const Q=await pub(link);await Q.fill('.ol .o_d','X');await Q.fill('#o_nom','Spam');await Q.fill('#o_tel','0505999999');await Q.selectOption('#o_zone','Cocody');await Q.fill('#o_q','A');await Q.click('#o_send');await Q.waitForTimeout(700);last=await Q.innerText('body')}
chk('limite de débit appliquée par le serveur',/Trop de demandes/.test(last),last.slice(0,200));
// renouvellement
await ay.evaluate(()=>ACT.cmdLienNew());await ay.waitForSelector('#mf .mf .btn.er');await ay.click('#mf .mf .btn:not(.ghost)');await ay.waitForSelector('#mf input[readonly]',{timeout:5000});
const link2=await ay.inputValue('#mf input[readonly]');chk('nouveau lien différent',link2!==link&&/#commande=/.test(link2));
const P3=await pub(link);chk('l\'ancien lien est refusé',/expiré ou invalide/.test(await P3.innerText('body')),(await P3.innerText('body')).slice(0,100));
const P4=await pub(link2);chk('le nouveau lien fonctionne',await P4.locator('#o_send').count()===1);
// un autre fournisseur ne voit pas les demandes
chk('aucune erreur JS fournisseur',ay.errs.length===0,ay.errs);
console.log(ok+' ok / '+ko+' échecs');await b.close()})();
