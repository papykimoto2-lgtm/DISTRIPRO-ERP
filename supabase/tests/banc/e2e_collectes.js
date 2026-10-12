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
// adresse de collecte
await ay.click('button:has-text("Renseigner mon adresse"), button:has-text("Modifier")');await ay.waitForSelector('input[name=q]');await ay.selectOption('select[name=z]',{index:1});await ay.fill('input[name=q]','Angré 8e tranche');await ay.fill('input[name=r]','près de la pharmacie');await ay.click('#mf .mf .btn:not(.ghost)');await ay.waitForTimeout(1500);
chk('adresse de collecte enregistrée côté serveur',/Angré 8e tranche/.test(sql("select adresse_collecte::text from public.vendeurs where id='00000000-0000-0000-0000-0000000000b1'")),await ay.evaluate(()=>__t));
// l'administrateur confirme une commande du vendeur puis planifie
const oid=sql("select id from public.commandes where vendeur_id='00000000-0000-0000-0000-0000000000b1' and statut='attente' order by numero limit 1");
const ad=await sess('admin');
await ad.evaluate(id=>CL.rpc("commande_action",{p_cid:id,p_action:"confirmer"}),oid);await ad.evaluate(()=>refresh());
await ad.evaluate(()=>{view='livraisons';render()});await ad.waitForTimeout(500);
chk('section collectes : commande confirmée à planifier',await ad.isVisible('button:has-text("Planifier la collecte")'));
await ad.click('button:has-text("Planifier la collecte")');await ad.waitForSelector('select[name=l]');await ad.fill('input[name=n]','Avant 16 h');await ad.click('#mf .mf .btn:not(.ghost)');await ad.waitForTimeout(1800);
chk('collecte créée côté serveur avec code',sql("select count(*) from public.collectes where statut='planifiee'")>='1'&&/^\d{4}$/.test(sql("select code from public.collecte_codes order by collecte_id limit 1")),await ad.evaluate(()=>__t));
const cid=sql("select id from public.collectes order by numero desc limit 1");const code=sql(`select code from public.collecte_codes where collecte_id='${cid}'`);
// le vendeur voit son code
await ay.evaluate(async()=>{await refresh();render()});await ay.waitForTimeout(300);
chk('vendeur : voit sa collecte et son code',await ay.evaluate(c=>S.collectes.some(x=>x.code===c),code)&&(await ay.innerText('body')).includes(code));
// livreur
const lv=await sess(sql(`select case when livreur_id='00000000-0000-0000-0000-0000000000a1' then 'issa' else 'kone' end from public.collectes where id='${cid}'`));
chk('livreur : carte de collecte, sans le code',await lv.evaluate(()=>S.collectes.length>=1&&S.collectes.every(c=>c.code===undefined)&&/Collecte COL-/.test(document.body.innerText)));
await lv.click('button:has-text("Accepter")');await lv.waitForTimeout(1200);await lv.click('button:has-text("Je pars chez le vendeur")');await lv.waitForTimeout(1200);
await lv.click('button:has-text("Colis collectés")');await lv.waitForSelector('input[name=code]');await lv.fill('input[name=code]','0000');await lv.click('#mf .mf .btn:not(.ghost)');await lv.waitForTimeout(1500);
chk('mauvais code refusé',sql(`select statut||essais_code from public.collectes where id='${cid}'`)==='en_route1'&&/incorrect/.test(await lv.innerText('body')),sql(`select statut from public.collectes where id='${cid}'`));
await lv.fill('input[name=code]',code);await lv.click('#mf .mf .btn:not(.ghost)');await lv.waitForTimeout(1800);
chk('bon code : collectée',sql(`select statut from public.collectes where id='${cid}'`)==='collectee',await lv.evaluate(()=>__t));
// préparateur : réception
const pr=await sess('moussa');await pr.evaluate(()=>{view='commandes';render()});await pr.waitForTimeout(500);
chk('préparateur : collecte à réceptionner',/Collectes à réceptionner/.test(await pr.innerText('body')));
await pr.click('button:has-text("Réceptionner")');await pr.waitForSelector('input[name^=r_]');await pr.click('#mf .mf .btn:not(.ghost)');await pr.waitForTimeout(2000);
chk('réceptionnée, commande en préparation',sql(`select statut from public.collectes where id='${cid}'`)==='recue'&&sql(`select statut from public.commandes where id='${oid}'`)==='preparation',await pr.evaluate(()=>__t));
// isolation
const ri=await sess('rival');chk('vendeur concurrent : aucune collecte',await ri.evaluate(()=>S.collectes.length===0));
console.log('erreurs JS',ay.errs,ad.errs,lv.errs,pr.errs);console.log(ok+' ok / '+ko+' échecs');await b.close()})().catch(e=>{console.error('CRASH',e.message.slice(0,400));process.exit(1)});
