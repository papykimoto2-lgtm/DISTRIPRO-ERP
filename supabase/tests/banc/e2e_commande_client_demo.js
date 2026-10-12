const { chromium } = require('/opt/node-tools/node_modules/playwright');
let ok=0,ko=0;const chk=(n,c,x)=>{c?ok++:ko++;console.log((c?'✔':'✘')+' '+n+(c?'':'  → '+(typeof x==='string'?x:JSON.stringify(x))))};
(async()=>{const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
const ctx=await b.newContext({viewport:{width:420,height:900},acceptDownloads:true,geolocation:{latitude:5.3571,longitude:-3.981,accuracy:25},permissions:['geolocation']});
const A=await ctx.newPage();const er=[];A.on('pageerror',e=>er.push('A:'+e.message));A.on('dialog',d=>d.accept());
const URL='file:///home/user/DISTRIPRO-ERP/index.html';
await A.goto(URL);await A.waitForTimeout(300);
const vid=await A.evaluate(()=>{const u=S.users.find(u=>u.role==='vendeur');ME=u;sessionStorage.setItem('angels_me',u.id);view='mesCmd';render();return vend().id});
await A.setViewportSize({width:1280,height:950});
let t=await A.innerText('body');
chk('section « Demandes reçues » avec la demande de démonstration',/Demandes reçues de vos clients \(1\)/.test(t)&&/Mme Traoré/.test(t)&&/prix à fixer/.test(t));
chk('position GPS jointe signalée',/position GPS/.test(t));
await A.click('button:has-text("Lien de commande client")');await A.waitForSelector('#mf input[readonly]');
const link=await A.inputValue('#mf input[readonly]');chk('lien de commande avec QR code',/#commande=/.test(link)&&await A.locator('#mf svg').count()>0,link);
await A.click('#mf .mf .btn:not(.ghost)').catch(()=>{});
// --- le client ouvre le lien
const B=await ctx.newPage();B.on('pageerror',e=>er.push('B:'+e.message));
await B.goto(link);await B.waitForSelector('#o_send');
let bt=await B.innerText('body');chk('page publique : fournisseur, articles, position',/Commander chez/.test(bt)&&/Vos articles/.test(bt)&&/Utiliser ma position/.test(bt)&&!/Tableau de bord|Déconnexion/.test(bt));
await B.click('#o_send');chk('envoi à vide refusé (articles)',/Ajoutez au moins un article/.test(await B.innerText('#o_err')));
await B.fill('.ol .o_d','Sac à main noir');await B.fill('.ol .o_q','2');await B.fill('.ol .o_p','15000');
const png=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==','base64');
await B.setInputFiles('.ol input[type=file]',{name:'capture.png',mimeType:'image/png',buffer:png});await B.waitForTimeout(500);
chk('capture jointe à l\'article',await B.locator('.ol img').count()===1);
await B.click('button:has-text("Ajouter un article")');await B.locator('.ol .o_d').nth(1).fill('Chaussures');
chk('le 1er article conserve sa saisie après ajout',(await B.inputValue('.ol .o_d'))==='Sac à main noir'&&(await B.inputValue('.ol .o_p'))==='15000');
await B.click('#o_send');chk('nom exigé',/votre nom/.test(await B.innerText('#o_err')));
await B.fill('#o_nom','Awa Koné');await B.fill('#o_tel','07 07 55 66 77');
await B.click('#o_send');chk('zone exigée',/zone/.test(await B.innerText('#o_err')));
await B.selectOption('#o_zone','Cocody');
await B.click('#o_send');chk('localisation exigée',/quartier|repère|position/.test(await B.innerText('#o_err')));
await B.click('button:has-text("Utiliser ma position")');await B.waitForTimeout(600);
chk('position GPS enregistrée',/Position enregistrée/.test(await B.innerText('#o_gps')));
chk('les champs saisis survivent à la position',(await B.inputValue('#o_nom'))==='Awa Koné');
await B.fill('#o_note','Après 17 h svp');
await B.click('#o_send');await B.waitForTimeout(500);bt=await B.innerText('body');
chk('confirmation avec référence',/Commande envoyée/.test(bt)&&/Référence\s+[A-Z0-9]{6}/.test(bt),bt.slice(0,200));
// --- le fournisseur voit la demande
await A.reload();await A.waitForTimeout(400);
await A.evaluate(()=>{view='mesCmd';render()});t=await A.innerText('body');
chk('la demande arrive chez le fournisseur (2 en attente)',/Demandes reçues de vos clients \(2\)/.test(t)&&/Awa Koné/.test(t)&&/Après 17 h/.test(t));
const d=await A.evaluate(()=>S.demandes.find(x=>x.nom==='Awa Koné'));
chk('données conservées : lignes, prix proposé, GPS, capture',d&&d.lignes.length===2&&d.lignes[0].pu===15000&&d.lignes[1].pu===null&&d.lat===5.3571&&d.photos.length===1&&d.lignes[0].img===0&&d.lignes[1].img===null,d&&{l:d.lignes,lat:d.lat,p:d.photos.length});
chk('aucune commande créée avant validation',await A.evaluate(()=>!S.commandes.some(c=>c.client_id&&cli(c.client_id).nom==='Awa Koné')));
// --- transformation en commande
await A.evaluate(id=>ACT.demTraiter(id),d.id);await A.waitForSelector('[data-wf="0:nom"]');
t=await A.innerText('body');chk('brouillon prérempli depuis la demande',(await A.inputValue('[data-wf="0:nom"]'))==='Awa Koné'&&(await A.inputValue('[data-wf="0:zone"]'))==='Cocody'&&(await A.inputValue('[data-wl="0:0:desig"]'))==='Sac à main noir'&&/Position GPS envoyée par le client/.test(t)&&/proposition/.test(t));
await A.click('#mf .mf .btn:not(.ghost)');await A.waitForTimeout(400);
chk('prix manquant : création refusée',/articles|prix/.test(await A.innerText('body'))&&await A.evaluate(()=>!S.commandes.some(c=>cli(c.client_id).nom==='Awa Koné')));
await A.fill('[data-wl="0:1:pu"]','20000');await A.click('#mf .mf .btn:not(.ghost)');await A.waitForTimeout(500);
const c=await A.evaluate(()=>{const c=S.commandes.find(c=>cli(c.client_id).nom==='Awa Koné');return c&&{gps:c.adr.gps,ph:(c.photos||[]).length,tot:c.lignes.reduce((a,l)=>a+l.qte*l.pu,0),st:c.statut}});
chk('commande créée avec GPS, capture et montants',c&&c.gps&&c.gps.lat===5.3571&&c.ph===1&&c.tot===50000&&c.st==='attente',c);
chk('demande marquée traitée et retirée de la liste',await A.evaluate(id=>S.demandes.find(x=>x.id===id).statut==='traitee',d.id)&&/Demandes reçues de vos clients \(1\)/.test(await A.innerText('body')));
// --- refus
const d0=await A.evaluate(()=>S.demandes.find(x=>x.nom==='Mme Traoré').id);
await A.evaluate(id=>ACT.demRejeter(id),d0);await A.waitForSelector('textarea[name=v]');await A.fill('textarea[name=v]','Article indisponible');await A.click('#mf .mf .btn:not(.ghost)');await A.waitForTimeout(400);
chk('demande refusée avec motif',await A.evaluate(id=>{const x=S.demandes.find(x=>x.id===id);return x.statut==='rejetee'&&x.motif==='Article indisponible'},d0)&&!/Demandes reçues de vos clients/.test(await A.innerText('body')));
// --- limite de débit
const C=await ctx.newPage();await C.goto(link);await C.waitForSelector('#o_send');
let last='';for(let i=0;i<6;i++){await C.fill('.ol .o_d','X');await C.fill('#o_nom','Spam');await C.fill('#o_tel','0505123123');await C.selectOption('#o_zone','Cocody');await C.fill('#o_q','A');await C.click('#o_send');await C.waitForTimeout(250);last=await C.innerText('body');if(/Commande envoyée/.test(last)){await C.reload();await C.waitForSelector('#o_send')}}
chk('limite de débit par téléphone (démo)',/Trop de demandes/.test(last));
// --- lien invalide
const D=await ctx.newPage();await D.goto(URL+'#commande=inconnu');await D.waitForTimeout(300);chk('lien invalide : message clair',/indisponible/.test(await D.innerText('body')));
chk('aucune erreur JS',er.length===0,er);
console.log(ok+' ok / '+ko+' échecs');await b.close()})();
