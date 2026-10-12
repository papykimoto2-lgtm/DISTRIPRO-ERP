const { chromium } = require('/opt/node-tools/node_modules/playwright');
let ok=0,ko=0;const chk=(n,c,x)=>{c?ok++:ko++;console.log((c?'✔':'✘')+' '+n+(c?'':'  → '+(typeof x==='string'?x:JSON.stringify(x))))};
(async()=>{const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
const ctx=await b.newContext({viewport:{width:1280,height:950},acceptDownloads:true});const pg=await ctx.newPage();const er=[];pg.on('pageerror',e=>er.push(e.message));pg.on('dialog',d=>d.accept());
await pg.goto('file:///home/user/DISTRIPRO-ERP/index.html');await pg.waitForTimeout(300);
const T=()=>pg.innerText('body');
// deux livraisons prêtes pour le livreur 1 (en cours)
const L=await pg.evaluate(()=>{ME=S.users.find(u=>u.role==='admin');const lv=S.livreurs[0];const out=[];
 for(let i=0;i<2;i++){const cl=S.clients[0],ad=cl.adresses[0];const c=creerCmd({client_id:cl.id,adr:Object.assign({},ad),lignes:[{produit_id:S.produits[0].id,qte:1,pu:S.produits[0].prix}],frais:1500,remise:0,paiement:"livraison",acompte:0,mode:"Espèces",priorite:"normale",canal:"Téléphone",obs:"",confirmer:true});
  setStatut(c,"preparation");marquerPrete(c);const l=affecter(c,lv.id,"");accepter(l);priseEnCharge(l,1);demarrer(l);out.push({lid:l.id,code:l.code,att:l.montant_attendu})}
 ME=S.users.find(u=>u.id===lv.user_id);sessionStorage.setItem("angels_me",ME.id);view="dashboard";save();render();return{out,lv:lv.id}});
const s0=await pg.evaluate(id=>soldeLiv(id),L.lv);
// 1. confirmation Wave sans référence
await pg.evaluate(id=>ACT.lConf(id),L.out[0].lid);await pg.waitForSelector('input[name=code]');
await pg.fill('input[name=code]',L.out[0].code);
chk('zone Mobile Money masquée en espèces',!(await pg.isVisible('#mm_box')));
await pg.selectOption('select[name=mode]','Wave');chk('zone Mobile Money affichée pour Wave',await pg.isVisible('#mm_box'));
await pg.click('#mf .mf .btn:not(.ghost)');await pg.waitForTimeout(250);chk('Wave sans référence refusé',/Référence de la transaction Mobile Money obligatoire/.test(await T())&&await pg.evaluate(id=>byId(S.livraisons,id).statut==='en_cours',L.out[0].lid));
await pg.fill('input[name=ref]','wv-0001');await pg.click('#mf .mf .btn:not(.ghost)');await pg.waitForTimeout(400);
const f1=await pg.evaluate(id=>S.fonds.find(f=>f.livraison_id===id),L.out[0].lid);chk('encaissement Wave enregistré avec référence en majuscules',f1&&f1.mode==='Wave'&&f1.ref==='WV-0001'&&!f1.direct,f1);
// 2. direct sur le compte ANGEL'S
await pg.evaluate(id=>ACT.lConf(id),L.out[1].lid);await pg.waitForSelector('input[name=code]');await pg.fill('input[name=code]',L.out[1].code);await pg.selectOption('select[name=mode]','Orange Money');
await pg.fill('input[name=ref]','wv-0001');await pg.click('#mf .mf .btn:not(.ghost)');await pg.waitForTimeout(250);chk('référence déjà utilisée refusée',/déjà enregistrée/.test(await T()));
await pg.fill('input[name=ref]','OM-0002');await pg.check('input[name=direct]');await pg.click('#mf .mf .btn:not(.ghost)');await pg.waitForTimeout(400);
const f2=await pg.evaluate(id=>S.fonds.find(f=>f.livraison_id===id),L.out[1].lid);chk('paiement direct sur le compte ANGEL\'S enregistré',f2&&f2.direct&&f2.ref==='OM-0002',f2);
const s1=await pg.evaluate(id=>soldeLiv(id),L.lv);chk('le direct n\'est pas détenu par le livreur (solde +16 000 seulement)',s1-s0===L.out[0].att,[s0,s1]);
// 3. écran livreur : panneau de versement
await pg.evaluate(()=>render());t=await T();chk('panneau « Mon argent à reverser »',/Mon argent à reverser/.test(t)&&/Au comptant/.test(t)&&/Wave : 05 84/.test(t));
chk('versement déclaré (démo) visible : en attente',/WV-DEMO-0001|en attente|En attente/.test(t));
await pg.click('button:has-text("J\'ai envoyé par Mobile Money")');await pg.waitForSelector('input[name=ref]');
await pg.fill('input[name=ref]','ab');await pg.click('#mf .mf .btn:not(.ghost)');await pg.waitForTimeout(200);chk('référence trop courte refusée',/Référence de la transaction obligatoire/.test(await T()));
await pg.fill('input[name=ref]','WV-0001');await pg.click('#mf .mf .btn:not(.ghost)');await pg.waitForTimeout(200);chk('référence déjà utilisée refusée',/déjà enregistrée/.test(await T()));
await pg.fill('input[name=m]','5000');await pg.fill('input[name=ref]','mp-5555');await pg.click('#mf .mf .btn:not(.ghost)');await pg.waitForTimeout(300);
chk('versement déclaré (en attente de la caisse)',await pg.evaluate(()=>S.versements.some(v=>v.ref==='MP-5555'&&v.statut==='declare'&&v.montant===5000)));
// 4. caissier : validation
await pg.evaluate(()=>{ME=S.users.find(u=>u.role==='caissier');view="finance";render()});await pg.waitForTimeout(200);t=await T();
chk('caissier : versements à valider',/Versements Mobile Money déclarés à valider \(2\)/.test(t)&&/MP-5555/.test(t));
chk('colonnes espèces / Mobile Money',/Encaissé en espèces/.test(t)&&/Encaissé en Mobile Money/.test(t)&&/payé direct sur le compte ANGEL/.test(t));
const sb=await pg.evaluate(id=>soldeLiv(id),L.lv);
await pg.click('button:has-text("Reçu — valider") >> nth=1');await pg.waitForTimeout(300);
const sa=await pg.evaluate(id=>soldeLiv(id),L.lv);chk('validation : reversement enregistré avec référence, solde réduit',sb-sa>0&&await pg.evaluate(()=>S.fonds.some(f=>f.type==='reversement'&&f.ref)),[sb,sa]);
await pg.click('button:has-text("Rejeter")');await pg.fill('#modal textarea','SMS non reçu');await pg.click('#mf .mf .btn:not(.ghost)');await pg.waitForTimeout(300);
chk('rejet avec motif',await pg.evaluate(()=>S.versements.some(v=>v.statut==='rejete'&&v.motif==='SMS non reçu')));
// 5. reversement au guichet en Mobile Money : référence obligatoire
await pg.click('button:has-text("Enregistrer un reversement") >> nth=0');await pg.waitForSelector('select[name=mode]');await pg.selectOption('select[name=mode]','MTN MoMo');chk('référence demandée pour Mobile Money au guichet',await pg.isVisible('#mm_box2'));
await pg.click('#mf .mf .btn:not(.ghost)');await pg.waitForTimeout(200);chk('sans référence refusé',/Référence de la transaction Mobile Money obligatoire/.test(await T()));await pg.evaluate(()=>closeModal());
// 6. états + export + paramètres
await pg.evaluate(()=>{ME=S.users.find(u=>u.role==='admin');view="etats";ui.ep="a";render()});await pg.waitForTimeout(200);t=await T();chk('états : versements et encaissements Mobile Money',/dont versements par Mobile Money/.test(t)&&/Paiements clients directs sur le compte/.test(t));
await pg.evaluate(()=>{view="finance";render()});const [dl]=await Promise.all([pg.waitForEvent('download'),pg.click('button:has-text("Paiements Mobile Money (CSV)")')]);chk('export CSV des paiements Mobile Money',/paiements_mobile_money_/.test(dl.suggestedFilename()));
await pg.evaluate(()=>{view="params";render();ACT.pTab("pay")});await pg.fill('#p_momo',"Wave : 07 11 22 33 44\nMoov Money : 01 55 66 77 88");await pg.evaluate(()=>ACT.saveParams());await pg.waitForTimeout(200);
chk('comptes Mobile Money enregistrés',await pg.evaluate(()=>S.config.momo_comptes.length===2&&/Moov/.test(S.config.momo_comptes[1])));
console.log('erreurs JS',er);console.log(ok+' ok / '+ko+' échecs');await b.close()})();
