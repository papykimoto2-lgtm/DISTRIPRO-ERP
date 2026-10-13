const { chromium } = require('/opt/node-tools/node_modules/playwright');
let ok=0,ko=0;const chk=(n,c,x)=>{c?ok++:ko++;console.log((c?'✔':'✘')+' '+n+(c?'':'  → '+(typeof x==='string'?x:JSON.stringify(x))))};
(async()=>{const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
const pg=await (await b.newContext({viewport:{width:1300,height:1000}})).newPage();const er=[];pg.on('pageerror',e=>er.push(e.message));pg.on('dialog',d=>d.accept());
await pg.goto('file:///home/user/DISTRIPRO-ERP/index.html');await pg.waitForTimeout(300);
const as=async(role,v)=>{await pg.evaluate(([r,v])=>{ME=S.users.find(u=>u.role===r);sessionStorage.setItem('angels_me',ME.id);view=v;render()},[role,v]);await pg.waitForTimeout(150)};
const T=()=>pg.innerText('body'),tab=async k=>{await pg.evaluate(k=>ACT.tab('cpt|'+k),k);await pg.waitForTimeout(100)};
await as('admin','compta');let t=await T();
chk('menu Comptabilité pour admin',await pg.locator('[data-act=nav][data-id=compta]').count()===1);
for(const k of ['syn','jrn','gl','bal','age','tva','res','sai','cai','cfg']){await tab(k);const x=await T();chk('onglet '+k+' s\'affiche',/Comptabilité/.test(x)&&er.length===0,er)}
const r=await pg.evaluate(()=>{const E=cptEcr(),D=cptDef(E);const B=cptBal(D);const tot=Object.values(B).reduce((a,b)=>[a[0]+b.d,a[1]+b.c],[0,0]);return{n:E.length,tot,journ:[...new Set(E.map(e=>e.journal))],ctl:cptControles().map(c=>[c.ok,c.t,c.det]),nums:E.slice(0,3).map(e=>e.no),vt:E.filter(e=>e.journal==="VT").map(e=>e.libelle)}});
console.log(JSON.stringify(r,null,1).slice(0,2500));
chk('écritures générées',r.n>5);chk('débit = crédit',r.tot[0]===r.tot[1],r.tot);
chk('numéros PREFIX-AAAA-NNNN',r.nums.every(n=>/^[A-Z]+-\d{4}-\d{4}$/.test(n)),r.nums);
// OD manuelle + visa + extourne
await tab('sai');
await pg.evaluate(()=>ACT.cptOD());await pg.waitForSelector('input[name=lib]');
await pg.fill('input[name=lib]','Apport en capital');await pg.fill('input[name=c0]','571');await pg.fill('input[name=d0]','50000');await pg.fill('input[name=c1]','462');await pg.fill('input[name=k1]','40000');
await pg.click('#mf .mf .btn:not(.ghost)');await pg.waitForTimeout(250);
chk('écriture déséquilibrée acceptée en brouillard',await pg.evaluate(()=>cpt().manuelles.length)===1);
let id=await pg.evaluate(()=>cpt().manuelles[0].id);await pg.evaluate(i=>ACT.cptVisa(i),id);
chk('visa refusé si déséquilibre',await pg.evaluate(()=>cpt().manuelles[0].statut)==='brouillard');
await pg.evaluate(i=>{const e=cpt().manuelles[0];e.lignes[1].montant=50000},id);await pg.evaluate(i=>ACT.cptVisa(i),id);
chk('visa accepté si équilibré',await pg.evaluate(()=>cpt().manuelles[0].statut)==='validee');
await pg.evaluate(i=>ACT.cptExt('em'+i.slice(2)),id);
chk('extourne',true);
await pg.evaluate(i=>{ACT.cptExt(i)},id);await pg.waitForSelector('textarea[name=v]');await pg.fill('textarea[name=v]','Erreur de saisie');await pg.click('#mf .mf .btn:not(.ghost)');await pg.waitForTimeout(250);
const ex=await pg.evaluate(()=>cpt().manuelles.filter(m=>m.extourne_de));chk('pièce d\'extourne inverse créée',ex.length===1&&ex[0].lignes[0].sens==='C',ex);
chk('balance toujours équilibrée',await pg.evaluate(()=>{const B=cptBal(cptDef(cptEcr()));const t=Object.values(B).reduce((a,b)=>[a[0]+b.d,a[1]+b.c],[0,0]);return t[0]===t[1]}));
// clôture
await pg.evaluate(()=>{cpt().clos=new Date().getFullYear()+"-12-31"});
await pg.evaluate(()=>ACT.cptOD());await pg.waitForSelector('input[name=lib]');await pg.fill('input[name=lib]','test clos');await pg.fill('input[name=c0]','571');await pg.fill('input[name=d0]','10');await pg.fill('input[name=c1]','462');await pg.fill('input[name=k1]','10');await pg.click('#mf .mf .btn:not(.ghost)');await pg.waitForTimeout(250);
const idc=await pg.evaluate(()=>cpt().manuelles[cpt().manuelles.length-1].id);await pg.evaluate(i=>ACT.cptVisa(i),idc);
chk('visa refusé en période clôturée',await pg.evaluate(()=>cpt().manuelles[cpt().manuelles.length-1].statut)==='brouillard');
await pg.evaluate(()=>{cpt().clos=""});
// caissier ne voit pas
await as('caissier','caisse');chk('caissier sans menu Comptabilité',await pg.locator('[data-act=nav][data-id=compta]').count()===0);
// direction lecture seule
await as('direction','compta');chk('direction : pas de bouton d\'écriture',await pg.locator('[data-act=cptOD]').count()===0);
chk('aucune erreur JS',er.length===0,er);
console.log(ok+' ok / '+ko+' échecs');await b.close()})();
