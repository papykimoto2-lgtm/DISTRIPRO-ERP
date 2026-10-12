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

const cx=n=>sql(n);
const ad=await sess('admin'),yao=await sess('yao');
const nm='Caisse '+Date.now().toString().slice(-6);
// 1. création par l'administrateur (interface)
await ad.setViewportSize({width:1300,height:1000});await ad.evaluate(()=>{view='caisse';render()});
await ad.evaluate(()=>ACT.cxNew());await ad.waitForSelector('input[name=n]');await ad.fill('input[name=n]',nm);await ad.click('#mf .mf .btn:not(.ghost)');await ad.waitForTimeout(1500);
const cid=cx(`select id from public.caisses where nom='${nm}'`);
chk('caisse créée côté serveur (compte 571)',!!cid&&cx(`select compte from public.caisses where id='${cid}'`)==='571',await ad.evaluate(()=>__t));
// 2. ouverture par le caissier
await yao.setViewportSize({width:1300,height:1000});await yao.evaluate(()=>refresh());await yao.waitForTimeout(600);await yao.evaluate(()=>{view='caisse';render()});await yao.waitForTimeout(300);
chk('le caissier voit la nouvelle caisse (FERMÉE)',/FERMÉE/.test(await yao.innerText('body')));
await yao.evaluate(id=>ACT.cxOuvrir(id),cid);await yao.waitForSelector('input[name=f]');await yao.fill('input[name=f]','40000');await yao.click('#mf .mf .btn:not(.ghost)');await yao.waitForTimeout(1500);
chk('caisse ouverte avec un fond de 40 000 F',cx(`select fond_ouverture||'/'||statut from public.caisse_sessions where caisse_id='${cid}'`)==='40000/ouverte',await yao.evaluate(()=>__t));
// 3. bon d'entrée en attente, solde inchangé
await yao.evaluate(id=>ACT.cxBon(id+"|entree"),cid);await yao.waitForSelector('input[name=m]');await yao.fill('input[name=m]','15000');await yao.fill('input[name=motif]','Vente au comptoir');await yao.fill('input[name=tiers]','Mme Koné');await yao.click('#mf .mf .btn:not(.ghost)');await yao.waitForTimeout(1500);
chk('bon enregistré en attente de validation',cx(`select statut||'/'||numero from public.caisse_mouvements where caisse_id='${cid}'`).startsWith('en_attente/BE-571-'),await yao.evaluate(()=>__t));
chk('bon non validé : solde toujours 40 000 F',await yao.evaluate(id=>cxSolde(cxCaisse(id)),cid)===40000);
chk('le caissier ne peut pas valider (serveur)',await yao.evaluate(async()=>{try{await CL.rpc("caisse_valider",{p_id:S.caisse_mvts[0].id,p_decision:"valider"});return false}catch(e){return true}}));
// 4. validation par l'administrateur
await ad.evaluate(()=>refresh());await ad.waitForTimeout(800);await ad.evaluate(()=>{view='caisse';render()});
await ad.locator('[data-act=cxVal]').first().click();await ad.waitForTimeout(1500);
chk('validation par l\'administrateur',cx(`select statut from public.caisse_mouvements where caisse_id='${cid}'`)==='valide');
// 5. reversement en espèces => entrée automatique
const ISSA=cx("select id from public.livreurs where nom like 'Issa%' limit 1"),sol=await ad.evaluate(async id=>{const r=await CL.rpc("solde_livreurs");return +r.find(x=>x.livreur_id===id).solde},ISSA);
if(sol>0){const caiss=await sess('yao');await caiss.evaluate(async([id,m])=>CL.rpc("reversement",{p_lid:id,p_montant:m,p_mode:"Espèces",p_note:"",p_ref:null}),[ISSA,Math.min(sol,1000)]);
 chk('reversement en espèces → entrée automatique validée (si c\'est la caisse principale ouverte)',+cx(`select count(*) from public.caisse_mouvements where source='reversement' and statut='valide'`)>=1);}
