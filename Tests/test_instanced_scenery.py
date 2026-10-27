"""GLB instanced object placement and no-prototype-duplication regression tests."""
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from test_textures import make_textured_fixture

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'Tools'))
from convert_gltf import convert

class InstancedSceneryTests(unittest.TestCase):
    def test_instanced_node_uses_trs_and_scene_center(self):
        with tempfile.TemporaryDirectory() as folder:
            f, doc, _ = make_textured_fixture(folder)
            # An ordinary floor mesh establishes the scene's center offset.
            # Two instanced props share one 3-vertex primitive.
            trans = struct.pack('<6f', 1,0,2, 5,0,2)
            rot = struct.pack('<8f', *([0,0,0,1]*2))
            scale = struct.pack('<6f', *([1,1,1]*2))
            data = trans+rot+scale
            (Path(folder)/'instances.bin').write_bytes(data)
            doc['buffers'].append({'uri':'instances.bin','byteLength':len(data)})
            ix = len(doc['buffers'])-1
            b = len(doc['bufferViews'])
            doc['bufferViews'] += [{'buffer':ix,'byteOffset':0},
                                   {'buffer':ix,'byteOffset':len(trans)},
                                   {'buffer':ix,'byteOffset':len(trans)+len(rot)}]
            a = len(doc['accessors'])
            doc['accessors'] += [{'bufferView':b,'componentType':5126,'count':2,'type':'VEC3'},
                                 {'bufferView':b+1,'componentType':5126,'count':2,'type':'VEC4'},
                                 {'bufferView':b+2,'componentType':5126,'count':2,'type':'VEC3'}]
            doc['nodes'].append({'mesh':0,'translation':[8,0,0],
              'extensions':{'EXT_mesh_gpu_instancing':{'attributes':{
                'TRANSLATION':a,'ROTATION':a+1,'SCALE':a+2}}}})
            doc['scenes'][0]['nodes'].append(1)
            f.write_text(json.dumps(doc))
            main = Path(folder)/'main.meshbin'
            inst = Path(folder)/'instances.meshbin'
            convert(f,main,0.5,100,texture_atlas=Path(folder)/'atlas.png',instances_out=inst)
            self.assertEqual(main.read_bytes()[:8],b'MERKMAP2')
            self.assertEqual(struct.unpack_from('<I',main.read_bytes(),8)[0],3)
            raw = inst.read_bytes()
            self.assertEqual(raw[:8],b'MERKINS1')
            self.assertEqual(struct.unpack_from('<3I',raw,8),(1,3,2))
            # base bounds X=0..2 -> offset X=1. first world X=8+1 =9.
            first_matrix = struct.unpack_from('<16f',raw,20+3*64)
            second_matrix = struct.unpack_from('<16f',raw,20+3*64+80)
            self.assertAlmostEqual(first_matrix[12],4.0)
            self.assertAlmostEqual(second_matrix[12],6.0)
            self.assertAlmostEqual(first_matrix[14],0.5)
            self.assertEqual(len(raw),20+3*64+2*80)

    def test_instanced_group_requires_texture_atlas(self):
        with tempfile.TemporaryDirectory() as tmp:
            f,_,_=make_textured_fixture(tmp)
            with self.assertRaises(ValueError):
                convert(f,Path(tmp)/'main.meshbin',1,100,instances_out=Path(tmp)/'instances.bin')

if __name__=='__main__': unittest.main()
