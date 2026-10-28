#!/usr/bin/env python3
"""Download immutable deployed web-game reference source for native port audit.

This does not execute the game or modify the Cloudflare deployment.
"""
import json, re, urllib.request, pathlib, hashlib, sys
BASE='https://56538cf3.merk-of-duty.pages.dev/'
FILES=[
 'index.html','maps.js','player-controller.js','movement-settings.js','navigation.js',
 'normal-modes.js','touch-controls.js','gunplay.js','weapon-controller.js',
 'weapon-ballistics.js','weapons.js','enemy-system.js','enemy-tactics.js',
 'team-deathmatch-match.js','free-for-all-match.js','hud.js','player-health.js',
 'viewmodel.js','nuketown_2020_nav_hints.json','nuketown_2020.navmesh.json',
 'nuketown_2020_collision_bvh.json','zombies.js'
]
PATTERN=re.compile(r'\b(spawn|respawn|startPosition|playerStart|spawnPoint|spawnLocation|spawnPosition|spawnOrigin|selectSpawn|chooseSpawn|spawnCandidates|spawnLocations|movementSpeed|sprintSpeed|slideSpeed|jumpVelocity|walkSpeed|gravity|fireRate|reloadTime|loadout|tacticalSprint)\b', re.I)
OUT=pathlib.Path('build/web-reference')
OUT.mkdir(parents=True,exist_ok=True)
report={'reference_base':BASE,'files':[],'snippets':{}}
for filename in FILES:
    request=urllib.request.Request(BASE+filename,headers={'User-Agent':'BO2-Native-Reference-Audit/1.0'})
    try:
        with urllib.request.urlopen(request, timeout=45) as response:
            data=response.read(3_000_001)
        if len(data)>3_000_000: raise ValueError('Source file exceeds 3 MB safety limit')
        if data[:200].lower().find(b'<html')>=0 and not filename.endswith('.html'):
            raise ValueError('Unexpected HTML response for source file')
        (OUT/filename).write_bytes(data)
        text=data.decode('utf-8',errors='replace')
        lines=text.splitlines()
        if filename.endswith('.json'):
            j=json.loads(text)
            print('JSON', filename, 'top keys',list(j)[:25] if isinstance(j,dict) else 'array')
        hits=[]
        for i, line in enumerate(lines):
            if PATTERN.search(line):
                lo=max(0,i-4);hi=min(len(lines),i+6)
                hits.append({'line':i+1,'context':'\n'.join(f'{k+1}: {lines[k]}' for k in range(lo,hi))[:1100]})
        report['files'].append({'name':filename,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest(),'matched_lines':len(hits)})
        report['snippets'][filename]=hits[:90]
        print('FETCH',filename,len(data),'bytes','matches',len(hits))
    except Exception as exc:
        report['files'].append({'name':filename,'error':str(exc)})
        print('ERROR',filename,exc)
(OUT/'audit-report.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
# Native changes must not ship from a failed source inspection.
required=['player-controller.js','movement-settings.js','navigation.js','weapons.js','nuketown_2020_nav_hints.json']
missing=[name for name in required if not (OUT/name).exists()]
print('AUDIT REQUIRED MISSING',missing)
if missing:sys.exit(1)
