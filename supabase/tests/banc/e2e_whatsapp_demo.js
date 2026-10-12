const { chromium } = require('/opt/node-tools/node_modules/playwright');
let ok=0,ko=0;const chk=(n,c,x)=>{c?ok++:ko++;console.log((c?'✔':'✘')+' '+n+(c?'':'  → '+(typeof x==='string'?x:JSON.stringify(x))))};
(async()=>{const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
const ctx=await b.newContext({viewport:{width:1280,height:950}});const pg=await ctx.newPage();const er=[];pg.on('pageerror',e=>er.push(e.message));pg.on('dialog',d=>d.accept());
await pg.goto('file:///home/user/DISTRIPRO-ERP/index.html');await pg.waitForTimeout(300);
await pg.evaluate(()=>{ME=null;render()});await pg.click('.pcard >> nth=7');await pg.waitForTimeout(300);
chk('bouton « Saisie depuis WhatsApp » chez le vendeur',await pg.isVisible('button:has-text("Saisie depuis WhatsApp")'));
const n0=await pg.evaluate(()=>S.commandes.length);const ids0=await pg.evaluate(()=>S.commandes.map(c=>c.id));
await pg.click('button:has-text("Saisie depuis WhatsApp")');await pg.waitForSelector('#wa_txt');
await pg.fill('#wa_txt',"Mme Konan 07 07 12 34 56\nAngré 8e tranche, près de la pharmacie\n2 robes wax 15000f\n1 sac à main 12.000 f\n\nSerge 05 05 99 99 99\nYopougon Sicogi\n3 pagnes 8000");
await pg.setInputFiles('#wa_img','/tmp/claude-0/t/id.png');await pg.waitForTimeout(500);
chk('capture ajoutée à l\'étape 1',(await pg.$$('.wthumb')).length===1);
await pg.click('#mf .mf .btn:not(.ghost)');await pg.waitForSelector('.wcard');
chk('2 fiches détectées',(await pg.$$('.wcard')).length===2);
let v=await pg.inputValue('[data-wf="0:nom"]');chk('fiche 1 : nom, tel, zone',v==='Mme Konan'&&await pg.inputValue('[data-wf="0:tel"]')==='0707123456'&&await pg.inputValue('[data-wf="0:zone"]')==='Cocody');
chk('fiche 1 : 2 articles',(await pg.$$('.wcard:nth-of-type(1) .wl tr')).length>=3||(await pg.$$('[data-wl^="0:"][data-wl$=":desig"]')).length===2);
chk('capture non attribuée proposée (plusieurs fiches)',await pg.isVisible('select[data-wass]'));
await pg.selectOption('select[data-wass="0"]','0');await pg.waitForTimeout(300);
chk('capture attribuée à la fiche 1',(await pg.$$('.wcard .wthumb')).length===1);
// correction : fiche 2 sans prix manquant ? corriger la zone/qté
await pg.fill('[data-wl="1:0:pu"]','8500');await pg.waitForTimeout(100);chk('total ligne recalculé (3 × 8500)',/25\s?500/.test(await pg.innerText('[data-wt="1:0"]')),await pg.innerText('[data-wt="1:0"]'));
chk('récapitulatif livraison + total',/livraison/.test(await pg.innerText('#wsum_1')));
await pg.click('#mf .mf .btn:not(.ghost)');await pg.waitForTimeout(600);
const res=await pg.evaluate(([n0,ids0])=>({n:S.commandes.length-n0,last:S.commandes.filter(c=>!ids0.includes(c.id)).reverse().map(c=>({st:c.statut,v:!!c.vendeur_id,ph:(c.photos||[]).length,l:c.lignes.map(l=>l.desig+"×"+l.qte+"@"+l.pu).join(","),cl:cli(c.client_id).nom,tel:cli(c.client_id).tel,z:c.adr.zone}))}),[n0,ids0]);
console.log(JSON.stringify(res));chk('2 commandes créées « en attente de confirmation »',res.n===2&&res.last.every(c=>c.st==='attente'&&c.v));
chk('photo attachée à la commande 1',res.last[0].ph===1&&res.last[1].ph===0);
chk('contenu fidèle',/Robes wax×2@15000/.test(res.last[0].l)&&res.last[0].tel==='0707123456'&&res.last[1].z==='Yopougon');
chk('modal fermé',!(await pg.isVisible('#wa_body')));
// fiche invalide : reste ouverte
await pg.click('button:has-text("Saisie depuis WhatsApp")');await pg.waitForSelector('#wa_txt');await pg.fill('#wa_txt',"Tel 0707000000\n2 robes wax");await pg.click('#mf .mf .btn:not(.ghost)');await pg.waitForSelector('.wcard');
await pg.click('#mf .mf .btn:not(.ghost)');await pg.waitForTimeout(500);chk('fiche incomplète : création refusée, fiche conservée',await pg.isVisible('.wcard')&&await pg.evaluate(n0=>S.commandes.length===n0+2,n0));
await pg.evaluate(()=>closeModal());
// import export .zip
await pg.click('button:has-text("Saisie depuis WhatsApp")');await pg.waitForSelector('#wa_file',{state:'attached'});
await pg.setInputFiles('#wa_file','/tmp/claude-0/t/wa_export.zip');await pg.waitForTimeout(800);
chk('export .zip chargé',/Bonjour je veux 2 robes/.test(await pg.inputValue('#wa_txt')));
await pg.click('#mf .mf .btn:not(.ghost)');await pg.waitForSelector('.wcard');
chk('export : tel depuis le numéro, zone, image du zip jointe',await pg.inputValue('[data-wf="0:tel"]')==='0707444444'&&await pg.inputValue('[data-wf="0:zone"]')==='Cocody'&&(await pg.$$('.wcard .wthumb')).length===1,await pg.inputValue('[data-wf="0:zone"]'));
await pg.screenshot({path:'/tmp/claude-0/t/s_wa.png'});await pg.evaluate(()=>closeModal());
// export .txt
await pg.click('button:has-text("Saisie depuis WhatsApp")');await pg.waitForSelector('#wa_file',{state:'attached'});await pg.setInputFiles('#wa_file','/tmp/claude-0/t/wa_export.txt');await pg.waitForTimeout(500);await pg.click('#mf .mf .btn:not(.ghost)');await pg.waitForSelector('.wcard');
chk('export .txt analysé',await pg.inputValue('[data-wf="0:tel"]')==='0707444444');
// détail de commande avec photo
await pg.evaluate(()=>closeModal());
const cid=await pg.evaluate(ids0=>S.commandes.filter(c=>!ids0.includes(c.id)).reverse()[0].id,ids0);
await pg.evaluate(id=>{ME=S.users.find(u=>u.role==='admin');view='commandes';render();cmdDetail(id)},cid);await pg.waitForTimeout(300);
chk('détail commande : bouton photos',await pg.isVisible('button:has-text("Photos jointes (1)")'));
await pg.click('button:has-text("Photos jointes")');await pg.waitForTimeout(300);chk('galerie ouverte',(await pg.$$('.wph img')).length===1);
console.log('erreurs JS',er);console.log(ok+' ok / '+ko+' échecs');await b.close()})();
