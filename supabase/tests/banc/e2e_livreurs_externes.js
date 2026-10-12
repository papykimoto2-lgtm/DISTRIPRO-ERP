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

const ay=await sess('aya'),ad=await sess('admin'),pr=await sess('moussa'),sv=await sess('awa'),is=await sess('issa');
const ISSA=sql("select id from public.livreurs where nom like 'Issa%' limit 1");
// 1. l'administrateur passe Issa en externe (20 %) via le formulaire
await ad.setViewportSize({width:1280,height:950});await ad.evaluate(()=>{view='livreurs';render()});
await ad.evaluate(id=>ACT.editLiv(id),ISSA);await ad.waitForSelector('#l_type');await ad.selectOption('#l_type','externe');await ad.fill('input[name=lcom]','20');
await ad.click('#mf .mf .btn:not(.ghost)');await ad.waitForTimeout(1500);
chk('livreur externe enregistré côté serveur',sql(`select type||'/'||commission_pct from public.livreurs where id='${ISSA}'`)==='externe/20.00',await ad.evaluate(()=>__t));
// 2. une commande livrée par Issa
await ay.click('button:has-text("Nouvelle commande")');await ay.waitForSelector('#v_pay');
await ay.fill('input[name=nom]','Cli Ext');await ay.fill('input[name=tel]','07'+String(Date.now()).slice(-8));await ay.fill('input[name=quartier]','Angré');await ay.fill('.vd >> nth=0','Robe');await ay.fill('.vq >> nth=0','2');await ay.fill('.vp >> nth=0','15000');
await ay.click('#mf .mf .btn:not(.ghost)');await ay.waitForTimeout(1800);
const oid=sql("select id from public.commandes where vendeur_id='00000000-0000-0000-0000-0000000000b1' order by numero desc limit 1");
await ad.evaluate(id=>CL.rpc("commande_action",{p_cid:id,p_action:"confirmer"}),oid);
await pr.evaluate(async id=>{await CL.rpc("commande_action",{p_cid:id,p_action:"preparer"});await CL.rpc("commande_action",{p_cid:id,p_action:"prete"})},oid);
const lid=await sv.evaluate(async([id,l])=>(await CL.rpc("affecter_livraison",{p_cid:id,p_lid:l,p_motif:"",p_force:true})).livraison_id,[oid,ISSA]);
const att=+sql(`select montant_attendu from public.livraisons where id='${lid}'`),frais=+sql(`select frais from public.commandes where id='${oid}'`);
const code=sql(`select code from public.livraison_codes where livraison_id='${lid}'`);
await is.evaluate(async([lid,code,att])=>{await CL.rpc("livreur_consentement");await CL.rpc("livraison_action",{p_lid:lid,p_action:"accepter",p:{}});await CL.rpc("livraison_action",{p_lid:lid,p_action:"prise_en_charge",p:{nb_colis:1}});await CL.rpc("livraison_action",{p_lid:lid,p_action:"demarrer",p:{}});return await CL.rpc("livraison_action",{p_lid:lid,p_action:"confirmer",p:{code,montant:att,mode:"Espèces",recu_par:"Cli"}})},[lid,code,att]);
const ca=Math.round(frais*0.2);
chk('course livrée : commission et part figées par le serveur',sql(`select commission_angels||'/'||part_livreur from public.livraisons where id='${lid}'`)===`${ca}/${frais-ca}`,sql(`select commission_angels||'/'||part_livreur from public.livraisons where id='${lid}'`));
// 3. l'écran et le serveur donnent le même restant
await ad.evaluate(()=>refresh());await ad.waitForTimeout(800);
const sc=await ad.evaluate(async id=>{const r=await CL.rpc("solde_livreurs");const x=r.find(y=>y.livreur_id===id);return{retenu:+x.retenu,solde:+x.solde,ui:soldeLiv(id),uiRet:retenuLiv(id)}},ISSA);
chk('écran = serveur (part retenue et restant à reverser)',sc.retenu===sc.uiRet&&sc.solde===sc.ui&&sc.retenu>=frais-ca,sc);
// 4. reversement limité au net
const caiss=await sess('yao');
const tooMuch=await caiss.evaluate(async([id,m])=>{try{await CL.rpc("reversement",{p_lid:id,p_montant:m,p_mode:"Espèces",p_note:"",p_ref:null});return "ok"}catch(e){return e.message}},[ISSA,sc.solde+1]);
chk('reverser plus que le restant net est refusé',/restant à reverser/.test(tooMuch),tooMuch);
chk('livreur interne (Kouamé) : aucune part',sql("select count(*) from public.livraisons l join public.livreurs v on v.id=l.livreur_id where v.type='interne' and l.part_livreur is not null")==='0');
// remise à l'état interne pour ne pas fausser les autres tests
sql(`update public.livreurs set type='interne', commission_pct=0 where id='${ISSA}'`);
chk('aucune erreur JS',ad.errs.length===0&&ay.errs.length===0,[ad.errs,ay.errs]);
console.log(ok+' ok / '+ko+' échecs');await b.close()})();
