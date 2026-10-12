const { chromium } = require('/opt/node-tools/node_modules/playwright');
let ok=0,ko=0;const chk=(n,c,x)=>{c?ok++:ko++;console.log((c?'✔':'✘')+' '+n+(c?'':'  → '+(typeof x==='string'?x:JSON.stringify(x))))};
(async()=>{const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
const pg=await (await b.newContext({viewport:{width:1300,height:1000}})).newPage();const er=[];pg.on('pageerror',e=>er.push(e.message));pg.on('dialog',d=>d.accept());
await pg.goto('file:///home/user/DISTRIPRO-ERP/index.html');await pg.waitForTimeout(300);
await pg.evaluate(()=>{ME=S.users.find(u=>u.role==='admin');sessionStorage.setItem('angels_me',ME.id);view='params';render()});
const labels=await pg.$$eval('#ptabs button',b=>b.map(x=>x.textContent));
chk('7 onglets de paramètres',labels.length===7&&/Zones/.test(labels[0])&&/Livreurs/.test(labels[1])&&/Listes/.test(labels[2])&&/Société/.test(labels[3])&&/Paiements/.test(labels[4])&&/Notifications/.test(labels[5])&&/Données/.test(labels[6]),labels);
const vis=async()=>pg.$$eval('[data-pt]',d=>d.filter(x=>!x.classList.contains('hide')).map(x=>x.dataset.pt));
chk('premier onglet : zones seulement',JSON.stringify(await vis())==='["zones"]'&&/Zones de livraison/.test(await pg.innerText('body'))&&!(await pg.isVisible('#p_motifs')));
const H=await pg.evaluate(()=>document.body.scrollHeight);
const exp={liv:['Rémunération par défaut','Dossiers des livreurs','Étiquettes colis'],listes:['Listes paramétrables'],ste:['Société et documents'],pay:['Paiements et versements'],notif:['Notifications aux clients'],data:['Données']};
for(const [k,L] of Object.entries(exp)){await pg.click(`#ptabs [data-id=${k}]`);const t=await pg.innerText('[data-pt]:not(.hide)');chk(`onglet « ${k} » : ${L.join(' + ')}`,JSON.stringify(await vis())===JSON.stringify([k])&&L.every(x=>t.includes(x)),t.slice(0,80))}
chk('la page n\'a plus à défiler longtemps (hauteur réduite)',await pg.evaluate(()=>document.body.scrollHeight)<=H+100,[H,await pg.evaluate(()=>document.body.scrollHeight)]);
// modifications non enregistrées conservées en changeant d'onglet, enregistrement global
await pg.click('#ptabs [data-id=listes]');await pg.fill('#p_motifs','Client absent\nAdresse incorrecte\nMotif test onglet');
await pg.click('#ptabs [data-id=pay]');await pg.fill('#p_momo','Wave : 07 00 00 00 00');
await pg.click('#ptabs [data-id=listes]');chk('saisie non enregistrée conservée au retour sur l\'onglet',(await pg.inputValue('#p_motifs')).includes('Motif test onglet'));
await pg.click('#ptabs [data-id=pay]');await pg.click('#psave');await pg.waitForTimeout(300);
chk('« Enregistrer » enregistre tous les onglets',await pg.evaluate(()=>S.config.motifs.includes('Motif test onglet')&&S.config.momo_comptes[0]==='Wave : 07 00 00 00 00'));
chk('l\'onglet actif est conservé après enregistrement',JSON.stringify(await vis())==='["pay"]');
// zones : modification depuis l'onglet
await pg.click('#ptabs [data-id=zones]');await pg.locator('[data-act=editZone]').first().click();await pg.waitForSelector('input[name=nom]');chk('modifier une zone depuis son onglet',await pg.inputValue('input[name=nom]')!=='');await pg.evaluate(()=>closeModal());
// autre rôle
await pg.setViewportSize({width:420,height:800});chk('mobile : onglets défilables',await pg.isVisible('#ptabs'));await pg.screenshot({path:'prm_mobile.png',clip:{x:0,y:0,width:420,height:420}});
chk('aucune erreur JS',er.length===0,er);console.log(ok+' ok / '+ko+' échecs');await b.close()})();
