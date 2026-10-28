import unittest,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'Tools'))
from import_web_movement import extract
class WebMovementTests(unittest.TestCase):
  def test_deployed_values(self):
    source=Path('/mnt/data/bo2_web_reference/movement-settings.js')
    if not source.exists():
       source=Path(__file__).resolve().parents[1]/'Tests/fixtures/movement-settings.js'
    result=extract(source.read_text())['values']
    self.assertEqual(result['walkSpeed'],3)
    self.assertEqual(result['sprintSpeed'],4.5)
    self.assertEqual(result['tacticalSprintSpeed'],5.05)
    self.assertEqual(result['gravity'],10.5)
    self.assertEqual(result['jumpVelocity'],3.3)
    self.assertEqual(result['slideDuration'],0.62)
    self.assertEqual(result['coyoteTime'],0.1)
  def test_missing_required_fails(self):
    with self.assertRaises(ValueError): extract('export const MOVEMENT_SETTINGS = {}')
if __name__=='__main__':unittest.main()
