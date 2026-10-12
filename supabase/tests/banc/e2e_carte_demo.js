const { chromium } = require('/opt/node-tools/node_modules/playwright');
let ok=0,ko=0;const chk=(n,c,x)=>{c?ok++:ko++;console.log((c?'✔':'✘')+' '+n+(c?'':'  → '+(x||'')))};
(async()=>{const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
const ctx=await b.newContext({viewport:{width:1280,height:850}});
const lf='/tmp/claude-0/t/lf/package/dist/';
await ctx.route('https://unpkg.com/leaflet@1.9.4/dist/leaflet.js',r=>r.fulfill({path:lf+'leaflet.js',contentType:'application/javascript'}));
await ctx.route('https://unpkg.com/leaflet@1.9.4/dist/leaflet.css',r=>r.fulfill({path:lf+'leaflet.css',contentType:'text/css'}));
await ctx.route('https://tile.openstreetmap.org/**',r=>r.fulfill({status:200,contentType:'image/png',body:Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==','base64')}));
const pg=await ctx.newPage();const er=[];pg.on('pageerror',e=>er.push(e.message));
await pg.goto('file:///home/user/DISTRIPRO-ERP/index.html');await pg.waitForTimeout(400);
for(const [i,role] of [[0,'admin'],[1,'superviseur'],[5,'direction']]){
 await pg.evaluate(()=>{ME=null;sessionStorage.clear();render()});await pg.click(`.pcard >> nth=${i}`);await pg.waitForTimeout(300);
 chk(role+' : menu « Carte en direct »',await pg.isVisible('aside a:has-text("Carte en direct")'))}
await pg.evaluate(()=>{ME=null;render()});await pg.click('.pcard >> nth=0');await pg.click('aside a:has-text("Carte en direct")');await pg.waitForSelector('.leaflet-container',{timeout:8000});await pg.waitForTimeout(800);
const n=await pg.evaluate(()=>({mk:document.querySelectorAll('.mk').length,dest:document.querySelectorAll('.mkd').length,list:document.querySelectorAll('#cm_list .it').length,riders:S.livreurs.length}));
console.log(n);chk('un marqueur par livreur',n.mk===n.riders&&n.list===n.riders,JSON.stringify(n));chk('destinations affichées',n.dest>=2);
const p0=await pg.evaluate(()=>{const l=S.livreurs.find(x=>x.nom.startsWith('Kouamé'));return S.pos[l.id].lat});await pg.waitForTimeout(7000);
const p1=await pg.evaluate(()=>{const l=S.livreurs.find(x=>x.nom.startsWith('Kouamé'));return S.pos[l.id].lat});chk('démo : le livreur en course avance',p0!==p1,p0+' → '+p1);
await pg.screenshot({path:'/tmp/claude-0/t/s_carte.png'});
await pg.click('#cm_list .it >> nth=0');await pg.waitForTimeout(500);chk('clic liste : fiche ouverte',await pg.isVisible('.leaflet-popup'));
await pg.selectOption('select[data-f=cs]','libre');await pg.waitForSelector('.leaflet-container');await pg.waitForTimeout(600);
chk('filtre « Libres »',await pg.evaluate(()=>document.querySelectorAll('.mk.libre').length>0&&document.querySelectorAll('.mk.mission').length===0));
// autres rôles
for(const [i,role] of [[2,'commercial'],[4,'caissier']]){await pg.evaluate(()=>{ME=null;render()});await pg.click(`.pcard >> nth=${i}`);chk(role+' : pas de carte',!(await pg.isVisible('aside a:has-text("Carte en direct")')))}
// quitter la page arrête les mises à jour
chk('minuteur coupé hors page',await pg.evaluate(()=>{view="clients";render();return CARTE.timer===null}));
console.log('erreurs JS',er);console.log(ok+' ok / '+ko+' échecs');await b.close()})();
