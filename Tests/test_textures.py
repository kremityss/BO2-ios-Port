"""MERKMAP2 conversion and atlas regression tests, no network required."""
import io
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest

from PIL import Image
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'Tools'))
from convert_gltf import convert, image_bytes
from bake_collision import triangles, bake


def make_textured_fixture(folder, texture_ref='data'):
    path = Path(folder)
    # Counter-clockwise flat XZ triangle faces up (floor).
    pos = struct.pack('<9f', 0,0,0, 0,0,2, 2,0,0)
    tex = struct.pack('<6f', 0.25,0.25, 1.25,0.25, 0.25,1.25)
    ibuf = struct.pack('<3H',0,1,2)
    data = pos + tex + ibuf
    (path/'geometry.bin').write_bytes(data)
    png = io.BytesIO()
    Image.new('RGB',(2,2),(220,30,50)).save(png,format='PNG')
    encoded = png.getvalue()
    import base64
    image_uri = 'data:image/png;base64,' + base64.b64encode(encoded).decode()
    if texture_ref == 'external':
        (path/'albedo.png').write_bytes(encoded)
        image_uri = 'albedo.png'
    doc = {
        'asset':{'version':'2.0'},
        'buffers':[{'uri':'geometry.bin','byteLength':len(data)}],
        'bufferViews':[{'buffer':0,'byteOffset':0,'byteLength':len(pos)},
                       {'buffer':0,'byteOffset':len(pos),'byteLength':len(tex)},
                       {'buffer':0,'byteOffset':len(pos)+len(tex),'byteLength':len(ibuf)}],
        'accessors':[{'bufferView':0,'componentType':5126,'count':3,'type':'VEC3'},
                     {'bufferView':1,'componentType':5126,'count':3,'type':'VEC2'},
                     {'bufferView':2,'componentType':5123,'count':3,'type':'SCALAR'}],
        'materials':[{'pbrMetallicRoughness':{'baseColorFactor':[0.8,0.5,1,1],
                                           'baseColorTexture':{'index':0, 'extensions':{
                                              'KHR_texture_transform':{'offset':[0.1,0], 'scale':[2,1]}}}}}],
        'textures':[{'source':0}], 'images':[{'uri':image_uri}],
        'meshes':[{'primitives':[{'material':0,'attributes':{'POSITION':0,'TEXCOORD_0':1},'indices':2}]}],
        'nodes':[{'mesh':0}], 'scenes':[{'nodes':[0]}], 'scene':0
    }
    (path/'test.gltf').write_text(json.dumps(doc))
    return path/'test.gltf', doc, encoded


class TexturedMapTests(unittest.TestCase):
    def test_embedded_png_uv_and_collision(self):
        with tempfile.TemporaryDirectory() as tmp:
            path,doc,img=make_textured_fixture(tmp)
            mesh=Path(tmp)/'MerkMap.meshbin'
            atlas=Path(tmp)/'MerkAtlas.png'
            convert(path,mesh,1,100,texture_atlas=atlas)
            payload=mesh.read_bytes()
            self.assertEqual(payload[:8],b'MERKMAP2')
            self.assertEqual(len(payload),12+3*64)
            self.assertEqual(struct.unpack_from('<I',payload,8)[0],3)
            # Texture transform: offset + 2*0.25.
            self.assertAlmostEqual(struct.unpack_from('<f',payload,12+40)[0],0.6)
            region=struct.unpack_from('<4f',payload,12+48)
            self.assertTrue(0<region[2]<1)
            with Image.open(atlas) as tex:
                u=region[0]+region[2]*0.5
                v=region[1]+region[3]*0.5
                color=tex.getpixel((int(u*tex.width), int(v*tex.height)))
            self.assertEqual(color[:3],(220,30,50))
            self.assertEqual(len(list(triangles(mesh))),1)
            out=Path(tmp)/'MerkCollision.bin'
            self.assertGreater(bake(mesh,out,0.5)['walkable_cells'],0)

    def test_external_png_material(self):
        with tempfile.TemporaryDirectory() as tmp:
            path,doc,encoded=make_textured_fixture(tmp,'external')
            self.assertEqual(image_bytes(doc,[],0,Path(tmp)),encoded)
            mesh=Path(tmp)/'mesh.meshbin'
            convert(path,mesh,1,100,texture_atlas=Path(tmp)/'atlas.png')
            self.assertTrue(mesh.exists())

    def test_untextured_old_format_still_works(self):
        with tempfile.TemporaryDirectory() as tmp:
            path,_,_=make_textured_fixture(tmp)
            mesh=Path(tmp)/'mesh.meshbin'
            convert(path,mesh,1,100)
            self.assertEqual(mesh.read_bytes()[:8],b'MERKMAP1')
            self.assertEqual(len(mesh.read_bytes()),132)


if __name__ == '__main__': unittest.main()
