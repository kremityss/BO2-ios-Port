import struct
import sys
import tempfile
import unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'Tools'))
from bake_collision import bake, MISSING

class CollisionTests(unittest.TestCase):
    def test_height_and_wall_grid(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d)
            source=root/'test.meshbin'
            triples=[
                ((-3,0,-3),(-3,0,3),(3,0,3),(0,1,0)),
                ((-3,0,-3),(3,0,3),(3,0,-3),(0,1,0)),
                ((0,0,-2),(0,2,-2),(0,2,2),(1,0,0))]
            with source.open('wb') as f:
                f.write(b'MERKMAP1'+struct.pack('<I',9))
                for a,b,c,n in triples:
                    for v in (a,b,c):
                        f.write(struct.pack('<10f',*v,*n,0.3,0.5,0.7,1))
            out=root/'MerkCollision.bin'
            report=bake(source,out,0.5)
            content=out.read_bytes()
            self.assertEqual(content[:8],b'MERKCOL1')
            width,height,originX,originZ,size=struct.unpack_from('<HHfff',content,8)
            self.assertEqual(len(content),24+6*width*height)
            self.assertGreater(report['walkable_cells'],20)
            self.assertAlmostEqual(size,0.5)
            ix=int((-2-originX)/size)
            iz=int((0-originZ)/size)
            low,walllow,wallhigh=struct.unpack_from('<hhh',content,24+6*(iz*width+ix))
            self.assertEqual(low,0)
            self.assertEqual(walllow,MISSING)
            self.assertEqual(wallhigh,MISSING)
            wallx=int((0-originX)/size)
            _,walllo,wallhi=struct.unpack_from('<hhh',content,24+6*(iz*width+wallx))
            self.assertNotEqual(walllo,MISSING)
            self.assertGreaterEqual(wallhi,200)

    def test_corrupt(self):
        with tempfile.TemporaryDirectory() as d:
            path=Path(d)/'corrupt.meshbin'
            path.write_bytes(b'MERKMAP1'+struct.pack('<I',3))
            with self.assertRaises(ValueError):
                bake(path,Path(d)/'collision.bin')

if __name__=='__main__': unittest.main()
