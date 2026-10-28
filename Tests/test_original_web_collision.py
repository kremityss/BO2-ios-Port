import importlib.util
import json
import struct
import tempfile
import unittest
from pathlib import Path

SPEC=importlib.util.spec_from_file_location('original_bvh',Path(__file__).resolve().parents[1]/'Tools/bake_collision.py')
mod=importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mod)

class OriginalBVHTests(unittest.TestCase):
    def test_collision_uses_authored_mesh_and_render_transform(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            # Upward-facing floor in source units, under a real spawn marker.
            vertices=[(-1615.,-64.,-1190.),(-1615.,-64.,-1170.),(-1590.,-64.,-1190.)]
            binary=b''.join(struct.pack('<fff',*v) for v in vertices)+struct.pack('<III',0,1,2)
            (root/'collision.bin').write_bytes(binary)
            (root/'collision.json').write_text(json.dumps({
                'format':'collision-bvh-v1','byteLength':len(binary),'triangles':1,
                'layout':{'position':{'byteOffset':0,'count':9},
                          'index':{'byteOffset':36,'count':3}}
            }))
            (root/'transform.json').write_text(json.dumps({
                'map':'mp_nuketown_2020','scale':0.01,'offset':[100.,-853.58,200.]
            }))
            tri=list(mod.original_collision_triangles(root/'collision.json',root/'collision.bin',root/'transform.json'))
            self.assertEqual(len(tri),1)
            self.assertAlmostEqual(tri[0][0][0],-17.15,places=4)
            self.assertAlmostEqual(tri[0][0][1],7.8958,places=4)
            self.assertGreater(tri[0][3][1],0.9)
    def test_invalid_format_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            (root/'collision.bin').write_bytes(b'')
            (root/'collision.json').write_text('{}')
            (root/'transform.json').write_text('{}')
            with self.assertRaises(ValueError):
                list(mod.original_collision_triangles(root/'collision.json',root/'collision.bin',root/'transform.json'))

if __name__ == '__main__':
    unittest.main()
