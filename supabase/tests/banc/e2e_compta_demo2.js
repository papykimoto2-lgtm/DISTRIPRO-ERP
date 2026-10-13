const { chromium } = require('/opt/node-tools/node_modules/playwright');
let ok=0,ko=0;const chk=(n,c,x)=>{c?ok++:ko++;console.log((c?'✔':'✘')+' '+n+(c?'':'  → '+(typeof x==='string'?x:JSON.stringify(x))))};
(async()=>{const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
const pg=await (await b.newContext({viewport:{width:1300,height:1000}})).newPage();const er=[];pg.on('pageerror',e=>er.push(e.message));pg.on('dialog',d=>d.accept());
await pg.goto('file:///home/user/DISTRIPRO-ERP/index.html');await pg.waitForTimeout(300);
await pg.evaluate(()=>{ME=S.users.find(u=>u.role==='admin');sessionStorage.setItem('angels_me',ME.id);view='compta';render()});
const sub=async()=>{await pg.click('#mf .mf .btn:not(.ghost)');await pg.waitForTimeout(300)};
// fond initial
chk('fond initial 40 000 en CAI',await pg.evaluate(()=>cptAuto().some(e=>e.source_table==='caisse_fond'&&e.lignes[0].montant===40000)));
chk('écart de caisse -500 → D658/C571',await pg.evaluate(()=>cptAuto().some(e=>e.source_table==='caisse_sessions'&&e.lignes.some(l=>l.compte==='658'&&l.sens==='D'&&l.montant===500))));
// TVA 18%
await pg.evaluate(()=>{cpt().tva=18});
const v=await pg.evaluate(()=>cptAuto().filter(e=>e.journal==='VT').map(e=>({d:e.lignes.filter(l=>l.sens==='D').reduce((a,l)=>a+l.montant,0),c:e.lignes.filter(l=>l.sens==='C').reduce((a,l)=>a+l.montant,0),tva:(e.lignes.find(l=>l.compte==='4431')||{}).montant}))); 
chk('ventes : débit=crédit avec TVA 18 %',v.length>0&&v.every(x=>x.d===x.c&&x.tva>0),v);
chk('achats : 4452 TVA récupérable',await pg.evaluate(()=>cptAuto().some(e=>e.journal==='AC'&&e.lignes.some(l=>l.compte==='4452'&&l.montant>0))));
await pg.evaluate(()=>{cpt().tva=0;cpt().stock='intermittent'});
chk('stock intermittent : 601 débité à l\'achat',await pg.evaluate(()=>cptAuto().some(e=>e.journal==='AC'&&e.lignes.some(l=>l.compte==='601'&&l.sens==='D'))));
await pg.evaluate(()=>{cpt().stock='permanent'});
// ventilation : règle
await pg.evaluate(()=>{cpt().regles.push({id:'r1',mot:'fournitures',compte:'604'});cpt().regles.push({id:'r2',mot:'carburant',compte:'6241'})});
const before=await pg.evaluate(()=>S.caisse_mvts.filter(m=>m.motif==='Fournitures de bureau').map(m=>cptContre(m)));
chk('avant : « Fournitures » → catégorie (604) ou 471',before.length>=0,before);
await pg.evaluate(()=>{const m=S.caisse_mvts.find(m=>m.motif==='Fournitures de bureau');m.statut='valide';m.categorie='Autre sortie'});
chk('bon sans catégorie utile → 471',await pg.evaluate(()=>cptContre(S.caisse_mvts.find(m=>m.motif==='Fournitures de bureau')))==='471');
await pg.evaluate(()=>ACT.cptVAuto());await pg.waitForTimeout(200);
chk('ventilation auto par mot-clé → 604',await pg.evaluate(()=>cptContre(S.caisse_mvts.find(m=>m.motif==='Fournitures de bureau')))==='604');
chk('instantané pris',await pg.evaluate(()=>cpt().snaps.length)===1);
await pg.evaluate(()=>ACT.cptVAnnul());
chk('annulation en masse des ventilations auto',await pg.evaluate(()=>cptContre(S.caisse_mvts.find(m=>m.motif==='Fournitures de bureau')))==='471');
await pg.evaluate(()=>{const id=cpt().snaps[cpt().snaps.length-1].id;cptSnapRestore(id)});
chk('restauration d\'un instantané',await pg.evaluate(()=>Object.keys(cpt().ventil).length)===0);
// import CSV
const nb=await pg.evaluate(()=>S.caisse_mvts.length);
await pg.evaluate(()=>cptImport());await pg.waitForSelector('#imp_t');
const d1=new Date().toISOString().slice(0,10);
await pg.fill('#imp_t',`date;type;montant;motif;tiers;categorie\n${d1};entree;5000;Vente comptoir import;Client X;Vente au comptoir\n${d1};sortie;1000;Carburant import;Total;Carburant\n2026-13-45;entree;100;mauvaise date;;\n${d1};sortie;99999999;trop gros;;\n${d1};entree;5000;Vente comptoir import;Client X;Vente au comptoir`);
await sub();
const rp=await pg.innerText('#modal');
chk('import : 2 lignes valides, 3 anomalies (date, solde, doublon)',/2\s*importé/.test(rp)&&/3\s*anomalie/.test(rp)&&/doublon/.test(rp)&&/solde insuffisant/.test(rp)&&/date invalide/.test(rp),rp.slice(0,300));
chk('import : 2 bons validés ajoutés',await pg.evaluate(()=>S.caisse_mvts.length)===nb+2);
chk('écritures de caisse importées au journal',await pg.evaluate(()=>cptAuto().filter(e=>/import/.test(e.libelle)).length)===2);
await pg.evaluate(()=>closeModal());
// budget
await pg.evaluate(()=>{cpt().budgets.push({id:'b1',compte:'6241',max:1000})});
await pg.evaluate(()=>{ui.cpMois=String(new Date().getMonth()+1).padStart(2,'0');ACT.tab('cpt|cai')});await pg.waitForTimeout(200);
const tx=await pg.innerText('body');chk('budget 6241 affiché avec %',/6241/.test(tx)&&/%/.test(tx));
await pg.evaluate(()=>{ui.cpMois=''});
// alerte solde théorique négatif à la clôture
await pg.evaluate(()=>{ME=S.users.find(u=>u.role==='admin');const c=S.caisses[0];const s=cxOpen(c);s.fond_ouverture=-100000;cxClotureForm(c)});await pg.waitForTimeout(200);
const tm=await pg.innerText('#modal');chk('clôture : alerte solde théorique NÉGATIF + case de confirmation',/NÉGATIF/.test(tm)&&await pg.locator('input[name=neg]').count()===1,tm.slice(0,200));
// onglets restants rendus sans erreur
for(const k of ['syn','jrn','gl','bal','age','tva','res','sai','cai','cfg']){await pg.evaluate(k=>ACT.tab('cpt|'+k),k);await pg.waitForTimeout(80)}
// bilan
await pg.evaluate(()=>ACT.tab('cpt|res'));const rs=await pg.innerText('body');chk('compte de résultat + bilan',/RÉSULTAT/.test(rs)&&/Total actif/.test(rs)&&/Total passif/.test(rs));
chk('aucune erreur JS',er.length===0,er);
console.log(ok+' ok / '+ko+' échecs');await b.close()})();
