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

const ISSA=sql("select id from public.livreurs where nom like 'Issa%' limit 1");
const is=await sess('issa'),sv=await sess('awa'),ad=await sess('admin'),yao=await sess('yao'),aya=await sess('aya');
await is.setViewportSize({width:420,height:900});await sv.setViewportSize({width:1100,height:900});await ad.setViewportSize({width:1100,height:900});
chk('le bouton SOS est présent côté livreur (cloud)',await is.isVisible('.sosbtn'));
// déclenchement par le livreur
await is.evaluate(()=>{window.__SANS_OFFRE=true;return sosSend('accident','Chute près du marché')});await is.waitForTimeout(1800);
const sid=sql(`select id from public.alertes_sos where livreur_id='${ISSA}' and statut in ('ouverte','prise')`);
chk('alerte enregistrée côté serveur (type, note)',!!sid&&sql(`select type||'/'||note from public.alertes_sos where id='${sid}'`)==='accident/Chute près du marché',await is.evaluate(()=>__t));
chk('le livreur voit son alerte en cours',/Alerte SOS en cours/.test(await is.innerText('#app')));
// l'équipe est alertée sans rien faire (≤ 15 s)
const t0=Date.now();await sv.waitForSelector('#sosbar',{timeout:16000});const dt=(Date.now()-t0)/1000;
chk('barre rouge chez le superviseur sans action de sa part ('+dt.toFixed(1)+' s)',/Issa/.test(await sv.innerText('#sosbar'))&&/Accident/.test(await sv.innerText('#sosbar')));
chk('sirène déclenchée',await sv.evaluate(()=>(window.__ring||0)>=1));
await ad.waitForSelector('#sosbar',{timeout:16000});chk('l\'administrateur voit la barre aussi',true);
// prise en charge : une seule personne
await sv.click('#sosbar [data-act=sosTake]');await sv.waitForTimeout(3500);
const pc=sql(`select statut||'/'||prise_par_nom from public.alertes_sos where id='${sid}'`);chk('prise en charge enregistrée (superviseur)',/^prise\/Awa/.test(pc),pc);
const dbl=await ad.evaluate(async id=>{try{await CL.rpc("sos_traiter",{p_id:id,p_action:"prendre"});return "ok"}catch(e){return e.message}},sid);
chk('pas de double prise en charge',/déjà prise en charge par Awa/.test(dbl),dbl);
// le livreur voit le changement
await is.waitForTimeout(16000);const rt=await is.innerText('#modal');chk('le livreur voit « prise en charge par Awa » automatiquement',/pris(e)? en charge par\s*Awa/i.test(rt),rt.match(/SOS[^\n]*/g));
// clôture par l'administrateur
await ad.evaluate(()=>refresh());await ad.waitForTimeout(600);await ad.evaluate(()=>render());await ad.waitForSelector('#sosbar [data-act=sosClose]');await ad.click('#sosbar [data-act=sosClose]');await ad.waitForSelector('textarea[name=v]');await ad.fill('textarea[name=v]','Livreur conduit à la clinique');await ad.click('#mf .mf .btn:not(.ghost)');await ad.waitForTimeout(1800);
chk('clôture enregistrée avec sa résolution',sql(`select statut||'/'||resolution from public.alertes_sos where id='${sid}'`)==='cloturee/Livreur conduit à la clinique');
await sv.waitForTimeout(8000);chk('la barre disparaît chez le superviseur',!(await sv.isVisible('#sosbar').catch(()=>false)));
// fausse alerte par le livreur
await is.evaluate(()=>sosSend('autre','test'));await is.waitForTimeout(2500);
const s2=sql(`select id from public.alertes_sos where livreur_id='${ISSA}' and statut='ouverte'`);
await is.evaluate(id=>sosAgir(id,"fausse"),s2);await is.waitForTimeout(3000);
chk('fausse alerte annulée par le livreur',sql(`select statut from public.alertes_sos where id='${s2}'`)==='fausse');
// droits
chk('le caissier ne voit aucune alerte',await yao.evaluate(()=>(S.sos||[]).length===0)&&!(await yao.isVisible('#sosbar').catch(()=>false)));
chk('le vendeur ne voit aucune alerte',await aya.evaluate(()=>(S.sos||[]).length===0));
chk('écriture directe refusée au livreur',await is.evaluate(async()=>{const r=await CL.sb.from('alertes_sos').update({statut:'cloturee'}).eq('livreur_id',livreurOf(ME).id);return !!r.error||!(r.data&&r.data.length)}));
chk('aucune erreur JS',is.errs.length===0&&sv.errs.length===0&&ad.errs.length===0,[is.errs,sv.errs,ad.errs]);
console.log(ok+' ok / '+ko+' échecs');await b.close()})();
