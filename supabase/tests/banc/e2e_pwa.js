const { chromium } = require('/opt/node-tools/node_modules/playwright');const {spawn}=require('child_process');
let ok=0,ko=0;const chk=(n,c,x)=>{c?ok++:ko++;console.log((c?'✔':'✘')+' '+n+(c?'':'  → '+(x||'')))};
(async()=>{const srv=spawn('python3',['-m','http.server','8765','--bind','127.0.0.1'],{cwd:'/home/user/DISTRIPRO-ERP',stdio:'ignore'});await new Promise(r=>setTimeout(r,1000));
const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
const ctx=await b.newContext({viewport:{width:1100,height:800}});const pg=await ctx.newPage();const er=[];pg.on('pageerror',e=>er.push(e.message));
await pg.goto('http://127.0.0.1:8765/index.html');await pg.waitForTimeout(500);
const man=await pg.evaluate(async()=>{const l=document.querySelector('link[rel=manifest]');const r=await fetch(l.href);return {ok:r.ok,j:await r.json()}});
chk('manifeste lisible',man.ok&&man.j.display==='standalone'&&man.j.start_url==='./'&&man.j.icons.length===3,JSON.stringify(man.j).slice(0,120));
const ic=await pg.evaluate(async()=>{const r=[];for(const i of ['icons/icon-192.png','icons/icon-512.png','icons/icon-maskable-512.png','icons/apple-touch-icon.png']){const x=await fetch(i);r.push(x.ok&&(x.headers.get('content-type')||'').includes('png'))}return r});chk('4 icônes servies',ic.every(Boolean),ic);
await pg.waitForFunction(()=>navigator.serviceWorker&&navigator.serviceWorker.controller||navigator.serviceWorker.ready.then(r=>!!r.active),null,{timeout:8000}).catch(()=>{});
const reg=await pg.evaluate(async()=>{const r=await navigator.serviceWorker.ready;return !!r.active});chk('service worker actif',reg);
await pg.reload();await pg.waitForTimeout(800);
await ctx.setOffline(true);await pg.reload();await pg.waitForTimeout(1000);
chk('ouverture hors connexion',/Essayez sans rien installer/.test(await pg.innerText('body')));
await pg.click('.pcard >> nth=0');await pg.waitForTimeout(300);chk('démo utilisable hors connexion',/Bonjour|Bon après-midi|Bonsoir/.test(await pg.innerText('body')));
await ctx.setOffline(false);
// invite d'installation (simulée)
await pg.evaluate(()=>{ME=null;render()});await pg.waitForTimeout(200);
chk('pas de bouton sans invite du navigateur',!(await pg.isVisible('[data-act=installApp]')));
await pg.evaluate(()=>{const e=new Event('beforeinstallprompt');e.prompt=()=>{window.__prompted=true};e.userChoice=Promise.resolve({outcome:'accepted'});window.dispatchEvent(e)});await pg.waitForTimeout(200);
chk('bouton « Installer l\'application » après invite',await pg.isVisible('[data-act=installApp]'));
await pg.click('[data-act=installApp]');await pg.waitForTimeout(300);chk('invite déclenchée puis bouton masqué',(await pg.evaluate(()=>window.__prompted))===true&&!(await pg.isVisible('[data-act=installApp]')));
// livreur : bouton aussi
await pg.evaluate(()=>{const e=new Event('beforeinstallprompt');e.prompt=()=>{};e.userChoice=Promise.resolve({});window.dispatchEvent(e)});
await pg.click('.pcard >> nth=6');await pg.waitForTimeout(500);chk('bouton visible sur l\'écran livreur',await pg.isVisible('.lvh [data-act=installApp]'));
await pg.screenshot({path:'/tmp/claude-0/t/s_pwa.png'});
console.log('erreurs JS',er);console.log(ok+' ok / '+ko+' échecs');await b.close();srv.kill()})().catch(e=>{console.error('CRASH',e.message.slice(0,300));process.exit(1)});
