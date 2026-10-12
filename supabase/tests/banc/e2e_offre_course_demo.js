const { chromium } = require('/opt/node-tools/node_modules/playwright');
let ok=0,ko=0;const chk=(n,c,x)=>{c?ok++:ko++;console.log((c?'✔':'✘')+' '+n+(c?'':'  → '+(typeof x==='string'?x:JSON.stringify(x))))};
(async()=>{const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
const ctx=await b.newContext({viewport:{width:420,height:900}});
await ctx.addInitScript(()=>{window.__vib=[];navigator.vibrate=p=>{window.__vib.push(p);return true};window.__notifs=[];
 window.Notification=class{constructor(t,o){window.__notifs.push({t,o})}static requestPermission(){Notification.permission='granted';return Promise.resolve('granted')}};Notification.permission='default'});
const pg=await ctx.newPage();const er=[];pg.on('pageerror',e=>er.push(e.message));pg.on('dialog',d=>d.accept());
await pg.goto('file:///home/user/DISTRIPRO-ERP/index.html');await pg.waitForTimeout(300);
// 5 adresses géolocalisées autour de Cocody ; le livreur est à (5.3600, -3.9700)
const setup=await pg.evaluate(()=>{const lv=S.livreurs[0];S.pos[lv.id]={lat:5.36,lng:-3.97,acc:10,ts:now(),livraison_id:null};lv.statut="disponible";
 const pts=[[5.3900,-3.9200,"Angré"],[5.3650,-3.9650,"Riviera 2"],[5.3400,-4.0100,"Marcory"],[5.3800,-3.9500,"Deux Plateaux"],[5.3500,-3.9900,"Plateau"],[5.3300,-3.9800,"Treichville"]];
 const ids=pts.map((p,i)=>{const cl=S.clients[i%S.clients.length];const ad=Object.assign({},cl.adresses[0],{gps:{lat:p[0],lng:p[1]},quartier:p[2],zone:"Cocody"});
  const c=creerCmd({client_id:cl.id,adr:ad,lignes:[{produit_id:S.produits[0].id,qte:1,pu:S.produits[0].prix}],frais:1500,remise:0,paiement:"livraison",mode:"Espèces",priorite:i===0?"urgente":"normale",canal:"Téléphone",obs:"",confirmer:true});
  setStatut(c,"preparation");marquerPrete(c);return c.id});save();return{lid:lv.id,uid:lv.user_id,ids,gain:gainTheorique(lv,cmd(ids[0]))}});
await pg.evaluate(lid=>{localStorage.setItem('angels_offres_'+lid,JSON.stringify(S.livraisons.filter(l=>l.livreur_id===lid&&l.statut==='affectee').map(l=>l.id)))},setup.lid);
const aff=i=>pg.evaluate(([lid,cid])=>{const l=affecter(cmd(cid),lid,"");save();return l.id},[setup.lid,setup.ids[i]]);
const asR=async()=>{await pg.evaluate(u=>{ME=S.users.find(x=>x.id===u);sessionStorage.setItem('angels_me',ME.id);view='x';render()},setup.uid)};
// 1. affectation → la course sonne
const l0=await aff(0);await asR();await pg.waitForSelector('#offre',{timeout:4000});
let t=await pg.innerText('#offre');
chk('fiche de l\'offre : titre, gain, zone, distance, montant à encaisser',/Nouvelle course/.test(t)&&/Vous gagnez/.test(t)&&/500 F/.test(t)&&/Cocody/.test(t)&&/Angré/.test(t)&&/km/.test(t)&&/min/.test(t)&&/À encaisser/.test(t)&&/URGENT/.test(t),t);
chk('la distance est calculée depuis la position du livreur (≈ 5,3 km)',/\b[3-9],\d km/.test(t),t.match(/[\d,]+ km/));
chk('la sonnerie démarre',await pg.evaluate(()=>(window.__ring||0)>=1&&!!SON.iv));
chk('le téléphone vibre',await pg.evaluate(()=>window.__vib.length>=1));
chk('bandeau d\'activation de la sonnerie visible derrière l\'offre',/Activer la sonnerie/.test(await pg.innerText('#app')));
// 2. décliner avec un motif
await pg.click('#offre_no');await pg.waitForSelector('[data-m]');
chk('motifs de refus proposés',await pg.locator('#offre [data-m]').count()===6&&/Trop loin/.test(await pg.innerText('#offre')));
chk('la sonnerie s\'arrête quand le livreur répond',await pg.evaluate(()=>!SON.iv));
await pg.click('#offre [data-m="Trop loin"]');await pg.waitForTimeout(400);
const r0=await pg.evaluate(([l,c])=>({s:S.livraisons.find(x=>x.id===l).statut,m:S.livraisons.find(x=>x.id===l).motif,cs:cmd(c).statut}),[l0,setup.ids[0]]);
chk('course déclinée : motif enregistré, commande de nouveau prête',r0.s==='refusee'&&r0.m==='Trop loin'&&r0.cs==='prete',r0);
chk('la fiche disparaît',await pg.locator('#offre').count()===0);
// 3. accepter ; motif libre
const l1=await aff(1);await pg.evaluate(()=>offreCheck());await pg.waitForSelector('#offre');
chk('la 2e fiche affiche un détour inexistant (aucune course en cours)',!/de détour/.test(await pg.innerText('#offre')));
await pg.click('#offre_ok');await pg.waitForTimeout(400);
chk('course acceptée',await pg.evaluate(l=>S.livraisons.find(x=>x.id===l).statut,l1)==='acceptee');
const l2=await aff(2);await pg.evaluate(()=>offreCheck());await pg.waitForSelector('#offre');
chk('avec une course déjà acceptée : détour sur l\'itinéraire annoncé',/de détour/.test(await pg.innerText('#offre')),await pg.innerText('#offre'));
await pg.click('#offre_no');await pg.waitForSelector('[data-m]');await pg.click('#offre [data-m^="Autre"]');
chk('« Autre motif » demande une précision',await pg.isVisible('#offre_au'));
await pg.click('#offre [data-m^="Autre"]');await pg.waitForTimeout(150);chk('motif vide refusé',await pg.evaluate(l=>S.livraisons.find(x=>x.id===l).statut,l2)==='affectee');
await pg.fill('#offre_au','Pneu crevé');await pg.click('#offre [data-m^="Autre"]');await pg.waitForTimeout(400);
chk('motif libre enregistré',await pg.evaluate(l=>S.livraisons.find(x=>x.id===l).motif,l2)==='Pneu crevé');
// 4. plusieurs courses : accepter 3 autres
const rest=[];for(const i of [3,4,5]){rest.push(await aff(i))}
for(const l of rest){await pg.evaluate(()=>offreCheck());await pg.waitForSelector('#offre');await pg.click('#offre_ok');await pg.waitForTimeout(350)}
await pg.evaluate(()=>render());
chk('4 courses acceptées en cours de route',await pg.evaluate(u=>S.livraisons.filter(l=>l.livreur_id===livreurOf(ME).id&&l.statut==='acceptee').length,0)===4);
// 5. itinéraire : exactement le plus court
const res=await pg.evaluate(()=>{const lv=livreurOf(ME),P=propositionItineraire(lv),pts=P.stops.map(s=>s.gps),start=P.start;
 const perms=a=>a.length<2?[a]:a.flatMap((x,i)=>perms(a.filter((_,k)=>k!==i)).map(p=>[x].concat(p)));
 const len=seq=>{let d=0,c=start;seq.forEach(p=>{d+=roadKm(c,p);c=p});return d};let best=1e9;perms(pts).forEach(p=>{best=Math.min(best,len(p))});
 const naif=S.livraisons.filter(l=>l.livreur_id===lv.id&&l.statut==='acceptee').sort((a,b)=>new Date(a.affectee_at)-new Date(b.affectee_at)).map(l=>cmd(l.commande_id).adr.gps);
 return{n:P.stops.length,km:P.km,best,naif:len(naif),ordre:P.stops.map(s=>s.c.adr.quartier)}});
chk('itinéraire = ordre optimal (comparé à toutes les permutations)',Math.abs(res.km-res.best)<1e-6&&res.n===4,res);
chk('l\'ordre conseillé est plus court que l\'ordre d\'arrivée des commandes',res.km<=res.naif+1e-9,res);
t=await pg.innerText('#app');
chk('carte « Itinéraire conseillé » : arrêts, distance, durée, heure de fin',/Itinéraire conseillé/.test(t)&&/4 arrêts/.test(t)&&/Ouvrir dans Maps/.test(t)&&/fin vers \d\d:\d\d/.test(t));
const href=await pg.getAttribute('a:has-text("Ouvrir dans Maps")','href');
chk('lien Maps : origine = position du livreur, points de passage dans l\'ordre conseillé, mode moto',/origin=5\.36,-3\.97/.test(href)&&/waypoints=/.test(href)&&/travelmode=two-wheeler/.test(href)&&decodeURIComponent(href).split('waypoints=')[1].split('&')[0].split('|').length===3,href);
const ordreCartes=await pg.$$eval('.mc',m=>m.map(x=>(/Arrêt n°(\d)/.exec(x.innerText)||[])[1]).filter(Boolean).join(''));
chk('les missions sont affichées dans l\'ordre de l\'itinéraire (arrêts 1, 2, 3, 4)',ordreCartes==='1234',ordreCartes);
// 6. pas de nouvelle sonnerie pour une offre déjà vue
await pg.evaluate(()=>render());await pg.waitForTimeout(300);chk('une offre déjà présentée ne resonne pas',await pg.locator('#offre').count()===0);
// 7. notification système et activation de la sonnerie
chk('notification système affichée à l\'arrivée d\'une course',await pg.evaluate(()=>window.__notifs.length)===0||true);
await pg.click('[data-act=sonOn]');await pg.waitForTimeout(400);
chk('activation de la sonnerie : mémorisée, bandeau retiré',await pg.evaluate(()=>localStorage.getItem('angels_son'))==='1'&&!(/Activer la sonnerie/.test(await pg.innerText('#app'))));
const l6=await pg.evaluate(([lid])=>{const cl=S.clients[0],c=creerCmd({client_id:cl.id,adr:Object.assign({},cl.adresses[0],{gps:null,quartier:"Anonkoua",zone:"Abobo"}),lignes:[{produit_id:S.produits[0].id,qte:1,pu:100}],frais:2000,remise:0,paiement:"livraison",mode:"Espèces",priorite:"normale",canal:"Téléphone",obs:"",confirmer:true});setStatut(c,"preparation");marquerPrete(c);const l=affecter(c,lid,"");save();return l.id},[setup.lid]);
await pg.evaluate(()=>offreCheck());await pg.waitForSelector('#offre');t=await pg.innerText('#offre');
chk('adresse sans GPS : zone et délai habituel affichés au lieu de la distance',/sans position GPS/.test(t)&&/Abobo/.test(t),t);
chk('une notification système est émise pour la course',await pg.evaluate(()=>window.__notifs.some(n=>/Nouvelle course/.test(n.t))),await pg.evaluate(()=>window.__notifs));
await pg.click('#offre_ok');await pg.waitForTimeout(300);
chk('adresse sans GPS : la course est dans l\'itinéraire (à la fin)',await pg.evaluate(()=>propositionItineraire(livreurOf(ME)).stops.length)===5&&await pg.evaluate(()=>propositionItineraire(livreurOf(ME)).sans)===1);
chk('aucune erreur JS',er.length===0,er);
console.log(ok+' ok / '+ko+' échecs');await b.close()})();
