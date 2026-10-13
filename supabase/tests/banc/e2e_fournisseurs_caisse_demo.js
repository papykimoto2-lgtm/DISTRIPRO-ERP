const { chromium } = require('/opt/node-tools/node_modules/playwright');
let ok=0,ko=0;const chk=(n,c,x)=>{c?ok++:ko++;console.log((c?'✔':'✘')+' '+n+(c?'':'  → '+(typeof x==='string'?x:JSON.stringify(x))))};
(async()=>{const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
const ctx=await b.newContext({viewport:{width:1300,height:1000}});await ctx.addInitScript(()=>{window.__SANS_OFFRE=true});
const pg=await ctx.newPage();const er=[];pg.on('pageerror',e=>er.push(e.message));pg.on('dialog',d=>d.accept());
await pg.goto('file:///home/user/DISTRIPRO-ERP/index.html');await pg.waitForTimeout(300);
const as=async(role,v)=>{await pg.evaluate(([r,v])=>{ME=S.users.find(u=>u.role===r);sessionStorage.setItem('angels_me',ME.id);view=v||'caisse';render()},[role,v]);await pg.waitForTimeout(150)};
const sub=async()=>{await pg.click('#mf .mf .btn:not(.ghost)');await pg.waitForTimeout(350)};
await as('caissier');
const due=await pg.evaluate(()=>S.vendeurs.map(v=>({id:v.id,nom:v.nom,r:vendDue(v).restant,n:vendDue(v).elig.length})).filter(x=>x.r>0));
chk('la liste « Fournisseurs à régler » existe dans la Caisse',await pg.locator('h2:has-text("Fournisseurs à régler")').count()===1&&due.length>=1,due);
let t=await pg.innerText('main');
chk('fournisseur, nombre de commandes, net acquis, déjà réglé et reste à régler affichés',due.every(d=>t.includes(d.nom))&&/Reste à régler/.test(t)&&/Net acquis/.test(t)&&/Déjà réglé/.test(t));
const tot=due.reduce((a,d)=>a+d.r,0);
chk('KPI « À régler aux fournisseurs » = total des restes',new RegExp(tot.toLocaleString('fr-FR').replace(/[\s  ]/g,'[\\s\\u202f\\u00a0]')).test(t)&&/À régler aux fournisseurs/.test(t),tot);
chk('information : paiement en espèces = sortie de la caisse principale',/sortie de la caisse « Caisse principale »/.test(t));
const aya=due[0];
await pg.locator(`tr:has-text("${aya.nom}") [data-act=vDet]`).click();await pg.waitForSelector('#modal table');
chk('détail : commandes livrées avec leur net, règlements déjà faits',/Commandes livrées et encaissées/.test(await pg.innerText('#modal'))&&/Règlements déjà faits/.test(await pg.innerText('#modal'))&&await pg.locator('#modal tbody tr').count()>=1);await pg.evaluate(()=>closeModal());
// règlement partiel en espèces
const so0=await pg.evaluate(()=>cxSolde(cxCaissePrinc()));
await pg.locator(`tr:has-text("${aya.nom}") [data-act=vReg]`).click();await pg.waitForSelector('input[name=m]');
chk('formulaire : reste, caisse, solde',/Reste à régler/.test(await pg.innerText('#mf'))&&/Caisse principale/.test(await pg.innerText('#mf')));
await pg.fill('input[name=m]',String(aya.r+1));await sub();chk('montant supérieur au reste refusé',await pg.evaluate(()=>S.reglements.length)===0||/Montant invalide/.test(await pg.innerText('body')));
await pg.fill('input[name=m]','10000');await sub();
const rg=await pg.evaluate(id=>S.reglements.filter(r=>r.vendeur_id===id).pop(),aya.id);
chk('règlement partiel enregistré (10 000 F, espèces)',rg&&rg.montant===10000&&/^esp/i.test(rg.mode),rg);
const mv=await pg.evaluate(()=>S.caisse_mvts.filter(m=>m.source==='reglement_vendeur').pop());
chk('sortie automatique dans la caisse (validée, catégorie « Règlement vendeur »)',mv&&mv.type==='sortie'&&mv.montant===10000&&mv.statut==='valide'&&mv.categorie==='Règlement vendeur',mv);
chk('le solde de la caisse baisse de 10 000 F',await pg.evaluate(()=>cxSolde(cxCaissePrinc()))===so0-10000);
chk('le reste à régler baisse de 10 000 F',await pg.evaluate(id=>vendDue(vendOf(id)).restant,aya.id)===aya.r-10000);
// solde de caisse insuffisant
await pg.evaluate(()=>{const c=cxCaissePrinc();const s=cxSolde(c);caisseAuto('sortie',s-1000,'Retrait test','x','Autre sortie','paie','zz'+Date.now())});await pg.evaluate(()=>render());
await pg.locator(`tr:has-text("${aya.nom}") [data-act=vReg]`).click();await pg.waitForSelector('input[name=m]');await pg.fill('input[name=m]','5000');await sub();
chk('espèces > solde de caisse : refusé avec le solde disponible',/Solde de caisse insuffisant/.test(await pg.innerText('body'))&&await pg.evaluate(id=>S.reglements.filter(r=>r.vendeur_id===id).length,aya.id)===1);
await pg.selectOption('select[name=mode]',{label:'Wave'});await sub();
chk('même montant par Mobile Money : accepté, sans écriture de caisse',await pg.evaluate(id=>S.reglements.filter(r=>r.vendeur_id===id).length,aya.id)===2&&await pg.evaluate(()=>S.caisse_mvts.filter(m=>m.source==='reglement_vendeur').length)===1);
// caisse fermée
await as('admin');await pg.evaluate(()=>{cxAttente().forEach(m=>{try{cxValiderLocal(m.id,'rejeter','test')}catch(e){}});const s=cxOpen(cxCaissePrinc());cxCloturerLocal(s.id,cxSoldeS(s),'');save();render()});
await as('caissier');t=await pg.innerText('main');chk('caisse fermée : avertissement dans la liste',/Aucune caisse ouverte : les règlements en espèces sont bloqués/.test(t));
const n0=await pg.evaluate(id=>S.reglements.filter(r=>r.vendeur_id===id).length,aya.id);
await pg.locator(`tr:has-text("${aya.nom}") [data-act=vReg]`).click();await pg.waitForSelector('input[name=m]');chk('le formulaire prévient que la caisse est fermée',/Aucune caisse ouverte/.test(await pg.innerText('#mf')));await pg.fill('input[name=m]','1000');await sub();
chk('espèces avec caisse fermée : refusé',/Aucune caisse ouverte : ouvrez la caisse/.test(await pg.innerText('body'))&&await pg.evaluate(id=>S.reglements.filter(r=>r.vendeur_id===id).length,aya.id)===n0);await pg.evaluate(()=>closeModal());
// Finance > Vendeurs garde le même règlement ; direction : lecture seule
await as('caissier','finance');await pg.click('.tabs [data-id="fin|ven"]');chk('Finance > Vendeurs : bouton de règlement toujours présent',await pg.locator('[data-act=vReg]').count()>=1);
await as('direction');chk('direction : voit la liste sans bouton « Régler »',await pg.locator('h2:has-text("Fournisseurs à régler")').count()===1&&await pg.locator('[data-act=vReg]').count()===0);
await as('commercial','accueil');chk('un commercial n\'a pas accès à la Caisse',await pg.locator('[data-act=nav][data-id=caisse]').count()===0);
chk('aucune erreur JS',er.length===0,er);console.log(ok+' ok / '+ko+' échecs');await b.close()})();
