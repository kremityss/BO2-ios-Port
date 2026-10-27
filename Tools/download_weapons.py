#!/usr/bin/env python3
"""Download four real, published viewmodels plus GLB sidecars from Cloudflare.

This script only requests references within the pinned Merk Pages deployment.
The optional build step makes textured native mesh assets; no WebView is used.
"""
import argparse
import json
import struct
import urllib.request
from pathlib import Path
from urllib.parse import quote, unquote, urlsplit
from download_level import BASE, fetch_external_images

WEAPONS = {
    'M27':'viewmodel/t6_wpn_ar_hk416_view_lod0.glb',
    'AN94':'viewmodel/t6_wpn_ar_an94_view_lod0.glb',
    'DSR50':'viewmodel/t6_wpn_sniper_dsr50_view_lod0.glb',
    'FiveSeven':'viewmodel/t6_wpn_pistol_fiveseven_view_lod0.glb',
}


def read_manifest(glb):
    data = glb.read_bytes()
    if data[:4] != b'glTF': raise ValueError('Not a GLB file')
    if len(data)<20 or struct.unpack_from('<I',data,4)[0] != 2:
        raise ValueError('Unsupported GLB version')
    cursor = 12
    while cursor+8 <= len(data):
        n, tag = struct.unpack_from('<I4s',data,cursor)
        if tag == b'JSON': return json.loads(data[cursor+8:cursor+8+n])
        cursor += 8+n
    raise ValueError('No GLB JSON found')


def download_resource(base, folder, relative):
    parsed = urlsplit(relative)
    if parsed.scheme or parsed.netloc or relative.startswith('/') or not parsed.path:
        raise ValueError(f'External resource disallowed: {relative}')
    clean=unquote(parsed.path)
    filepath=(folder/clean).resolve()
    if not filepath.is_relative_to(folder.resolve()):
        raise ValueError(f'Unsafe URI: {relative}')
    filepath.parent.mkdir(parents=True,exist_ok=True)
    target=base.rstrip('/')+'/'+quote(clean,safe='/')
    req=urllib.request.Request(target,headers={'User-Agent':'MerkOfDutyNative/0.4'})
    with urllib.request.urlopen(req,timeout=90) as response:
        if 'text/html' in response.headers.get('Content-Type',''):
            raise ValueError(f'HTML fallback for {relative}')
        data=response.read(40_000_001)
    if len(data)>40_000_000 or len(data)<12:
        raise ValueError(f'Unexpected asset size for {relative}')
    filepath.write_bytes(data)
    return filepath


def download(folder,base=BASE):
    folder.mkdir(parents=True,exist_ok=True)
    results={}
    for key,relative in WEAPONS.items():
        glb=download_resource(base,folder,relative)
        meta=read_manifest(glb)
        sidecars=[]
        for buf in meta.get('buffers',[]):
            uri=buf.get('uri')
            if uri and not uri.startswith('data:'):
                source=download_resource(base,folder, 'viewmodel/'+uri)
                sidecars.append(source.as_posix())
        # Texture images may also be embedded directly in the downloaded GLB.
        from convert_gltf import load_gltf
        doc,buffers=load_gltf(glb)
        # GLB texture URIs resolve relative to the viewmodel subfolder.
        textures=fetch_external_images(glb.parent,base+'/viewmodel',limit=256,glb_name=glb.name)
        results[key]={'glb':str(glb),'sidecars':sidecars,'textures':textures}
    (folder/'weapons-recovery.json').write_text(json.dumps(results,indent=2))
    return results


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--out',type=Path,default=Path('build/recovered-weapons'))
    p.add_argument('--base',default=BASE)
    args=p.parse_args()
    if not args.base.startswith('https://') or not args.base.endswith('.pages.dev'):
        p.error('Only https://*.pages.dev deployment origins are supported')
    print(json.dumps(download(args.out,args.base),indent=2))
