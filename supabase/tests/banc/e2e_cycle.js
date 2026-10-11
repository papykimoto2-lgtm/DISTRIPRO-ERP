const { chromium } = require('/opt/node-tools/node_modules/playwright');
const fs=require('fs');const {execSync}=require('child_process');
const ANON=fs.readFileSync('/tmp/pgr/anon.key','utf8').trim();
const sql=q=>execSync(`psql -h 127.0.0.1 -p 54330 -U postgres -d t -At -c "${q}"`).toString().trim();
let ok=0,ko=0;const chk=(n,c,x)=>{c?ok++:ko++;console.log((c?'✔':'✘')+' '+n+(c?'':'  → '+(x||'')))};
(async()=>{
 const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
 async function sess(u){
  const ctx=await b.newContext({viewport:{width:1200,height:1000},geolocation:{latitude:5.3,longitude:-4},permissions:['geolocation']});
  await ctx.addInitScript(k=>{window.ANGELS_CLOUD={url:'http://127.0.0.1:3011',key:k}},ANON);
  await ctx.route('https://cdn.jsdelivr.net/npm/@supabase/**',r=>r.fulfill({path:'/tmp/pgr/sbjs/package/dist/umd/supabase.js',contentType:'application/javascript'}));
  const pg=await ctx.newPage();pg.errs=[];pg.on('pageerror',e=>pg.errs.push(e.message));pg.on('dialog',d=>d.accept());
  await pg.goto('file:///home/user/DISTRIPRO-ERP/index.html');await pg.waitForSelector('#lf');
  await pg.fill('input[name=ident]',u);await pg.fill('input[name=pwd]','pwd'+u);await pg.click('#lf button');
  await pg.waitForFunction(()=>typeof ME!=='undefined'&&ME&&S.users.length>0,null,{timeout:8000});
  pg.T=()=>pg.innerText('body');pg.act=async(f,...a)=>{await pg.evaluate(([f,a])=>ACT[f](...a),[f,a]);await pg.waitForTimeout(700)};
  return pg};
 // --- commercial : crée une commande via l'écran
 const ko_=await sess('koffi');
 await ko_.click('aside a:has-text("Commandes")');
 await ko_.click('button:has-text("Nouvelle commande")');
 await ko_.waitForSelector('#f_client');
 await ko_.selectOption('#f_client','__new');
 await ko_.fill('input[name=n_nom]','Client Test');await ko_.fill('input[name=n_tel]','0102030405');
 await ko_.fill('input[name=a_q]','Riviera 2');
 await ko_.selectOption('.l_prod >> nth=0',{index:1});
 await ko_.fill('.l_qte >> nth=0','2');
 await ko_.check('input[name=confirmer]').catch(()=>{});
 await ko_.click('#mf .mf .btn:not(.ghost)');await ko_.waitForTimeout(1500);
 const n=sql("select numero||'|'||statut||'|'||total from public.commandes order by numero desc limit 1");
 chk('commande créée côté serveur',/^CMD/.test(n)||n.includes('|'),n);
 const cid=sql("select id from public.commandes order by numero desc limit 1");
 chk('lignes + stock réservé',sql(`select count(*) from public.commande_lignes where commande_id='${cid}'`)==='1');
 chk('aucune erreur JS koffi',ko_.errs.length===0,ko_.errs);
 // --- préparateur
 const mo=await sess('moussa');
 await mo.act('cmdConfirm',cid).catch(()=>{});
 let st=sql(`select statut from public.commandes where id='${cid}'`);console.log('statut après koffi:',st);
 if(st==='attente'){const aw=await sess('awa');await aw.act('cmdConfirm',cid);st=sql(`select statut from public.commandes where id='${cid}'`)}
 chk('confirmée',st==='confirmee',st);
 await mo.evaluate(()=>refresh());await mo.act('cmdPrep',cid);await mo.act('cmdPrete',cid);
 chk('prête',sql(`select statut from public.commandes where id='${cid}'`)==='prete');
 // étiquettes
 await mo.evaluate(id=>etiqueter?0:0,cid).catch(()=>{});
 const r=await mo.evaluate(async id=>{await CL.etiqueter(cmd(id),2);return cmd(id).colis&&cmd(id).colis.length},cid);
 chk('2 étiquettes avec jeton',r===2&&sql(`select count(*) from public.colis where commande_id='${cid}'`)==='2',r);
 chk('aucune erreur JS moussa',mo.errs.length===0,mo.errs);
 // --- superviseur affecte
 const aw=await sess('awa');
 const aff=await aw.evaluate(async id=>{const c=cmd(id);const lv=S.livreurs.find(l=>l.nom.startsWith('Issa'));return await CL.affecter(c,{lid:lv.id,motif:''},lv)},cid);
 chk('affectation',aff===true&&sql(`select count(*) from public.livraisons where commande_id='${cid}'`)==='1');
 const lid=sql(`select id from public.livraisons where commande_id='${cid}'`);
 const code=sql(`select code from public.livraison_codes where livraison_id='${lid}'`);
 // --- livreur
 const is=await sess('issa');
 await is.act('lAcc',lid);
 chk('mission acceptée',sql(`select statut from public.livraisons where id='${lid}'`)==='acceptee',sql(`select statut from public.livraisons where id='${lid}'`));
 // prise en charge avec scans (jetons lus en base)
 const toks=sql(`select tok from public.colis where commande_id='${cid}' order by n`).split('\n');
 const pr=await is.evaluate(async([id,toks])=>{const l=byId(S.livraisons,id);return await CL.liv(id,'prise_en_charge',{etat:'Bon état',scans:toks},'ok')},[lid,toks]);
 chk('prise en charge scannée',pr===true,sql(`select statut from public.livraisons where id='${lid}'`));
 await is.act('lGo',lid);await is.waitForSelector('button:has-text("J\'ai compris")',{timeout:3000}).then(()=>is.click('button:has-text("J\'ai compris")')).catch(e=>console.log('pas de modal consentement'));await is.waitForTimeout(1500);
 chk('départ',sql(`select statut from public.livraisons where id='${lid}'`)==='en_cours',sql(`select statut from public.livraisons where id='${lid}'`));
 chk('consentement GPS enregistré',sql(`select gps_consent from public.livreurs where nom like 'Issa%'`)==='t');
 // mauvais code
 const bad=await is.evaluate(async([id])=>{const l=byId(S.livraisons,id),c=cmd(l.commande_id);return await CL.confirmer(l,c,{code:'0000',montant:String(l.montant_attendu),mode:'Espèces',recu_par:'Test',colis_ok:JSON.stringify([])})},[lid]);
 chk('mauvais code refusé',bad===false&&sql(`select statut from public.livraisons where id='${lid}'`)==='en_cours');
 const sig='data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';
 const good=await is.evaluate(async([id,code,toks,sig])=>{const l=byId(S.livraisons,id),c=cmd(l.commande_id);return await CL.confirmer(l,c,{code,montant:String(l.montant_attendu),mode:'Espèces',recu_par:'M. Test',colis_ok:JSON.stringify(toks.map(t=>({txt:t}))),signature:sig})},[lid,code,toks,sig]);
 const fin=sql(`select statut from public.livraisons where id='${lid}'`);
 chk('livraison confirmée',good===true&&fin==='livree',fin);
 chk('commande livrée',sql(`select statut from public.commandes where id='${cid}'`)==='livree');
 chk('aucune erreur JS issa',is.errs.length===0,is.errs);
 // --- caissier : reversement
 const ya=await sess('yao');
 const dueTxt=await ya.evaluate(()=>S.livreurs.map(l=>l.nom+':'+(typeof livDue==='function'?livDue(l.id):'?')).join(','));console.log('dû livreurs:',dueTxt);
 await ya.click('aside a:has-text("Finance")');await ya.waitForTimeout(500);
 console.log((await ya.T()).slice(0,500).replace(/\n+/g,' | '));
 chk('aucune erreur JS yao',ya.errs.length===0,ya.errs);
 console.log(`\n${ok} ok / ${ko} échecs`);
 await b.close();
})().catch(e=>{console.error('CRASH',e.message.slice(0,400));process.exit(1)});
