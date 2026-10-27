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


def bake(source, dest, resolution=0.75):
    if not 0.3 <= resolution <= 3.0:
        raise ValueError('resolution must be 0.3..3m')
    tri = list(triangles(source))
    if not tri:
        raise ValueError('empty mesh')
    xs = [p[0] for a,b,c,_ in tri for p in (a,b,c)]
    zs = [p[2] for a,b,c,_ in tri for p in (a,b,c)]
    xmin,xmax = min(xs), max(xs)
    zmin,zmax = min(zs), max(zs)
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
    for a,b,c,n in tri:
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
           'bytes':dest.stat().st_size}
    print(json.dumps(stats,indent=2))
    return stats

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('mesh',type=Path)
    p.add_argument('--out',type=Path,default=Path('MerkOfDuty/Resources/MerkCollision.bin'))
    p.add_argument('--cell-size',type=float,default=0.75)
    x=p.parse_args()
    bake(x.mesh,x.out,x.cell_size)
