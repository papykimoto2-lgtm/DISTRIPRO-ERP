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

const ad=await sess('admin');await ad.setViewportSize({width:1300,height:1000});await ad.evaluate(()=>{view='params';render()});
const labels=await ad.$$eval('#ptabs button',b=>b.map(x=>x.textContent));
chk('cloud : 6 onglets, sans « Données »',labels.length===6&&!labels.some(l=>/Données/.test(l)),labels);
await ad.click('#ptabs [data-id=pay]');await ad.fill('#p_momo','Wave : 07 12 12 12 12');await ad.click('#ptabs [data-id=listes]');await ad.fill('#p_cats','Retard\nTest onglet cloud');
await ad.click('#psave');await ad.waitForTimeout(1800);
chk('enregistrement global côté serveur (paiements + listes)',/Wave : 07 12 12 12 12/.test(sql("select config->>'momo_comptes' from public.organisations limit 1"))&&/Test onglet cloud/.test(sql("select config->>'cats' from public.organisations limit 1")),sql("select config->>'momo_comptes' from public.organisations limit 1"));
chk('onglet conservé après enregistrement',await ad.evaluate(()=>[...document.querySelectorAll('[data-pt]')].filter(x=>!x.classList.contains('hide')).map(x=>x.dataset.pt).join())==='listes');
chk('aucune erreur JS',ad.errs.length===0,ad.errs);
console.log(ok+' ok / '+ko+' échecs');await b.close()})();
