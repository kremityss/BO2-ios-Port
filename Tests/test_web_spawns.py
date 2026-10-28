import unittest
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'Tools'))
from import_web_spawns import native_spawns

HINTS={'map':'mp_nuketown_2020','spawns':[
    {'guid':'A','classname':'mp_tdm_spawn_allies_start','position':[1669.4,-28,-212],'yaw':1.8727383},
    {'guid':'B','classname':'mp_tdm_spawn_axis_start','position':[-1818,-24,-554],'yaw':4.363323},
    {'guid':'C','classname':'not_spawn','position':[0,0,0],'yaw':0},
]}
T={'map':'mp_nuketown_2020','scale':0.01,'offset':[2251.2749,-853.578,-716.02688]}

class WebSpawnImportTests(unittest.TestCase):
    def test_maps_source_coordinates_to_the_same_native_scene_offset(self):
        out=native_spawns(HINTS,T)
        self.assertEqual(len(out['spawns']),2)
        a=out['spawns'][0]
        self.assertEqual(a['xyz'],[-5.81875,8.25578,5.04027])
        self.assertAlmostEqual(a['yaw'],-1.8727383)
        self.assertEqual(a['id'],'A')
    def test_separates_team_classes(self):
        result=native_spawns(HINTS,T)
        self.assertEqual(result['spawns'][1]['class'],'mp_tdm_spawn_axis_start')
    def test_invalid_transform_rejected(self):
        with self.assertRaises(ValueError):
            native_spawns(HINTS,{**T,'map':'mp_hijacked'})
        with self.assertRaises(ValueError):
            native_spawns(HINTS,{**T,'scale':1e10})
    def test_invalid_coordinates_ignored(self):
        h={**HINTS,'spawns':[{'guid':'bad','classname':'mp_tdm_spawn','position':[float('nan'),0,0],'yaw':0},HINTS['spawns'][0]]}
        self.assertEqual(len(native_spawns(h,T)['spawns']),1)

if __name__=='__main__': unittest.main()
