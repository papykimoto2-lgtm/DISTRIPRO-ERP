const { chromium } = require('/opt/node-tools/node_modules/playwright');
let ok=0,ko=0;const chk=(n,c,x)=>{c?ok++:ko++;console.log((c?'✔':'✘')+' '+n+(c?'':'  → '+(x||'')))};
(async()=>{const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
const ctx=await b.newContext({viewport:{width:1280,height:900},acceptDownloads:true});const pg=await ctx.newPage();const er=[];pg.on('pageerror',e=>er.push(e.message));pg.on('dialog',d=>d.accept());
await pg.goto('file:///home/user/DISTRIPRO-ERP/index.html');await pg.waitForTimeout(400);
const as=async i=>{await pg.evaluate(()=>{ME=null;sessionStorage.clear();render()});await pg.click(`.pcard >> nth=${i}`);await pg.waitForTimeout(250)};
await as(0);
for(const [v,l] of [['journal','Journal des mouvements'],['inventaire','Inventaire'],['etats','États périodiques']])chk('menu '+l,await pg.isVisible(`aside a:has-text("${l}")`));
// journal
await pg.click('aside a:has-text("Journal des mouvements")');await pg.waitForTimeout(300);
let t=await pg.innerText('body');chk('journal : mouvements et soldes',/Entrée/.test(t)&&/Sortie/.test(t)&&(await pg.$$('tbody tr')).length>=5,t.slice(0,200));
const coh=await pg.evaluate(()=>{const r=journalLocal("2000-01-01","2100-01-01","","");return S.produits.every(p=>{const L=r.filter(x=>x.produit_id===p.id);return !L.length||L[0].solde===p.stock})});chk('solde du dernier mouvement = stock actuel',coh);
await pg.selectOption('select[data-f=jtype]','entree');await pg.waitForTimeout(200);chk('filtre type « Entrée »',(await pg.$$('tbody tr')).length>=5&&!/Sortie \(commande\)/.test(await pg.innerText('tbody')));
await pg.selectOption('select[data-f=jtype]','');
const [dl]=await Promise.all([pg.waitForEvent('download'),pg.click('button:has-text("Exporter (CSV)")')]);chk('export CSV',/journal_stock_.*\.csv/.test(dl.suggestedFilename()));
await pg.click('button:has-text("Imprimer")');await pg.waitForSelector('#docf');chk('impression : rapport',/Journal des mouvements de stock/.test(await pg.$eval('#docf',e=>e.srcdoc)));await pg.evaluate(()=>closeModal());
// entrée de stock
const p0=await pg.evaluate(()=>S.produits[1].stock);
await pg.click('button:has-text("Entrée de stock")');await pg.selectOption('select[name=p]',{index:1});await pg.fill('input[name=q]','25');await pg.fill('input[name=r]','BL-TEST-1');await pg.fill('input[name=c]','4800');await pg.click('#mf .mf .btn:not(.ghost)');await pg.waitForTimeout(300);
chk('entrée de stock : stock +25, coût mis à jour',await pg.evaluate(p=>S.produits[1].stock===p+25&&S.produits[1].cout===4800,p0));
// inventaire
await pg.click('aside a:has-text("Inventaire")');t=await pg.innerText('body');chk('historique : INV-2026-0001 validé',/INV-2026-0001/.test(t)&&/Validé/.test(t));
await pg.click('button:has-text("Voir")');await pg.waitForSelector('#docf');const rp=await pg.$eval('#docf',e=>e.srcdoc);chk('rapport d\'inventaire : écarts valorisés',/Rapport d(&#39;|')inventaire/.test(rp)&&/Valeur totale des écarts/.test(rp)&&/2 sacs éventrés/.test(rp));await pg.evaluate(()=>closeModal());
await pg.click('button:has-text("Ouvrir un inventaire")');await pg.fill('input[name=n]','Test');await pg.click('#mf .mf .btn:not(.ghost)');await pg.waitForTimeout(300);
chk('inventaire ouvert, comptage à l\'aveugle',/En cours/.test(await pg.innerText('body'))&&!(await pg.isVisible('th:has-text("Théorique")')));
chk('validation refusée tant que non compté',await (async()=>{await pg.click('button:has-text("Valider")');await pg.waitForTimeout(200);return /non compté/.test(await pg.innerText('#toasts,body'))})());
const inputs=await pg.$$('input[data-inv]');const th=await pg.evaluate(()=>invOuvert().lignes.map(l=>l.theorique));
for(let i=0;i<inputs.length;i++){const v=i===1?th[i]-3:th[i];await pg.fill(`input[data-inv]>>nth=${i}`,String(v));await pg.press(`input[data-inv]>>nth=${i}`,'Tab')}
await pg.waitForTimeout(300);chk('progression complète',new RegExp(inputs.length+' / '+inputs.length).test(await pg.innerText('#inv_prog')));
await pg.check('#inv_th');await pg.waitForTimeout(200);chk('stock théorique affiché + écart -3',/-3/.test(await pg.innerText('tbody')));
await pg.click('button:has-text("Fiche de comptage")');await pg.waitForSelector('#docf');chk('fiche de comptage imprimable',/Fiche de comptage INV-/.test(await pg.$eval('#docf',e=>e.srcdoc)));await pg.evaluate(()=>closeModal());
const st0=await pg.evaluate(()=>S.produits[1].stock);
await pg.click('button:has-text("Valider")');await pg.waitForSelector('button:has-text("Valider définitivement")');await pg.click('button:has-text("Valider définitivement")');await pg.waitForTimeout(400);
chk('inventaire validé : stock corrigé -3 et mouvement',await pg.evaluate(s=>S.produits[1].stock===s-3&&S.stock_mvts.some(m=>m.type==="inventaire"&&m.qte===-3),st0));
chk('plus d\'inventaire ouvert',await pg.evaluate(()=>!invOuvert()));
// états
await pg.click('aside a:has-text("États périodiques")');await pg.waitForTimeout(300);t=await pg.innerText('body');chk('états : stock, activité, caisse',/1\. État des stocks/.test(t)&&/2\. Activité de livraison/.test(t)&&/3\. Caisse/.test(t));
const cohe=await pg.evaluate(()=>{const r=etatStockLocal("2000-01-01",ymd(new Date()));return r.every(x=>x.ouverture+x.entrees+x.sorties+x.retours+x.ajustements+x.inventaires===x.cloture)&&r.every((x,i)=>x.cloture===S.produits[i].stock)});chk('ouverture + mouvements = clôture = stock actuel',cohe);
await pg.selectOption('select[data-f=ep]','7');await pg.waitForTimeout(200);chk('changement de période',/Période du/.test(await pg.innerText('body')));
await pg.click('button:has-text("Imprimer / PDF")');await pg.waitForSelector('#docf');chk('état imprimable',/État périodique/.test(await pg.$eval('#docf',e=>e.srcdoc)));await pg.evaluate(()=>closeModal());
const [d2]=await Promise.all([pg.waitForEvent('download'),pg.click('button:has-text("Stock (CSV)")')]);chk('export état CSV',/etat_stock_/.test(d2.suggestedFilename()));
await pg.screenshot({path:'/tmp/claude-0/t/s_etats.png'});
// droits par rôle
await as(5);chk('direction : journal et inventaire en lecture',await pg.isVisible('aside a:has-text("Inventaire")'));await pg.click('aside a:has-text("Inventaire")');chk('direction : pas de bouton d\'ouverture',!(await pg.isVisible('button:has-text("Ouvrir un inventaire")')));
await as(4);chk('caissier : états seulement',await pg.isVisible('aside a:has-text("États périodiques")')&&!(await pg.isVisible('aside a:has-text("Journal des mouvements")')));
await as(3);chk('préparateur : inventaire sans validation',await pg.isVisible('aside a:has-text("Inventaire")'));
console.log('erreurs JS',er);console.log(ok+' ok / '+ko+' échecs');await b.close()})();
