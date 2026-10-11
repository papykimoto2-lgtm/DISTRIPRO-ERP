const { chromium } = require('/opt/node-tools/node_modules/playwright');
const fs=require('fs');
const ANON=fs.readFileSync('/tmp/pgr/anon.key','utf8').trim();
(async()=>{
 const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
 async function sess(ident,pwd){
  const ctx=await b.newContext({viewport:{width:1200,height:1000}});
  await ctx.addInitScript(k=>{window.ANGELS_CLOUD={url:'http://127.0.0.1:3011',key:k}},ANON);
  await ctx.route('https://cdn.jsdelivr.net/npm/@supabase/**',r=>r.fulfill({path:'/tmp/pgr/sbjs/package/dist/umd/supabase.js',contentType:'application/javascript'}));
  const pg=await ctx.newPage();const errs=[];pg.on('pageerror',e=>errs.push(e.message));pg.on('dialog',d=>d.accept());
  pg.errs=errs;
  await pg.goto('file:///home/user/DISTRIPRO-ERP/index.html');
  await pg.waitForSelector('#lf');
  if(ident){await pg.fill('input[name=ident]',ident);await pg.fill('input[name=pwd]',pwd);await pg.click('#lf button');}
  return pg;
 };
 let pg=await sess('admin','mauvais');await pg.waitForTimeout(1500);
 console.log('mauvais mdp:',(await pg.innerText('body')).includes('incorrect'));
 await pg.fill('input[name=pwd]','pwdadmin');await pg.click('#lf button');await pg.waitForTimeout(2500);
 const t=await pg.innerText('body');console.log('admin connecté:',t.includes('Administrateur'),'| erreurs:',pg.errs);
 console.log(t.slice(0,400).replace(/\n+/g,' | '));
 await pg.screenshot({path:'/tmp/claude-0/t/c_admin.png'});
 for(const u of ['awa','koffi','moussa','yao','dg','issa','aya']){
  const p=await sess(u,'pwd'+u);await p.waitForTimeout(2000);
  console.log(u,(await p.innerText('body')).slice(0,90).replace(/\n+/g,' | '),p.errs);
 }
 await b.close();
})();
