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
  await pg.evaluate(()=>{window.__t=[];const o=window.toast;window.toast=(m,k)=>{if(k==='err')__t.push(m);return o(m,k)}});
  pg.T=()=>pg.innerText('body');return pg};
 // chaque profil ouvre chacune de ses pages
 for(const u of ['admin','awa','koffi','moussa','yao','dg','issa','aya']){
  const pg=await sess(u);
  const views=await pg.evaluate(()=>NAV.filter(n=>n.r.includes(ME.role)).map(n=>n.v));
  const bad=[];
  for(const v of views){await pg.evaluate(v=>{view=v;render()},v).catch(e=>bad.push(v+':'+e.message.slice(0,80)))}
  chk(`${u}: ${views.length} pages sans erreur`,bad.length===0&&pg.errs.length===0,bad.concat(pg.errs).join(' ; '));
  pg.close&&0;
 }
 // vendeur : dépôt + isolation
 const ay=await sess('aya'),ri=await sess('rival');
 const dep=await ay.evaluate(async()=>{const z=S.config.zones[0].nom;const p=S.produits[0];
   return await CL.vendDepot({nom:'Cliente V',tel:'0505050505',zone:z,quartier:'Zone 4',repere:'',ref:'WEB-1',paiement:'prepaye',montant:0,note:''},[{desig:'Robe',qte:1,pu:12000}])}).catch(e=>'ERR '+e.message);
 console.log('dépôt vendeur →',dep, await ay.evaluate(()=>__t));
 const nv=sql("select count(*) from public.commandes where vendeur_id='00000000-0000-0000-0000-0000000000b1'");
 chk('commande vendeur créée',+nv>=1,nv);
 await ri.evaluate(()=>refresh());
 chk('rival ne voit pas la commande',await ri.evaluate(()=>S.commandes.every(c=>!c.vendeur_id||c.vendeur_id==='00000000-0000-0000-0000-0000000000b2')));
 chk('aya ne voit que ses commandes',await ay.evaluate(()=>S.commandes.every(c=>c.vendeur_id==='00000000-0000-0000-0000-0000000000b1')));
 // import CSV (3 lignes dont 1 invalide)
 const imp=await ay.evaluate(async()=>{const z=S.config.zones[0].nom;await CL.vendImport([{nom:'A',tel:'0101',zone:z,quartier:'Q',ref:'I1',lignes:[{desig:'X',qte:1,pu:1000}]},{nom:'B',tel:'0102',zone:z,quartier:'Q',ref:'I2',lignes:[{desig:'Y',qte:2,pu:500}]}]);return S.commandes.length}).catch(e=>'ERR '+e.message);
 console.log('import →',imp);
 // admin : params, documents, entretien, utilisateur, notif, portail
 const ad=await sess('admin');
 const par=await ad.evaluate(async()=>{S.config.signature_seuil=75000;await CL.saveConfig();await refresh();return S.config.signature_seuil});
 chk('paramètres enregistrés',par===75000,par);
 const cid=sql("select id from public.commandes where statut='livree' and vendeur_id is null limit 1");
 const doc=await ad.evaluate(async id=>{const ok=await CL.doc(id,'facture');return {ok,n:S.docs.length}},cid);
 chk('facture émise (numérotée)',doc.ok===true&&/^FAC-/.test(sql("select numero from public.documents order by numero limit 1")),JSON.stringify(doc)+await ad.evaluate(()=>__t));
 const ent=await ad.evaluate(async()=>{const m=S.motos[0];return await CL.go(()=>CL.rpc("enregistrer_entretien",{p_moto:m.id,p_date:new Date().toISOString().slice(0,10),p_type:"Vidange",p_km:m.km+10,p_cout:5000,p_prochain_dans:3000,p_statut:"disponible",p_note:""}))});
 chk('entretien enregistré',ent===true&&sql("select count(*) from public.entretiens")==='1',await ad.evaluate(()=>__t));
 const nu=await ad.evaluate(async()=>{try{await CL.fn("creer-utilisateur",{nom:'Nouveau Livreur',role:'livreur',identifiant:'nouv1',mot_de_passe:'123456',tel:'0700000099',zone:'Cocody',remu:{type:'fixe',fixe:1000,pct:0}});return 'ok'}catch(e){return e.message}});
 chk('compte livreur créé via fonction',nu==='ok'&&sql("select count(*) from public.membres where nom='Nouveau Livreur'")==='1',nu);
 const lg=await (async()=>{const ctx=await b.newContext();await ctx.addInitScript(k=>{window.ANGELS_CLOUD={url:'http://127.0.0.1:3011',key:k}},ANON);await ctx.route('https://cdn.jsdelivr.net/npm/@supabase/**',r=>r.fulfill({path:'/tmp/pgr/sbjs/package/dist/umd/supabase.js',contentType:'application/javascript'}));const p=await ctx.newPage();await p.goto('file:///home/user/DISTRIPRO-ERP/index.html');await p.waitForSelector('#lf');await p.fill('input[name=ident]','nouv1');await p.fill('input[name=pwd]','123456');await p.click('#lf button');await p.waitForTimeout(2500);return (await p.innerText('body')).includes('Nouveau Livreur')})().then(()=>true).catch(e=>false);
 chk('nouveau compte peut se connecter',lg);
 const lk=await ad.evaluate(async()=>{const c=S.clients[0];if(!c||!c.adresses[0])return 'noaddr';return await CL.rpc("creer_lien_portail",{p_adresse:c.adresses[0].id,p_ref:null})});
 chk('lien portail créé (64 hex)',/^[a-f0-9]{64}$/.test(lk),lk);
 if(/^[a-f0-9]{64}$/.test(lk)){
  const ctx=await b.newContext();await ctx.addInitScript(k=>{window.ANGELS_CLOUD={url:'http://127.0.0.1:3011',key:k}},ANON);
  await ctx.route('https://cdn.jsdelivr.net/npm/@supabase/**',r=>r.fulfill({path:'/tmp/pgr/sbjs/package/dist/umd/supabase.js',contentType:'application/javascript'}));
  const po=await ctx.newPage();const pe=[];po.on('pageerror',e=>pe.push(e.message));
  await po.goto('file:///home/user/DISTRIPRO-ERP/index.html#portail='+lk);await po.waitForTimeout(2500);
  const t=await po.innerText('body');console.log('portail:',t.slice(0,160).replace(/\n+/g,' | '),pe);
  chk('portail client chargé sans connexion',!/invalide|expiré/i.test(t)&&pe.length===0);
 }
 const nt=await ad.evaluate(()=>{view='notifs';render();return S.notifs.length});
 console.log('notifications en file:',nt);
 console.log(`\n${ok} ok / ${ko} échecs`);await b.close();
})().catch(e=>{console.error('CRASH',e.message.slice(0,500));process.exit(1)});
