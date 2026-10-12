const { chromium } = require('/opt/node-tools/node_modules/playwright');
let ok=0,ko=0;const chk=(n,c,x)=>{c?ok++:ko++;console.log((c?'✔':'✘')+' '+n+(c?'':'  → '+(typeof x==='string'?x:JSON.stringify(x))))};
const png=i=>Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==','base64');
const F=(n)=>Array.from({length:n},(_,i)=>({name:'p'+i+'.png',mimeType:'image/png',buffer:png(i)}));
(async()=>{const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
const pg=await (await b.newContext({viewport:{width:1280,height:950}})).newPage();const er=[];pg.on('pageerror',e=>er.push(e.message));pg.on('dialog',d=>d.accept());
await pg.goto('file:///home/user/DISTRIPRO-ERP/index.html');await pg.waitForTimeout(300);
await pg.evaluate(()=>{const u=S.users.find(u=>u.role==='vendeur');ME=u;sessionStorage.setItem('angels_me',u.id);view='mesCmd';render()});
// 1. photos dès la création
await pg.click('button:has-text("Nouvelle commande")');await pg.waitForSelector('#v_phf',{state:'attached'});
await pg.fill('input[name=nom]','Cli Photo');await pg.fill('input[name=tel]','0707121212');await pg.fill('input[name=quartier]','Angré');await pg.fill('.vd >> nth=0','Montre');await pg.fill('.vp >> nth=0','12000');
await pg.setInputFiles('#v_phf',F(2));await pg.waitForTimeout(600);
chk('formulaire : 2 photos visibles avant dépôt',await pg.locator('#v_ph .wthumb').count()===2);
await pg.click('#v_ph .wthumb button');chk('formulaire : une photo retirée',await pg.locator('#v_ph .wthumb').count()===1);
await pg.click('#mf .mf .btn:not(.ghost)');await pg.waitForTimeout(500);
const c=await pg.evaluate(()=>{const c=S.commandes.find(c=>cli(c.client_id).nom==='Cli Photo');return c&&{id:c.id,n:(c.photos||[]).length,st:c.statut}});
chk('commande créée avec sa photo',c&&c.n===1&&c.st==='attente',c);
let t=await pg.innerText('body');chk('ligne de commande : bouton photos avec compteur',/📷 1/.test(t));
// 2. ajout / retrait sur une commande existante
await pg.evaluate(id=>ACT.cmdPhotos(id),c.id);await pg.waitForSelector('#ph_f',{state:'attached'});
chk('gestionnaire : 1 photo + bouton d\'ajout',await pg.locator('.wph img').count()===1&&/1\/8/.test(await pg.innerText('#mf')));
await pg.setInputFiles('#ph_f',F(2));await pg.waitForTimeout(800);
chk('2 photos ajoutées → 3',await pg.locator('.wph img').count()===3&&await pg.evaluate(id=>cmd(id).photos.length,c.id)===3);
await pg.click('.wph .wthumb button >> nth=0');await pg.waitForTimeout(400);
chk('une photo retirée → 2',await pg.locator('.wph img').count()===2&&await pg.evaluate(id=>cmd(id).photos.length,c.id)===2);
await pg.setInputFiles('#ph_f',F(9));await pg.waitForTimeout(1500);
chk('limite de 8 photos respectée',await pg.evaluate(id=>cmd(id).photos.length,c.id)===8&&await pg.locator('.wph img').count()===8);
chk('compteur 8/8',/8\/8/.test(await pg.innerText('#mf')));
// 3. détail de commande pour une commande sans photo
const c2=await pg.evaluate(()=>{const v=vend();const x=S.commandes.find(c=>c.vendeur_id===v.id&&!nPhotos(c)&&!['livree','annulee'].includes(c.statut));return x&&x.id});
await pg.evaluate(()=>closeModal());
await pg.evaluate(id=>ACT.cmdDetail(id),c2);await pg.waitForTimeout(300);chk('détail : bouton « Ajouter des photos »',/Ajouter des photos/.test(await pg.innerText('body')));
await pg.evaluate(()=>closeModal());
// 4. commande terminée : lecture seule ; commande d'un autre vendeur : pas d'ajout
const liv=await pg.evaluate(()=>{const v=vend();const x=S.commandes.find(c=>c.vendeur_id===v.id&&c.statut==='livree');if(x){x.photos=x.photos||['data:image/png;base64,AAAA'];save()}return x&&x.id});
if(liv){await pg.evaluate(id=>ACT.cmdPhotos(id),liv);await pg.waitForTimeout(400);chk('commande livrée : photos visibles mais ni ajout ni retrait',await pg.locator('#ph_f').count()===0&&await pg.locator('.wph .wthumb button').count()===0&&/terminée/.test(await pg.innerText('#mf')));await pg.evaluate(()=>closeModal())}
const autre=await pg.evaluate(()=>{const v=vend();const x=S.commandes.find(c=>c.vendeur_id!==v.id&&!['livree','annulee'].includes(c.statut));return x&&x.id});
chk('commande d\'un autre : droit d\'ajout refusé',await pg.evaluate(id=>canPhoto(cmd(id)),autre)===false);
// 5. admin peut ajouter
await pg.evaluate(()=>{ME=S.users.find(u=>u.role==='admin');sessionStorage.setItem('angels_me',ME.id);view='commandes';render()});
await pg.evaluate(id=>ACT.cmdPhotos(id),c2);await pg.waitForSelector('#ph_f',{state:'attached'});await pg.setInputFiles('#ph_f',F(1));await pg.waitForTimeout(700);
chk('l\'administrateur ajoute une photo à la commande du vendeur',await pg.evaluate(id=>cmd(id).photos.length,c2)===1);
// 6. livreur : lecture seule
await pg.evaluate(()=>{closeModal();ME=S.users.find(u=>u.role==='livreur');sessionStorage.setItem('angels_me',ME.id);render()});
chk('un livreur ne peut pas ajouter',await pg.evaluate(id=>canPhoto(cmd(id)),c2)===false);
chk('aucune erreur JS',er.length===0,er);
console.log(ok+' ok / '+ko+' échecs');await b.close()})();
