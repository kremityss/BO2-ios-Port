"""Weapon texture URI resolution stays inside the archive's sibling images folder."""
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'Tools'))
from convert_gltf import image_bytes
from download_weapons import fetch_weapon_images

class WeaponWebPTests(unittest.TestCase):
    def test_sibling_images_dds_uses_published_webp(self):
        with tempfile.TemporaryDirectory() as t:
            root=Path(t)
            (root/'viewmodel').mkdir();(root/'images').mkdir()
            f=root/'images'/'rifle_col.webp'
            f.write_bytes(b'RIFF'+b'\x00'*4+b'WEBP'+b'mock')
            doc={'images':[{'uri':'../images/rifle_col.dds'}]}
            self.assertEqual(image_bytes(doc,[],0,root/'viewmodel'),f.read_bytes())

    def test_unrelated_parent_traversal_still_rejected(self):
        with tempfile.TemporaryDirectory() as t:
            root=Path(t);(root/'viewmodel').mkdir()
            for uri in ('../../secret.png','../other/secret.dds','../images/../../secret.dds'):
                with self.assertRaises(ValueError):
                    image_bytes({'images':[{'uri':uri}]},[],0,root/'viewmodel')

    def test_public_webp_fetch_is_strictly_scoped(self):
        with tempfile.TemporaryDirectory() as t:
            root=Path(t);model=root/'viewmodel'/'rifle.glb'
            model.parent.mkdir()
            with patch('download_weapons.read_manifest',return_value={'images':[{'uri':'../../secret.dds'},{'uri':'../images/metal_col.dds'}]}), \
                 patch('download_weapons.urllib.request.urlopen') as request:
                class Resp:
                    def __enter__(self): return self
                    def __exit__(self,*_):return False
                    def read(self,_):return b'RIFF'+b'\x00'*4+b'WEBP'+b'mock data'
                request.return_value=Resp()
                report=fetch_weapon_images(model,root,'https://example.pages.dev')
                self.assertEqual(len(report['missing']),1)
                self.assertEqual(len(report['downloaded']),1)
                self.assertTrue((root/'images'/'metal_col.webp').exists())
                self.assertEqual(request.call_count,1)

if __name__=='__main__':unittest.main()