else chk('reversement automatique (non testable : aucun solde livreur)',true);
// 6. clôture refusée avec bon en attente puis avec écart
await yao.evaluate(id=>ACT.cxBon(id+"|sortie"),cid);await yao.waitForSelector('input[name=m]');await yao.fill('input[name=m]','2000');await yao.fill('input[name=motif]','Carburant');await yao.fill('input[name=tiers]','Station');await yao.click('#mf .mf .btn:not(.ghost)');await yao.waitForTimeout(1500);
await yao.evaluate(()=>refresh());await yao.waitForTimeout(500);
await yao.evaluate(id=>ACT.cxCloture(id),cid);await yao.waitForSelector('#cx_r');await yao.fill('#cx_r','54000');await yao.click('#mf .mf .btn:not(.ghost)');await yao.waitForTimeout(1500);
chk('clôture refusée avec un bon en attente',cx(`select statut from public.caisse_sessions where caisse_id='${cid}'`)==='ouverte'&&/en attente de validation/.test(await yao.innerText('body')));
await yao.evaluate(()=>closeModal());
await ad.evaluate(()=>refresh());await ad.waitForTimeout(600);await ad.evaluate(()=>{view='caisse';render()});await ad.locator('[data-act=cxVal]').first().click();await ad.waitForTimeout(1500);
await yao.evaluate(()=>refresh());await yao.waitForTimeout(600);
const th=await yao.evaluate(async id=>{await refresh();const t=cxSoldeS(cxOpen(cxCaisse(id)));ACT.cxCloture(id);return t},cid);await yao.waitForSelector('#cx_r');await yao.fill('#cx_r',String(th-500));await yao.fill('textarea[name=j]','Pièce de 500 F manquante');await yao.click('#mf .mf .btn:not(.ghost)');await yao.waitForTimeout(1800);
chk('clôture avec écart −500 F et justification',cx(`select ecart||'/'||ecart_regularise||'/'||fond_cloture_theorique from public.caisse_sessions where caisse_id='${cid}'`)===`-500/false/${th}`,cx(`select ecart||'/'||ecart_regularise||'/'||fond_cloture_theorique||'/'||statut from public.caisse_sessions where caisse_id='${cid}'`)+' th='+th);
// 7. régularisation
await ad.evaluate(()=>refresh());await ad.waitForTimeout(600);await ad.evaluate(()=>{view='caisse';render()});
chk('écart visible chez l\'administrateur',await ad.locator('[data-act=cxRegul]').count()>=1);
const sid=cx(`select id from public.caisse_sessions where caisse_id='${cid}'`);
await ad.evaluate(id=>ACT.cxRegul(id),sid);await ad.waitForSelector('textarea[name=v]');await ad.fill('textarea[name=v]','Manquant imputé au caissier');await ad.click('#mf .mf .btn:not(.ghost)');await ad.waitForTimeout(1500);
chk('écart régularisé côté serveur',cx(`select ecart_regularise from public.caisse_sessions where id='${sid}'`)==='t');
// 8. impressions + isolation
await ad.evaluate(()=>refresh());await ad.waitForTimeout(500);
chk('brouillard imprimable depuis le serveur',await ad.evaluate(id=>{ui.cxsel=id;ui.cxbm="session";ui.cxss=null;const d=cxBrData();return d&&d.rows.length>=2&&d.open===40000},cid));
const issa=await sess('issa');chk('un livreur ne voit aucune caisse',await issa.evaluate(()=>(S.caisses||[]).length===0&&(S.caisse_mvts||[]).length===0));
const aya=await sess('aya');chk('un vendeur ne voit aucune caisse',await aya.evaluate(()=>(S.caisses||[]).length===0));
chk('écriture directe refusée au caissier',await yao.evaluate(async()=>{const r=await CL.sb.from('caisse_mouvements').insert({org_id:CL.org,caisse_id:S.caisses[0].id,session_id:S.caisse_sessions[0].id,numero:'ZZ',type:'entree',montant:1,motif:'x'});return !!r.error}));
chk('aucune erreur JS',ad.errs.length===0&&yao.errs.length===0,[ad.errs,yao.errs]);
console.log(ok+' ok / '+ko+' échecs');await b.close()})();
