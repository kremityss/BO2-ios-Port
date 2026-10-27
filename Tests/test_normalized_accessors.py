"""Quantized glTF vertex attribute regression tests using the actual GLB formats."""
import sys
import struct
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'Tools'))
from convert_gltf import accessor_values, transform, local_matrix


class QuantizedAccessorsTests(unittest.TestCase):
    def test_signed_short_positions(self):
        raw=struct.pack('<6h',-32768,0,32767,16384,-16384,0)
        doc={'bufferViews':[{'buffer':0,'byteOffset':0,'byteLength':len(raw)}],
             'accessors':[{'bufferView':0,'componentType':5122,'type':'VEC3','count':2,'normalized':True}]}
        got=accessor_values(doc,[raw],0)
        self.assertEqual(got[0],(-1.0,0.0,1.0))
        self.assertAlmostEqual(got[1][0],16384/32767)
        self.assertAlmostEqual(got[1][1],-16384/32767)
        transformed=transform(local_matrix({'scale':[716,716,716], 'translation':[-2510.5,-68.5,-2415]}),got[0])
        self.assertEqual(transformed,(-3226.5,-68.5,-1699.0))

    def test_signed_byte_and_unsigned_uv(self):
        raw=struct.pack('<3b',-128,0,127)
        doc={'bufferViews':[{'buffer':0,'byteLength':3}],
             'accessors':[{'bufferView':0,'componentType':5120,'type':'VEC3','count':1,'normalized':True}]}
        self.assertEqual(accessor_values(doc,[raw],0)[0],(-1.0,0.0,1.0))
        raw=struct.pack('<2H',0,65535)
        doc['bufferViews'][0]['byteLength']=4
        doc['accessors'][0].update(componentType=5123,type='VEC2')
        self.assertEqual(accessor_values(doc,[raw],0)[0],(0.0,1.0))

    def test_non_normalized_indices_still_integers(self):
        raw=struct.pack('<3H',0,1,2)
        doc={'bufferViews':[{'buffer':0,'byteLength':len(raw)}],
             'accessors':[{'bufferView':0,'componentType':5123,'type':'SCALAR','count':3}]}
        self.assertEqual(accessor_values(doc,[raw],0),[(0,),(1,),(2,)])

    def test_malformed_out_of_range_view_rejected(self):
        doc={'bufferViews':[{'buffer':0,'byteLength':6}],
             'accessors':[{'bufferView':0,'componentType':5126,'type':'VEC3','count':1}]}
        with self.assertRaises(ValueError): accessor_values(doc,[b'123456'],0)

if __name__=='__main__':unittest.main()
