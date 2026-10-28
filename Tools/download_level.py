#!/usr/bin/env python3
"""Recover the three externally split glTF map files from a pinned Pages deployment.
No Cloudflare secrets needed. The output is used by the native GLB importer.
"""
import argparse
import json
import time
import urllib.request
from urllib.parse import unquote, quote, urlsplit
from pathlib import Path

BASE = 'https://56538cf3.merk-of-duty.pages.dev'
PARTS = ('nuketown_2020_optimized.glb', 'nuketown_2020_optimized.buffer-0.bin',
         'nuketown_2020_optimized.buffer-1.bin',
         'nuketown_2020_collision_bvh.bin', 'nuketown_2020_collision_bvh.json')


def fetch_external_images(folder, base=BASE, limit=512, glb_name=PARTS[0]):
    """Fetch locally referenced external glTF images from the same deployment.

    Asset URLs are confined to the deployment origin. Missing files are reported
    (converter falls back to flat albedo), rather than silently sourcing images
    from third parties.
    """
    from convert_gltf import load_gltf
    doc, _buffers = load_gltf(folder / glb_name)
    images = doc.get('images', [])
    downloaded, missing = [], []
    for item in images:
        uri = item.get('uri', '')
        if not uri or uri.startswith('data:'):
            continue
        parts = urlsplit(uri)
        if parts.netloc or parts.scheme or uri.startswith('/'):
            missing.append({'image':uri,'reason':'external/absolute URI'})
            continue
        decoded = unquote(parts.path)
        destination = (folder / decoded).resolve()
        if not destination.is_relative_to(folder.resolve()):
            missing.append({'image':uri,'reason':'traversal path'})
            continue
        if destination.exists():
            continue
        if len(downloaded) >= limit:
            missing.append({'image':uri,'reason':'image limit reached'})
            continue
        destination.parent.mkdir(parents=True, exist_ok=True)
        remote = base.rstrip('/') + '/' + quote(decoded, safe='/')
        try:
            req = urllib.request.Request(remote, headers={'User-Agent':'MerkOfDutyNative/0.4'})
            with urllib.request.urlopen(req, timeout=45) as reply:
                data = reply.read(12_000_001)
                mime = reply.headers.get('Content-Type', '')
            if len(data) > 12_000_000 or len(data) < 16 or mime.startswith('text/html'):
                raise ValueError('image too big/small or HTML fallback')
            if not (data[:4] in (b'RIFF',b'\x89PNG',b'GIF8') or data[:3] == b'\xff\xd8\xff'):
                raise ValueError('not a supported encoded image')
            destination.write_bytes(data)
            downloaded.append(uri)
        except (OSError, ValueError) as exc:
            missing.append({'image':uri,'reason':str(exc)})
    return {'downloaded':downloaded,'missing':missing,'referenced_images':len(images)}


def download(folder, base=BASE, textures=True, map_name='nuketown_2020'):
    if map_name not in ('nuketown_2020','hijacked'):
        raise ValueError('Only verified native maps are supported')
    parts = PARTS if map_name == 'nuketown_2020' else ('hijacked_optimized.glb','hijacked_collision_bvh.bin','hijacked_collision_bvh.json')
    folder.mkdir(parents=True,exist_ok=True)
    sizes={}
    for name in parts:
        url=base.rstrip('/')+'/'+name
        last=None
        for tries in range(3):
            try:
                req=urllib.request.Request(url,headers={'User-Agent':'MerkOfDutyNative/0.3'})
                with urllib.request.urlopen(req,timeout=90) as response:
                    mime=response.headers.get('Content-Type','')
                    data=response.read()
                if name.endswith('.json') and json.loads(data).get('format') != 'collision-bvh-v1':
                    raise ValueError('Invalid original collision BVH metadata')
                if name.endswith('.glb') and data[:4] != b'glTF':
                    raise ValueError('Invalid GLB magic')
                if mime.startswith('text/html') or data[:30].lower().startswith(b'<!doctype html'):
                    raise ValueError('Received HTML fallback')
                if len(data)<500: raise ValueError('Unexpectedly short file')
                (folder/name).write_bytes(data)
                sizes[name]=len(data)
                print(f'{name}: {len(data)} bytes',flush=True)
                break
            except Exception as exc:
                last=exc
                if tries<2: time.sleep(tries+1)
        else:
            raise RuntimeError(f'Unable to retrieve {url}: {last}')
    if textures:
        sizes['texture_recovery'] = fetch_external_images(folder,base,glb_name=map_name+'_optimized.glb')
    (folder/'recovery-report.json').write_text(json.dumps(sizes,indent=2))
    return sizes


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--out',type=Path,default=Path('build/recovered-map'))
    p.add_argument('--map',default='nuketown_2020',choices=['nuketown_2020','hijacked'])
    p.add_argument('--base',default=BASE)
    p.add_argument('--no-textures',action='store_true',help='Skip external texture recovery')
    x=p.parse_args()
    if not x.base.startswith('https://') or not x.base.endswith('.pages.dev'):
        p.error('The base must be an HTTPS *.pages.dev deployment')
    download(x.out,x.base,textures=not x.no_textures,map_name=x.map)
