const { chromium } = require('/opt/node-tools/node_modules/playwright');
let ok=0,ko=0;const chk=(n,c,x)=>{c?ok++:ko++;console.log((c?'✔':'✘')+' '+n+(c?'':'  → '+(typeof x==='string'?x:JSON.stringify(x))))};
(async()=>{const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
const ctx=await b.newContext({viewport:{width:1300,height:950}});await ctx.addInitScript(()=>{window.__SANS_OFFRE=true});
const pg=await ctx.newPage();const er=[];pg.on('pageerror',e=>er.push(e.message));pg.on('dialog',d=>d.accept());
await pg.goto('file:///home/user/DISTRIPRO-ERP/index.html');await pg.waitForTimeout(300);
const as=async(role,v)=>{await pg.evaluate(([r,v])=>{ME=S.users.find(u=>u.role===r);sessionStorage.setItem('angels_me',ME.id);view=v||'dashboard';render()},[role,v]);await pg.waitForTimeout(150)};
const sub=async()=>{await pg.click('#mf .mf .btn:not(.ghost)');await pg.waitForTimeout(350)};
await as('caissier');
chk('menu Finance : pastille rouge avec le nombre de versements à valider',await pg.innerText('[data-act=nav][data-id=finance] .nb')==='1');
await pg.evaluate(()=>{view='finance';render()});
const tabs=await pg.$$eval('.tabs button',b=>b.map(x=>x.textContent));
chk('onglet « 📲 Versements (1) » dans Finance',tabs.some(t=>/Versements \(1\)/.test(t)),tabs);
await pg.click('.tabs [data-id="fin|vers"]');
let t=await pg.innerText('body');
chk('liste « en validation » : WV-DEMO-0001, 10 000 F, statut ⏳ En validation',/WV-DEMO-0001/.test(t)&&/10 000 F/.test(t)&&/En validation/.test(t)&&await pg.locator('[data-act=versOk]').count()===1);
chk('bouton « Encaissé » (et pas « Reçu »)',/✔ Encaissé/.test(t));
chk('compteurs : 1 en validation',/En validation\s*\n?\s*1 · 10 000 F|1 · 10 000 F/.test(t));
// le livreur déclare un nouveau versement
const s0=await pg.evaluate(()=>{const lv=livreurOf(S.users.find(u=>u.role==='livreur'))||S.livreurs[0];return{id:lv.id,solde:soldeLiv(lv.id)}});
await as('livreur');await pg.evaluate(()=>{const lv=livreurOf(ME);S.fonds.push({id:uid('f'),type:'encaissement',livreur_id:lv.id,montant:40000,mode:'Espèces',ts:now(),par:'x'});render()});
await pg.click('button[data-act=verserMomo]');await pg.waitForSelector('input[name=ref]');await pg.fill('input[name=m]','15000');await pg.fill('input[name=ref]','wv-vrs-0002');await sub();
chk('livreur : « ⏳ En validation » dans son historique',/En validation/.test(await pg.innerText('#app')));
await as('caissier','finance');chk('la déclaration arrive chez le caissier (pastille 2)',await pg.innerText('[data-act=nav][data-id=finance] .nb')==='2');
await pg.click('.tabs [data-id="fin|vers"]');
chk('2 versements en validation',await pg.locator('[data-act=versOk]').count()===2&&/WV-VRS-0002/.test(await pg.innerText('body')));
const sBefore=await pg.evaluate(id=>soldeLiv(id),(await pg.evaluate(()=>S.versements.find(v=>v.ref==='WV-VRS-0002').livreur_id)));
// encaisser
await pg.locator('tr:has-text("WV-VRS-0002") [data-act=versOk]').click();await pg.waitForTimeout(350);
const v2=await pg.evaluate(()=>S.versements.find(v=>v.ref==='WV-VRS-0002'));
chk('validation : statut encaissé, date et nom du valideur',v2.statut==='valide'&&!!v2.traite_le&&!!v2.traite_par_nom,v2);
chk('un reversement est enregistré et le solde du livreur baisse de 15 000 F',await pg.evaluate(([id,b])=>soldeLiv(id)===b-15000&&S.fonds.some(f=>f.type==='reversement'&&f.ref==='WV-VRS-0002'),[v2.livreur_id,sBefore]));
chk('la pastille passe à 1',await pg.innerText('[data-act=nav][data-id=finance] .nb')==='1');
await pg.selectOption('select[data-f=vfilt]','valide');await pg.waitForTimeout(150);t=await pg.innerText('body');
chk('onglet « Encaissés » : le versement apparaît avec « ✅ Encaissé » et la date',/WV-VRS-0002/.test(t)&&/✅ Encaissé/.test(t)&&/par /.test(t)&&!/WV-DEMO-0001/.test(t));
chk('compteur « Encaissés aujourd\'hui » : 15 000 F',/Encaissés aujourd'hui\s*\n?\s*15 000 F|15 000 F\s*\n?\s*✅ Encaissés aujourd'hui/.test(t)||/15 000 F/.test(t));
// rejet
await pg.selectOption('select[data-f=vfilt]','declare');await pg.locator('[data-act=versNo]').first().click();await pg.waitForSelector('textarea[name=v]');await pg.fill('textarea[name=v]','Somme non reçue sur le compte');await sub();
await pg.selectOption('select[data-f=vfilt]','rejete');t=await pg.innerText('body');
chk('rejet : motif conservé, statut ✖ Rejeté',/✖ Rejeté/.test(t)&&/Somme non reçue/.test(t));
await pg.selectOption('select[data-f=vfilt]','tous');await pg.fill('input[data-f=vq]','vrs-0002');await pg.press('input[data-f=vq]','Tab');await pg.waitForTimeout(200);
chk('filtre « Tous » et recherche par référence',await pg.locator('tbody tr').count()===1&&/WV-VRS-0002/.test(await pg.innerText('tbody')));
chk('la pastille disparaît quand tout est traité',await pg.locator('[data-act=nav][data-id=finance] .nb').count()===0);
// côté livreur
await as('livreur');t=await pg.innerText('#app');chk('livreur : historique « ✅ Encaissé le … » et « ✖ Rejeté »',/Encaissé le/.test(t)&&/Rejeté/.test(t));
// direction : lecture seule
await as('direction','finance');await pg.click('.tabs [data-id="fin|vers"]');chk('direction : voit la liste mais sans boutons d\'action',await pg.locator('[data-act=versOk]').count()===0);
// smartphone : pastille sur le bouton menu
await pg.evaluate(()=>{S.versements.push({id:uid('vd'),livreur_id:S.livreurs[0].id,montant:5000,mode:'Wave',ref:'WV-NEW-1',note:'',statut:'declare',cree_le:now()})});await as('caissier','finance');await pg.setViewportSize({width:420,height:850});await pg.waitForTimeout(150);
chk('smartphone : pastille sur le bouton ☰',await pg.getAttribute('.burger','data-n')==='1');await pg.screenshot({path:'vers_mobile.png',clip:{x:0,y:0,width:420,height:120}});
chk('aucune erreur JS',er.length===0,er);console.log(ok+' ok / '+ko+' échecs');await b.close()})();
