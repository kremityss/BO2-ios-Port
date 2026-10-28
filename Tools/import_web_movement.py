#!/usr/bin/env python3
"""Extract exact browser movement tuning into native metres-per-second JSON."""
import argparse, json, pathlib, re, urllib.request
URL='https://56538cf3.merk-of-duty.pages.dev/movement-settings.js'
REQUIRED={'walkSpeed','sprintSpeed','tacticalSprintSpeed','crouchSpeed','proneSpeed','groundAcceleration','groundDeceleration','airAcceleration','friction','slideSpeed','slideDuration','slideCooldown','slideFriction','slideSteer','slideMinSpeed','slideExitSpeed','gravity','jumpVelocity','coyoteTime','jumpBufferTime','airControl','maxAirSpeed','slideHopBoost','cameraSmoothing'}
DISTANCE={'walkSpeed','sprintSpeed','tacticalSprintSpeed','crouchSpeed','proneSpeed','groundAcceleration','groundDeceleration','airAcceleration','slideSpeed','slideMinSpeed','slideExitSpeed','gravity','jumpVelocity','maxAirSpeed','slideCameraDrop','landingDip'}

def extract(source, scale=.01):
    if not (0 < scale <= .1): raise ValueError('Invalid map scale')
    if 'export const MOVEMENT_SETTINGS' not in source: raise ValueError('Not the web-game movement registry')
    entries={k:float(v) for k,v in re.findall(r'^\s*([a-zA-Z][\w]*)\s*:\s*([0-9]+(?:\.[0-9]+)?)\s*,?\s*$',source,re.M)}
    missing=REQUIRED-entries.keys()
    if missing: raise ValueError(f'Missing web movement tuning: {sorted(missing)}')
    out={k:round(v*(scale if k in DISTANCE else 1),7) for k,v in entries.items()}
    return {'source':'movement-settings.js','mapScale':scale,'values':out}

def main():
    p=argparse.ArgumentParser();p.add_argument('--source',type=pathlib.Path);p.add_argument('--out',type=pathlib.Path,required=True)
    a=p.parse_args()
    if a.source: source=a.source.read_text()
    else:
        with urllib.request.urlopen(urllib.request.Request(URL,headers={'User-Agent':'BO2NativePort/0.8'}),timeout=45) as r: source=r.read(100_000).decode()
    data=extract(source)
    a.out.parent.mkdir(parents=True,exist_ok=True)
    a.out.write_text(json.dumps(data,indent=2)+'\n')
    print('Imported',len(data['values']),'web movement parameters:',a.out)
if __name__=='__main__':main()
