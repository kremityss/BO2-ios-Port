import json, unittest
from pathlib import Path
P=Path(__file__).resolve().parents[1]/'MerkOfDuty/Resources/MerkWebWeapons.json'
class WebWeaponsTests(unittest.TestCase):
    def test_original_weapons_registry(self):
        j=json.loads(P.read_text())
        self.assertEqual(j['source'],'web weapons.js + weapon-ballistics.js')
        self.assertEqual(len(j['weapons']),17)
        self.assertEqual(j['defaultLoadout']['primary'],'m27')
        self.assertEqual(j['defaultLoadout']['secondary'],'fiveseven')
    def test_derived_weapon_stats(self):
        w=json.loads(P.read_text())['weapons']
        self.assertEqual(w['m27']['roundsPerMinute'],750)
        self.assertEqual(w['an94']['initialRoundsPerMinute'],937.5)
        self.assertEqual(w['an94']['initialShotCount'],2)
        self.assertEqual(w['dsr50']['magazineSize'],5)
        for id in ['m27','an94','dsr50','fiveseven']:
            b=w[id]['ballistics']
            self.assertIn('head',b['locations']);self.assertIn('hipSpread',b);self.assertGreater(len(b['ranges']),0)
if __name__=='__main__':unittest.main()
