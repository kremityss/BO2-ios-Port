import importlib.util
import json
import struct
import tempfile
import unittest
from pathlib import Path

SPEC=importlib.util.spec_from_file_location(
    'clear_spawns',Path(__file__).resolve().parents[1]/'Tools/clear_authored_spawn_walls.py')
module=importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(module)

class SpawnClearanceTests(unittest.TestCase):
    def test_authored_spawn_walls_only(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            collision=root/'MerkCollision.bin'
            spawns=root/'MerkWebSpawns.json'
            data=bytearray(b'MERKCOL1'+struct.pack('<HHfff',8,8,0,0,.75))
            for _ in range(64):data.extend(struct.pack('<hhh',100,100,200))
            collision.write_bytes(data)
            points=[{'id':str(i),'class':'mp_dm_spawn',
                     'xyz':[1.875,1.4,1.875],'yaw':0} for i in range(267)]
            spawns.write_text(json.dumps({'map':'mp_nuketown_2020','spawns':points}))
            stats=module.clear_authored_spawns(collision,spawns)
            data=collision.read_bytes()
            self.assertEqual(struct.unpack_from('<hhh',data,24+6*(2*8+2)),
                             (100,-32768,-32768))
            self.assertEqual(struct.unpack_from('<hhh',data,24+6*(7*8+7)),
                             (100,100,200))
            self.assertGreater(stats['cleared_wall_cells'],0)

    def test_bad_collision_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            a=root/'bad.bin'
            b=root/'bad.json'
            a.write_bytes(b'bad')
            b.write_text('{}')
            with self.assertRaises(ValueError):
                module.clear_authored_spawns(a,b)

if __name__=='__main__':
    unittest.main()
