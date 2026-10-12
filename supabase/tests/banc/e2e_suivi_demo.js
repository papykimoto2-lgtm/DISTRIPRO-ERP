const { chromium } = require('/opt/node-tools/node_modules/playwright');
let ok=0,ko=0;const chk=(n,c,x)=>{c?ok++:ko++;console.log((c?'✔':'✘')+' '+n+(c?'':'  → '+(x||'')))};
(async()=>{const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
const ctx=await b.newContext({viewport:{width:1100,height:850}});const pg=await ctx.newPage();const er=[];pg.on('pageerror',e=>er.push(e.message));pg.on('dialog',d=>d.accept());
await pg.goto('file:///home/user/DISTRIPRO-ERP/index.html');await pg.waitForTimeout(400);await pg.click('.pcard >> nth=0');await pg.waitForTimeout(300);
chk('KPI satisfaction au tableau de bord',/Satisfaction client/.test(await pg.innerText('body')));
await pg.click('aside a:has-text("Livreurs")');chk('colonne Avis clients',/★ \d\.\d/.test(await pg.innerText('body')));
// ETA dans formulaire
await pg.click('aside a:has-text("Commandes")');await pg.click('button:has-text("Nouvelle commande")');await pg.waitForSelector('#f_client');
await pg.selectOption('#f_client',{index:1});await pg.waitForTimeout(300);chk('délai estimé dans le formulaire',/estimé \d+ min/.test(await pg.innerText('#f_eta')),await pg.innerText('#f_eta'));await pg.evaluate(()=>closeModal());
// commande en route
const ids=await pg.evaluate(()=>({enr:S.commandes.find(c=>c.statut==="en_cours").id,liv:S.commandes.find(c=>c.statut==="livree"&&!S.avis.some(a=>a.livraison_id===livsOf(c.id).slice(-1)[0].id))}));
chk('bouton lien de suivi',await pg.evaluate(id=>{cmdDetail(id);return document.body.innerText.includes('Lien de suivi client')},ids.enr));await pg.evaluate(()=>closeModal());
await pg.evaluate(id=>ACT.suiviLien(id),ids.enr);await pg.waitForTimeout(300);
const link=await pg.inputValue('#modal input[readonly]');console.log('lien:',link.slice(-40));chk('lien #suivi=',/#suivi=/.test(link));
// ouvrir la page client (même appareil)
const cp=await ctx.newPage();cp.on('pageerror',e=>er.push('client:'+e.message));await cp.goto(link);await cp.waitForTimeout(1200);
let t=await cp.innerText('body');console.log(t.replace(/\n+/g,' | ').slice(0,420));
chk('statut « en route »',/Votre livreur est en route/.test(t));chk('arrivée estimée',/Arrivée estimée vers \d\d:\d\d/.test(t));chk('prénom du livreur seul',/Kouamé/.test(t)&&!/Kouamé Yves/.test(t));
chk('code non affiché',!/code\s*:?\s*\d{4}/i.test(t));chk('étapes',(await cp.$$('.stp li')).length===6);
await cp.screenshot({path:'s_suivi.png'});
// notation d'une commande livrée
const vd=await pg.evaluate(()=>{const c=S.commandes.find(c=>c.statut==="livree");const l=livsOf(c.id).slice(-1)[0];S.avis=S.avis.filter(a=>a.livraison_id!==l.id);save();return c.id});
await cp.goto('about:blank');await cp.goto(link.replace(/#suivi=.*/,'#suivi='+vd));await cp.waitForTimeout(1000);
chk('invitation à noter',await cp.isVisible('#sv_st'));
await cp.click('#sv_st button >> nth=3');await cp.fill('#sv_cm','Merci');await cp.click('#sv_ok');await cp.waitForTimeout(1500);
t=await cp.innerText('body');chk('merci pour votre avis ★★★★☆',/Merci pour votre avis/.test(t)&&/★★★★☆/.test(t),t.slice(0,200));
chk('avis enregistré (démo)',await pg.evaluate(()=>{const d=JSON.parse(localStorage.getItem(KEY));return d.avis.some(a=>a.note===4&&a.commentaire==="Merci")}));
await cp.goto('about:blank');await cp.goto(link.replace(/#suivi=.*/,'#suivi=inconnu'));await cp.waitForTimeout(600);chk('commande inconnue',/introuvable/i.test(await cp.innerText('body')));
console.log('erreurs JS',er);console.log(ok+' ok / '+ko+' échecs');await b.close()})();
