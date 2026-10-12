const { chromium } = require('/opt/node-tools/node_modules/playwright');
let ok=0,ko=0;const chk=(n,c,x)=>{c?ok++:ko++;console.log((c?'✔':'✘')+' '+n+(c?'':'  → '+(typeof x==='string'?x:JSON.stringify(x))))};
(async()=>{const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
const pg=await (await b.newContext({viewport:{width:1280,height:950}})).newPage();const er=[];pg.on('pageerror',e=>er.push(e.message));pg.on('dialog',d=>d.accept());
await pg.goto('file:///home/user/DISTRIPRO-ERP/index.html');await pg.waitForTimeout(300);
await pg.evaluate(()=>{ME=S.users.find(u=>u.role==='admin');sessionStorage.setItem('angels_me',ME.id);view='livreurs';render()});
// 1. formulaire livreur
await pg.click('button[data-act=newLiv]');await pg.waitForSelector('#l_type');
chk('formulaire : rémunération visible pour un interne',await pg.isVisible('#l_rem')&&!(await pg.isVisible('#l_cw')));
await pg.selectOption('#l_type','externe');
chk('externe : champ commission visible, rémunération masquée',await pg.isVisible('#l_cw')&&!(await pg.isVisible('#l_rem'))&&/garde les frais/.test(await pg.innerText('#l_cn')));
await pg.fill('input[name=nom]','Moussa Externe');await pg.fill('input[name=tel]','0707404142');await pg.fill('input[name=lcom]','20');await pg.fill('input[name=pin]','4321');
await pg.click('#mf .mf .btn:not(.ghost)');await pg.waitForTimeout(400);
const nl=await pg.evaluate(()=>S.livreurs.find(l=>l.nom==='Moussa Externe'));
chk('livreur externe enregistré avec son taux',nl&&nl.type==='externe'&&nl.commission_pct===20,nl);
chk('liste des livreurs : « Externe — ANGEL\'S prélève 20 % »',/Externe/.test(await pg.innerText('body'))&&/ANGEL'S prélève 20 % des frais/.test(await pg.innerText('body')));
// 2. livraison par l'externe (frais 1 500) payée en espèces
const L=await pg.evaluate(id=>{const lv=liv(id);const cl=S.clients[0],ad=cl.adresses[0];
 const c=creerCmd({client_id:cl.id,adr:Object.assign({},ad),lignes:[{produit_id:S.produits[0].id,qte:1,pu:S.produits[0].prix}],frais:1500,remise:0,paiement:"livraison",mode:"Espèces",priorite:"normale",canal:"Téléphone",obs:"",confirmer:true});
 setStatut(c,"preparation");marquerPrete(c);const l=affecter(c,lv.id,"");accepter(l);priseEnCharge(l,1);demarrer(l);save();return{lid:l.id,code:l.code,att:l.montant_attendu,lv:lv.id}},nl.id);
await pg.evaluate(id=>{ME=S.users.find(u=>u.id===liv(id).user_id);sessionStorage.setItem('angels_me',ME.id);view='dashboard';render()},nl.id);
await pg.evaluate(id=>ACT.lConf(id),L.lid);await pg.waitForSelector('input[name=code]');await pg.fill('input[name=code]',L.code);
await pg.click('#mf .mf .btn:not(.ghost)');await pg.waitForTimeout(500);
const l1=await pg.evaluate(id=>{const l=S.livraisons.find(x=>x.id===id);return{st:l.statut,ca:l.commission_angels,pt:l.part_livreur}},L.lid);
chk('course livrée : commission 300 F, part du livreur 1 200 F',l1.st==='livree'&&l1.ca===300&&l1.pt===1200,l1);
const sol=await pg.evaluate(id=>({enc:encaisseLiv(id),ret:retenuLiv(id),sol:soldeLiv(id)}),nl.id);
chk('reste à reverser = encaissé − part retenue',sol.enc===L.att&&sol.ret===1200&&sol.sol===L.att-1200,sol);
chk('commission due par ANGEL\'S à ce livreur : 0 (déjà retenue)',await pg.evaluate(()=>{const l=S.livraisons.find(x=>x.part_livreur!=null);return commissionLiv(l)===0}));
// 3. finance
await pg.evaluate(()=>{ME=S.users.find(u=>u.role==='caissier');sessionStorage.setItem('angels_me',ME.id);view='finance';render()});
const t=await pg.innerText('body');chk('finance : part gardée par le livreur externe expliquée',/gardés par le livreur externe/.test(t)&&t.includes('1 200 F'));
await pg.evaluate(id=>ACT.reverser(id),nl.id);await pg.waitForSelector('input[name=m]');
chk('reversement : montant proposé = net (encaissé − part)',(await pg.inputValue('input[name=m]'))===String(L.att-1200)&&/Montant dû par le livreur/.test(await pg.innerText('#mf')));
await pg.fill('input[name=m]',String(L.att-1200));await pg.click('#mf .mf .btn:not(.ghost)');await pg.waitForTimeout(400);
chk('après reversement du net, solde nul',await pg.evaluate(id=>soldeLiv(id),nl.id)===0);
// 4. états
await pg.evaluate(()=>{ME=S.users.find(u=>u.role==='admin');sessionStorage.setItem('angels_me',ME.id);view='etats';render()});
const et=await pg.evaluate(()=>{try{return JSON.stringify(Object.keys(window).filter(k=>/^etat/i.test(k)))}catch(e){return ''}});
// 5. taux modifié : course passée inchangée
await pg.evaluate(id=>{liv(id).commission_pct=50;save()},nl.id);chk('modifier le taux ne change pas la course passée',await pg.evaluate(id=>S.livraisons.find(x=>x.id===id).commission_angels,L.lid)===300);
chk('livreur interne : aucune part',await pg.evaluate(()=>S.livraisons.filter(l=>!estExterne(liv(l.livreur_id))).every(l=>l.part_livreur==null)));
chk('aucune erreur JS',er.length===0,er);
console.log(ok+' ok / '+ko+' échecs');await b.close()})();
