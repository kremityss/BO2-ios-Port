import json
from pathlib import Path
import struct
import tempfile
import unittest
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'Tools'))
from convert_gltf import convert, load_gltf, matmul, identity


class ConversionTests(unittest.TestCase):
    def test_identity_matrix(self):
        a = identity()
        self.assertEqual(matmul(a,a), a)

    def test_triangle_glb(self):
        with tempfile.TemporaryDirectory() as work:
            root = Path(work)
            positions = struct.pack('<9f', 0,0,0, 1,0,0, 0,1,0)
            indices = struct.pack('<3H', 0,1,2)
            raw = positions + indices
            meta = {
                'asset': {'version':'2.0'},
                'buffers':[{'byteLength':len(raw)}],
                'bufferViews':[{'buffer':0,'byteOffset':0,'byteLength':len(positions)},
                               {'buffer':0,'byteOffset':len(positions),'byteLength':len(indices)}],
                'accessors':[{'bufferView':0,'componentType':5126,'count':3,'type':'VEC3'},
                             {'bufferView':1,'componentType':5123,'count':3,'type':'SCALAR'}],
                'meshes':[{'primitives':[{'attributes':{'POSITION':0},'indices':1}]}],
                'nodes':[{'mesh':0}],
                'scenes':[{'nodes':[0]}],
                'scene':0
            }
            js = json.dumps(meta,separators=(',',':')).encode()
            js += b' ' * ((4 - len(js)%4)%4)
            raw += b'\0' * ((4 - len(raw)%4)%4)
            chunks = struct.pack('<I4s',len(js),b'JSON') + js + struct.pack('<I4s',len(raw),b'BIN\0') + raw
            glb = root/'sample.glb'
            glb.write_bytes(struct.pack('<4sII',b'glTF',2,12+len(chunks)) + chunks)
            doc, buffers = load_gltf(glb)
            self.assertEqual(doc['meshes'][0]['primitives'][0]['indices'],1)
            self.assertEqual(len(buffers[0]),len(raw))
            out = root/'MerkMap.meshbin'
            convert(glb,out,1.0,20)
            data=out.read_bytes()
            self.assertEqual(data[:8],b'MERKMAP1')
            self.assertEqual(struct.unpack_from('<I',data,8)[0],3)
            self.assertEqual(len(data),12+3*40)
            self.assertAlmostEqual(struct.unpack_from('<f',data,12+20)[0],1)


if __name__=='__main__':unittest.main()

# The deployed 2026-09-22 map references external .bin buffers, unlike the
# minimal embedded GLB tested above. Verify this glTF path remains supported.
class ExternalBufferTests(unittest.TestCase):
    def test_external_buffer_translation(self):
        with tempfile.TemporaryDirectory() as folder:
            base=Path(folder)
            positions=struct.pack('<9f',0,0,0, 1,0,0, 0,0,1)
            indices=struct.pack('<3H',0,2,1)
            (base/'sample.bin').write_bytes(positions+indices)
            doc={
                'asset':{'version':'2.0'},
                'buffers':[{'uri':'sample.bin','byteLength':len(positions+indices)}],
                'bufferViews':[{'buffer':0,'byteOffset':0,'byteLength':len(positions)},
                               {'buffer':0,'byteOffset':len(positions),'byteLength':len(indices)}],
                'accessors':[{'bufferView':0,'componentType':5126,'count':3,'type':'VEC3'},
                             {'bufferView':1,'componentType':5123,'count':3,'type':'SCALAR'}],
                'meshes':[{'primitives':[{'attributes':{'POSITION':0},'indices':1}]}],
                'nodes':[{'mesh':0,'translation':[9,1,5]}],
                'scenes':[{'nodes':[0]}], 'scene':0
            }
            (base/'sample.gltf').write_text(json.dumps(doc))
            out=base/'level.meshbin'
            convert(base/'sample.gltf',out,0.01,10)
            blob=out.read_bytes()
            self.assertEqual(struct.unpack_from('<I',blob,8)[0],3)
            # Centering removes map origin and shifts the lowest point to ground level.
            self.assertAlmostEqual(struct.unpack_from('<f',blob,12+4)[0],0.0)
            self.assertEqual(len(blob),132)

    def test_refuses_silent_truncation(self):
        with tempfile.TemporaryDirectory() as folder:
            base=Path(folder)
            positions=struct.pack('<9f',0,0,0, 1,0,0, 0,0,1)
            (base/'buffer.bin').write_bytes(positions)
            doc={'asset':{'version':'2.0'}, 'buffers':[{'uri':'buffer.bin','byteLength':len(positions)}],
                 'bufferViews':[{'buffer':0,'byteLength':len(positions)}],
                 'accessors':[{'bufferView':0,'componentType':5126,'count':3,'type':'VEC3'}],
                 'meshes':[{'primitives':[{'attributes':{'POSITION':0}}]}],
                 'nodes':[{'mesh':0}], 'scenes':[{'nodes':[0]}], 'scene':0}
            (base/'test.gltf').write_text(json.dumps(doc))
            with self.assertRaises(ValueError):
                convert(base/'test.gltf',base/'test.meshbin',1,0)
