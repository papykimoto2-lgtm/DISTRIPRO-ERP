const { chromium } = require('/opt/node-tools/node_modules/playwright');
let ok=0,ko=0;const chk=(n,c,x)=>{c?ok++:ko++;console.log((c?'✔':'✘')+' '+n+(c?'':'  → '+(typeof x==='string'?x:JSON.stringify(x))))};
(async()=>{const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
const ctx=await b.newContext({viewport:{width:1280,height:950}});const pg=await ctx.newPage();const er=[];pg.on('pageerror',e=>er.push(e.message));pg.on('dialog',d=>d.accept());
await pg.addInitScript(()=>{window.__SANS_OFFRE=true});await pg.goto('file:///home/user/DISTRIPRO-ERP/index.html');await pg.waitForTimeout(300);
const as=async i=>{await pg.evaluate(()=>{ME=null;sessionStorage.clear();render()});await pg.click(`.pcard >> nth=${i}`);await pg.waitForTimeout(300)};
const T=()=>pg.innerText('body');
await as(0);chk('alerte « à collecter » au tableau de bord',/à collecter chez le vendeur/.test(await T()));
await pg.click('aside a:has-text("Centre de livraison")');await pg.waitForTimeout(200);
chk('section Collectes : vendeur avec commande confirmée',/Collectes chez les vendeurs/.test(await T())&&/M\. Diallo|CMD-/.test(await T())&&await pg.isVisible('button:has-text("Planifier la collecte")'));
await pg.click('button:has-text("Planifier la collecte")');await pg.waitForSelector('select[name=l]');
chk('formulaire : adresse pré-remplie',await pg.inputValue('input[name=q]')==='Angré 8e tranche');
await pg.fill('input[name=n]','Passer avant 16 h');await pg.click('#mf .mf .btn:not(.ghost)');await pg.waitForTimeout(400);
const col=await pg.evaluate(()=>{const c=S.collectes[0];return c&&{n:c.numero,st:c.statut,code:c.code,l:c.lignes.length,liv:c.livreur_prenom}});
chk('collecte planifiée avec code à 4 chiffres',col&&/^COL-\d{4}-0001$/.test(col.n)&&col.st==='planifiee'&&/^\d{4}$/.test(col.code)&&col.l===1,col);
chk('la commande n\'est plus « à collecter »',await pg.evaluate(()=>S.vendeurs.every(v=>aCollecter(v.id).length===0)));
// bouton préparation bloqué
const oid=await pg.evaluate(()=>S.collectes[0].lignes[0].commande_id);
await pg.evaluate(id=>{view='commandes';render();cmdDetail(id)},oid);await pg.waitForTimeout(200);chk('préparation bloquée pendant la collecte',await pg.isVisible('button:has-text("Collecte COL-")')&&!(await pg.isVisible('button:has-text("démarrer la préparation")')));await pg.evaluate(()=>closeModal());
// vendeur
await as(7);t=await T();chk('vendeur : voit sa collecte, le créneau et son code',/Collecte de mes colis/.test(t)&&t.includes(col.code)&&/Code à remettre au livreur/.test(t));
chk('vendeur : adresse de collecte affichée',/Angré 8e tranche/.test(t));
// livreur : le livreur du créneau
const lvIdx=await pg.evaluate(()=>{const c=S.collectes[0];const l=liv(c.livreur_id);return S.users.filter(u=>u.role==='livreur').findIndex(u=>u.id===l.user_id)});
const order=['admin','superviseur','commercial','preparateur','caissier','direction','livreur','vendeur'];
await pg.evaluate(()=>{ME=null;render()});
const cards=await pg.$$eval('.pcard',els=>els.map(e=>e.innerText.split('\n')[0]));
// connexion directe du livreur concerné
await pg.evaluate(()=>{const c=S.collectes[0],l=liv(c.livreur_id);ME=S.users.find(u=>u.id===l.user_id);sessionStorage.setItem("angels_me",ME.id);view="dashboard";render()});await pg.waitForTimeout(300);
t=await T();chk('livreur : carte de collecte avec vendeur, adresse, articles',/Collecte COL-/.test(t)&&/Angré 8e tranche/.test(t)&&/Pagnes/.test(t),t.slice(0,200));
await pg.click('button:has-text("Accepter")');await pg.waitForTimeout(200);chk('accepter',await pg.evaluate(()=>S.collectes[0].statut==='acceptee'));
await pg.click('button:has-text("Je pars chez le vendeur")');await pg.waitForTimeout(200);chk('en route',await pg.evaluate(()=>S.collectes[0].statut==='en_route'));
await pg.click('button:has-text("Colis collectés")');await pg.waitForSelector('input[name=code]');
await pg.fill('input[name=code]','0000');await pg.click('#mf .mf .btn:not(.ghost)');await pg.waitForTimeout(300);
chk('mauvais code : refusé, essais comptés',await pg.evaluate(()=>S.collectes[0].statut==='en_route'&&S.collectes[0].essais_code===1)&&/Code du vendeur incorrect/.test(await T()));
await pg.fill('input[name=code]',col.code);await pg.click('#mf .mf .btn:not(.ghost)');await pg.waitForTimeout(400);
chk('bon code : colis collectés',await pg.evaluate(()=>S.collectes[0].statut==='collectee'&&S.collectes[0].lignes[0].colis_collectes===1));
// préparateur : réception
await as(3);t=await T();chk('préparateur : « Collectes à réceptionner »',/Collectes à réceptionner/.test(t));
await pg.click('button:has-text("Réceptionner")');await pg.waitForSelector('input[name^=r_]');await pg.click('#mf .mf .btn:not(.ghost)');await pg.waitForTimeout(400);
chk('réception : collecte « réceptionnée », commande en préparation',await pg.evaluate(()=>S.collectes[0].statut==='recue'&&cmd(S.collectes[0].lignes[0].commande_id).statut==='preparation'));
// admin : bon imprimable, réaffectation impossible après réception
await as(0);await pg.click('aside a:has-text("Centre de livraison")');await pg.click('button:has-text("Bon")');await pg.waitForSelector('#docf');chk('bon de collecte imprimable',/Bon de collecte COL-/.test((await pg.$eval('#docf',e=>e.srcdoc)).replace(/&#39;/g,"'")));await pg.evaluate(()=>closeModal());
// nouvelle collecte puis refus du livreur et réaffectation
await pg.evaluate(()=>{const v=S.vendeurs[0];const c=creerCmdVendeur(v,{nom:"Mme Z",tel:"0505000111",zone:"Cocody",quartier:"Riviera",repere:"",ins:"",lignes:[{desig:"Robe",qte:1,pu:10000}],pay:"livraison",obs:""});setStatut(c,"confirmee");save();render()});
await pg.click('aside a:has-text("Centre de livraison")');await pg.click('button:has-text("Planifier la collecte")');await pg.waitForSelector('select[name=l]');await pg.click('#mf .mf .btn:not(.ghost)');await pg.waitForTimeout(300);
const c2=await pg.evaluate(()=>S.collectes[1].id);
await pg.evaluate(id=>{const c=S.collectes.find(x=>x.id===id),l=liv(c.livreur_id);ME=S.users.find(u=>u.id===l.user_id);view="dashboard";render()},c2);await pg.waitForTimeout(200);
await pg.click('button:has-text("Impossible")');await pg.fill('#modal textarea','Moto en panne');await pg.click('#mf .mf .btn:not(.ghost)');await pg.waitForTimeout(300);
chk('refus du livreur : collecte « non réalisée »',await pg.evaluate(id=>S.collectes.find(x=>x.id===id).statut==='echouee',c2));
await as(1);t=await T();chk('superviseur : alerte rouge « non réalisée »',/non réalisée.*à réaffecter/.test(t));
await pg.click('aside a:has-text("Centre de livraison")');await pg.click('button:has-text("Réaffecter")');await pg.waitForSelector('select[name=l]');await pg.selectOption('select[name=l]',{index:1});await pg.click('#mf .mf .btn:not(.ghost)');await pg.waitForTimeout(300);
chk('réaffectation : de nouveau planifiée',await pg.evaluate(id=>{const c=S.collectes.find(x=>x.id===id);return c.statut==='planifiee'&&c.motif==null},c2));
await pg.click('button:has-text("Annuler")');await pg.fill('#modal textarea','Vendeur injoignable');await pg.click('#mf .mf .btn:not(.ghost)');await pg.waitForTimeout(300);
chk('annulation avec motif',await pg.evaluate(id=>S.collectes.find(x=>x.id===id).statut==='annulee',c2));
// vendeur : adresse de collecte
await as(7);await pg.click('button:has-text("Modifier")');await pg.waitForSelector('input[name=q]');await pg.fill('input[name=q]','Angré 7e tranche');await pg.click('#mf .mf .btn:not(.ghost)');await pg.waitForTimeout(300);
chk('vendeur : modification de son adresse de collecte',await pg.evaluate(()=>vend().adresse_collecte.quartier==='Angré 7e tranche'));
await pg.screenshot({path:'/tmp/claude-0/t/s_col.png'});
console.log('erreurs JS',er);console.log(ok+' ok / '+ko+' échecs');await b.close()})();
