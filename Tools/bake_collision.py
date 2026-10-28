#!/usr/bin/env python3
"""Bake a coarse, native 2.5D height/wall collision grid from a MERKMAP1 mesh.

This is a first collision approximation only, not triangle-accurate sweeps.
MERKCOL1 header: uint16 width,height; float originX,originZ,cellSize.
Cells are row-major int16 floor, wallBottom, wallTop, in centimeters;
-32768 means absent. Geometry must be in meters before baking.
"""
import argparse
import json
import math
import struct
from pathlib import Path

MAGIC = b'MERKCOL1'
MISSING = -32768


def triangles(path):
    data = path.read_bytes()
    if len(data) < 12 or data[:8] not in (b'MERKMAP1', b'MERKMAP2'):
        raise ValueError('Expected MERKMAP1 or MERKMAP2 data')
    stride = 64 if data[:8] == b'MERKMAP2' else 40
    vertices, = struct.unpack_from('<I', data, 8)
    if vertices % 3 or len(data) != 12 + stride * vertices:
        raise ValueError('Truncated or malformed mesh file')
    for n in range(0, vertices, 3):
        off = 12 + stride*n
        a = struct.unpack_from('<3f', data, off)
        b = struct.unpack_from('<3f', data, off + stride)
        c = struct.unpack_from('<3f', data, off + 2*stride)
        normal = struct.unpack_from('<3f', data, off + 12)
        yield a, b, c, normal


def original_collision_triangles(metadata, binary, transform_json):
    """Read the original deployed ThreeMeshBVH collision triangle stream.

    GLB render geometry is NOT a reliable collision floor; the official web
    collider has its own authored 383,761 vertices / 439,726 triangles.
    All 3D coordinates use the exact transform exported by convert_gltf.py.
    """
    doc=json.loads(Path(metadata).read_text())
    transform=json.loads(Path(transform_json).read_text())
    if doc.get('format')!='collision-bvh-v1' or transform.get('map')!='mp_nuketown_2020':
        raise ValueError('Map identity or web BVH format mismatch')
    offset=transform.get('offset')
    scale=float(transform.get('scale',0))
    if not isinstance(offset,list) or len(offset)!=3 or not 0<scale<=0.1:
        raise ValueError('Invalid native map transform')
    data=Path(binary).read_bytes()
    layout=doc['layout']
    if len(data)!=doc['byteLength'] or doc['triangles']<=0:
        raise ValueError('Incomplete original collision BVH file')
    pos=layout['position']['byteOffset']
    idx=layout['index']['byteOffset']
    components=layout['position']['count']
    if pos+components*4>len(data) or idx+doc['triangles']*12>len(data):
        raise ValueError('Original collision BVH layout exceeds binary')
    def vertex(n):
        if n*3+2>=components: raise ValueError('Invalid collision vertex index')
        coords=struct.unpack_from('<fff',data,pos+n*12)
        return tuple((coords[i]-offset[i])*scale for i in range(3))
    for t in range(doc['triangles']):
        ids=struct.unpack_from('<III',data,idx+12*t)
        a,b,c=[vertex(i) for i in ids]
        ab=[b[i]-a[i] for i in range(3)]
        ac=[c[i]-a[i] for i in range(3)]
        cross=(ab[1]*ac[2]-ab[2]*ac[1],
               ab[2]*ac[0]-ab[0]*ac[2],
               ab[0]*ac[1]-ab[1]*ac[0])
        magnitude=math.sqrt(sum(x*x for x in cross))
        if magnitude < 1e-10: continue
        yield a,b,c,tuple(x/magnitude for x in cross)


def height_at(x, z, a, b, c):
    det = (b[2]-c[2])*(a[0]-c[0])+(c[0]-b[0])*(a[2]-c[2])
    if abs(det) < 1e-8:
        return None
    s = ((b[2]-c[2])*(x-c[0])+(c[0]-b[0])*(z-c[2]))/det
    t = ((c[2]-a[2])*(x-c[0])+(a[0]-c[0])*(z-c[2]))/det
    if min(s, t, 1-s-t) < -0.001:
        return None
    return s*a[1]+t*b[1]+(1-s-t)*c[1]


def cm(y):
    return max(-32767, min(32767, round(y*100)))


