const { chromium } = require('/opt/node-tools/node_modules/playwright');
let ok=0,ko=0;const chk=(n,c,x)=>{c?ok++:ko++;console.log((c?'✔':'✘')+' '+n+(c?'':'  → '+(typeof x==='string'?x:JSON.stringify(x))))};
(async()=>{const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
const pg=await (await b.newContext({viewport:{width:1300,height:900}})).newPage();const er=[];pg.on('pageerror',e=>er.push(e.message));pg.on('dialog',d=>d.accept());
await pg.goto('file:///home/user/DISTRIPRO-ERP/index.html');await pg.waitForTimeout(300);
const as=async role=>{await pg.evaluate(r=>{ME=S.users.find(u=>u.role===r);sessionStorage.setItem('angels_me',ME.id);view='dashboard';render()},role);await pg.waitForTimeout(150)};
await as('admin');
// ordinateur
chk('ordinateur : barre latérale visible, pas de bouton menu',!(await pg.isVisible('.burger'))&&await pg.isVisible('aside .navp')&&await pg.isVisible('aside [data-id=commandes]'));
for(const [w,h,nom] of [[420,850,'smartphone'],[820,1100,'tablette portrait'],[1024,768,'tablette paysage']]){
 await pg.setViewportSize({width:w,height:h});await pg.waitForTimeout(150);
 chk(`${nom} (${w}px) : bouton ☰ et titre de la page, menu replié`,await pg.isVisible('.burger')&&/Tableau de bord/.test(await pg.innerText('.mtit'))&&!(await pg.isVisible('.navp')));
 await pg.click('.burger');await pg.waitForTimeout(100);
 const items=await pg.$$eval('.navp a[data-act=nav]',a=>a.map(x=>{const r=x.getBoundingClientRect();return{y:Math.round(r.top),x:Math.round(r.left),w:Math.round(r.width)}}));
 const vertical=items.every((it,i)=>i===0||it.y>items[i-1].y)&&new Set(items.map(i=>i.x)).size===1;
 chk(`${nom} : liste verticale, un élément par ligne (${items.length} entrées)`,await pg.isVisible('.navp')&&items.length>=15&&vertical,items.slice(0,4));
 chk(`${nom} : titres de section visibles dans le menu`,(await pg.$$eval('.navp .gt',g=>g.filter(x=>x.offsetParent).length))>=6);
 chk(`${nom} : bouton devient ✕, aria-expanded vrai`,(await pg.innerText('.burger'))==='✕'&&await pg.getAttribute('.burger','aria-expanded')==='true');
 chk(`${nom} : le menu tient dans l'écran et défile`,await pg.evaluate(()=>{const e=document.querySelector('.navp'),p=e.getBoundingClientRect();return p.bottom<=innerHeight-50&&e.scrollHeight>=e.clientHeight}),await pg.evaluate(()=>{const e=document.querySelector('.navp'),p=e.getBoundingClientRect();return[Math.round(p.top),Math.round(p.bottom),innerHeight,e.scrollHeight]}));
 await pg.click('.navp [data-id=commandes]');await pg.waitForTimeout(200);
 chk(`${nom} : choisir une page ferme le menu et ouvre la page`,!(await pg.isVisible('.navp'))&&/Commandes/.test(await pg.innerText('.mtit'))&&await pg.evaluate(()=>view)==='commandes');
 await pg.click('.burger');await pg.mouse.click(w/2,h-20);await pg.waitForTimeout(100);chk(`${nom} : toucher en dehors ferme le menu`,!(await pg.isVisible('.navp')));
 await pg.click('.burger');await pg.keyboard.press('Escape');await pg.waitForTimeout(100);chk(`${nom} : Échap ferme le menu`,!(await pg.isVisible('.navp')));
 await pg.evaluate(()=>window.scrollTo(0,600));await pg.waitForTimeout(100);chk(`${nom} : la barre reste visible en haut quand on défile`,await pg.evaluate(()=>Math.round(document.querySelector('aside').getBoundingClientRect().top))===0||await pg.evaluate(()=>document.documentElement.scrollHeight<=innerHeight+10));
 await pg.evaluate(()=>{ACT.menuClose();view='dashboard';render()});
}
// le menu ouvert n'est pas refermé par le rafraîchissement automatique
await pg.setViewportSize({width:420,height:850});await pg.click('.burger');await pg.evaluate(()=>render());await pg.waitForTimeout(100);chk('un rafraîchissement garde le menu ouvert et le bouton ✕',await pg.isVisible('.navp')&&(await pg.innerText('.burger'))==='✕');
// passage à l'ordinateur pendant que le menu est ouvert
await pg.setViewportSize({width:1300,height:900});await pg.waitForTimeout(200);chk('retour en grand écran : menu refermé, barre latérale normale',!(await pg.evaluate(()=>document.body.classList.contains('menu-open')))&&await pg.isVisible('aside [data-id=commandes]'));
// autres profils
await pg.setViewportSize({width:420,height:850});
await as('vendeur');chk('vendeur sur smartphone : menu déroulant avec ses 2 pages',await pg.isVisible('.burger')&&(await pg.$$eval('.navp a[data-act=nav]',a=>a.length))===2);
await as('caissier');await pg.click('.burger');chk('caissier : déconnexion et couleurs dans le menu',await pg.isVisible('.navp [data-act=logout]')&&await pg.isVisible('.navp .themes'));
await pg.screenshot({path:'menu_mobile_ouvert.png'});await pg.click('.burger');await pg.screenshot({path:'menu_mobile_ferme.png',clip:{x:0,y:0,width:420,height:200}});
// le livreur garde son écran dédié
await as('livreur');chk('livreur : écran dédié inchangé (pas de menu latéral)',await pg.locator('aside').count()===0&&await pg.isVisible('.lv'));
chk('aucune erreur JS',er.length===0,er);console.log(ok+' ok / '+ko+' échecs');await b.close()})();
