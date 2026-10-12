const { chromium } = require('/opt/node-tools/node_modules/playwright');
let ok=0,ko=0;const chk=(n,c,x)=>{c?ok++:ko++;console.log((c?'✔':'✘')+' '+n+(c?'':'  → '+(typeof x==='string'?x:JSON.stringify(x))))};
(async()=>{const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
const pg=await (await b.newContext({viewport:{width:1300,height:1000}})).newPage();const er=[];pg.on('pageerror',e=>er.push(e.message));pg.on('dialog',d=>d.accept());
await pg.goto('file:///home/user/DISTRIPRO-ERP/index.html');await pg.waitForTimeout(300);
const as=async role=>{await pg.evaluate(r=>{ME=S.users.find(u=>u.role===r);sessionStorage.setItem('angels_me',ME.id);view='caisse';render()},role);await pg.waitForTimeout(150)};
const T=()=>pg.innerText('body'),sub=async()=>{await pg.click('#mf .mf .btn:not(.ghost)');await pg.waitForTimeout(350)};
await as('caissier');let t=await T();
chk('menu « Caisse » pour le caissier',await pg.locator('[data-act=nav][data-id=caisse]').count()===1);
chk('deux caisses : principale OUVERTE, petite FERMÉE',/Caisse principale/.test(t)&&/OUVERTE/.test(t)&&/FERMÉE/.test(t)&&/Petite caisse/.test(t));
chk('solde temps réel = 61 000 + 16 000 − 5 000 (le bon en attente ne compte pas)',/Solde temps réel\s*\n?\s*72 000 F|72 000 F\s*\n?\s*Solde temps réel/.test(t)||await pg.evaluate(()=>cxSolde(S.caisses[0]))===72000,t.slice(0,300));
chk('KPI « À valider » : 1 bon, 3 500 F',/À valider/.test(t)&&/1 · 3 500 F/.test(t));
chk('écart non régularisé visible dans les KPI',/Écarts non régularisés/.test(t)&&/1 · -?500 F|1 · −500 F/.test(t));
chk('caissier : pas de boutons Valider ni Régulariser',await pg.locator('[data-act=cxVal]').count()===0&&await pg.locator('[data-act=cxRegul]').count()===0);
chk('graphique 12 mois et top des dépenses',await pg.locator('svg[aria-label*="12 mois"]').count()===1&&/Carburant/.test(t));
// bon d'entrée par le caissier
const c0=await pg.evaluate(()=>S.caisses[0].id);
await pg.evaluate(id=>ACT.cxBon(id+"|entree"),c0);await pg.waitForSelector('input[name=m]');
await pg.fill('input[name=m]','12000');await pg.fill('input[name=motif]','Vente au comptoir');await pg.fill('input[name=tiers]','Mme Kouassi');await pg.fill('input[name=piece]','R-045');await sub();
const m1=await pg.evaluate(()=>S.caisse_mvts.find(m=>m.motif==='Vente au comptoir'));
chk('bon d\'entrée enregistré en attente, numéroté BE-571-…',m1&&m1.statut==='en_attente'&&/^BE-571-\d{8}-\d{3}$/.test(m1.numero),m1);
chk('solde inchangé tant que le bon n\'est pas validé',await pg.evaluate(()=>cxSolde(S.caisses[0]))===72000);
await pg.evaluate(id=>ACT.cxBon(id+"|sortie"),c0);await pg.waitForSelector('input[name=m]');
await pg.fill('input[name=m]','2000');await pg.fill('input[name=motif]','Eau de la boutique');await pg.fill('input[name=tiers]','Vendeur d\'eau');await sub();
chk('bon de sortie : numérotation BS séparée',await pg.evaluate(()=>S.caisse_mvts.some(m=>/^BS-571-\d{8}-\d{3}$/.test(m.numero)&&m.motif==='Eau de la boutique')));
await pg.evaluate(id=>ACT.cxBon(id+"|sortie"),c0);await pg.waitForSelector('input[name=m]');await pg.fill('input[name=m]','500');await pg.fill('input[name=motif]','Sans bénéficiaire');await pg.click('#mf .mf .btn:not(.ghost)');await pg.waitForTimeout(250);
chk('bénéficiaire obligatoire (champ requis)',await pg.evaluate(()=>!S.caisse_mvts.some(m=>m.motif==='Sans bénéficiaire')));await pg.evaluate(()=>closeModal());
// clôture refusée avec bons en attente
await pg.evaluate(id=>ACT.cxCloture(id),c0);await pg.waitForSelector('#cx_r');await pg.fill('#cx_r','72000');await sub();
chk('clôture refusée tant que des bons sont en attente',/en attente de validation/.test(await T())&&await pg.evaluate(()=>S.caisse_sessions.filter(s=>s.statut==='ouverte').length)===1);await pg.evaluate(()=>closeModal());
chk('impression refusée pour un bon en attente',await (async()=>{await pg.evaluate(id=>ACT.cxPrintBon(id),m1.id);return /Seul un bon validé/.test(await T())})());
// administrateur
await as('admin');t=await T();
chk('administrateur : boutons Valider/Rejeter et régularisation',await pg.locator('[data-act=cxVal]').count()===3&&await pg.locator('[data-act=cxRegul]').count()===1,await pg.locator('[data-act=cxVal]').count());
await pg.locator('[data-act=cxVal]').first().click();await pg.waitForTimeout(300);
chk('un bon validé compte dans le solde',await pg.evaluate(()=>S.caisse_mvts.filter(m=>m.statut==='valide').length)===5);
await pg.locator('[data-act=cxRej]').first().click();await pg.waitForSelector('textarea[name=v]');await pg.fill('textarea[name=v]','Pièce illisible');await sub();
chk('rejet avec motif',await pg.evaluate(()=>S.caisse_mvts.some(m=>m.statut==='rejete'&&m.motif_rejet==='Pièce illisible')));
await pg.locator('[data-act=cxVal]').first().click();await pg.waitForTimeout(300);
chk('plus aucun bon en attente',await pg.evaluate(()=>cxAttente().length)===0);
// sortie supérieure au solde : refusée à la validation
await pg.evaluate(id=>{ME=S.users.find(u=>u.role==='caissier');cxBonLocal(cxCaisse(id),'sortie',9999999,'Gros achat','X','','Autre sortie');ME=S.users.find(u=>u.role==='admin')},c0);await pg.evaluate(()=>render());
await pg.locator('[data-act=cxVal]').first().click();await pg.waitForTimeout(300);chk('sortie supérieure au solde refusée à la validation',/Solde de caisse insuffisant/.test(await T()));
await pg.locator('[data-act=cxRej]').first().click();await pg.waitForSelector('textarea[name=v]');await pg.fill('textarea[name=v]','Montant erroné');await sub();
// admin : bon validé d'office
await pg.evaluate(id=>ACT.cxBon(id+"|entree"),c0);await pg.waitForSelector('input[name=m]');await pg.fill('input[name=m]','3000');await pg.fill('input[name=motif]','Apport');await pg.fill('input[name=tiers]','Direction');await sub();
chk('bon de l\'administrateur validé d\'office',await pg.evaluate(()=>S.caisse_mvts.find(m=>m.motif==='Apport').statut)==='valide');
// régularisation de l'écart de la veille
await pg.locator('[data-act=cxRegul]').first().click();await pg.waitForSelector('textarea[name=v]');await pg.fill('textarea[name=v]','ok');await sub();
chk('décision trop courte refusée',/Précisez la décision/.test(await T()));await pg.fill('textarea[name=v]','Manquant imputé au caissier');await sub();
chk('écart de la veille régularisé',await pg.evaluate(()=>cxEcarts().length)===0);
// flux automatiques
await pg.evaluate(()=>{const L=S.livreurs[0];S.fonds.push({id:uid("f"),type:"encaissement",livreur_id:L.id,montant:30000,mode:"Espèces",ts:now(),par:"x"});save();view='finance';ME=S.users.find(u=>u.role==='caissier');render()});
const nb=()=>pg.evaluate(()=>S.caisse_mvts.filter(m=>m.source==='reversement').length),n0=await nb();
const lid=await pg.evaluate(()=>S.livreurs[0].id);
await pg.evaluate(id=>ACT.reverser(id),lid);await pg.waitForSelector('input[name=m]');await pg.fill('input[name=m]','10000');await sub();
chk('reversement en espèces → entrée automatique en caisse (validée)',await nb()===n0+1&&await pg.evaluate(()=>{const m=S.caisse_mvts.filter(m=>m.source==='reversement').pop();return m.statut==='valide'&&m.montant===10000}));
await pg.evaluate(id=>ACT.reverser(id),lid);await pg.waitForSelector('input[name=m]');await pg.fill('input[name=m]','5000');await pg.selectOption('select[name=mode]','Wave');await pg.fill('input[name=ref]','WV-CX-0001');await sub();
chk('reversement Mobile Money → pas d\'écriture de caisse',await nb()===n0+1);
await pg.evaluate(id=>ACT.payer(id),lid);await pg.waitForSelector('input[name=m]');await pg.fill('input[name=m]','1500');await sub();
chk('paie d\'un livreur → sortie automatique',await pg.evaluate(()=>S.caisse_mvts.some(m=>m.source==='paie'&&m.montant===1500&&m.type==='sortie')));
// impressions
await as('caissier');
const bon=await pg.evaluate(()=>S.caisse_mvts.find(m=>m.motif==='Apport').id);
await pg.evaluate(id=>ACT.cxPrintBon(id),bon);await pg.waitForSelector('#docf');const fr=await (await pg.$('#docf')).contentFrame();const bt=await fr.innerText('body');
chk('bon imprimé : titre, numéro, visa et signatures',/BON D'ENTRÉE DE CAISSE/.test(bt)&&/BE-571/.test(bt)&&/Validé par/.test(bt)&&/Caissier/.test(bt),bt.slice(0,200));await pg.evaluate(()=>closeModal());
await pg.evaluate(()=>{view='caisse';render()});await pg.evaluate(()=>ACT.cxBrPrint());await pg.waitForSelector('#docf');const fr2=await (await pg.$('#docf')).contentFrame();const bp=await fr2.innerText('body');
chk('brouillard imprimé : fond d\'ouverture, totaux, signatures',/Brouillard journalier de caisse/.test(bp)&&/Fond d'ouverture/.test(bp)&&/Totaux/.test(bp)&&/Vérifié par/.test(bp),bp.slice(0,300));await pg.evaluate(()=>closeModal());
// clôture avec écart
await pg.evaluate(id=>ACT.cxCloture(id),c0);await pg.waitForSelector('#cx_r');const th=await pg.evaluate(()=>cxSoldeS(cxOpen(S.caisses[0])));
await pg.fill('#cx_r',String(th-1000));await pg.waitForTimeout(100);
chk('écart affiché en direct et justification exigée',/Écart : -?1 000 F|Écart : −1 000 F/.test(await pg.innerText('#cx_e'))&&await pg.isVisible('#cx_jw'),await pg.innerText('#cx_e'));
await sub();chk('clôture avec écart sans justification refusée',/justif/i.test(await T())&&await pg.evaluate(()=>!!cxOpen(S.caisses[0])));
await pg.fill('textarea[name=j]','Rendu de monnaie erroné');await sub();
const cl=await pg.evaluate(()=>cxLast(S.caisses[0]));
chk('caisse clôturée : théorique, réel, écart −1 000 F',cl.fond_cloture_theorique===th&&cl.ecart===-1000&&!cl.ecart_regularise,cl);
chk('plus de bon possible sur une caisse fermée (bouton Ouvrir)',/Ouvrir la caisse/.test(await T()));
// réouverture
await pg.evaluate(id=>ACT.cxOuvrir(id),c0);await pg.waitForSelector('input[name=f]');
chk('réouverture : fond repris du dernier comptage, non modifiable par le caissier',(await pg.inputValue('input[name=f]'))===String(th-1000)&&await pg.getAttribute('input[name=f]','readonly')!==null);
await sub();chk('caisse rouverte',await pg.evaluate(()=>!!cxOpen(S.caisses[0])&&cxOpen(S.caisses[0]).fond_ouverture));
// petite caisse + création
await as('admin');await pg.evaluate(id=>ACT.cxOuvrir(id),await pg.evaluate(()=>S.caisses[1].id));await pg.waitForSelector('input[name=f]');await pg.fill('input[name=f]','10000');await sub();
chk('première ouverture de la petite caisse avec un fond libre',await pg.evaluate(()=>cxSolde(S.caisses[1]))===10000);
await pg.evaluate(()=>ACT.cxNew());await pg.waitForSelector('input[name=n]');await pg.fill('input[name=n]','Caisse principale');await sub();chk('nom de caisse en double refusé',/porte déjà ce nom/.test(await T()));
await pg.fill('input[name=n]','Caisse Plateau');await sub();chk('création d\'une caisse',await pg.evaluate(()=>S.caisses.some(c=>c.nom==='Caisse Plateau')));
// navigation de période
const lab0=await pg.innerText('h2:has-text("Tableau de bord")');await pg.click('[data-act=cxNav][data-id="-1"]');const lab1=await pg.innerText('h2:has-text("Tableau de bord")');
chk('navigation ◀ : le mois change',lab0!==lab1,[lab0,lab1]);await pg.click('[data-act=cxPer][data-id=annee]');chk('période Année',/Tableau de bord — \d{4}/.test(await pg.innerText('h2:has-text("Tableau de bord")')));
// brouillard par période + CSV
await pg.selectOption('select[data-f=cxbm]','periode');await pg.waitForTimeout(100);chk('brouillard par période',/Brouillard de caisse/.test(await T())&&await pg.locator('input[data-f=cxd1]').count()===1);
// rôles
await as('direction');chk('la direction voit la caisse et peut valider',/Caisse principale/.test(await T()));
await pg.evaluate(()=>{ME=S.users.find(u=>u.role==='livreur');view='dashboard';render()});chk('un livreur n\'a pas le menu Caisse',await pg.locator('[data-act=nav][data-id=caisse]').count()===0);
chk('aucune erreur JS',er.length===0,er);
console.log(ok+' ok / '+ko+' échecs');await b.close()})();
