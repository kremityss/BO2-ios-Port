"""Standalone native viewmodel conversion validation (no deployment connection)."""
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1] / 'Tools'))
from convert_gltf import convert
from download_weapons import read_manifest, download_resource


def glb_for_mesh(path):
    positions = struct.pack('<9f', 0,0,0, 8,0,0, 0,1,1)
    idx = struct.pack('<3H',0,1,2)
    packed = positions+idx
    doc = {'asset':{'version':'2.0'},'buffers':[{'byteLength':len(packed)}],
           'bufferViews':[{'buffer':0,'byteOffset':0,'byteLength':len(positions)},
                          {'buffer':0,'byteOffset':len(positions),'byteLength':len(idx)}],
           'accessors':[{'bufferView':0,'componentType':5126,'count':3,'type':'VEC3'},
                        {'bufferView':1,'componentType':5123,'count':3,'type':'SCALAR'}],
           'meshes':[{'primitives':[{'attributes':{'POSITION':0},'indices':1}]}],
           'nodes':[{'mesh':0}], 'scenes':[{'nodes':[0]}], 'scene':0}
    raw=json.dumps(doc,separators=(',',':')).encode()
    raw+=b' '*((-len(raw))%4)
    packed+=b'\0'*((-len(packed))%4)
    payload=struct.pack('<I4s',len(raw),b'JSON')+raw+struct.pack('<I4s',len(packed),b'BIN\0')+packed
    path.write_bytes(struct.pack('<4sII',b'glTF',2,12+len(payload))+payload)
    return doc


class WeaponImportTests(unittest.TestCase):
    def test_weapon_long_axis_rescaled_to_one_meter(self):
        with tempfile.TemporaryDirectory() as d:
            path=Path(d)/'rifle.glb'
            gltf=glb_for_mesh(path)
            self.assertEqual(read_manifest(path),gltf)
            mesh=Path(d)/'weapon.meshbin'
            convert(path,mesh,1,10,weapon_length=1.0,texture_atlas=Path(d)/'weapon.png')
            data=mesh.read_bytes()
            self.assertEqual(data[:8],b'MERKMAP2')
            coords=[struct.unpack_from('<3f',data,12+64*i) for i in range(3)]
            self.assertAlmostEqual(max(v[2] for v in coords)-min(v[2] for v in coords),1.0)
            self.assertLessEqual(max(abs(v[0]) for v in coords),0.2)
    def test_block_external_escape(self):
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaises(ValueError):
                download_resource('https://merk-of-duty.pages.dev',Path(d),'../private.key')
            with self.assertRaises(ValueError):
                download_resource('https://merk-of-duty.pages.dev',Path(d),'https://example.com/texture.png')

if __name__=='__main__': unittest.main()
