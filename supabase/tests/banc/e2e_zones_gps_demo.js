const { chromium } = require('/opt/node-tools/node_modules/playwright');
let ok=0,ko=0;const chk=(n,c,x)=>{c?ok++:ko++;console.log((c?'✔':'✘')+' '+n+(c?'':'  → '+(typeof x==='string'?x:JSON.stringify(x))))};
(async()=>{const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
const ctx=await b.newContext({viewport:{width:1100,height:950},geolocation:{latitude:5.3571,longitude:-3.981,accuracy:25},permissions:['geolocation']});
const pg=await ctx.newPage();const er=[];pg.on('pageerror',e=>er.push(e.message));pg.on('dialog',d=>d.accept());
const URL='file:///home/user/DISTRIPRO-ERP/index.html';await pg.goto(URL);await pg.waitForTimeout(300);
const names=await pg.evaluate(()=>S.config.zones.map(z=>z.nom));
chk('22 zones par défaut',names.length===22,names.length);
chk('Grand Abidjan + périphérie : Songon, Dabou, Grand-Bassam, Bingerville, Anyama, Adjamé',['Songon','Dabou','Grand-Bassam','Bingerville','Anyama','Adjamé','Attécoubé','Jacqueville'].every(n=>names.includes(n)),names);
chk('zone « autre localité » en dernier recours',names.some(n=>/Autre localité/.test(n)));
// migration d'une ancienne configuration (8 zones, tarif personnalisé)
await pg.evaluate(()=>{S.config.zones=S.config.zones.filter(z=>["Cocody","Abobo","Yopougon","Marcory","Treichville","Koumassi","Port-Bouët","Plateau"].includes(z.nom));S.config.zones.find(z=>z.nom==="Cocody").frais=1700;delete S.config.zones_ga;save()});
await pg.reload();await pg.waitForTimeout(300);
const z2=await pg.evaluate(()=>S.config.zones.map(z=>[z.nom,z.frais]));
chk('ancienne installation : les zones manquantes sont ajoutées',z2.length===22&&z2.some(z=>z[0]==='Songon'),z2.length);
chk('le tarif personnalisé existant est conservé',z2.find(z=>z[0]==='Cocody')[1]===1700);
await pg.evaluate(()=>{S.config.zones=S.config.zones.filter(z=>z.nom!=='Dabou');save()});await pg.reload();await pg.waitForTimeout(300);
chk('une zone supprimée par l\'administrateur n\'est pas réajoutée',!(await pg.evaluate(()=>S.config.zones.some(z=>z.nom==='Dabou'))));
// suggestions de quartiers par zone
await pg.evaluate(()=>{const u=S.users.find(u=>u.role==='vendeur');ME=u;sessionStorage.setItem('angels_me',u.id);view='mesCmd';render()});
await pg.click('button:has-text("Nouvelle commande")');await pg.waitForSelector('#v_zone');
const opts=await pg.$$eval('#v_zone option',o=>o.map(x=>x.textContent));chk('liste des zones dans le formulaire vendeur',opts.includes('Songon')&&opts.includes('Grand-Bassam')&&opts.length>=21,opts.length);
await pg.selectOption('#v_zone','Yopougon');await pg.focus('input[name=quartier]');
chk('suggestions limitées à la zone choisie (Yopougon)',await pg.getAttribute('input[name=quartier]','list')==='dl_q_yopougon'&&await pg.$$eval('#dl_q_yopougon option',o=>o.map(x=>x.value)).then(v=>v.includes('Niangon Nord')&&v.includes('Selmer')&&!v.includes('Angré')));
await pg.selectOption('#v_zone','Songon');await pg.focus('input[name=quartier]');
chk('Songon : ses propres quartiers',await pg.getAttribute('input[name=quartier]','list')==='dl_q_songon'&&await pg.$$eval('#dl_q_songon option',o=>o.map(x=>x.value)).then(v=>v.includes('Songon-Agban')));
chk('liste globale pour une zone libre (≥ 150 quartiers)',await pg.$$eval('#dl_q option',o=>o.length)>=150);
await pg.evaluate(()=>closeModal());
// analyse des messages WhatsApp : nouvelles zones reconnues
const r=await pg.evaluate(()=>["Bonjour c'est Awa 0707112233\n2 sacs à 5000 F\nlivrer à Songon","Salut Koffi 0505332211\n1 montre 15000\nDabou centre","Awa 0707334455\n3 pagnes 6000\nGrand-Bassam quartier France","Moi 0707998877\n1 robe 10000\nBingerville","Fatou 0102030405\n1 sac 8000\nniangon"].map(t=>waParseBlock(t,S.config.zones).zone));
chk('messages WhatsApp : Songon, Dabou (zone supprimée → vide), Grand-Bassam, Bingerville, Niangon→Yopougon',r[0]==='Songon'&&r[2]==='Grand-Bassam'&&r[3]==='Bingerville'&&r[4]==='Yopougon'&&r[1]==='',r);
// GPS du fournisseur
await pg.evaluate(()=>{view='mesCmd';render()});
await pg.evaluate(()=>vAdrForm());await pg.waitForSelector('#va_gps');
chk('adresse de collecte : bouton position + collage de lien',await pg.locator('input[name=geo]').count()===1&&/Sans position/.test(await pg.innerText('#va_gt')));
await pg.selectOption('select[name=z]','Cocody');await pg.fill('input[name=q]','Angré 8e tranche');await pg.click('#va_gps');await pg.waitForTimeout(500);
chk('position trouvée',/Position enregistrée \(5\.35710, -3\.98100\)/.test(await pg.innerText('#va_gt')));
await pg.click('#mf .mf .btn:not(.ghost)');await pg.waitForTimeout(300);
const a1=await pg.evaluate(()=>vend().adresse_collecte);chk('position enregistrée sur la fiche du fournisseur',a1.lat===5.3571&&a1.lng===-3.981&&a1.zone==='Cocody',a1);
chk('la position apparaît dans l\'adresse de collecte',/GPS/.test(await pg.innerText('body')));
await pg.evaluate(()=>vAdrForm());await pg.waitForSelector('#va_gps');chk('à la réouverture la position est rappelée',/Position enregistrée/.test(await pg.innerText('#va_gt')));
await pg.fill('input[name=geo]','https://www.google.com/maps?q=5.3010,-4.0121');await pg.click('#mf .mf .btn:not(.ghost)');await pg.waitForTimeout(300);
const a2=await pg.evaluate(()=>vend().adresse_collecte);chk('lien Google Maps collé → coordonnées enregistrées',a2.lat===5.301&&a2.lng===-4.0121,a2);
await pg.evaluate(()=>vAdrForm());await pg.waitForSelector('#va_clr');await pg.click('#va_clr');await pg.click('#mf .mf .btn:not(.ghost)');await pg.waitForTimeout(300);
chk('effacer la position',await pg.evaluate(()=>vend().adresse_collecte.lat===undefined));
await pg.evaluate(()=>vAdrForm());await pg.waitForSelector('input[name=geo]');await pg.fill('input[name=geo]','n importe quoi');await pg.click('#mf .mf .btn:not(.ghost)');await pg.waitForTimeout(300);
chk('lien non reconnu refusé',/non reconnus/.test(await pg.innerText('body')));
chk('aucune erreur JS',er.length===0,er);
console.log(ok+' ok / '+ko+' échecs');await b.close()})();
