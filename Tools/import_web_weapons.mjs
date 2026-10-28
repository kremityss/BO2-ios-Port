#!/usr/bin/env node
// Generate native weapon data from the pinned deployed web-game module exports.
// Source files are parsed as ESM by Node; no eval, browser execution, or CDN code.
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { pathToFileURL } from 'node:url';
const url='https://56538cf3.merk-of-duty.pages.dev/';
const args=process.argv.slice(2);
const out=args[args.indexOf('--out')+1];
if(!out || args.indexOf('--out')<0) throw new Error('--out path is required');
const existing=args.includes('--source-dir') ? args[args.indexOf('--source-dir')+1] : null;
const dir=await fs.mkdtemp(path.join(os.tmpdir(),'bo2-source-'));
try {
  for(const name of ['weapons','weapon-ballistics']){
    const body=existing ? await fs.readFile(path.join(existing,name+'.js'),'utf8') : await (async()=>{
      const r=await fetch(url+name+'.js');if(!r.ok)throw new Error(`${name} HTTP ${r.status}`);
      const s=await r.text();if(s.length>500000)throw new Error('Source exceeds cap');return s;
    })();
    await fs.writeFile(path.join(dir,name+'.mjs'),body);
  }
  const w=await import(pathToFileURL(path.join(dir,'weapons.mjs')).href);
  const b=await import(pathToFileURL(path.join(dir,'weapon-ballistics.mjs')).href);
  if(!w.WEAPONS?.m27 || !b.WEAPON_BALLISTICS?.m27) throw new Error('Incorrect web module exports');
  const weapons={};
  for(const [id,def] of Object.entries(w.WEAPONS)){
    weapons[id]={id,name:def.name,class:def.class,role:def.role,magazineSize:def.magazineSize,
      reserveAmmo:def.reserveAmmo,roundsPerMinute:def.roundsPerMinute,
      initialRoundsPerMinute:def.initialRoundsPerMinute??null,initialShotCount:def.initialShotCount??0,
      fireMode:def.fireMode,burstCount:def.burstCount??0,damage:def.damage,
      ballistics:b.WEAPON_BALLISTICS?.[id]??null};
  }
  const v={version:1,source:'web weapons.js + weapon-ballistics.js',defaultLoadout:w.DEFAULT_LOADOUT,
           weapons};
  if(Object.keys(weapons).length<12) throw new Error('Unexpectedly small weapon registry');
  await fs.mkdir(path.dirname(out),{recursive:true});await fs.writeFile(out,JSON.stringify(v,null,2)+'\n');
  console.log('Exported',Object.keys(weapons).length,'authored weapons into',out);
}finally{await fs.rm(dir,{recursive:true,force:true});}
