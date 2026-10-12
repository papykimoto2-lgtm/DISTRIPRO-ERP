const { chromium } = require('/opt/node-tools/node_modules/playwright');
const fs=require('fs');const {execSync}=require('child_process');
const ANON=fs.readFileSync('/tmp/pgr/anon.key','utf8').trim();
const sql=q=>execSync(`psql -h 127.0.0.1 -p 54330 -U postgres -d t -At -c "${q}"`).toString().trim();
let ok=0,ko=0;const chk=(n,c,x)=>{c?ok++:ko++;console.log((c?'✔':'✘')+' '+n+(c?'':'  → '+(x||'')))};
(async()=>{const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
async function sess(u){const ctx=await b.newContext({viewport:{width:1280,height:900}});
 await ctx.addInitScript(k=>{window.ANGELS_CLOUD={url:'http://127.0.0.1:3011',key:k}},ANON);
 await ctx.route('https://cdn.jsdelivr.net/npm/@supabase/**',r=>r.fulfill({path:'/tmp/pgr/sbjs/package/dist/umd/supabase.js',contentType:'application/javascript'}));
 const pg=await ctx.newPage();pg.errs=[];pg.on('pageerror',e=>pg.errs.push(e.message));pg.on('dialog',d=>d.accept());
 await pg.goto('file:///home/user/DISTRIPRO-ERP/index.html');await pg.waitForSelector('#lf');
 await pg.fill('input[name=ident]',u);await pg.fill('input[name=pwd]','pwd'+u);await pg.click('#lf button');
 await pg.waitForFunction(()=>typeof ME!=='undefined'&&ME&&S.users.length>0,null,{timeout:8000});
 await pg.evaluate(()=>{window.__t=[];const o=window.toast;window.toast=(m,k)=>{if(k==='err')__t.push(m);return o(m,k)}});return pg}
const ad=await sess('admin');
await ad.click('aside a:has-text("Livreurs")');
await ad.click('tr:has-text("Issa") button:has-text("Dossier")');await ad.waitForSelector('[data-slot=photo]');
for(const k of ['photo','piece_recto','piece_verso','permis'])await ad.setInputFiles(`input[data-img=${k}]`,'/tmp/claude-0/t/id.png');
await ad.waitForTimeout(800);
await ad.selectOption('select[name=piece_type]','cni');await ad.fill('input[name=piece_numero]','CI123');await ad.fill('input[name=piece_expire]','2031-01-01');
await ad.fill('input[name=permis_numero]','P-77');await ad.fill('input[name=permis_expire]','2031-01-01');await ad.fill('input[name=contact_urgence_tel]','0100000009');await ad.check('input[name=consent]');
await ad.click('#mf .mf .btn:not(.ghost)');await ad.waitForTimeout(1500);
console.log('toasts err:',await ad.evaluate(()=>__t));
chk('dossier + 4 images en base',sql("select count(*) from public.livreur_fichiers")==='4'&&sql("select piece_numero from public.livreur_dossiers")==='CI123');
chk('dossier complet côté serveur',sql("select app.dossier_complet('00000000-0000-0000-0000-0000000000a1')")==='t');
chk('journal sans contenu image',sql("select count(*) from public.audit_log where detail like '%base64%'")==='0');
chk('statut affiché « Dossier complet »',(await ad.innerText('body')).includes('Dossier complet'));
// rechargement : images relues à l'ouverture
await ad.evaluate(()=>refresh());await ad.click('tr:has-text("Issa") button:has-text("Dossier")');await ad.waitForTimeout(1500);
chk('images relues depuis le serveur',(await ad.$$('.slot img:not(.hide)')).length===4);
await ad.evaluate(()=>closeModal());
// remplacer / retirer
await ad.click('tr:has-text("Issa") button:has-text("Dossier")');await ad.waitForTimeout(1200);await ad.click('[data-slot=permis] button:has-text("Retirer")');await ad.click('#mf .mf .btn:not(.ghost)');await ad.waitForTimeout(1200);
chk('image retirée',sql("select count(*) from public.livreur_fichiers")==='3');
// confidentialité
const ko_=await sess('koffi');chk('commercial : aucun dossier lisible',await ko_.evaluate(()=>S.livreurs.every(l=>!l.dossier)));
const rr=await ko_.evaluate(async()=>{const {data}=await CL.sb.from('livreur_fichiers').select('fichier');return data.length});chk('commercial : aucune image',rr===0,rr);
const is=await sess('issa');const mine=await is.evaluate(async()=>{const {data}=await CL.sb.from('livreur_fichiers').select('kind');return data.length});chk('livreur : voit ses images seulement',mine===3,mine);
const kn=await sess('kone');const kk=await kn.evaluate(async()=>{const {data}=await CL.sb.from('livreur_fichiers').select('kind');return data.length});chk('autre livreur : rien',kk===0,kk);
// exigence : affectation refusée par le serveur pour Kouamé
await ad.evaluate(async()=>{S.config.dossier_obligatoire=true;await CL.saveConfig()});await ad.waitForTimeout(800);
chk('paramètre enregistré',sql("select config->>'dossier_obligatoire' from public.organisations limit 1")==='true');
console.log('erreurs JS',ad.errs,ko_.errs,is.errs);console.log(`${ok} ok / ${ko} échecs`);await b.close()})().catch(e=>{console.error('CRASH',e.message.slice(0,300));process.exit(1)});
