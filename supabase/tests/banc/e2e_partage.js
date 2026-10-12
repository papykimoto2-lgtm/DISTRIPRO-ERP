const { chromium } = require('/opt/node-tools/node_modules/playwright');const {spawn}=require('child_process');const fs=require('fs');
let ok=0,ko=0;const chk=(n,c,x)=>{c?ok++:ko++;console.log((c?'✔':'✘')+' '+n+(c?'':'  → '+(typeof x==='string'?x:JSON.stringify(x))))};
(async()=>{const srv=spawn('python3',['-m','http.server','8766','--bind','127.0.0.1'],{cwd:'/home/user/DISTRIPRO-ERP',stdio:'ignore'});await new Promise(r=>setTimeout(r,900));
const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});const ctx=await b.newContext({viewport:{width:1100,height:900}});const pg=await ctx.newPage();const er=[];pg.on('pageerror',e=>er.push(e.message));
await pg.goto('http://127.0.0.1:8766/index.html');await pg.waitForTimeout(800);await pg.reload();await pg.waitForTimeout(800);
const man=await pg.evaluate(async()=>(await (await fetch('manifest.webmanifest')).json()).share_target);chk('manifeste : share_target',man&&man.method==='POST'&&man.params.files[0].name==='medias',man);
chk('service worker contrôle la page',await pg.evaluate(()=>!!navigator.serviceWorker.controller));
// simulation d'un partage depuis WhatsApp : texte + capture + export
const png=fs.readFileSync('/tmp/claude-0/t/id.png').toString('base64');
const status=await pg.evaluate(async png=>{const fd=new FormData();fd.append('text',"Mme Konan 07 07 12 34 56\nAngré 8e tranche\n2 robes wax 15000");fd.append('medias',new File([Uint8Array.from(atob(png),c=>c.charCodeAt(0))],'capture.png',{type:'image/png'}));const r=await fetch('./?partage=1',{method:'POST',body:fd,redirect:'manual'});return r.type+':'+r.status},png);
chk('POST partage intercepté (redirection)',/opaqueredirect/.test(status),status);
await pg.goto('http://127.0.0.1:8766/?partage=1');await pg.waitForTimeout(1200);
chk('l\'application s\'ouvre sur l\'écran de connexion avec le partage en attente',await pg.isVisible('.pcard >> nth=0'));
await pg.click('.pcard >> nth=7');await pg.waitForSelector('#wa_txt',{timeout:6000});
chk('saisie WhatsApp ouverte avec le texte partagé',/Mme Konan/.test(await pg.inputValue('#wa_txt')));
await pg.waitForTimeout(600);chk('capture partagée reçue',(await pg.$$('.wthumb')).length===1);
chk('adresse nettoyée (?partage retiré)',!/partage/.test(await pg.evaluate(()=>location.search)));
await pg.click('#mf .mf .btn:not(.ghost)');await pg.waitForSelector('.wcard');chk('analyse du texte partagé',await pg.inputValue('[data-wf="0:tel"]')==='0707123456');
await pg.evaluate(()=>closeModal());
// partage reçu par un compte non vendeur
await pg.evaluate(async png=>{const fd=new FormData();fd.append('text',"test");await fetch('./?partage=1',{method:'POST',body:fd,redirect:'manual'})},png);
await pg.evaluate(()=>{ME=null;sessionStorage.clear();render()});await pg.goto('http://127.0.0.1:8766/?partage=1');await pg.waitForTimeout(1000);await pg.evaluate(()=>{ME=null;render()});await pg.click('.pcard >> nth=0');await pg.waitForTimeout(800);
chk('compte non vendeur : refus explicite',/réservé aux comptes vendeurs/.test(await pg.innerText('body'))&&!(await pg.isVisible('#wa_body')));
console.log('erreurs JS',er);console.log(ok+' ok / '+ko+' échecs');await b.close();srv.kill()})().catch(e=>{console.error('CRASH',e.message.slice(0,300));process.exit(1)});
