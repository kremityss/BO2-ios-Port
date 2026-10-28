#!/usr/bin/env python3
"""Clear wall raster overreach at original, verified web-game spawn points."""
import argparse
import json
import math
import struct
from pathlib import Path

MISSING=-32768

def clear_authored_spawns(collision, spawns, clearance_radius=0.85):
    if not 0.16 <= clearance_radius <= 1.5:
        raise ValueError('Spawn clearance must remain within a body-sized radius')
    data=bytearray(Path(collision).read_bytes())
    if len(data)<24 or data[:8]!=b'MERKCOL1':
        raise ValueError('Unexpected MERKCOL1 format')
    width,height=struct.unpack_from('<HH',data,8)
    ox,oz,cell=struct.unpack_from('<fff',data,12)
    if len(data)!=24+width*height*6 or not 0.3<=cell<=3:
        raise ValueError('Malformed collision grid')
    root=json.loads(Path(spawns).read_text())
    if root.get('map')!='mp_nuketown_2020' or len(root.get('spawns',[]))<200:
        raise ValueError('Missing original Nuketown spawn registry')
    touched=set()
    grounded=0
    for marker in root['spawns']:
        xyz=marker.get('xyz')
        if not isinstance(xyz,list) or len(xyz)!=3:continue
        x,y,z=xyz
        if not all(math.isfinite(v) for v in (x,y,z)):continue
        nearest=math.floor((x-ox)/cell)
        row=math.floor((z-oz)/cell)
        radius=math.ceil(clearance_radius/cell)+1
        safe=False
        for j in range(max(0,row-radius),min(height,row+radius+1)):
            cz=oz+(j+.5)*cell
            for i in range(max(0,nearest-radius),min(width,nearest+radius+1)):
                cx=ox+(i+.5)*cell
                if math.hypot(cx-x,cz-z)>clearance_radius:continue
                k=24+6*(j*width+i)
                floor,lo,hi=struct.unpack_from('<hhh',data,k)
                if floor==MISSING:continue
                level=floor*.01
                # Do not remove walls on roofs or other unrelated elevations.
                if abs(level-y)>1.25 or level>y+.32:continue
                safe=True
                if lo!=MISSING or hi!=MISSING:
                    struct.pack_into('<hh',data,k+2,MISSING,MISSING)
                    touched.add(j*width+i)
        if safe:grounded+=1
    if grounded<100:
        raise ValueError(f'Too few authored spawns projected to collision: {grounded}')
    Path(collision).write_bytes(data)
    stats={'authored_spawns':len(root['spawns']),
           'spawns_with_same_surface':grounded,
           'cleared_wall_cells':len(touched),
           'clearance_radius':clearance_radius}
    print(json.dumps(stats,indent=2))
    return stats

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--collision',type=Path,required=True)
    parser.add_argument('--spawns',type=Path,required=True)
    parser.add_argument('--radius',type=float,default=0.85)
    args=parser.parse_args()
    clear_authored_spawns(args.collision,args.spawns,args.radius)
