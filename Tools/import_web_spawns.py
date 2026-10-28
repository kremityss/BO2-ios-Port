#!/usr/bin/env python3
"""Convert the *authored* web-game spawn hints to the exact native map transform.

Uses nuketown_2020_nav_hints.json emitted by the web game's own map bake.
The map converter's output transform JSON must come from the *same* GLB
conversion, otherwise source spawn coordinates will not align.
"""
import argparse
import json
import math
from pathlib import Path
from urllib.request import urlopen, Request

PINNED_URL = 'https://56538cf3.merk-of-duty.pages.dev/nuketown_2020_nav_hints.json'


def native_spawns(hints, transform):
    if hints.get('map') != 'mp_nuketown_2020' or not isinstance(hints.get('spawns'), list):
        raise ValueError('Expected the deployed Nuketown 2025 nav-hints spawn registry')
    if transform.get('map') != 'mp_nuketown_2020':
        raise ValueError('Spawn/map transform identity mismatch')
    scale = transform['scale']
    offset = transform['offset']
    if not (isinstance(offset, list) and len(offset) == 3 and
            all(math.isfinite(x) for x in offset) and 0 < scale <= 0.1):
        raise ValueError('Invalid native map coordinate transform')
    result = []
    for v in hints['spawns']:
        position = v.get('position')
        if not (isinstance(position, list) and len(position) == 3 and
                all(isinstance(n, (int, float)) and math.isfinite(n) for n in position)):
            continue
        classname = v.get('classname', '')
        yaw = float(v.get('yaw', 0))
        if not classname.startswith('mp_') or 'spawn' not in classname or not math.isfinite(yaw):
            continue
        # Native GameWorld yaw uses sin(yaw), -cos(yaw) as forward. The web
        # coordinate conversion yaw rotates the camera in the opposite sign.
        result.append({
            'id': str(v.get('guid', '')),
            'class': classname,
            'xyz': [round((float(position[i]) - offset[i]) * scale, 5) for i in range(3)],
            'yaw': round(-yaw, 7),
        })
    if not result:
        raise ValueError('Deployed map contained no supported spawn markers')
    return {'version': 1, 'map': hints['map'], 'source': 'nuketown_2020_nav_hints.json',
            'scale': scale, 'offset': offset, 'spawns': result}


def fetch_hints(url=PINNED_URL):
    if url != PINNED_URL:
        raise ValueError('Only pinned HTTPS deployment is allowed')
    with urlopen(Request(url, headers={'User-Agent': 'MerkOfDutyNative/0.7'}), timeout=60) as r:
        raw = r.read(8_000_001)
        if len(raw) > 8_000_000:
            raise ValueError('Spawn hint file too large')
        return json.loads(raw)


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--transform', type=Path, required=True)
    p.add_argument('--out', type=Path, required=True)
    p.add_argument('--hints', type=Path, help='Local JSON file for tests/offline conversion')
    args = p.parse_args()
    hints = json.loads(args.hints.read_text()) if args.hints else fetch_hints()
    result = native_spawns(hints, json.loads(args.transform.read_text()))
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, indent=2) + '\n')
    print(f"Converted {len(result['spawns'])} authored web spawns into {args.out}")


if __name__ == '__main__':
    main()
