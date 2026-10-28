#!/usr/bin/env python3
"""Fail the full iOS build if either native map silently falls back to dummy data."""
import json
import struct
from pathlib import Path

MAPS=(('NUKETOWN 2025','', 'mp_nuketown_2020'),
      ('HIJACKED','Hijacked','mp_hijacked'))

def validate(root):
    root=Path(root)
    results=[]
    for display,suffix,expected_id in MAPS:
        def path(name,ext):
            return root/(name+suffix+'.'+ext)
        mesh=path('MerkMap','meshbin')
        atlas=path('MerkAtlas','png')
        coll=path('MerkCollision','bin')
        spawns=path('MerkWebSpawns','json')
        instances=path('MerkInstances','bin')
        for file in [mesh,atlas,coll,spawns,instances]:
            if not file.is_file():
                raise ValueError(f'{display}: missing {file.name}')
        if mesh.stat().st_size<15000 or mesh.open('rb').read(8)!=b'MERKMAP2':
            raise ValueError(f'{display}: invalid or placeholder mesh')
        if atlas.stat().st_size<20000 or atlas.open('rb').read(8)!=b'\x89PNG\r\n\x1a\n':
            raise ValueError(f'{display}: no real decoded texture atlas')
        raw=coll.read_bytes()
        if raw[:8]!=b'MERKCOL1':raise ValueError(f'{display}: invalid collision')
        w,h=struct.unpack_from('<HH',raw,8)
        if not (w>=50 and h>=50 and len(raw)==24+w*h*6):
            raise ValueError(f'{display}: damaged collision grid')
        floors=[struct.unpack_from('<h',raw,24+6*i)[0] for i in range(w*h)]
        walkable=sum(1 for y in floors if y!=-32768)
        if walkable<3000:
            raise ValueError(f'{display}: insufficient walkable floor: {walkable}')
        hints=json.loads(spawns.read_text())
        if hints.get('map')!=expected_id or len(hints.get('spawns',[]))<30:
            raise ValueError(f'{display}: wrong map spawn registry')
        if instances.stat().st_size<12 or instances.open('rb').read(8)!=b'MERKINS1':
            raise ValueError(f'{display}: missing instanced scenery')
        results.append({'map':display,'mesh_bytes':mesh.stat().st_size,
                        'atlas_bytes':atlas.stat().st_size,'walkable':walkable,
                        'spawns':len(hints['spawns'])})
    enemy=root/'MerkEnemyAssault.meshbin'
    enemyAtlas=root/'MerkEnemyAssaultAtlas.png'
    if not enemy.is_file() or enemy.stat().st_size<10000:
        raise ValueError('Native soldier model missing')
    if not enemyAtlas.is_file() or enemyAtlas.stat().st_size<15000:
        raise ValueError('Native soldier textures missing')
    if (root/'MerkMapHijacked.meshbin').stat().st_size == (root/'MerkMap.meshbin').stat().st_size:
        # The final 'path' resolves Hijacked, so detect accidentally duplicated scenes.
        raise ValueError('Nuketown and Hijacked have identical scene content')
    print(json.dumps({'validated':results,'soldier_bytes':enemy.stat().st_size},indent=2))
    return results

if __name__=='__main__':
    import sys
    validate(Path(sys.argv[1]) if len(sys.argv)>1 else Path('MerkOfDuty/Resources'))
