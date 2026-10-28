#!/usr/bin/env python3
"""Recover a native-renderable published soldier LOD and its WebP materials."""
import argparse
import json
from pathlib import Path
from download_level import BASE
from download_weapons import download_resource, fetch_weapon_images, read_manifest

GLB='enemies/c_chn_mp_pla_assault_fb_lod2.glb'
def download(folder,base=BASE):
    folder=Path(folder)
    if not base.startswith('https://') or not base.endswith('.pages.dev'):
        raise ValueError('Only pinned Pages deployment allowed')
    glb=download_resource(base,folder,GLB)
    manifest=read_manifest(glb)
    for buffer in manifest.get('buffers',[]):
        uri=buffer.get('uri')
        if uri:
            raise ValueError('Unexpected external enemy buffer: '+str(uri))
    textures=fetch_weapon_images(glb,folder,base)
    if not textures['downloaded']:
        raise ValueError('Soldier textures unavailable; refusing cube-only build')
    print(json.dumps({'glb':GLB,'size':glb.stat().st_size,'textures':textures},indent=2))
if __name__=='__main__':
    p=argparse.ArgumentParser()
    p.add_argument('--out',type=Path,default=Path('build/recovered-enemy'))
    a=p.parse_args()
    download(a.out)
