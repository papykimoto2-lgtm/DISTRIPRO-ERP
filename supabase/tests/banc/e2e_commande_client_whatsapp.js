const { chromium } = require('/opt/node-tools/node_modules/playwright');
let ok=0,ko=0;const chk=(n,c,x)=>{c?ok++:ko++;console.log((c?'✔':'✘')+' '+n+(c?'':'  → '+(typeof x==='string'?x:JSON.stringify(x))))};
(async()=>{const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
const URL='file:///home/user/DISTRIPRO-ERP/index.html',er=[];
// 1. le fournisseur génère son lien (appareil A)
const ca=await b.newContext({viewport:{width:1280,height:950}});const A=await ca.newPage();A.on('pageerror',e=>er.push('A:'+e.message));A.on('dialog',d=>d.accept());
await A.goto(URL);await A.waitForTimeout(300);
await A.evaluate(()=>{const u=S.users.find(u=>u.role==='vendeur');ME=u;sessionStorage.setItem('angels_me',u.id);view='mesCmd';render()});
await A.click('button:has-text("Lien de commande client")');await A.waitForSelector('#mf input[readonly]');
const link=await A.inputValue('#mf input[readonly]');chk('lien autonome (données dans le lien)',/#commande=[A-Za-z0-9_-]{40,}$/.test(link),link.slice(0,120));
chk('explication « sans serveur » dans la fenêtre',/Sans serveur/.test(await A.innerText('#mf')));
await A.click('#mf .mf .btn:not(.ghost)').catch(()=>{});
// 2. le client, sur un AUTRE appareil (contexte vierge, aucun stockage)
const cb=await b.newContext({viewport:{width:390,height:844},geolocation:{latitude:5.3571,longitude:-3.981,accuracy:25},permissions:['geolocation']});await cb.addInitScript(()=>{navigator.canShare=d=>!!(d&&d.files&&d.files.length);navigator.share=async d=>{window.__shared={n:d.files.length,text:d.text,type:d.files[0]&&d.files[0].type}}});const B=await cb.newPage();B.on('pageerror',e=>er.push('B:'+e.message));
await B.goto(link);await B.waitForSelector('#o_send');
let bt=await B.innerText('body');chk('autre appareil : la page de commande s\'affiche (plus d\'« appareil de démonstration »)',/Commander chez/.test(bt)&&!/appareil de démonstration/.test(bt));
chk('sélecteur de capture présent sur chaque article',/partira avec votre message/.test(bt)&&await B.locator('.ol input[type=file]').count()===1);
chk('zones du fournisseur proposées',await B.locator('#o_zone option').count()>=3);
await B.fill('.ol .o_d','Robe wax');const png=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==','base64');await B.setInputFiles('.ol input[type=file]',{name:'capture.png',mimeType:'image/png',buffer:png});await B.waitForTimeout(500);chk('capture ajoutée à l\'article',await B.locator('.ol img').count()===1);await B.fill('.ol .o_q','2');await B.fill('.ol .o_p','15000');
await B.click('button:has-text("Ajouter un article")');await B.locator('.ol .o_d').nth(1).fill('Foulard à pois');
await B.fill('#o_nom','Awa Koné');await B.fill('#o_tel','07 07 55 66 77');await B.selectOption('#o_zone','Cocody');await B.fill('#o_rep','Portail bleu');
await B.click('button:has-text("Utiliser ma position")');await B.waitForTimeout(600);await B.fill('#o_note','Après 17 h');
await B.click('#o_send');await B.waitForTimeout(400);bt=await B.innerText('body');
chk('étape finale : bouton message + captures',/Dernière étape/.test(bt)&&await B.locator('#o_share').count()===1&&/1 capture/.test(bt));
await B.click('#o_share');await B.waitForTimeout(300);const sh=await B.evaluate(()=>window.__shared);chk('partage natif : 1 capture + message avec marqueur',sh&&sh.n===1&&/image\//.test(sh.type)&&/\[ANGELS:/.test(sh.text)&&/1 capture\(s\) d'écran jointe/.test(sh.text),sh);
const wa=await B.getAttribute('p a[href^="https://wa.me"]','href');
chk('WhatsApp ouvert vers le numéro du vendeur',/^https:\/\/wa\.me\/225\d{10}\?text=/.test(wa),wa.slice(0,60));
const msg=decodeURIComponent(wa.split('?text=')[1]);
chk('message lisible : client, articles, position',/Awa Koné/.test(msg)&&/2 x Robe wax \(15 000 F\)/.test(msg)&&/1 x Foulard à pois/.test(msg)&&/maps\.google\.com\/\?q=5\.3571,-3\.981/.test(msg)&&/\[ANGELS:/.test(msg),msg);
// 3. le fournisseur colle le message reçu dans « Saisie depuis WhatsApp »
await A.evaluate(()=>{view='mesCmd';render()});await A.evaluate(()=>ACT.waOpen());await A.waitForSelector('textarea');
await A.fill('textarea',msg);await A.click('#mf .mf .btn:not(.ghost)');await A.waitForSelector('[data-wf="0:nom"]');
chk('brouillon prérempli depuis le message',(await A.inputValue('[data-wf="0:nom"]'))==='Awa Koné'&&(await A.inputValue('[data-wf="0:tel"]'))==='0707556677'&&(await A.inputValue('[data-wf="0:zone"]'))==='Cocody'&&(await A.inputValue('[data-wf="0:repere"]'))==='Portail bleu'&&(await A.inputValue('[data-wl="0:0:desig"]'))==='Robe wax'&&(await A.inputValue('[data-wl="0:0:qte"]'))==='2'&&(await A.inputValue('[data-wl="0:0:pu"]'))==='15000'&&(await A.inputValue('[data-wl="0:1:desig"]'))==='Foulard à pois');
t=await A.innerText('body');chk('position GPS reconnue et prix manquant signalé',/Position GPS envoyée par le client/.test(t)&&/prix à fixer/.test(t));
await A.click('#mf .mf .btn:not(.ghost)');await A.waitForTimeout(300);chk('prix manquant : création refusée',await A.evaluate(()=>!S.commandes.some(c=>cli(c.client_id).nom==='Awa Koné')));
await A.fill('[data-wl="0:1:pu"]','3000');await A.click('#mf .mf .btn:not(.ghost)');await A.waitForTimeout(500);
const c=await A.evaluate(()=>{const c=S.commandes.find(c=>cli(c.client_id).nom==='Awa Koné');return c&&{gps:c.adr.gps,tot:c.lignes.reduce((a,l)=>a+l.qte*l.pu,0),st:c.statut,rep:c.adr.repere,obs:c.obs}});
chk('commande créée avec position GPS et montants',c&&c.gps&&c.gps.lat===5.3571&&c.tot===33000&&c.st==='attente'&&c.rep==='Portail bleu'&&/17 h/.test(c.obs),c);
// 4. anciens liens et protections
const cc=await b.newContext();const D=await cc.newPage();await D.goto(URL+'#commande=n_importe_quoi');await D.waitForTimeout(300);chk('lien corrompu : message clair',/indisponible/.test(await D.innerText('body')));
// injection : le texte du client reste du texte
const cd=await b.newContext();const E=await cd.newPage();E.on('pageerror',e=>er.push('E:'+e.message));
const evil={o:'<img src=x onerror=window.__x=1>',w:'',v:'<b id=pwn>V</b>',t:'0707000000',z:['<i>Zone</i>']};
await E.goto(URL+'#commande='+await A.evaluate(o=>b64(o),evil));await E.waitForSelector('#o_send');chk('contenu du lien échappé (pas d\'injection HTML)',await E.locator('#pwn').count()===0&&await E.evaluate(()=>!window.__x));
chk('aucune erreur JS',er.length===0,er);
console.log(ok+' ok / '+ko+' échecs');await b.close()})();