def bake(source, dest, resolution=0.75, playable_radius=None, web_bvh_meta=None, web_bvh_binary=None, web_transform=None):
    if not 0.3 <= resolution <= 3.0:
        raise ValueError('resolution must be 0.3..3m')
    if playable_radius is not None and not 10 <= playable_radius <= 1000:
        raise ValueError('playable_radius must be 10..1000m')
    if bool(web_bvh_meta) != bool(web_bvh_binary) or (web_bvh_meta and not web_transform):
        raise ValueError('Original collision requires BVH metadata, binary and scene transform')
    tri = list(original_collision_triangles(web_bvh_meta,web_bvh_binary,web_transform)
               if web_bvh_meta else triangles(source))
    if not tri:
        raise ValueError('empty mesh')
    xs = [p[0] for a,b,c,_ in tri for p in (a,b,c)]
    zs = [p[2] for a,b,c,_ in tri for p in (a,b,c)]
    xmin,xmax = min(xs), max(xs)
    zmin,zmax = min(zs), max(zs)
    # A large outdoor scene can contain 700m+ of sky, scenery and outskirts.
    # Bake only the playable core into the 2.5D collision format, while leaving
    # render geometry untouched. The GLB converter centers horizontal geometry
    # on (0,0), so the gameplay crop uses that same world-space origin.
    if playable_radius is not None:
        xmin,xmax = -playable_radius, playable_radius
        zmin,zmax = -playable_radius, playable_radius
    originX = math.floor(xmin/resolution)*resolution-resolution
    originZ = math.floor(zmin/resolution)*resolution-resolution
    w = math.ceil((xmax-originX)/resolution)+2
    h = math.ceil((zmax-originZ)/resolution)+2
    if w*h > 250_000 or max(w,h)>65535:
        raise ValueError('collision raster too large: increase --cell-size')
    floors=[MISSING]*(w*h)
    bottom=[MISSING]*(w*h)
    top=[MISSING]*(w*h)
    groundTriangles=wallTriangles=0
    rejected=0
    for a,b,c,n in tri:
        # Avoid spending CPU on off-map terrain triangles and extended sky.
        if playable_radius is not None:
            bx0=min(a[0],b[0],c[0]);bx1=max(a[0],b[0],c[0])
            bz0=min(a[2],b[2],c[2]);bz1=max(a[2],b[2],c[2])
            if bx1 < xmin or bx0 > xmax or bz1 < zmin or bz0 > zmax:
                rejected+=1
                continue
        ymin,ymax=min(a[1],b[1],c[1]),max(a[1],b[1],c[1])
        if n[1] > 0.58:
            groundTriangles+=1
            x0=max(0,math.floor((min(a[0],b[0],c[0])-originX)/resolution)-1)
            x1=min(w-1,math.ceil((max(a[0],b[0],c[0])-originX)/resolution)+1)
            z0=max(0,math.floor((min(a[2],b[2],c[2])-originZ)/resolution)-1)
            z1=min(h-1,math.ceil((max(a[2],b[2],c[2])-originZ)/resolution)+1)
            for j in range(z0,z1+1):
                z=originZ+(j+0.5)*resolution
                for i in range(x0,x1+1):
                    x=originX+(i+0.5)*resolution
                    y=height_at(x,z,a,b,c)
                    if y is not None:
                        index=j*w+i
                        floors[index] = min(floors[index], cm(y)) if floors[index]!=MISSING else cm(y)
        elif abs(n[1]) < 0.5 and ymax-ymin > 0.5:
            wallTriangles+=1
            # Rasterize each edge, broaden by one grid cell to approximate body radius.
            for p,q in ((a,b),(b,c),(c,a)):
                steps=max(1,math.ceil(math.hypot(p[0]-q[0],p[2]-q[2])/(resolution*0.6)))
                for step in range(steps+1):
                    u=step/steps
                    x=p[0]*(1-u)+q[0]*u
                    z=p[2]*(1-u)+q[2]*u
                    ix=math.floor((x-originX)/resolution)
                    iz=math.floor((z-originZ)/resolution)
                    for j in range(max(0,iz-1),min(h,iz+2)):
                        for i in range(max(0,ix-1),min(w,ix+2)):
                            index=j*w+i
                            bottom[index] = min(bottom[index],cm(ymin)) if bottom[index]!=MISSING else cm(ymin)
                            top[index] = max(top[index],cm(ymax)) if top[index]!=MISSING else cm(ymax)
    walkable=sum(v!=MISSING for v in floors)
    if walkable==0:
        raise ValueError('No walkable floor triangles: verify map orientation and normals')
    dest.parent.mkdir(parents=True,exist_ok=True)
    with dest.open('wb') as out:
        out.write(MAGIC+struct.pack('<HHfff',w,h,originX,originZ,resolution))
        for cell in zip(floors,bottom,top):
            out.write(struct.pack('<hhh',*cell))
    stats={'source':str(source),'out':str(dest),'width':w,'height':h,'cell_size':resolution,
           'floor_triangles':groundTriangles,'wall_triangles':wallTriangles,'walkable_cells':walkable,
           'bytes':dest.stat().st_size, 'playable_radius':playable_radius, 'off_core_triangles':rejected}
    print(json.dumps(stats,indent=2))
    return stats

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('mesh',type=Path)
    p.add_argument('--out',type=Path,default=Path('MerkOfDuty/Resources/MerkCollision.bin'))
    p.add_argument('--cell-size',type=float,default=0.75)
    p.add_argument('--playable-radius',type=float,default=None,help='Crop approximate collision to +/- meters around centered map origin')
    p.add_argument('--web-bvh-meta',type=Path)
    p.add_argument('--web-bvh-binary',type=Path)
    p.add_argument('--web-transform',type=Path)
    x=p.parse_args()
    bake(x.mesh,x.out,x.cell_size,x.playable_radius,x.web_bvh_meta,x.web_bvh_binary,x.web_transform)
