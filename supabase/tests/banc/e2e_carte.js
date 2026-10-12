const { chromium } = require('/opt/node-tools/node_modules/playwright');const fs=require('fs');const {execSync}=require('child_process');
const ANON=fs.readFileSync('/tmp/pgr/anon.key','utf8').trim();
const sql=q=>execSync(`psql -h 127.0.0.1 -p 54330 -U postgres -d t -At -c "${q}"`).toString().trim();
(async()=>{const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
const lf='/tmp/claude-0/t/lf/package/dist/';
async function sess(u){const ctx=await b.newContext({viewport:{width:1280,height:850}});await ctx.addInitScript(k=>{window.ANGELS_CLOUD={url:'http://127.0.0.1:3011',key:k}},ANON);
 await ctx.route('https://cdn.jsdelivr.net/npm/@supabase/**',r=>r.fulfill({path:'/tmp/pgr/sbjs/package/dist/umd/supabase.js',contentType:'application/javascript'}));
 await ctx.route('https://unpkg.com/leaflet@1.9.4/dist/leaflet.js',r=>r.fulfill({path:lf+'leaflet.js',contentType:'application/javascript'}));
 await ctx.route('https://unpkg.com/leaflet@1.9.4/dist/leaflet.css',r=>r.fulfill({path:lf+'leaflet.css',contentType:'text/css'}));
 await ctx.route('https://tile.openstreetmap.org/**',r=>r.fulfill({status:200,contentType:'image/png',body:Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==','base64')}));
 const pg=await ctx.newPage();pg.errs=[];pg.on('pageerror',e=>pg.errs.push(e.message));
 await pg.goto('file:///home/user/DISTRIPRO-ERP/index.html');await pg.waitForSelector('#lf');await pg.fill('input[name=ident]',u);await pg.fill('input[name=pwd]','pwd'+u);await pg.click('#lf button');
 await pg.waitForFunction(()=>typeof ME!=='undefined'&&ME&&S.users.length>0,null,{timeout:8000});return pg}
// une position récente pour Issa (insertion directe côté serveur pour le test)
sql("insert into public.positions_gps(org_id,livreur_id,lat,lng,acc) select org_id,id,5.352,-3.975,12 from public.livreurs where nom like 'Issa%'");
const ad=await sess('admin');await ad.evaluate(()=>{view='carte';render()});await ad.waitForSelector('.leaflet-container',{timeout:8000});await ad.waitForTimeout(1200);
const n=await ad.evaluate(()=>({mk:document.querySelectorAll('.mk').length,pos:Object.keys(S.pos).length,list:document.querySelectorAll('#cm_list .it').length}));console.log('admin',n,ad.errs);
const dg=await sess('dg');await dg.evaluate(()=>{view='carte';render()});await dg.waitForSelector('.leaflet-container',{timeout:8000});await dg.waitForTimeout(1200);
console.log('direction',await dg.evaluate(()=>({mk:document.querySelectorAll('.mk').length,list:document.querySelectorAll('#cm_list .it').length})),dg.errs);
await b.close()})().catch(e=>{console.error('CRASH',e.message.slice(0,300))});
