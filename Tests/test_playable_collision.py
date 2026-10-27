"""Regression for rendering an extended map while baking a compact gameplay collision grid."""
import struct
import tempfile
import unittest
from pathlib import Path
from sys import path as sys_path
sys_path.insert(0, str(Path(__file__).resolve().parents[1] / 'Tools'))
from bake_collision import bake, MAGIC


class PlayableCollisionTests(unittest.TestCase):
    def test_large_scenery_extent_does_not_enlarge_playable_grid(self):
        with tempfile.TemporaryDirectory() as tmp:
            mesh=Path(tmp)/'large.meshbin'
            with mesh.open('wb') as f:
                f.write(b'MERKMAP1'+struct.pack('<I',6))
                # A walkable flat ground tri near center and a remote flat
                # distant tri that would inflate the grid beyond its limit.
                for v in ((-5,0,-5),(-5,0,5),(5,0,-5),
                          (4000,0,4000),(4000,0,4010),(4010,0,4000)):
                    f.write(struct.pack('<10f',*v,0,1,0,1,1,1,1))
            dest=Path(tmp)/'collision.bin'
            result=bake(mesh,dest,0.75,playable_radius=150)
            self.assertEqual(dest.read_bytes()[:8],MAGIC)
            self.assertLess(result['width']*result['height'],250_000)
            self.assertEqual(result['off_core_triangles'],1)
            self.assertGreater(result['walkable_cells'],0)

    def test_bad_radius_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(ValueError):
                bake(Path(tmp)/'missing',Path(tmp)/'out',0.75,playable_radius=0)

if __name__=='__main__':unittest.main()
