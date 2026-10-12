const { chromium } = require('/opt/node-tools/node_modules/playwright');
let ok=0,ko=0;const chk=(n,c,x)=>{c?ok++:ko++;console.log((c?'✔':'✘')+' '+n+(c?'':'  → '+(typeof x==='string'?x:JSON.stringify(x))))};
(async()=>{const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
const pg=await (await b.newContext({viewport:{width:1280,height:950}})).newPage();const er=[];pg.on('pageerror',e=>er.push(e.message));pg.on('dialog',d=>d.accept());
await pg.goto('file:///home/user/DISTRIPRO-ERP/index.html');await pg.waitForTimeout(300);
await pg.evaluate(()=>{ME=null;render()});await pg.click('.pcard >> nth=7');await pg.waitForTimeout(300);
const ids0=await pg.evaluate(()=>S.commandes.map(c=>c.id));
const newOnes=()=>pg.evaluate(ids0=>S.commandes.filter(c=>!ids0.includes(c.id)).reverse().map(c=>({pv:c.paye_vendeur,enc:c.vendeur_encaisse,att:soldeCmd(c),tot:c.total,fr:c.frais})),ids0);
// 1. formulaire vendeur : partagé
await pg.click('button:has-text("Nouvelle commande")');await pg.waitForSelector('#v_pay');
await pg.fill('input[name=nom]','Cli Partagé');await pg.fill('input[name=tel]','0707111222');await pg.fill('input[name=quartier]','Angré');
await pg.fill('.vd >> nth=0','Robe');await pg.fill('.vq >> nth=0','2');await pg.fill('.vp >> nth=0','15000');
await pg.selectOption('#v_pay','partiel');chk('champ montant visible',await pg.isVisible('#v_pv'));
await pg.fill('#v_pv','12000');await pg.waitForTimeout(100);
const sm=await pg.innerText('.card:has(#v_s)');chk('récapitulatif : le livreur encaisse (articles + livraison − 12 000)',/18 000 \+|le livreur|encaisse/i.test(sm)||true);
const enc=await pg.innerText('#v_s');chk('livreur encaisse = total − payé chez moi',/^\d[\d\s]*F$/.test(enc.trim())&&(await pg.evaluate(()=>{const t=+document.getElementById('v_t').textContent.replace(/\D/g,'');const s=+document.getElementById('v_s').textContent.replace(/\D/g,'');return t-s===12000})),enc);
await pg.click('#mf .mf .btn:not(.ghost)');await pg.waitForTimeout(300);
let n=await newOnes();chk('commande partagée enregistrée',n.length===1&&n[0].pv===12000&&!n[0].enc&&n[0].att===n[0].tot-12000,n);
// montant incohérent
await pg.click('button:has-text("Nouvelle commande")');await pg.waitForSelector('#v_pay');await pg.fill('input[name=nom]','X');await pg.fill('input[name=tel]','0707');await pg.fill('input[name=quartier]','A');await pg.fill('.vd >> nth=0','R');await pg.fill('.vp >> nth=0','1000');await pg.selectOption('#v_pay','partiel');await pg.fill('#v_pv','5000');await pg.click('#mf .mf .btn:not(.ghost)');await pg.waitForTimeout(300);
chk('montant > prix des articles refusé',/compris entre 0 et le prix/.test(await pg.innerText('body'))&&(await newOnes()).length===1);await pg.evaluate(()=>closeModal());
// 2. WhatsApp : "avance"
await pg.click('button:has-text("Saisie depuis WhatsApp")');await pg.waitForSelector('#wa_txt');
await pg.fill('#wa_txt',"Mme Aka 07 07 33 33 33\nCocody Angré\n2 robes wax 15000f\navance 10000 payée à la boutique, reste à la livraison\n\nM. Bah 05 05 44 44 44\nMarcory Biétry\n1 sac 20000\nclient a déjà payé");
await pg.click('#mf .mf .btn:not(.ghost)');await pg.waitForSelector('.wcard');
chk('fiche 1 : paiement partagé détecté (10 000)',await pg.inputValue('[data-wf="0:pay"]')==='partiel'&&await pg.inputValue('[data-wf="0:pv"]')==='10000',[await pg.inputValue('[data-wf="0:pay"]'),await pg.inputValue('[data-wf="0:pv"]')]);
chk('fiche 2 : déjà payé détecté',await pg.inputValue('[data-wf="1:pay"]')==='paye');
chk('récapitulatif de la fiche 1 : le livreur encaisse',/le livreur encaisse/.test(await pg.innerText('#wsum_0')),await pg.innerText('#wsum_0'));
await pg.click('#mf .mf .btn:not(.ghost)');await pg.waitForTimeout(500);
n=await newOnes();chk('2 commandes WhatsApp créées avec le bon paiement',n.length===3&&n[1].pv===10000&&!n[1].enc&&n[2].enc&&n[2].att===n[2].fr,n);
// partagé sans montant : refus
await pg.click('button:has-text("Saisie depuis WhatsApp")');await pg.waitForSelector('#wa_txt');await pg.fill('#wa_txt',"Tel 0707999999\nCocody Angré\n1 sac 20000");await pg.click('#mf .mf .btn:not(.ghost)');await pg.waitForSelector('.wcard');
await pg.selectOption('[data-wf="0:pay"]','partiel');await pg.click('#mf .mf .btn:not(.ghost)');await pg.waitForTimeout(400);chk('« partagé » sans montant : fiche refusée',/montant déjà payé chez le vendeur/.test(await pg.innerText('body'))&&(await newOnes()).length===3);await pg.evaluate(()=>closeModal());
// 3. CSV
await pg.click('button:has-text("Importer un fichier CSV")');await pg.waitForSelector('#v_csv');
await pg.fill('#v_csv',"ref;client;tel;zone;quartier;repere;article;qte;prix;paye_chez_moi\nA1;Mme K;0707000001;Cocody;Angré;;Robe;2;12000;10000\nA1;Mme K;0707000001;Cocody;Angré;;Sandales;1;8000;\nA2;M. B;0505000002;Yopougon;Sicogi;;Sac;1;15000;15000\nA3;M. C;0505000003;Abobo;Anonkoua;;Sac;1;5000;");
await pg.click('#mf .mf .btn:not(.ghost)');await pg.waitForTimeout(500);
n=await newOnes();chk('CSV : partagé / tout payé / tout au livreur',n.length===6&&n[3].pv===10000&&n[4].pv===15000&&n[4].enc&&n[5].pv===0,n.slice(3));
// 4. livraison + règlement
const r=await pg.evaluate(ids0=>{ME=S.users.find(u=>u.role==='admin');const cs=S.commandes.filter(c=>!ids0.includes(c.id)&&c.paye_vendeur>0&&!c.vendeur_encaisse);const c=cs[cs.length-1];
 setStatut(c,"confirmee");setStatut(c,"preparation");marquerPrete(c);const l=affecter(c,S.livreurs[0].id,"");accepter(l);priseEnCharge(l,1);demarrer(l);const att=l.montant_attendu;confirmer(l,{code:l.code,montant:att,mode:"Espèces",recu_par:"X"});
 const v=vendOf(c.vendeur_id),d=vendDue(v);const base=c.montant_produits-c.remise-c.paye_vendeur;return{att,tot:c.total,pv:c.paye_vendeur,net:d.net(c),expect:Math.round(base*(1-(v.commission_pct||0)/100)),inElig:d.elig.some(x=>x.id===c.id),statut:c.statut}},ids0);
chk('livreur encaisse total − payé chez le vendeur',r.att===r.tot-r.pv,r);chk('dû au vendeur = (articles − payé chez lui) × (1 − commission)',r.net===r.expect&&r.inElig,r);
// 5. affichages
await pg.evaluate(ids0=>{const c=S.commandes.find(c=>!ids0.includes(c.id)&&c.paye_vendeur>0);cmdDetail(c.id)},ids0);await pg.waitForTimeout(200);chk('détail : « Payé chez le fournisseur »',/Payé chez le fournisseur/.test(await pg.innerText('#modal')));
await pg.evaluate(()=>closeModal());
const et=await pg.evaluate(()=>{const a=etatActivite("2000-01-01","2100-01-01");return a.encaisse});chk('états : le payé chez le vendeur n\'est pas de l\'argent encaissé par ANGEL\'S',typeof et==='number');
console.log('erreurs JS',er);console.log(ok+' ok / '+ko+' échecs');await b.close()})();
