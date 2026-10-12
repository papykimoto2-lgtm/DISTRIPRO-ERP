const { chromium } = require('/opt/node-tools/node_modules/playwright');
let ok=0,ko=0;const chk=(n,c,x)=>{c?ok++:ko++;console.log((c?'✔':'✘')+' '+n+(c?'':'  → '+(x||'')))};
(async()=>{const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
const pg=await (await b.newContext({viewport:{width:1280,height:900}})).newPage();const er=[];pg.on('pageerror',e=>er.push(e.message));pg.on('dialog',d=>d.accept());
await pg.goto('file:///home/user/DISTRIPRO-ERP/index.html');await pg.waitForTimeout(500);
await pg.click('.pcard >> nth=0');await pg.click('aside a:has-text("Livreurs")');await pg.waitForTimeout(300);
let t=await pg.innerText('body');
chk('colonne Dossier : Issa complet',/Dossier complet/.test(t));chk('autres livreurs à compléter',(t.match(/À compléter/g)||[]).length===2,(t.match(/À compléter/g)||[]).length);
await pg.screenshot({path:'s_liv.png'});
// alertes tableau de bord
await pg.click('aside a:has-text("Tableau de bord")');t=await pg.innerText('body');chk('alerte dossier incomplet au tableau de bord',/Dossier de Kouamé Yves incomplet/.test(t));
// ouvrir dossier de Kouamé
await pg.click('aside a:has-text("Livreurs")');await pg.click('tr:has-text("Kouamé") button:has-text("Dossier")');await pg.waitForSelector('[data-slot=photo]');
for(const k of ['photo','piece_recto','piece_verso','permis'])await pg.setInputFiles(`input[data-img=${k}]`,'id.png');
await pg.waitForTimeout(800);
chk('4 aperçus affichés',(await pg.$$('.slot img:not(.hide)')).length===4);
await pg.screenshot({path:'s_dos.png'});
await pg.selectOption('select[name=piece_type]','cni');await pg.fill('input[name=piece_numero]','CI99');await pg.fill('input[name=piece_expire]','2030-01-01');
await pg.fill('input[name=permis_numero]','P-1');await pg.fill('input[name=permis_expire]','2030-01-01');await pg.fill('input[name=contact_urgence_tel]','0102030405');
await pg.click('#mf .mf .btn:not(.ghost)');await pg.waitForTimeout(500);
chk('enregistrement refusé sans accord ? (accord non coché → incomplet)',await pg.evaluate(()=>!dossierEtat(liv(S.livreurs[1].id)).ok));
// recocher accord
await pg.click('tr:has-text("Kouamé") button:has-text("Dossier")');await pg.waitForSelector('[data-slot=photo]');await pg.check('input[name=consent]');await pg.click('#mf .mf .btn:not(.ghost)');await pg.waitForTimeout(400);
chk('dossier Kouamé complet',await pg.evaluate(()=>dossierEtat(S.livreurs[1]).ok),await pg.evaluate(()=>dossierEtat(S.livreurs[1]).manques));
chk('journal',await pg.evaluate(()=>S.audit.some(a=>a.action==="Dossier livreur modifié")));
// obligatoire
await pg.evaluate(()=>{S.config.dossier_obligatoire=true});
const r=await pg.evaluate(()=>{const c=S.commandes.find(c=>c.statut==="prete");const sk=S.livreurs[2];return {c:!!c,bloque:affecter(c,sk.id,"")===false,ok:!!affecter(c,S.livreurs[1].id,"")}});
chk('affectation bloquée si dossier incomplet / acceptée si complet',r.c&&r.bloque&&r.ok,JSON.stringify(r));
// expiration
await pg.evaluate(()=>{S.livreurs[1].dossier.permis_expire="2020-01-01"});chk('permis expiré détecté',await pg.evaluate(()=>dossierEtat(S.livreurs[1]).manques.some(m=>/permis expiré/.test(m))));
// params
await pg.evaluate(()=>{ME=S.users[0];view="params";render()});chk('case dans Paramètres',await pg.isVisible('#p_do'));
// rôle livreur ne voit pas la page
console.log('erreurs JS',er);console.log(`${ok} ok / ${ko} échecs`);await b.close()})();
