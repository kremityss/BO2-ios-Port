"""The deployed GLB uses KHR_texture_basisu for all Nuketown albedo maps."""
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch
from PIL import Image
from test_textures import make_textured_fixture
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'Tools'))
from convert_gltf import convert

class BasisTextures(unittest.TestCase):
    def fixture(self, tmp):
        path,doc,_ = make_textured_fixture(tmp)
        (Path(tmp) / 'tex.ktx2').write_bytes(b'\xabKTX 20\xbb\r\n\x1a\n' + b'fixture')
        doc['images']=[{'uri':'tex.ktx2','mimeType':'image/ktx2'}]
        doc['textures']=[{'extensions':{'KHR_texture_basisu':{'source':0}}}]
        path.write_text(json.dumps(doc))
        return path

    def test_khr_basis_texture_material_is_visible_in_atlas(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=self.fixture(tmp)
            output=Path(tmp)/'mesh.meshbin'
            atlas=Path(tmp)/'atlas.png'
            with patch('convert_gltf.decode_ktx2',return_value=Image.new('RGB',(4,4),(12,72,180))):
                convert(path,output,1.0,100,texture_atlas=atlas,minimum_decoded_textures=1)
            data=output.read_bytes()
            u,v,sx,sy=struct.unpack_from('<4f',data,12+48)
            self.assertGreater(sx,0)
            with Image.open(atlas) as image:
                self.assertEqual(image.convert('RGB').getpixel((int((u+sx/2)*image.width),int((v+sy/2)*image.height))),(12,72,180))

    def test_texture_decode_failure_refuses_deceptive_white_map(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=self.fixture(tmp)
            with patch('convert_gltf.decode_ktx2',side_effect=OSError('transcode failed')):
                with self.assertRaisesRegex(ValueError,'Too few albedo textures decoded'):
                    convert(path,Path(tmp)/'mesh.meshbin',1,100,texture_atlas=Path(tmp)/'atlas.png',minimum_decoded_textures=1)

if __name__=='__main__': unittest.main()
